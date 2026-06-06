import 'dart:async';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../core/utils/app_logger.dart';

/// Android 自动备份前台服务：用于让相册备份在 App 退到后台时继续运行。
///
/// 功能：
/// - 后台持续监听相册变化
/// - 自动上传新照片到云端
/// - 支持仅在 WiFi 下备份
/// - 支持充电时备份
class AutoBackupForegroundService {
  static const int _serviceId = 46042;
  static const String _channelId = 'cloudreve_auto_backup_service';
  static const String _channelName = 'Cloudreve 自动备份';
  static const String _channelDescription = '自动备份手机照片到云端';

  static bool _initialized = false;
  static bool _permissionAsked = false;
  static bool _isRunning = false;

  /// 备份统计
  static int _uploadedCount = 0;
  static int _failedCount = 0;
  static String _currentFile = '';
  static double _currentProgress = 0.0;

  static bool get _supportsForegroundService => Platform.isAndroid;
  static bool get isRunning => _isRunning;
  static int get uploadedCount => _uploadedCount;
  static int get failedCount => _failedCount;
  static String get currentFile => _currentFile;
  static double get currentProgress => _currentProgress;

  /// 初始化 communication port，必须在 runApp 前调用。
  static void initCommunicationPort() {
    if (!_supportsForegroundService) return;
    FlutterForegroundTask.initCommunicationPort();
  }

  /// 初始化前台服务配置。
  static Future<void> initialize() async {
    if (!_supportsForegroundService || _initialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: _channelName,
        channelDescription: _channelDescription,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _initialized = true;
  }

  /// 启动自动备份服务
  static Future<bool> start({
    bool wifiOnly = true,
    bool chargingOnly = false,
  }) async {
    if (!_supportsForegroundService) return false;

    await initialize();
    await _requestNotificationPermissionIfNeeded();

    try {
      if (await FlutterForegroundTask.isRunningService) {
        AppLogger.d('自动备份服务已在运行');
        return true;
      }

      await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        serviceTypes: const [ForegroundServiceTypes.dataSync],
        notificationTitle: 'Cloudreve 自动备份',
        notificationText: '正在准备备份...',
        notificationInitialRoute: '/',
        callback: autoBackupForegroundTaskStartCallback,
      );

      _isRunning = true;
      _uploadedCount = 0;
      _failedCount = 0;
      AppLogger.i('自动备份服务已启动');
      return true;
    } catch (e, stackTrace) {
      AppLogger.e('启动自动备份服务失败: $e\n$stackTrace');
      return false;
    }
  }

  /// 停止自动备份服务
  static Future<void> stop() async {
    if (!_supportsForegroundService) return;

    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
      _isRunning = false;
      _currentFile = '';
      _currentProgress = 0.0;
      AppLogger.i('自动备份服务已停止');
    } catch (e) {
      AppLogger.d('停止自动备份服务失败: $e');
    }
  }

  /// 更新通知状态
  static Future<void> updateNotification({
    required String title,
    required String text,
  }) async {
    if (!_supportsForegroundService || !_isRunning) return;

    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
        );
      }
    } catch (e) {
      AppLogger.d('更新自动备份通知失败: $e');
    }
  }

  /// 更新当前备份进度
  static Future<void> updateProgress({
    required String fileName,
    required double progress,
    bool incrementUploaded = false,
    bool incrementFailed = false,
  }) async {
    _currentFile = fileName;
    _currentProgress = progress;
    if (incrementUploaded) _uploadedCount++;
    if (incrementFailed) _failedCount++;

    final percent = (progress * 100).clamp(0, 100).toStringAsFixed(0);
    await updateNotification(
      title: 'Cloudreve 正在备份',
      text: '$fileName · $percent%',
    );
  }

  /// 显示完成状态
  static Future<void> showFinished({
    int? uploaded,
    int? failed,
  }) async {
    final uploadedCount = uploaded ?? _uploadedCount;
    final failedCount = failed ?? _failedCount;

    String text;
    if (failedCount > 0) {
      text = '已备份 $uploadedCount 张，失败 $failedCount 张';
    } else {
      text = '已备份 $uploadedCount 张照片';
    }

    await updateNotification(
      title: 'Cloudreve 备份完成',
      text: text,
    );

    // 2秒后停止服务
    await Future.delayed(const Duration(seconds: 2));
    await stop();
  }

  static Future<void> _requestNotificationPermissionIfNeeded() async {
    if (_permissionAsked) return;
    _permissionAsked = true;

    try {
      final permission = await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } catch (e) {
      AppLogger.d('请求通知权限失败: $e');
    }
  }

  /// 重置统计
  static void resetStats() {
    _uploadedCount = 0;
    _failedCount = 0;
    _currentFile = '';
    _currentProgress = 0.0;
  }
}

/// flutter_foreground_task 要求 callback 必须是顶层函数或静态函数。
@pragma('vm:entry-point')
void autoBackupForegroundTaskStartCallback() {
  FlutterForegroundTask.setTaskHandler(_AutoBackupForegroundTaskHandler());
}

class _AutoBackupForegroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    AppLogger.d('Auto backup foreground task started: ${starter.name}');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 实际备份逻辑由 AutoBackupService 执行
    // 这里保持前台服务存活
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    AppLogger.d('Auto backup foreground task destroyed, isTimeout=$isTimeout');
    AutoBackupForegroundService._isRunning = false;
  }

  @override
  void onReceiveData(Object data) {
    AppLogger.d('Auto backup foreground task receive data: $data');
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }
}
