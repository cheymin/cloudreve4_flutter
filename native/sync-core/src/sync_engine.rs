use crate::api_client::ApiClient;
use crate::conflict_resolver::ConflictResolver;
use crate::errors::{Result, SyncError};
use crate::event_handler::EventHandler;
use crate::fs_scanner::FsScanner;
use crate::models::*;
use crate::sync_db::SyncDb;
use crate::transfer::TransferManager;
use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::RwLock;
use tokio_util::sync::CancellationToken;

pub struct SyncEngine {
    state: RwLock<SyncState>,
    db: Arc<SyncDb>,
    api: Arc<ApiClient>,
    transfer: Arc<TransferManager>,
    conflict: ConflictResolver,
    config: SyncConfig,
    sync_root_id: Option<String>,
    shutdown_token: CancellationToken,
}

impl SyncEngine {
    pub async fn new(config: SyncConfig) -> Result<Self> {
        let db_path = config.local_root.join(".sync_db.sqlite3");
        let db = Arc::new(SyncDb::open(&db_path)?);

        let api = Arc::new(ApiClient::new(&config.base_url, &config.access_token));

        let transfer_config = TransferConfig {
            max_concurrent: config.max_concurrent_transfers,
            bandwidth_limit: config.bandwidth_limit,
            ..Default::default()
        };
        let transfer = Arc::new(TransferManager::new(db.clone(), api.clone(), transfer_config));

        let conflict = ConflictResolver::new(config.conflict_strategy.clone());

        let sync_root_id = db.upsert_sync_root(&config).await.ok();

        Ok(Self {
            state: RwLock::new(SyncState::Idle),
            db,
            api,
            transfer,
            conflict,
            config,
            sync_root_id,
            shutdown_token: CancellationToken::new(),
        })
    }

    /// 初始全量同步
    pub async fn run_initial_sync(&self) -> Result<SyncSummary> {
        let start = Instant::now();
        *self.state.write().await = SyncState::Initializing;

        // 1. 扫描本地文件系统
        let scanner = FsScanner::new();
        tracing::info!("开始扫描本地文件系统: {}", self.config.local_root.display());
        let local_files = scanner.scan(&self.config.local_root, 50, false).await?;
        tracing::info!("本地扫描完成: {} 个条目", local_files.len());

        // 2. 扫描远程文件树
        tracing::info!("开始扫描远程文件树: {}", self.config.remote_root);
        let remote_files = self.api.list_all_files(&self.config.remote_root).await?;
        tracing::info!("远程扫描完成: {} 个条目", remote_files.len());

        // 3. 计算三路差异
        let db_mappings = self.load_all_mappings().await?;
        let plan = self.compute_diff(&local_files, &remote_files, &db_mappings);
        tracing::info!(
            "差异计算完成: 上传={}, 下载={}, 删本地={}, 删远程={}, 冲突={}",
            plan.uploads.len(),
            plan.downloads.len(),
            plan.delete_local.len(),
            plan.delete_remote.len(),
            plan.conflicts.len(),
        );

        // 4. 执行同步计划
        *self.state.write().await = SyncState::InitialSync {
            progress: InitialSyncProgress {
                scanned_local: local_files.len() as u64,
                scanned_remote: remote_files.len() as u64,
                total_to_sync: plan.total_actions(),
                ..Default::default()
            },
        };

        let summary = self.execute_sync_plan(&plan).await?;

        *self.state.write().await = SyncState::Continuous;
        tracing::info!("初始同步完成, 耗时 {}ms", start.elapsed().as_millis());

        Ok(SyncSummary {
            duration_ms: start.elapsed().as_millis() as u64,
            ..summary
        })
    }

    /// 从数据库加载当前所有 file_mapping
    async fn load_all_mappings(&self) -> Result<HashMap<String, FileMapping>> {
        let root_id = match &self.sync_root_id {
            Some(id) => id.clone(),
            None => return Ok(HashMap::new()),
        };

        let pool = self.db.read_pool();
        let result = tokio::task::spawn_blocking(move || -> Result<HashMap<String, FileMapping>> {
            let conn = pool.get()?;
            let mut stmt = conn.prepare(
                "SELECT id, sync_root_id, local_path, remote_uri, remote_file_id,
                        local_hash, remote_hash, local_mtime, remote_mtime,
                        local_size, remote_size, sync_status, is_placeholder
                 FROM file_mapping WHERE sync_root_id = ?1"
            )?;

            let mappings: HashMap<String, FileMapping> = stmt.query_map(
                rusqlite::params![root_id],
                |row| {
                    let local_path: String = row.get(2)?;
                    Ok((
                        local_path.clone(),
                        FileMapping {
                            id: row.get(0)?,
                            sync_root_id: row.get(1)?,
                            local_path: std::path::PathBuf::from(local_path),
                            remote_uri: row.get(3)?,
                            remote_file_id: row.get(4)?,
                            local_hash: row.get(5)?,
                            remote_hash: row.get(6)?,
                            local_mtime: row.get(7)?,
                            remote_mtime: row.get(8)?,
                            local_size: row.get(9)?,
                            remote_size: row.get(10)?,
                            sync_status: parse_sync_status_from_str(&row.get::<_, String>(11)?),
                            is_placeholder: row.get::<_, i32>(12)? != 0,
                        },
                    ))
                },
            )?.filter_map(|r| r.ok()).collect();

            Ok(mappings)
        }).await??;

        Ok(result)
    }

