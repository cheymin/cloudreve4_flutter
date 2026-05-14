use flutter_rust_bridge::frb;
use std::sync::Arc;

use crate::api::ffi_types::*;
use crate::sync_engine::SyncEngine;

/// 全局引擎实例
static ENGINE: once_cell::sync::OnceCell<Arc<SyncEngine>> = once_cell::sync::OnceCell::new();

// 内部类型 -> FFI 类型的转换函数

fn error_to_ffi(e: crate::errors::SyncError) -> SyncErrorFfi {
    match e {
        crate::errors::SyncError::Network(msg) => SyncErrorFfi::NetworkError { message: msg },
        crate::errors::SyncError::DiskFull { needed, available } => {
            SyncErrorFfi::DiskFull { needed, available }
        }
        crate::errors::SyncError::Auth(msg) => SyncErrorFfi::AuthError { message: msg },
        crate::errors::SyncError::Conflict { count } => SyncErrorFfi::ConflictError { count },
        crate::errors::SyncError::NotInitialized => SyncErrorFfi::NotInitialized,
        _ => SyncErrorFfi::InternalError {
            message: e.to_string(),
        },
    }
}

fn config_from_ffi(ffi: SyncConfigFfi) -> crate::models::SyncConfig {
    use crate::models::{ConflictStrategy, SyncMode};
    use std::path::PathBuf;

    let sync_mode = match ffi.sync_mode.as_str() {
        "selective" => SyncMode::Selective,
        "album" => SyncMode::Album,
        _ => SyncMode::Full,
    };

    let conflict_strategy = match ffi.conflict_strategy.as_str() {
        "keep_local" => ConflictStrategy::KeepLocal,
        "keep_remote" => ConflictStrategy::KeepRemote,
        "newest_wins" => ConflictStrategy::NewestWins,
        "largest_wins" => ConflictStrategy::LargestWins,
        "manual" => ConflictStrategy::Manual,
        _ => ConflictStrategy::KeepBoth,
    };

    let bandwidth_limit = if ffi.bandwidth_limit_kbps > 0 {
        Some(ffi.bandwidth_limit_kbps * 1024)
    } else {
        None
    };

    crate::models::SyncConfig {
        base_url: ffi.base_url,
        access_token: ffi.access_token,
        refresh_token: ffi.refresh_token,
        local_root: PathBuf::from(&ffi.local_root),
        remote_root: ffi.remote_root,
        sync_mode,
        conflict_strategy,
        max_concurrent_transfers: ffi.max_concurrent_transfers as usize,
        bandwidth_limit,
        excluded_paths: ffi.excluded_paths,
        selective_dirs: ffi.selective_dirs,
        data_dir: PathBuf::from(&ffi.data_dir),
    }
}

fn config_to_ffi(c: &crate::models::SyncConfig) -> SyncConfigFfi {
    use crate::models::{ConflictStrategy, SyncMode};

    let sync_mode = match c.sync_mode {
        SyncMode::Full => "full",
        SyncMode::Selective => "selective",
        SyncMode::Album => "album",
    };

    let conflict_strategy = match c.conflict_strategy {
        ConflictStrategy::KeepLocal => "keep_local",
        ConflictStrategy::KeepRemote => "keep_remote",
        ConflictStrategy::KeepBoth => "keep_both",
        ConflictStrategy::NewestWins => "newest_wins",
        ConflictStrategy::LargestWins => "largest_wins",
        ConflictStrategy::Manual => "manual",
    };

    SyncConfigFfi {
        base_url: c.base_url.clone(),
        access_token: c.access_token.clone(),
        refresh_token: c.refresh_token.clone(),
        local_root: c.local_root.to_string_lossy().to_string(),
        remote_root: c.remote_root.clone(),
        sync_mode: sync_mode.to_string(),
        conflict_strategy: conflict_strategy.to_string(),
        max_concurrent_transfers: c.max_concurrent_transfers as u32,
        bandwidth_limit_kbps: c.bandwidth_limit.map(|b| b / 1024).unwrap_or(0),
        excluded_paths: c.excluded_paths.clone(),
        selective_dirs: c.selective_dirs.clone(),
        data_dir: c.data_dir.to_string_lossy().to_string(),
    }
}

