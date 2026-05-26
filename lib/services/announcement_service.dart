import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'api_service.dart';
import 'storage_service.dart';
import '../core/constants/storage_keys.dart';

class SiteAnnouncement {
  final String title;
  final String html;
  final String baseUrl;
  final String fingerprint;

  const SiteAnnouncement({
    required this.title,
    required this.html,
    required this.baseUrl,
    required this.fingerprint,
  });
}

/// 登录后公告服务。
///
/// Cloudreve V4 SiteConfig 的公告字段是 site_notice。
/// 不读取 custom_html.headless_bottom / sidebar_bottom，那些是页面装饰 HTML。
///
/// 弹窗策略：
/// - 公告为空：不弹；
/// - 当前公告内容和用户上次关闭时一致：不弹；
/// - 公告内容变化：重新弹。
class AnnouncementService {
  AnnouncementService._();

  static final AnnouncementService instance = AnnouncementService._();

  bool _shownInSession = false;

  /// 兼容旧调用。新的判断以持久化 fingerprint 为准。
  bool get hasShown => _shownInSession;

  /// 兼容旧调用。新的业务请使用 [markDismissed]。
  void markShown() {
    _shownInSession = true;
  }

  Future<SiteAnnouncement?> getSiteNotice() async {
    final response = await ApiService.instance.get<Map<String, dynamic>>(
      '/site/config/basic',
    );

    final data = _asMap(response['data']) ?? response;
    final notice = data['site_notice']?.toString().trim();

    if (notice == null || notice.isEmpty) {
      return null;
    }

    final baseUrl = ApiService.instance.dio.options.baseUrl;
    return SiteAnnouncement(
      title: '公告',
      html: notice,
      baseUrl: baseUrl,
      fingerprint: _fingerprint(baseUrl: baseUrl, html: notice),
    );
  }

  /// 只返回需要弹出的公告。
  ///
  /// 用户关闭过同一条公告后，后续启动不会重复弹；站点公告内容改变后会再次弹。
  Future<SiteAnnouncement?> getChangedSiteNotice() async {
    final notice = await getSiteNotice();
    if (notice == null) return null;

    if (_shownInSession) return null;

    final dismissedFingerprint = await StorageService.instance.getString(
      StorageKeys.siteAnnouncementDismissedFingerprint,
    );

    if (dismissedFingerprint == notice.fingerprint) {
      _shownInSession = true;
      return null;
    }

    return notice;
  }

  /// 用户关闭公告后调用。
  Future<void> markDismissed(SiteAnnouncement announcement) async {
    _shownInSession = true;
    await StorageService.instance.setString(
      StorageKeys.siteAnnouncementDismissedFingerprint,
      announcement.fingerprint,
    );
  }

  String _fingerprint({required String baseUrl, required String html}) {
    final normalized = '${baseUrl.trim()}\n${html.trim()}';
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }
}