    /// 三路差异计算: 本地 vs 远程 vs 数据库
    fn compute_diff(
        &self,
        local_files: &[LocalFileEntry],
        remote_files: &[RemoteFileEntry],
        db_mappings: &HashMap<String, FileMapping>,
    ) -> SyncPlan {
        let mut plan = SyncPlan::default();

        // 构建索引: relative_path → entry
        let local_map: HashMap<String, &LocalFileEntry> = local_files
            .iter()
            .map(|e| (e.relative_path.to_string_lossy().to_string(), e))
            .collect();

        // 构建 remote_path: 用 remote.path 去掉前缀作为相对路径
        let remote_root = &self.config.remote_root;
        let remote_map: HashMap<String, &RemoteFileEntry> = remote_files
            .iter()
            .filter_map(|e| {
                let rel = remote_relative_path(remote_root, &e.path, &e.name, e.is_dir);
                Some((rel, e))
            })
            .collect();

        // 收集所有路径
        let mut all_paths: std::collections::HashSet<String> = std::collections::HashSet::new();
        for k in local_map.keys() {
            all_paths.insert(k.clone());
        }
        for k in remote_map.keys() {
            all_paths.insert(k.clone());
        }
        for k in db_mappings.keys() {
            all_paths.insert(k.clone());
        }

        for path in &all_paths {
            let local = local_map.get(path.as_str()).copied();
            let remote = remote_map.get(path.as_str()).copied();
            let db = db_mappings.get(path.as_str());

            match (local, remote, db) {
                // 本地有，远程无
                (Some(l), None, _) => {
                    if let Some(db_m) = db {
                        if db_m.sync_status == SyncFileStatus::Synced {
                            // 数据库有记录且已同步 → 远程已删除 → 初始同步中保留本地
                            plan.uploads.push(SyncAction {
                                relative_path: path.clone(),
                                local_entry: Some((*l).clone()),
                                remote_entry: None,
                                db_mapping: Some(db_m.clone()),
                            });
                        }
                    } else {
                        // 数据库无记录，新文件 → 上传
                        plan.uploads.push(SyncAction {
                            relative_path: path.clone(),
                            local_entry: Some((*l).clone()),
                            remote_entry: None,
                            db_mapping: None,
                        });
                    }
                }

                // 远程有，本地无
                (None, Some(r), _) => {
                    if let Some(db_m) = db {
                        if db_m.sync_status == SyncFileStatus::Synced {
                            // 数据库有记录且已同步 → 本地已删除 → 删远程
                            plan.delete_remote.push(SyncAction {
                                relative_path: path.clone(),
                                local_entry: None,
                                remote_entry: Some((*r).clone()),
                                db_mapping: Some(db_m.clone()),
                            });
                        }
                    } else {
                        // 新远程文件 → 下载
                        if r.is_dir {
                            plan.mkdirs_local.push(path.clone());
                        } else {
                            plan.downloads.push(SyncAction {
                                relative_path: path.clone(),
                                local_entry: None,
                                remote_entry: Some((*r).clone()),
                                db_mapping: None,
                            });
                        }
                    }
                }

                // 两边都有
                (Some(l), Some(r), db_m) => {
                    if l.is_dir && r.is_dir {
                        continue;
                    }

                    // 比较哈希判断是否相同
                    let hashes_match = match (&l.quick_hash, &r.hash) {
                        (lh, Some(rh)) if !lh.is_empty() => lh == rh,
                        _ => {
                            // 无哈希比较，用 mtime + size 近似判断
                            l.size == r.size && l.mtime_ms == r.mtime_ms
                        }
                    };

                    if hashes_match {
                        // 内容一致，标记已同步
                    } else {
                        let conflict_type = if l.is_dir != r.is_dir {
                            ConflictType::TypeMismatch
                        } else {
                            ConflictType::BothModified
                        };

                        plan.conflicts.push(SyncConflict {
                            relative_path: path.clone(),
                            conflict_type,
                            local_entry: Some((*l).clone()),
                            remote_entry: Some((*r).clone()),
                            db_mapping: db_m.cloned(),
                        });
                    }
                }

                // 两边都没有但数据库有记录 → 清理
                (None, None, Some(_)) => {}

                _ => {}
            }
        }

        // 远程目录结构: 需要先在远程创建本地独有的目录
        for (path, local) in &local_map {
            if local.is_dir && !remote_map.contains_key(path.as_str()) {
                plan.mkdirs_remote.push(path.clone());
            }
        }

        plan
    }