fn status_to_ffi(s: crate::models::SyncStatusSnapshot) -> SyncStatusFfi {
    let error_msg = if let crate::models::SyncState::Error { ref message } = s.state {
        Some(message.clone())
    } else {
        s.error_message
    };

    let state = match s.state {
        crate::models::SyncState::Idle => "idle".to_string(),
        crate::models::SyncState::Initializing => "initializing".to_string(),
        crate::models::SyncState::InitialSync { .. } => "initialSync".to_string(),
        crate::models::SyncState::Continuous => "continuous".to_string(),
        crate::models::SyncState::Paused => "paused".to_string(),
        crate::models::SyncState::Error { .. } => "error".to_string(),
        crate::models::SyncState::Stopped => "stopped".to_string(),
    };

    SyncStatusFfi {
        state,
        synced_files: s.synced_files,
        total_files: s.total_files,
        uploading_count: s.uploading_count,
        downloading_count: s.downloading_count,
        conflict_count: s.conflict_count,
        error_count: s.error_count,
        last_sync_time: s.last_sync_time,
        error_message: error_msg,
    }
}

fn summary_to_ffi(s: crate::models::SyncSummary) -> SyncSummaryFfi {
    SyncSummaryFfi {
        uploaded: s.uploaded,
        downloaded: s.downloaded,
        conflicts: s.conflicts,
        skipped: s.skipped,
        deleted_local: s.deleted_local,
        deleted_remote: s.deleted_remote,
        duration_ms: s.duration_ms,
    }
}

fn album_result_to_ffi(r: crate::models::CloudAlbumCheckResult) -> CloudAlbumCheckResultFfi {
    CloudAlbumCheckResultFfi {
        dcim_exists: r.dcim_exists,
        pictures_exists: r.pictures_exists,
        dcim_uri: r.dcim_uri,
        pictures_uri: r.pictures_uri,
    }
}

/// 获取引擎引用，未初始化则返回错误
fn get_engine() -> Result<&'static SyncEngine, SyncErrorFfi> {
    ENGINE.get().map(|arc| arc.as_ref()).ok_or(SyncErrorFfi::NotInitialized)
}

// ========== 生命周期 ==========

/// 初始化同步引擎
#[frb]
pub async fn init_sync_engine(config: SyncConfigFfi) -> Result<(), SyncErrorFfi> {
    // 确保本地同步目录存在
    let local_root = std::path::PathBuf::from(&config.local_root);
    if !local_root.exists() {
        std::fs::create_dir_all(&local_root).map_err(|e| SyncErrorFfi::InternalError {
            message: format!("无法创建同步目录: {}", e),
        })?;
    }

    // 确保程序数据目录存在
    let data_dir = std::path::PathBuf::from(&config.data_dir);
    let db_dir = data_dir.join("sync_core").join("datas");
    let log_dir = data_dir.join("sync_core").join("logs");
    if !db_dir.exists() {
        std::fs::create_dir_all(&db_dir).map_err(|e| SyncErrorFfi::InternalError {
            message: format!("无法创建数据库目录: {}", e),
        })?;
    }
    if !log_dir.exists() {
        std::fs::create_dir_all(&log_dir).map_err(|e| SyncErrorFfi::InternalError {
            message: format!("无法创建日志目录: {}", e),
        })?;
    }

    // 初始化 tracing 日志：输出到程序数据目录的 logs 和 stderr
    let log_path = log_dir.join("sync_log.txt");
    eprintln!("[sync-core] 日志文件: {}", log_path.display());

    let log_file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_path)
        .ok();

    if log_file.is_none() {
        eprintln!("[sync-core] 警告: 无法创建日志文件 {}", log_path.display());
    }

    // 尝试初始化 subscriber（仅首次有效，后续调用忽略）
    {
        use tracing_subscriber::layer::SubscriberExt;
        use tracing_subscriber::util::SubscriberInitExt;

        let filter = tracing_subscriber::EnvFilter::from_default_env()
            .add_directive("sync_core=debug".parse().unwrap());

        let registry = tracing_subscriber::registry().with(filter);

        if let Some(file) = log_file {
            let _ = registry
                .with(tracing_subscriber::fmt::layer()
                    .with_writer(std::sync::Mutex::new(file))
                    .with_ansi(false))
                .with(tracing_subscriber::fmt::layer()
                    .with_writer(std::io::stderr))
                .try_init();
        } else {
            let _ = registry
                .with(tracing_subscriber::fmt::layer()
                    .with_writer(std::io::stderr))
                .try_init();
        }
    }

    let engine = SyncEngine::new(config_from_ffi(config)).await
        .map_err(error_to_ffi)?;

    ENGINE.set(Arc::new(engine))
        .map_err(|_| SyncErrorFfi::InternalError {
            message: "引擎已初始化".to_string(),
        })?;

    tracing::info!("同步引擎初始化完成, 日志文件: {}", log_path.display());
    Ok(())
}

