import 'dart:async';

/// 全局弹窗队列。
///
/// 用于登录后自动弹出的公告、更新、剪贴板分享链接等场景，保证同一时间
/// 只有一个弹窗/引导流程在前台显示。前一个流程结束后，后一个流程才会执行。
class DialogQueueService {
  DialogQueueService._();

  static final DialogQueueService instance = DialogQueueService._();

  Future<void> _tail = Future<void>.value();

  Future<T?> enqueue<T>(Future<T?> Function() task) {
    final completer = Completer<T?>();

    _tail = _tail.catchError((_) {}).then((_) async {
      try {
        final result = await task();
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    });

    return completer.future;
  }
}
