import 'package:dio/dio.dart';

import 'api_service.dart';
import '../core/utils/file_type_utils.dart';
import '../core/utils/file_utils.dart';
import '../data/models/file_model.dart';

class FileAppViewer {
  final String id;
  final String type;
  final String displayName;
  final List<String> exts;
  final String? icon;
  final int maxSize;
  final String? url;

  const FileAppViewer({
    required this.id,
    required this.type,
    required this.displayName,
    required this.exts,
    this.icon,
    this.maxSize = 0,
    this.url,
  });

  factory FileAppViewer.fromJson(Map<String, dynamic> json) {
    return FileAppViewer(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      displayName: json['display_name']?.toString() ??
          json['displayName']?.toString() ??
          json['name']?.toString() ??
          '文件应用',
      exts: _parseExts(json['exts'] ?? json['extensions'] ?? json['ext']),
      icon: json['icon']?.toString(),
      maxSize: (json['max_size'] as num?)?.toInt() ??
          (json['maxSize'] as num?)?.toInt() ??
          0,
      url: json['url']?.toString(),
    );
  }

  static List<String> _parseExts(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => e.toString().toLowerCase().replaceAll('.', '').trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    if (raw is String) {
      return raw
          .split(',')
          .map((e) => e.toLowerCase().replaceAll('.', '').trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return const [];
  }

  bool supports(FileModel file) {
    final ext = FileTypeUtils.getExtension(file.name).toLowerCase();
    if (ext.isEmpty || !exts.contains(ext)) return false;
    if (maxSize > 0 && file.size > maxSize) return false;
    return id.isNotEmpty;
  }

  bool get isWopi => type.toLowerCase().contains('wopi');
}

class FileAppSession {
  final FileAppViewer viewer;
  final String wopiSrc;
  final String? accessToken;
  final int? expires;

  const FileAppSession({
    required this.viewer,
    required this.wopiSrc,
    this.accessToken,
    this.expires,
  });

  bool get hasAccessToken => accessToken != null && accessToken!.isNotEmpty;
}

/// Cloudreve V4 文件应用服务。
///
/// 注意：部分 Cloudreve V4 站点没有 `/site/config`，只有 `/site/config/basic`。
/// 所以这里优先请求 `/site/config/basic`，如果没有 file_viewers 再尝试
/// `/site/config`，并且对 404 做静默降级，避免 WebView 打开器直接崩溃。
class FileAppService {
  FileAppService._();

  static final FileAppService instance = FileAppService._();

  List<FileAppViewer>? _cachedViewers;
  DateTime? _cachedAt;

  Future<List<FileAppViewer>> getViewers({bool forceRefresh = false}) async {
    final cached = _cachedViewers;
    final cachedAt = _cachedAt;
    if (!forceRefresh &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt).inMinutes < 10) {
      return cached;
    }

    final viewers = await _loadViewersFromSiteConfig();

    _cachedViewers = viewers;
    _cachedAt = DateTime.now();

    return viewers;
  }

  Future<List<FileAppViewer>> _loadViewersFromSiteConfig() async {
    // 当前项目登录验证码就是从 /site/config/basic 取的；
    // /site/config 在部分 Cloudreve 部署中不存在，会返回 404。
    const endpoints = <String>[
      '/site/config/basic',
      '/site/config',
    ];

    for (final endpoint in endpoints) {
      final root = await _tryGetSiteConfig(endpoint);
      if (root == null) continue;

      final viewers = _extractViewers(root);
      if (viewers.isNotEmpty) {
        return viewers;
      }
    }

    return const [];
  }

  Future<Map<String, dynamic>?> _tryGetSiteConfig(String endpoint) async {
    try {
      final response = await ApiService.instance.dio.get<dynamic>(
        endpoint,
        options: Options(
          extra: {'noAuth': true},
          // 404 也作为普通响应返回，由这里自己处理，避免进入全局错误拦截器。
          validateStatus: (status) => status != null && status >= 200 && status < 500,
        ),
      );

      if (response.statusCode == 404) {
        return null;
      }

      final raw = response.data;
      final map = _asMap(raw);
      if (map == null) return null;

      final code = map['code'];
      if (code is int && code != 0 && code != 203) {
        return null;
      }

      return _asMap(map['data']) ?? map;
    } catch (_) {
      return null;
    }
  }

  Future<FileAppViewer?> findViewerForFile(
    FileModel file, {
    bool forceRefresh = false,
  }) async {
    final viewers = await getViewers(forceRefresh: forceRefresh);
    final ext = FileTypeUtils.getExtension(file.name).toLowerCase();

    final candidates = viewers.where((viewer) => viewer.supports(file)).toList();
    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final aw = a.isWopi ? 0 : 1;
      final bw = b.isWopi ? 0 : 1;
      if (aw != bw) return aw.compareTo(bw);

      final aExact = a.exts.contains(ext) ? 0 : 1;
      final bExact = b.exts.contains(ext) ? 0 : 1;
      return aExact.compareTo(bExact);
    });