/// 销毁同步引擎
#[frb]
pub async fn dispose_sync_engine() -> Result<(), SyncErrorFfi> {
    let engine = get_engine()?;
    engine.stop().await.map_err(error_to_ffi)?;
    tracing::info!("同步引擎已停止");
    Ok(())
}

// ========== 同步控制 ==========

/// 执行初始全量同步
#[frb]
pub async fn start_initial_sync() -> Result<SyncSummaryFfi, SyncErrorFfi> {
    let engine = get_engine()?;
    engine.run_initial_sync().await
        .map(summary_to_ffi)
        .map_err(error_to_ffi)
}

/// 启动持续同步（后台运行，立即返回）
#[frb]
pub async fn start_continuous_sync() -> Result<(), SyncErrorFfi> {
    let engine = get_engine()?;
    let engine = engine.clone();
    tokio::spawn(async move {
        if let Err(e) = engine.run_continuous().await {
            tracing::error!("持续同步异常退出: {}", e);
        }
    });
    Ok(())
}

/// 停止同步
#[frb]
pub async fn stop_sync() -> Result<(), SyncErrorFfi> {
    let engine = get_engine()?;
    engine.stop().await.map_err(error_to_ffi)
}

/// 暂停同步
#[frb]
pub async fn pause_sync() -> Result<(), SyncErrorFfi> {
    let engine = get_engine()?;
    engine.pause().await.map_err(error_to_ffi)
}

/// 恢复同步
#[frb]
pub async fn resume_sync() -> Result<(), SyncErrorFfi> {
    let engine = get_engine()?;
    engine.resume().await.map_err(error_to_ffi)
}

/// 强制同步（重新扫描全量差异）
#[frb]
pub async fn force_sync() -> Result<SyncSummaryFfi, SyncErrorFfi> {
    let engine = get_engine()?;
    engine.force_sync().await
        .map(summary_to_ffi)
        .map_err(error_to_ffi)
}

// ========== 状态查询 ==========

/// 获取同步状态快照
#[frb]
pub async fn get_sync_status() -> Result<SyncStatusFfi, SyncErrorFfi> {
    let engine = get_engine()?;
    Ok(status_to_ffi(engine.status()))
}

/// 获取同步配置
#[frb]
pub async fn get_sync_config() -> Result<SyncConfigFfi, SyncErrorFfi> {
    let engine = get_engine()?;
    Ok(config_to_ffi(&engine.config()))
}

/// 更新同步配置
#[frb]
pub async fn update_sync_config(config: SyncConfigFfi) -> Result<(), SyncErrorFfi> {
    let engine = get_engine()?;
    engine.update_config(config_from_ffi(config)).await.map_err(error_to_ffi)
}

// ========== Token 管理 ==========

/// Dart 推送新 Token 给 Rust
#[frb]
pub async fn update_tokens(access_token: String) -> Result<(), SyncErrorFfi> {
    let engine = get_engine()?;
    engine.update_access_token(access_token).await;
    Ok(())
}

// ========== Windows 专用 ==========

/// 水合文件（Windows 按需下载）
#[frb]
pub async fn hydrate_file(local_path: String) -> Result<(), SyncErrorFfi> {
    let engine = get_engine()?;
    engine.hydrate_file(&local_path).await.map_err(error_to_ffi)
}

// ========== Android 专用 ==========

/// 同步相册到云端
#[frb]
pub async fn sync_album_to_cloud(
    album_paths: Vec<String>,
    remote_dcim_uri: String,
) -> Result<(), SyncErrorFfi> {
    let engine = get_engine()?;
    engine.sync_album(album_paths, &remote_dcim_uri).await.map_err(error_to_ffi)
}

/// 检查云端是否存在 DCIM/Pictures 目录
#[frb]
pub async fn check_cloud_album_dirs(base_uri: String) -> Result<CloudAlbumCheckResultFfi, SyncErrorFfi> {
    let engine = get_engine()?;
    engine.check_album_dirs(&base_uri).await
        .map(album_result_to_ffi)
        .map_err(error_to_ffi)
}

/// 在云端创建 DCIM/Pictures 目录
#[frb]
pub async fn create_cloud_album_dirs(base_uri: String) -> Result<(), SyncErrorFfi> {
    let engine = get_engine()?;
    engine.create_album_dirs(&base_uri).await.map_err(error_to_ffi)
}
