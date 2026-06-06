import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../services/auto_backup_service.dart';
import '../../../services/auto_backup_foreground_service.dart';
import '../../widgets/toast_helper.dart';

/// 自动备份设置页面
class AutoBackupSettingsPage extends StatefulWidget {
  const AutoBackupSettingsPage({super.key});

  @override
  State<AutoBackupSettingsPage> createState() => _AutoBackupSettingsPageState();
}

class _AutoBackupSettingsPageState extends State<AutoBackupSettingsPage> {
  AutoBackupConfig _config = const AutoBackupConfig();
  DateTime? _lastBackupTime;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final config = AutoBackupService.instance.config;
    final lastTime = await AutoBackupService.instance.getLastBackupTime();

    if (mounted) {
      setState(() {
        _config = config;
        _lastBackupTime = lastTime;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('自动备份'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // 状态卡片
                _buildStatusCard(theme),
                const SizedBox(height: 8),

                // 开关设置
                _buildSection(
                  title: '备份开关',
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.backup_outlined),
                      title: const Text('启用自动备份'),
                      subtitle: Text(
                        _config.enabled ? '已开启' : '已关闭',
                        style: TextStyle(
                          color: _config.enabled ? Colors.green : theme.hintColor,
                        ),
                      ),
                      value: _config.enabled,
                      onChanged: (value) => _toggleEnabled(value),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.photo_library_outlined),
                      title: const Text('备份照片'),
                      subtitle: const Text('自动备份新拍摄的照片'),
                      value: _config.backupPhotos,
                      onChanged: _config.enabled ? (value) => _updateConfig(backupPhotos: value) : null,
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.videocam_outlined),
                      title: const Text('备份视频'),
                      subtitle: const Text('自动备份新拍摄的视频'),
                      value: _config.backupVideos,
                      onChanged: _config.enabled ? (value) => _updateConfig(backupVideos: value) : null,
                    ),
                  ],
                ),

                // 条件设置
                _buildSection(
                  title: '备份条件',
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.wifi_outlined),
                      title: const Text('仅在 WiFi 下备份'),
                      subtitle: const Text('移动网络下不执行备份'),
                      value: _config.wifiOnly,
                      onChanged: _config.enabled ? (value) => _updateConfig(wifiOnly: value) : null,
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.battery_charging_full_outlined),
                      title: const Text('仅在充电时备份'),
                      subtitle: const Text('电量消耗更低'),
                      value: _config.chargingOnly,
                      onChanged: _config.enabled ? (value) => _updateConfig(chargingOnly: value) : null,
                    ),
                  ],
                ),

                // 定时设置
                _buildSection(
                  title: '定时备份',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.schedule_outlined),
                      title: const Text('备份时间'),
                      subtitle: Text(
                        '每天 ${_config.backupHour.toString().padLeft(2, '0')}:${_config.backupMinute.toString().padLeft(2, '0')} 自动备份',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _config.enabled ? () => _pickBackupTime() : null,
                    ),
                  ],
                ),

                // 手动操作
                _buildSection(
                  title: '手动操作',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.cloud_upload_outlined),
                      title: const Text('立即备份'),
                      subtitle: const Text('手动触发一次备份'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _triggerBackup(),
                    ),
                    ListTile(
                      leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                      title: Text('清除备份记录', style: TextStyle(color: theme.colorScheme.error)),
                      subtitle: const Text('清除后所有照片将重新备份'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _clearRecords(),
                    ),
                  ],
                ),

                // 说明
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                '使用说明',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '• 开启后，应用会在后台自动检测新照片并上传到云端\n'
                            '• 照片将备份到「我的文件 / DCIM / Camera」目录\n'
                            '• 可设置仅在 WiFi 或充电时备份以节省流量和电量\n'
                            '• 定时备份会在指定时间自动检查并备份新照片',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildStatusCard(ThemeData theme) {
    final isRunning = AutoBackupService.instance.isBackingUp;
    final uploadedCount = AutoBackupForegroundService.uploadedCount;
    final currentFile = AutoBackupForegroundService.currentFile;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            theme.colorScheme.tertiaryContainer.withValues(alpha: 0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // 状态图标和文字
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _config.enabled
                      ? Colors.green.withValues(alpha: 0.1)
                      : theme.colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _config.enabled ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                  size: 32,
                  color: _config.enabled ? Colors.green : theme.hintColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _config.enabled ? '自动备份已开启' : '自动备份已关闭',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_lastBackupTime != null) ...[
            const SizedBox(height: 4),
            Text(
              '上次备份: ${_formatTime(_lastBackupTime!)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
          ],
          if (isRunning) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: AutoBackupForegroundService.currentProgress,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 8),
            Text(
              currentFile.isNotEmpty ? '正在备份: $currentFile' : '正在备份...',
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ] else if (uploadedCount > 0 && _config.enabled) ...[
            const SizedBox(height: 8),
            Text(
              '本次已备份 $uploadedCount 张',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.green,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: children),
        ),
      ],
    );
  }

  Future<void> _toggleEnabled(bool value) async {
    if (value) {
      // 开启前检查权限
      final hasPermission = await _checkPermissions();
      if (!hasPermission) return;
    }

    setState(() {
      _config = _config.copyWith(enabled: value);
    });

    await AutoBackupService.instance.updateConfig(_config);

    if (mounted) {
      ToastHelper.success(value ? '自动备份已开启' : '自动备份已关闭');
    }
  }

  Future<bool> _checkPermissions() async {
    if (!Platform.isAndroid) return true;

    final photosStatus = await Permission.photos.status;
    final videosStatus = await Permission.videos.status;

    if (!photosStatus.isGranted || !videosStatus.isGranted) {
      final results = await [
        Permission.photos,
        Permission.videos,
      ].request();

      if (!results[Permission.photos]!.isGranted ||
          !results[Permission.videos]!.isGranted) {
        if (mounted) {
          ToastHelper.failure('需要相册和视频权限才能备份');
          final shouldOpen = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('权限不足'),
              content: const Text('自动备份需要访问照片和视频的权限，请在系统设置中开启。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('去设置'),
                ),
              ],
            ),
          );
          if (shouldOpen == true) {
            await openAppSettings();
          }
        }
        return false;
      }
    }

    return true;
  }

  Future<void> _updateConfig({
    bool? wifiOnly,
    bool? chargingOnly,
    bool? backupPhotos,
    bool? backupVideos,
    int? backupHour,
    int? backupMinute,
  }) async {
    setState(() {
      _config = _config.copyWith(
        wifiOnly: wifiOnly,
        chargingOnly: chargingOnly,
        backupPhotos: backupPhotos,
        backupVideos: backupVideos,
        backupHour: backupHour,
        backupMinute: backupMinute,
      );
    });

    await AutoBackupService.instance.updateConfig(_config);
  }

  Future<void> _pickBackupTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _config.backupHour,
        minute: _config.backupMinute,
      ),
    );

    if (time != null) {
      await _updateConfig(
        backupHour: time.hour,
        backupMinute: time.minute,
      );
    }
  }

  Future<void> _triggerBackup() async {
    final hasPermission = await _checkPermissions();
    if (!hasPermission) return;

    ToastHelper.info('开始备份...');

    try {
      await AutoBackupService.instance.triggerBackup();
      if (mounted) {
        ToastHelper.success('备份完成');
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.failure('备份失败: $e');
      }
    }
  }

  Future<void> _clearRecords() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除备份记录'),
        content: const Text('确定要清除所有备份记录吗？清除后所有照片将重新备份。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AutoBackupService.instance.clearBackedUpRecords();
      if (mounted) {
        ToastHelper.success('备份记录已清除');
      }
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) {
      return '刚刚';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes} 分钟前';
    } else if (diff.inDays < 1) {
      return '${diff.inHours} 小时前';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} 天前';
    } else {
      return '${time.month}月${time.day}日 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}