    return candidates.first;
  }

  Future<FileAppSession> createViewerSession({
    required FileModel file,
    required FileAppViewer viewer,
    String preferredAction = 'view',
  }) async {
    final uri = FileUtils.toCloudreveUri(file.relativePath);
    final data = <String, dynamic>{
      'uri': uri,
      'viewer_id': viewer.id,
      'preferred_action': preferredAction,
      'parent_uri': _parentUri(uri),
    };

    final response = await ApiService.instance.put<Map<String, dynamic>>(
      '/file/viewerSession',
      data: data,
    );

    final root = _asMap(response['data']) ?? response;
    final session = _asMap(root['session']);
    final wopiSrc = root['wopi_src']?.toString() ??
        root['wopiSrc']?.toString() ??
        root['url']?.toString() ??
        '';

    if (wopiSrc.isEmpty) {
      throw Exception('文件应用没有返回可打开的 URL');
    }

    return FileAppSession(
      viewer: viewer,
      wopiSrc: _absoluteUrl(wopiSrc),
      accessToken: session?['access_token']?.toString() ??
          session?['accessToken']?.toString(),
      expires: (session?['expires'] as num?)?.toInt(),
    );
  }

  Future<FileAppSession> openFile({
    required FileModel file,
    String preferredAction = 'view',
  }) async {
    final viewer = await findViewerForFile(file);
    if (viewer == null) {
      throw Exception('没有找到支持 ${FileTypeUtils.getExtension(file.name)} 的 Cloudreve 文件应用');
    }

    try {
      return await createViewerSession(
        file: file,
        viewer: viewer,
        preferredAction: preferredAction,
      );
    } catch (_) {
      if (preferredAction != 'view') {
        return createViewerSession(
          file: file,
          viewer: viewer,
          preferredAction: 'view',
        );
      }
      rethrow;
    }
  }

  List<FileAppViewer> _extractViewers(Map<String, dynamic> root) {
    final raw = _findValueByKey(root, const [
      'file_viewers',
      'fileViewers',
      'file_viewer',
      'viewers',
    ]);

    dynamic viewerList = raw;

    final rawMap = _asMap(raw);
    if (rawMap != null) {
      viewerList = rawMap['viewers'] ?? rawMap['items'] ?? rawMap['data'];
    }

    if (viewerList is! List) return const [];

    return viewerList
        .whereType<Map>()
        .map((item) => FileAppViewer.fromJson(Map<String, dynamic>.from(item)))
        .where((viewer) => viewer.id.isNotEmpty && viewer.exts.isNotEmpty)
        .toList();
  }

  dynamic _findValueByKey(dynamic value, List<String> keys) {
    if (value is Map) {
      for (final key in keys) {
        if (value.containsKey(key)) {
          return value[key];
        }
      }

      for (final child in value.values) {
        final found = _findValueByKey(child, keys);
        if (found != null) return found;
      }
    } else if (value is List) {
      for (final child in value) {
        final found = _findValueByKey(child, keys);
        if (found != null) return found;
      }
    }

    return null;
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  String _parentUri(String uri) {
    final normalized = uri.endsWith('/') ? uri.substring(0, uri.length - 1) : uri;
    final index = normalized.lastIndexOf('/');
    if (index <= 'cloudreve://my'.length) {
      return 'cloudreve://my';
    }
    return normalized.substring(0, index);
  }

  String _absoluteUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    final base = Uri.parse(ApiService.instance.dio.options.baseUrl);
    final origin = Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
    ).toString();

    if (url.startsWith('/')) {
      return '$origin$url';
    }

    return '$origin/$url';
  }
}