    /// 执行同步计划
    async fn execute_sync_plan(&self, plan: &SyncPlan) -> Result<SyncSummary> {
        let mut summary = SyncSummary::default();
        let root_id = self.sync_root_id.clone().unwrap_or_default();

        // 1. 创建远程目录结构
        for dir_path in &plan.mkdirs_remote {
            match self.api.create_directory(&self.config.remote_root, dir_path).await {
                Ok(_) => tracing::debug!("创建远程目录: {}", dir_path),
                Err(e) => tracing::warn!("创建远程目录失败 {}: {}", dir_path, e),
            }
        }

        // 2. 创建本地目录结构
        for dir_path in &plan.mkdirs_local {
            let local_path = self.config.local_root.join(dir_path);
            if let Err(e) = tokio::fs::create_dir_all(&local_path).await {
                tracing::warn!("创建本地目录失败 {}: {}", dir_path, e);
            }
        }

        // 3. 处理冲突
        for conflict in &plan.conflicts {
            let local_mtime = conflict.local_entry.as_ref().map(|l| l.mtime_ms).unwrap_or(0);
            let remote_mtime = conflict.remote_entry.as_ref().map(|r| r.mtime_ms).unwrap_or(0);
            let local_size = conflict.local_entry.as_ref().map(|l| l.size).unwrap_or(0);
            let remote_size = conflict.remote_entry.as_ref().map(|r| r.size).unwrap_or(0);
            let local_name = conflict.local_entry.as_ref()
                .map(|l| l.relative_path.file_name()
                    .map(|n| n.to_string_lossy().to_string())
                    .unwrap_or_default())
                .unwrap_or_default();

            let resolution = self.conflict.resolve(
                conflict.conflict_type.clone(),
                local_mtime,
                remote_mtime,
                local_size,
                remote_size,
                &local_name,
            );

            match resolution {
                ConflictResolution::UploadLocal => {
                    if let Some(ref local) = conflict.local_entry {
                        let action = SyncAction {
                            relative_path: conflict.relative_path.clone(),
                            local_entry: Some(local.clone()),
                            remote_entry: conflict.remote_entry.clone(),
                            db_mapping: conflict.db_mapping.clone(),
                        };
                        self.execute_upload(&root_id, &action).await?;
                        summary.uploaded += 1;
                    }
                }
                ConflictResolution::DownloadRemote => {
                    if let Some(ref remote) = conflict.remote_entry {
                        let action = SyncAction {
                            relative_path: conflict.relative_path.clone(),
                            local_entry: conflict.local_entry.clone(),
                            remote_entry: Some(remote.clone()),
                            db_mapping: conflict.db_mapping.clone(),
                        };
                        self.execute_download(&root_id, &action).await?;
                        summary.downloaded += 1;
                    }
                }
                ConflictResolution::RenameLocal { ref new_name } => {
                    if let Some(ref local) = conflict.local_entry {
                        let old_path = self.config.local_root.join(&local.relative_path);
                        let new_rel = format!(
                            "{}/{}",
                            local.relative_path.parent()
                                .map(|p| p.to_string_lossy().to_string())
                                .unwrap_or_default(),
                            new_name
                        );
                        let new_path = self.config.local_root.join(&new_rel);
                        if let Err(e) = tokio::fs::rename(&old_path, &new_path).await {
                            tracing::warn!("重命名冲突文件失败: {}", e);
                        } else {
                            let action = SyncAction {
                                relative_path: new_rel,
                                local_entry: Some(LocalFileEntry {
                                    relative_path: std::path::PathBuf::from(new_name.clone()),
                                    ..local.clone()
                                }),
                                remote_entry: None,
                                db_mapping: None,
                            };
                            self.execute_upload(&root_id, &action).await?;
                            summary.uploaded += 1;
                        }
                    }
                }
                ConflictResolution::DeleteLocal => {
                    if let Some(ref local) = conflict.local_entry {
                        let local_path = self.config.local_root.join(&local.relative_path);
                        let _ = tokio::fs::remove_file(&local_path).await;
                        summary.deleted_local += 1;
                    }
                }
                ConflictResolution::DeleteRemote => {
                    if let Some(ref remote) = conflict.remote_entry {
                        let _ = self.api.delete_files(&[&remote.uri]).await;
                        summary.deleted_remote += 1;
                    }
                }
                ConflictResolution::MarkManual => {
                    summary.conflicts += 1;
                    tracing::warn!("手动解决冲突: {}", conflict.relative_path);
                }
            }
        }

        // 4. 上传本地独有文件
        for action in &plan.uploads {
            match self.execute_upload(&root_id, action).await {
                Ok(_) => summary.uploaded += 1,
                Err(e) => {
                    tracing::error!("上传失败 {}: {}", action.relative_path, e);
                    summary.conflicts += 1;
                }
            }
        }

        // 5. 下载远程独有文件
        for action in &plan.downloads {
            match self.execute_download(&root_id, action).await {
                Ok(_) => summary.downloaded += 1,
                Err(e) => {
                    tracing::error!("下载失败 {}: {}", action.relative_path, e);
                    summary.conflicts += 1;
                }
            }
        }

        // 6. 删除本地文件
        for action in &plan.delete_local {
            if let Some(ref local) = action.local_entry {
                let local_path = self.config.local_root.join(&local.relative_path);
                match tokio::fs::remove_file(&local_path).await {
                    Ok(_) => {
                        summary.deleted_local += 1;
                        let _ = self.db.delete_file_mapping(&root_id, &action.relative_path).await;
                    }
                    Err(e) => tracing::warn!("删除本地文件失败 {}: {}", action.relative_path, e),
                }
            }
        }

        // 7. 删除远程文件
        let remote_uris: Vec<&str> = plan.delete_remote.iter()
            .filter_map(|a| a.remote_entry.as_ref().map(|r| r.uri.as_str()))
            .collect();
        if !remote_uris.is_empty() {
            match self.api.delete_files(&remote_uris).await {
                Ok(_) => summary.deleted_remote += remote_uris.len() as u32,
                Err(e) => tracing::error!("批量删除远程文件失败: {}", e),
            }
            for action in &plan.delete_remote {
                let _ = self.db.delete_file_mapping(&root_id, &action.relative_path).await;
            }
        }

        Ok(summary)
    }

    /// 上传单个文件（含重试）
    async fn execute_upload(&self, root_id: &str, action: &SyncAction) -> Result<()> {
        let local = action.local_entry.as_ref().ok_or_else(|| {
            SyncError::Internal("上传操作缺少本地文件信息".into())
        })?;

        if local.is_dir {
            let remote_uri = format!("{}/{}", self.config.remote_root, action.relative_path);
            self.db.upsert_file_mapping(&FileMapping {
                id: 0,
                sync_root_id: root_id.to_string(),
                local_path: local.relative_path.clone(),
                remote_uri,
                remote_file_id: None,
                local_hash: Some(local.quick_hash.clone()),
                remote_hash: None,
                local_mtime: Some(local.mtime_ms),
                remote_mtime: None,
                local_size: Some(local.size),
                remote_size: None,
                sync_status: SyncFileStatus::Synced,
                is_placeholder: false,
            }).await?;
            return Ok(());
        }

        let local_path = self.config.local_root.join(&local.relative_path);
        let parent_uri = self.config.remote_root.clone();
        let max_retries = 3u32;

        // 读取文件
        let data = tokio::fs::read(&local_path).await?;

        // 带重试的上传
        let session = self.retry_upload_session(&parent_uri, local.size, max_retries).await?;
        let chunk_size = session.chunk_size as usize;
        let mut index = 0u32;

        for chunk in data.chunks(chunk_size) {
            let mut chunk_retries = 0u32;
            loop {
                match self.api.upload_chunk(&session.session_id, index, chunk).await {
                    Ok(_) => break,
                    Err(SyncError::Auth(_)) => return Err(SyncError::Auth("Token 过期".into())),
                    Err(e) if chunk_retries < max_retries => {
                        chunk_retries += 1;
                        let delay = crate::utils::retry_delay_ms(chunk_retries, 1000, 30000);
                        tracing::warn!("分片上传失败，{}ms后重试 ({}): {}", delay, chunk_retries, e);
                        tokio::time::sleep(std::time::Duration::from_millis(delay)).await;
                    }
                    Err(e) => return Err(e),
                }
            }
            index += 1;
        }

        // 上传完成后获取远程文件信息
        let remote_uri = format!("{}/{}", parent_uri, action.relative_path);
        let (remote_file_id, remote_hash) = match self.api.get_file_info(&remote_uri).await {
            Ok(info) => (info.file_id.clone(), info.hash.clone()),
            Err(e) => {
                tracing::warn!("上传后获取文件信息失败: {}", e);
                (None, None)
            }
        };

        self.db.upsert_file_mapping(&FileMapping {
            id: 0,
            sync_root_id: root_id.to_string(),
            local_path: local.relative_path.clone(),
            remote_uri,
            remote_file_id,
            local_hash: Some(local.quick_hash.clone()),
            remote_hash: remote_hash.or(Some(local.quick_hash.clone())),
            local_mtime: Some(local.mtime_ms),
            remote_mtime: Some(local.mtime_ms),
            local_size: Some(local.size),
            remote_size: Some(local.size),
            sync_status: SyncFileStatus::Synced,
            is_placeholder: false,
        }).await?;

        tracing::debug!("上传完成: {}", action.relative_path);
        Ok(())
    }

    /// 下载单个文件（含重试）
    async fn execute_download(&self, root_id: &str, action: &SyncAction) -> Result<()> {
        let remote = action.remote_entry.as_ref().ok_or_else(|| {
            SyncError::Internal("下载操作缺少远程文件信息".into())
        })?;

        if remote.is_dir {
            let local_path = self.config.local_root.join(&action.relative_path);
            tokio::fs::create_dir_all(&local_path).await?;
            return Ok(());
        }

        let local_path = self.config.local_root.join(&action.relative_path);

        // 确保父目录存在
        if let Some(parent) = local_path.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }

        let max_retries = 3u32;
        let mut attempt = 0u32;

        loop {
            attempt += 1;

            // 获取下载 URL
            let urls = match self.api.get_download_url(&[&remote.uri]).await {
                Ok(urls) => urls,
                Err(SyncError::Auth(_)) => return Err(SyncError::Auth("Token 过期".into())),
                Err(e) if attempt <= max_retries => {
                    let delay = crate::utils::retry_delay_ms(attempt, 1000, 30000);
                    tracing::warn!("获取下载链接失败，{}ms后重试 ({}): {}", delay, attempt, e);
                    tokio::time::sleep(std::time::Duration::from_millis(delay)).await;
                    continue;
                }
                Err(e) => return Err(e),
            };

            let download_url = match urls.first() {
                Some(u) => u.clone(),
                None => return Err(SyncError::Network("未获取到下载链接".into())),
            };

            // 流式下载
            let resp = match self.api.stream_download(&download_url, 0).await {
                Ok(r) => r,
                Err(SyncError::Auth(_)) => return Err(SyncError::Auth("Token 过期".into())),
                Err(e) if attempt <= max_retries => {
                    let delay = crate::utils::retry_delay_ms(attempt, 1000, 30000);
                    tracing::warn!("下载连接失败，{}ms后重试 ({}): {}", delay, attempt, e);
                    tokio::time::sleep(std::time::Duration::from_millis(delay)).await;
                    continue;
                }
                Err(e) => return Err(e),
            };

            let tmp_path = local_path.with_extension(".sync_tmp");

            match self.stream_to_file(resp, &tmp_path).await {
                Ok(_) => {
                    // 原子重命名
                    tokio::fs::rename(&tmp_path, &local_path).await?;

                    // 设置修改时间
                    if remote.mtime_ms > 0 {
                        let mtime = std::time::UNIX_EPOCH + std::time::Duration::from_millis(remote.mtime_ms as u64);
                        let _ = filetime::set_file_mtime(&local_path, filetime::FileTime::from_system_time(mtime.into()));
                    }

                    // 更新数据库映射
                    let local_hash = crate::utils::quick_hash(&local_path, remote.size).await.unwrap_or_default();
                    self.db.upsert_file_mapping(&FileMapping {
                        id: 0,
                        sync_root_id: root_id.to_string(),
                        local_path: std::path::PathBuf::from(&action.relative_path),
                        remote_uri: remote.uri.clone(),
                        remote_file_id: remote.file_id.clone(),
                        local_hash: Some(local_hash.clone()),
                        remote_hash: remote.hash.clone().or(Some(local_hash)),
                        local_mtime: Some(remote.mtime_ms),
                        remote_mtime: Some(remote.mtime_ms),
                        local_size: Some(remote.size),
                        remote_size: Some(remote.size),
                        sync_status: SyncFileStatus::Synced,
                        is_placeholder: false,
                    }).await?;

                    tracing::debug!("下载完成: {}", action.relative_path);
                    return Ok(());
                }
                Err(e) if attempt <= max_retries => {
                    let delay = crate::utils::retry_delay_ms(attempt, 1000, 30000);
                    tracing::warn!("下载写入失败，{}ms后重试 ({}): {}", delay, attempt, e);
                    let _ = tokio::fs::remove_file(&tmp_path).await;
                    tokio::time::sleep(std::time::Duration::from_millis(delay)).await;
                    continue;
                }
                Err(e) => {
                    let _ = tokio::fs::remove_file(&tmp_path).await;
                    return Err(e);
                }
            }
        }
    }

    /// 流式写入文件
    async fn stream_to_file(
        &self,
        resp: reqwest::Response,
        tmp_path: &std::path::Path,
    ) -> Result<()> {
        let mut file = tokio::fs::File::create(tmp_path).await?;
        use tokio::io::AsyncWriteExt;
        let mut stream = resp.bytes_stream();
        use futures_util::StreamExt;
        while let Some(chunk) = stream.next().await {
            let chunk = chunk.map_err(|e| SyncError::Network(e.to_string()))?;
            file.write_all(&chunk).await?;
        }
        file.flush().await?;
        Ok(())
    }

    /// 带重试的创建上传会话
    async fn retry_upload_session(
        &self,
        parent_uri: &str,
        file_size: u64,
        max_retries: u32,
    ) -> Result<UploadSession> {
        let mut attempt = 0u32;
        loop {
            attempt += 1;
            match self.api.create_upload_session(parent_uri, file_size).await {
                Ok(session) => return Ok(session),
                Err(SyncError::Auth(_)) => return Err(SyncError::Auth("Token 过期".into())),
                Err(e) if attempt <= max_retries => {
                    let delay = crate::utils::retry_delay_ms(attempt, 1000, 30000);
                    tracing::warn!("创建上传会话失败，{}ms后重试 ({}): {}", delay, attempt, e);
                    tokio::time::sleep(std::time::Duration::from_millis(delay)).await;
                }
                Err(e) => return Err(e),
            }
        }
    }

    /// 持续同步：双事件源驱动 (SSE + 本地文件监听)
    pub async fn run_continuous(&self) -> Result<()> {
        let event_handler = EventHandler::new(
            self.api.clone(),
            uuid::Uuid::new_v4().to_string(),
        );

        // 订阅远程 SSE 事件
        let mut remote_rx = event_handler.subscribe_sse(&self.config.remote_root).await?;

        // 启动本地文件监听 (notify)
        let local_root = self.config.local_root.clone();
        let (local_tx, mut local_rx) = tokio::sync::mpsc::channel::<LocalFileEvent>(256);
        let shutdown_clone = self.shutdown_token.clone();

        std::thread::spawn(move || {
            use notify::{RecommendedWatcher, RecursiveMode, Event, EventKind};
            use notify::Watcher;

            let (notify_tx, notify_rx) = std::sync::mpsc::channel::<notify::Result<Event>>();

            let mut watcher = match RecommendedWatcher::new(
                move |res: notify::Result<Event>| { let _ = notify_tx.send(res); },
                notify::Config::default().with_poll_interval(std::time::Duration::from_secs(2)),
            ) {
                Ok(w) => w,
                Err(e) => {
                    tracing::error!("无法启动文件监听: {}", e);
                    return;
                }
            };

            if let Err(e) = watcher.watch(&local_root, RecursiveMode::Recursive) {
                tracing::error!("文件监听启动失败: {}", e);
                return;
            }

            tracing::info!("本地文件监听已启动: {}", local_root.display());

            // 事件去重缓冲
            let mut created_buf: Vec<std::path::PathBuf> = Vec::new();
            let mut modified_buf: Vec<std::path::PathBuf> = Vec::new();
            let mut deleted_buf: Vec<std::path::PathBuf> = Vec::new();

            loop {
                if shutdown_clone.is_cancelled() {
                    break;
                }

                match notify_rx.recv_timeout(std::time::Duration::from_millis(500)) {
                    Ok(Ok(event)) => {
                        // 忽略 .sync_tmp 临时文件
                        let paths: Vec<_> = event.paths.iter()
                            .filter(|p| {
                                !p.extension().map(|e| e == "sync_tmp").unwrap_or(false)
                            })
                            .cloned()
                            .collect();

                        if paths.is_empty() {
                            continue;
                        }

                        match event.kind {
                            EventKind::Create(_) => created_buf.extend(paths),
                            EventKind::Modify(_) => modified_buf.extend(paths),
                            EventKind::Remove(_) => deleted_buf.extend(paths),
                            _ => {}
                        }
                    }
                    Ok(Err(e)) => {
                        tracing::warn!("文件监听错误: {}", e);
                    }
                    Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {}
                    Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => break,
                }

                // 批量发送缓冲的事件
                if !created_buf.is_empty() {
                    let _ = local_tx.blocking_send(LocalFileEvent::Created(std::mem::take(&mut created_buf)));
                }
                if !modified_buf.is_empty() {
                    let _ = local_tx.blocking_send(LocalFileEvent::Modified(std::mem::take(&mut modified_buf)));
                }
                if !deleted_buf.is_empty() {
                    let _ = local_tx.blocking_send(LocalFileEvent::Deleted(std::mem::take(&mut deleted_buf)));
                }
            }

            let _ = watcher.unwatch(&local_root);
            tracing::info!("本地文件监听已停止");
        });

        *self.state.write().await = SyncState::Continuous;
        tracing::info!("持续同步已启动");

        let mut debounce = crate::event_handler::EventDebouncer::new(
            std::time::Duration::from_millis(500),
        );

        loop {
            tokio::select! {
                _ = self.shutdown_token.cancelled() => {
                    tracing::info!("持续同步收到停止信号");
                    break;
                }

                // 本地文件变化
                Some(event) = local_rx.recv() => {
                    for path in event.paths() {
                        if !debounce.should_process(path) {
                            continue;
                        }

                        let relative = path.strip_prefix(&self.config.local_root)
                            .unwrap_or(path)
                            .to_string_lossy()
                            .to_string();

                        match &event {
                            LocalFileEvent::Created(_) | LocalFileEvent::Modified(_) => {
                                tracing::debug!("本地上传: {}", relative);
                                if let Ok(metadata) = tokio::fs::metadata(path).await {
                                    let size = metadata.len();
                                    let mtime_ms = metadata.modified().ok()
                                        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                                        .map(|d| d.as_millis() as i64)
                                        .unwrap_or(0);
                                    let quick_hash = crate::utils::quick_hash(path, size).await.unwrap_or_default();

                                    let action = SyncAction {
                                        relative_path: relative.clone(),
                                        local_entry: Some(LocalFileEntry {
                                            relative_path: std::path::PathBuf::from(&relative),
                                            size,
                                            mtime_ms,
                                            quick_hash,
                                            is_dir: metadata.is_dir(),
                                        }),
                                        remote_entry: None,
                                        db_mapping: None,
                                    };

                                    let root_id = self.sync_root_id.clone().unwrap_or_default();
                                    if let Err(e) = self.execute_upload(&root_id, &action).await {
                                        tracing::error!("持续同步上传失败 {}: {}", relative, e);
                                    }
                                }
                            }
                            LocalFileEvent::Deleted(_) => {
                                tracing::debug!("本地删除，删除远程: {}", relative);
                                let remote_uri = format!("{}/{}", self.config.remote_root, relative);
                                if let Err(e) = self.api.delete_files(&[&remote_uri]).await {
                                    tracing::error!("持续同步删除远程失败 {}: {}", relative, e);
                                }
                            }
                        }
                    }
                    debounce.cleanup();
                }

                // 远程文件变化
                Some(event) = remote_rx.recv() => {
                    match &event {
                        RemoteFileEvent::Created(remote) | RemoteFileEvent::Modified(remote) => {
                            let relative = remote_relative_path(
                                &self.config.remote_root,
                                &remote.path,
                                &remote.name,
                                remote.is_dir,
                            );
                            tracing::debug!("远程下载: {}", relative);

                            let action = SyncAction {
                                relative_path: relative.clone(),
                                local_entry: None,
                                remote_entry: Some(remote.clone()),
                                db_mapping: None,
                            };

                            let root_id = self.sync_root_id.clone().unwrap_or_default();
                            if let Err(e) = self.execute_download(&root_id, &action).await {
                                tracing::error!("持续同步下载失败 {}: {}", relative, e);
                            }
                        }
                        RemoteFileEvent::Deleted { uri, name } => {
                            let relative = remote_relative_path(
                                &self.config.remote_root,
                                uri,
                                name,
                                false,
                            );
                            tracing::debug!("远程删除，删除本地: {}", relative);
                            let local_path = self.config.local_root.join(&relative);
                            let _ = tokio::fs::remove_file(&local_path).await;
                        }
                    }
                }

                // 定期心跳
                _ = tokio::time::sleep(std::time::Duration::from_secs(60)) => {
                    tracing::debug!("持续同步心跳");
                    debounce.cleanup();
                }
            }
        }

        Ok(())
    }

    pub async fn stop(&self) -> Result<()> {
        self.shutdown_token.cancel();
        Ok(())
    }

    pub async fn pause(&self) -> Result<()> {
        *self.state.write().await = SyncState::Paused;
        Ok(())
    }

    pub async fn resume(&self) -> Result<()> {
        *self.state.write().await = SyncState::Continuous;
        Ok(())
    }

    pub async fn force_sync(&self) -> Result<SyncSummary> {
        self.run_initial_sync().await
    }

    pub fn status(&self) -> SyncStatusSnapshot {
        // 使用 try_read 避免阻塞，如果被锁住则用 Idle
        let state = self.state.try_read().map(|g| g.clone()).unwrap_or(SyncState::Idle);
        SyncStatusSnapshot {
            state,
            synced_files: 0,
            total_files: 0,
            uploading_count: 0,
            downloading_count: 0,
            conflict_count: 0,
            error_count: 0,
            last_sync_time: None,
            error_message: None,
        }
    }

    pub fn config(&self) -> SyncConfig {
        self.config.clone()
    }

    pub async fn update_config(&self, _config: SyncConfig) -> Result<()> {
        Ok(())
    }

    pub async fn update_access_token(&self, token: String) {
        self.api.update_token(token).await;
    }

    pub async fn shutdown(self) -> Result<()> {
        self.shutdown_token.cancel();
        Ok(())
    }

    pub async fn hydrate_file(&self, _local_path: &str) -> Result<()> {
        Ok(())
    }

    pub async fn sync_album(
        &self,
        album_paths: Vec<String>,
        remote_dcim_uri: &str,
    ) -> Result<()> {
        let synced = self.db.get_album_sync_records().await?;

        let new_photos: Vec<_> = album_paths.iter()
            .filter(|p| !synced.contains_key(*p))
            .collect();

        let total = new_photos.len();
        if total == 0 {
            tracing::info!("相册同步: 无新照片");
            return Ok(());
        }

        tracing::info!("相册同步: 发现 {} 张新照片", total);

        for (i, photo_path) in new_photos.iter().enumerate() {
            let local_path = Path::new(photo_path);
            let file_name = local_path.file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_else(|| format!("photo_{}", i));

            match tokio::fs::metadata(photo_path).await {
                Ok(metadata) => {
                    let file_size = metadata.len();

                    // 创建上传会话
                    match self.api.create_upload_session(remote_dcim_uri, file_size).await {
                        Ok(session) => {
                            // 读取文件并分片上传
                            match tokio::fs::read(photo_path).await {
                                Ok(data) => {
                                    let chunk_size = session.chunk_size as usize;
                                    let mut index = 0u32;
                                    let mut upload_ok = true;

                                    for chunk in data.chunks(chunk_size) {
                                        if let Err(e) = self.api.upload_chunk(&session.session_id, index, chunk).await {
                                            tracing::error!("上传分片失败 {}: {}", file_name, e);
                                            upload_ok = false;
                                            break;
                                        }
                                        index += 1;
                                    }

                                    if upload_ok {
                                        let remote_uri = format!("{}/{}", remote_dcim_uri, file_name);
                                        let hash = crate::utils::quick_hash(local_path, file_size).await.unwrap_or_default();

                                        if let Err(e) = self.db.add_album_sync_record(
                                            photo_path,
                                            &remote_uri,
                                            &hash,
                                        ).await {
                                            tracing::warn!("记录同步状态失败: {}", e);
                                        }

                                        tracing::info!("照片上传完成 ({}/{}): {}", i + 1, total, file_name);
                                    }
                                }
                                Err(e) => {
                                    tracing::error!("读取照片失败 {}: {}", file_name, e);
                                }
                            }
                        }
                        Err(e) => {
                            tracing::error!("创建上传会话失败 {}: {}", file_name, e);
                        }
                    }
                }
                Err(e) => {
                    tracing::warn!("无法读取照片元数据 {}: {}", photo_path, e);
                }
            }
        }

        Ok(())
    }

    pub async fn check_album_dirs(&self, base_uri: &str) -> Result<CloudAlbumCheckResult> {
        let files = self.api.list_files_page(base_uri, 0, 200, None).await?;

        let dcim_exists = files.files.iter().any(|f| f.name == "DCIM" && f.is_dir);
        let pictures_exists = files.files.iter().any(|f| f.name == "Pictures" && f.is_dir);

        Ok(CloudAlbumCheckResult {
            dcim_exists,
            pictures_exists,
            dcim_uri: if dcim_exists { Some(format!("{}/DCIM", base_uri)) } else { None },
            pictures_uri: if pictures_exists { Some(format!("{}/Pictures", base_uri)) } else { None },
        })
    }

    pub async fn create_album_dirs(&self, base_uri: &str) -> Result<()> {
        self.api.create_directory(base_uri, "DCIM").await?;
        self.api.create_directory(base_uri, "Pictures").await?;
        Ok(())
    }
}

/// 从远程 path 字段提取相对路径
fn remote_relative_path(remote_root: &str, path: &str, name: &str, is_dir: bool) -> String {
    let _ = is_dir;
    if path.starts_with(remote_root) {
        let rel = &path[remote_root.len()..];
        let rel = rel.trim_start_matches('/');
        rel.to_string()
    } else {
        name.to_string()
    }
}

fn parse_sync_status_from_str(s: &str) -> SyncFileStatus {
    match s {
        "uploading" => SyncFileStatus::Uploading,
        "downloading" => SyncFileStatus::Downloading,
        "conflict" => SyncFileStatus::Conflict,
        "placeholder" => SyncFileStatus::Placeholder,
        _ => SyncFileStatus::Synced,
    }
}
