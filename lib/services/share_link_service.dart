import 'package:dio/dio.dart';

import 'api_service.dart';
import '../core/utils/file_utils.dart';

class ShareLinkCandidate {
  final String id;
  final String url;
  final String? password;

  const ShareLinkCandidate({
    required this.id,
    required this.url,
    this.password,
  });
}

class ShareLinkInfo {
  final String id;
  final String name;
  final int visited;
  final bool expired;
  final bool unlocked;
  final bool isPrivate;
  final int sourceType;
  final String? sourceUri;
  final int size;
  final String? url;
  final String? ownerName;
  final String? ownerId;
  final String? ownerAvatar;
  final String? contextHint;
  final DateTime? createdAt;
  final DateTime? expires;

  const ShareLinkInfo({
    required this.id,
    required this.name,
    required this.visited,
    required this.expired,
    required this.unlocked,
    required this.isPrivate,
    required this.sourceType,
    this.sourceUri,
    this.size = 0,
    this.url,
    this.ownerName,
    this.ownerId,
    this.ownerAvatar,
    this.contextHint,
    this.createdAt,
    this.expires,
  });

  bool get isFolder => sourceType == 1;
  bool get isFile => !isFolder;

  factory ShareLinkInfo.fromJson(Map<String, dynamic> json) {
    final owner = _asMap(json['owner']);
    final source = _asMap(json['source']);
    final file = _asMap(json['file']);
    final object = _asMap(json['object']);
    final entity = _asMap(json['entity']);
    final rawSource = json['source'];

    final ownerId = (owner?['id'] ??
            json['owner_id'] ??
            json['ownerId'] ??
            source?['owner_id'] ??
            file?['owner_id'])
        ?.toString();

    final name = (json['name'] ??
            file?['name'] ??
            source?['name'] ??
            object?['name'] ??
            '分享文件')
        .toString();

    final parsedSourceUri = (json['source_uri'] ??
            json['sourceUri'] ??
            json['uri'] ??
            json['path'] ??
            (rawSource is String ? rawSource : null) ??
            source?['uri'] ??
            source?['source_uri'] ??
            source?['path'] ??
            source?['url'] ??
            file?['uri'] ??
            file?['source_uri'] ??
            file?['path'] ??
            object?['uri'] ??
            object?['source_uri'] ??
            object?['path'] ??
            entity?['uri'] ??
            entity?['source_uri'] ??
            entity?['path'])
        ?.toString();

    final resolvedSourceUri = _looksLikeCloudreveUri(parsedSourceUri)
        ? parsedSourceUri
        : _fallbackSourceUri(ownerId: ownerId, name: name);

    final size = _asInt(json['size'] ??
        json['source_size'] ??
        json['sourceSize'] ??
        source?['size'] ??
        file?['size'] ??
        object?['size'] ??
        entity?['size']);

    return ShareLinkInfo(
      id: json['id']?.toString() ?? '',
      name: name,
      size: size,
      visited: _asInt(json['visited']),
      expired: json['expired'] as bool? ?? false,
      unlocked: json['unlocked'] as bool? ?? false,
      isPrivate: json['is_private'] as bool? ?? false,
      sourceType: _asInt(json['source_type'] ??
          source?['type'] ??
          file?['type'] ??
          object?['type']),
      sourceUri: resolvedSourceUri,
      url: json['url']?.toString(),
      ownerName: owner?['nickname']?.toString() ??
          owner?['name']?.toString() ??
          json['owner_name']?.toString(),
      ownerId: ownerId,
      ownerAvatar: owner?['avatar']?.toString(),
      contextHint: json['context_hint']?.toString() ??
          json['contextHint']?.toString() ??
          json['context']?.toString(),
      createdAt: _parseDate(json['created_at']),
      expires: _parseDate(json['expires']),
    );
  }

  static bool _looksLikeCloudreveUri(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    return value.trim().startsWith('cloudreve://');
  }

  static String? _fallbackSourceUri({
    required String? ownerId,
    required String name,
  }) {
    // 不再用 owner@my 兜底。公开分享上下文不是当前账号的 my 文件系统，
    // 用 owner@my 会导致 /file/url 返回 40081 或空 urls。
    // 真正的兜底由 ShareLinkService.getShareInfo 根据分享 ID 构造
    // cloudreve://<shareId>@share/ 完成。
    return null;
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime? _parseDate(dynamic value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }
}

class ShareLinkFile {
  final int type;
  final String id;
  final String name;
  final int size;
  final String path;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? primaryEntity;
  final String? capability;
  final String? contextHint;
  final Map<String, dynamic>? metadata;

  const ShareLinkFile({
    required this.type,
    required this.id,
    required this.name,
    required this.size,
    required this.path,
    this.createdAt,
    this.updatedAt,
    this.primaryEntity,
    this.capability,
    this.contextHint,
    this.metadata,
  });

  bool get isFolder => type == 1;
  bool get isFile => !isFolder;

  factory ShareLinkFile.fromJson(Map<String, dynamic> json) {
    return ShareLinkFile(
      type: _asInt(json['type']),
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名文件',
      size: _asInt(json['size']),
      path: json['path']?.toString() ?? '',
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
      primaryEntity: json['primary_entity']?.toString() ??
          json['entity']?.toString(),
      capability: json['capability']?.toString(),
      contextHint: json['context_hint']?.toString(),
      metadata: _asMap(json['metadata']),
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime? _parseDate(dynamic value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }
}

class ShareLinkFileListResult {
  final List<ShareLinkFile> files;
  final ShareLinkFile? parent;
  final String? contextHint;
  final bool hasMore;
  final String? nextPageToken;

  const ShareLinkFileListResult({
    required this.files,
    this.parent,
    this.contextHint,
    this.hasMore = false,
    this.nextPageToken,
  });

  factory ShareLinkFileListResult.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'];
    final rawParent = json['parent'];
    final pagination = ShareLinkService._asMap(json['pagination']);

    return ShareLinkFileListResult(
      files: rawFiles is List
          ? rawFiles
              .whereType<Map>()
              .map((item) => ShareLinkFile.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
      parent: rawParent is Map
          ? ShareLinkFile.fromJson(Map<String, dynamic>.from(rawParent))
          : null,
      contextHint: json['context_hint']?.toString(),
      hasMore: pagination?['next_token'] != null,
      nextPageToken: pagination?['next_token']?.toString(),
    );
  }
}

class ShareDownloadUrlResult {
  final String url;
  final DateTime? expires;

  const ShareDownloadUrlResult({
    required this.url,
    this.expires,
  });
}

class ShareLinkService {
  ShareLinkService._();

  static final ShareLinkService instance = ShareLinkService._();

  /// 兼容当前站点固定域名，也兼容用户自定义 Cloudreve 域名的 /s/{id}/{password?} 分享链接。
  static final RegExp _shareLinkRegExp = RegExp(
    r'https?://[^\s]+?/s/([A-Za-z0-9_-]+)(?:/([A-Za-z0-9_-]+))?',
    caseSensitive: false,
  );

  ShareLinkCandidate? parseShareLink(String? text) {
    if (text == null || text.trim().isEmpty) return null;

    final match = _shareLinkRegExp.firstMatch(text.trim());
    if (match == null) return null;

    final id = match.group(1);
    if (id == null || id.isEmpty) return null;

    final password = match.group(2);
    final url = match.group(0)!;

    return ShareLinkCandidate(
      id: id,
      url: url,
      password: password == null || password.isEmpty ? null : password,
    );
  }

  Future<ShareLinkInfo> getShareInfo(
    ShareLinkCandidate candidate, {
    String? password,
  }) async {
    final resolvedPassword = password ?? candidate.password;
    final query = <String, dynamic>{
      'count_views': true,
      'owner_extended': true,
      if (resolvedPassword != null && resolvedPassword.isNotEmpty)
        'password': resolvedPassword,
    };

    final response = await ApiService.instance.dio.get<Map<String, dynamic>>(
      '/share/info/${candidate.id}',
      queryParameters: query,
      options: Options(
        extra: const {'noAuth': true},
        headers: const {
          'X-Cr-Context-Hint': 'share',
        },
      ),
    );

    final body = response.data ?? <String, dynamic>{};
    final data = _asMap(body['data']) ?? body;
    final headerContext = _headerValue(response.headers, 'X-Cr-Context-Hint');
    final sourceType = ShareLinkInfo._asInt(data['source_type']);

    // 公开分享页面访问文件时，必须使用 Cloudreve 官方 share 文件系统 URI，
    // 即 cloudreve://{shareId}[:password]@share[/...]。
    // /share/info 返回的 source_uri 往往是所有者 my 文件系统里的真实路径，
    // 匿名/noAuth 场景拿它直接请求 /file/url 会被服务端按普通文件解析，
    // 进而返回 40081 Entity not exist。
    final accessUri = shareRootUri(
      shareId: candidate.id,
      password: resolvedPassword,
      trailingSlash: sourceType != 0,
    );

    return ShareLinkInfo.fromJson(<String, dynamic>{
      ...data,
      'source_uri': accessUri,
      if ((data['context_hint'] == null || data['context_hint'].toString().isEmpty) &&
          headerContext != null &&
          headerContext.isNotEmpty)
        'context_hint': headerContext,
    });
  }

  String? ownerAvatarUrl(ShareLinkInfo info) {
    final ownerId = info.ownerId;
    if (ownerId == null || ownerId.isEmpty) return null;

    final avatar = info.ownerAvatar;
    if (avatar != null && avatar.startsWith(RegExp(r'https?://'))) {
      return avatar;
    }

    final base = ApiService.instance.dio.options.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return '$base/user/avatar/${Uri.encodeComponent(ownerId)}';
  }

  /// 按分享的 source_uri 读取目录文件。
  ///
  /// Cloudreve V4 的 /file 接口支持 JWT Optional，并通过 X-Cr-Context-Hint
  /// 绑定分享上下文。首次读取时用 `share`，服务端返回 context_hint 后，后续下载
  /// 和进入子目录都继续携带该 context_hint。
  Future<ShareLinkFileListResult> listSharedFiles({
    required String uri,
    String? contextHint,
    int page = 0,
    int pageSize = 100,
    String? nextPageToken,
  }) async {
    final response = await ApiService.instance.dio.get<Map<String, dynamic>>(
      '/file',
      queryParameters: <String, dynamic>{
        'uri': uri,
        'page': page,
        'page_size': pageSize,
        if (nextPageToken != null && nextPageToken.isNotEmpty)
          'next_page_token': nextPageToken,
      },
      options: Options(
        extra: const {'noAuth': true},
        headers: <String, dynamic>{
          'X-Cr-Context-Hint': _firstContextHint(contextHint),
        },
      ),
    );

    final body = response.data ?? <String, dynamic>{};
    final data = _asMap(body['data']) ?? body;
    final headerContext = _headerValue(response.headers, 'X-Cr-Context-Hint');
    return ShareLinkFileListResult.fromJson(<String, dynamic>{
      ...data,
      if ((data['context_hint'] == null || data['context_hint'].toString().isEmpty) &&
          headerContext != null &&
          headerContext.isNotEmpty)
        'context_hint': headerContext,
    });
  }

  /// 读取分享上下文中文件详情，主要用于拿到 primary_entity。
  Future<ShareLinkFile> getSharedFileInfo({
    required String uri,
    String? contextHint,
    String? shareId,
    String? password,
  }) async {
    Object? lastError;

    for (final hint in _contextHintCandidates(contextHint, shareId: shareId)) {
      try {
        final response = await ApiService.instance.dio.get<Map<String, dynamic>>(
          '/file/info',
          queryParameters: <String, dynamic>{
            'uri': uri,
            'extended': true,
          },
          options: Options(
            extra: const {'noAuth': true},
            headers: <String, dynamic>{
              'X-Cr-Context-Hint': hint,
            },
          ),
        );

        final body = response.data ?? <String, dynamic>{};
        final data = _asMap(body['data']) ?? body;
        final headerContext = _headerValue(response.headers, 'X-Cr-Context-Hint');
        return ShareLinkFile.fromJson(<String, dynamic>{
          ...data,
          'context_hint': data['context_hint'] ?? headerContext ?? hint,
        });
      } catch (e) {
        lastError = e;
      }
    }

    throw lastError ?? Exception('文件详情读取失败');
  }

  ShareLinkFile fileFromShareInfo(ShareLinkInfo info) {
    final sourceUri = info.sourceUri ??
        ShareLinkInfo._fallbackSourceUri(
          ownerId: info.ownerId,
          name: info.name,
        ) ??
        '';
    return ShareLinkFile(
      type: info.sourceType,
      id: info.id,
      name: info.name,
      size: info.size,
      path: sourceUri,
      createdAt: info.createdAt,
      updatedAt: info.createdAt,
      contextHint: info.contextHint,
    );
  }

  /// 获取分享上下文中的下载 URL。
  ///
  /// 按 Cloudreve V4 官方 `/file/url` 方式创建临时下载链接：
  /// body 只提交 `uris`，文件夹批量下载时提交 `archive: true`；
  /// 分享访问走 JWT Optional，因此这里使用 noAuth，避免当前登录用户的
  /// Authorization 影响分享上下文。
  Future<ShareDownloadUrlResult> createShareDownloadUrl({
    required String uri,
    String? contextHint,
    String? shareId,
    String? password,
    String? entity,
    String? fileName,
    bool archive = false,
  }) async {
    Object? lastError;

    // Cloudreve V4 官方接口：POST /file/url
    // Header: X-Cr-Context-Hint
    // Body: { "uris": [...], "archive": true? }
    //
    // 分享下载必须不带当前账号 token；否则服务端可能按当前账号解析 URI，
    // 出现 Entity not exist (40081)。
    for (final candidateUri in _uriCandidates(
      uri,
      shareId: shareId,
      password: password,
      fileName: fileName,
    )) {
      for (final hint in _contextHintCandidates(contextHint, shareId: shareId)) {
        try {
          return await _createShareDownloadUrlOnce(
            uri: candidateUri,
            contextHint: hint,
            archive: archive,
          );
        } catch (e) {
          lastError = e;
        }
      }
    }

    throw lastError ?? Exception('服务端没有返回可用的下载链接');
  }

  Future<ShareDownloadUrlResult> _createShareDownloadUrlOnce({
    required String uri,
    required String contextHint,
    bool archive = false,
  }) async {
    final body = <String, dynamic>{
      'uris': <String>[uri],
      'download': true,
      if (archive) 'archive': true,
    };

    final response = await ApiService.instance.dio.post<Map<String, dynamic>>(
      '/file/url',
      data: body,
      options: Options(
        extra: const {'noAuth': true},
        headers: <String, dynamic>{
          'Content-Type': 'application/json',
          'X-Cr-Context-Hint': contextHint,
        },
      ),
    );

    final raw = response.data ?? <String, dynamic>{};
    final data = _asMap(raw['data']) ?? raw;
    final url = _extractDownloadUrl(data) ?? _extractDownloadUrl(raw);
    if (url != null && url.isNotEmpty) {
      return ShareDownloadUrlResult(
        url: url,
        expires: ShareLinkInfo._parseDate(data['expires'] ?? raw['expires']),
      );
    }

    throw Exception('服务端没有返回可用的下载链接');
  }

  /// 将分享文件转存到当前用户网盘。
  ///
  /// Cloudreve V4 使用 /file/move，同一接口可移动/复制文件；传入 copy=true
  /// 时即为转存/复制到目标目录。
  Future<void> saveSharedFiles({
    required List<String> uris,
    required String destination,
    String? contextHint,
    String? shareId,
    String? password,
    String? fileName,
  }) async {
    final dst = FileUtils.toCloudreveUri(destination);
    Object? lastError;

    final uriCandidateSets = uris
        .map((uri) => _uriCandidates(
              uri,
              shareId: shareId,
              password: password,
              // 单文件分享的 source_uri 是 cloudreve://{id}@share 根。
              // /file/move 不允许复制 share 根目录，因此需要优先尝试
              // cloudreve://{id}@share/{fileName}，并过滤掉根 URI。
              fileName: uris.length == 1 ? fileName : null,
              includeRootFallback: false,
            )
                .where((candidate) => !isShareRootUri(candidate, shareId: shareId))
                .toList())
        .where((candidates) => candidates.isNotEmpty)
        .toList();

    if (uriCandidateSets.isEmpty) {
      throw Exception('不能直接转存分享根目录，请选择具体文件或进入目录后再转存');
    }

    for (final hint in _contextHintCandidates(contextHint, shareId: shareId)) {
      for (final candidateUris in _cartesianUriCandidates(uriCandidateSets)) {
        if (candidateUris.isEmpty) continue;
        try {
          await ApiService.instance.post<void>(
            '/file/move',
            data: <String, dynamic>{
              'uris': candidateUris,
              'dst': dst,
              'copy': true,
            },
            headers: <String, dynamic>{
              'Content-Type': 'application/json',
              'X-Cr-Context-Hint': hint,
            },
          );
          return;
        } catch (e) {
          lastError = e;
        }
      }
    }

    throw lastError ?? Exception('转存失败');
  }

  static List<String> _uriCandidates(
    String uri, {
    String? shareId,
    String? password,
    String? fileName,
    bool includeRootFallback = true,
  }) {
    final values = <String>[];

    void add(String? value) {
      final text = value?.trim();
      if (text != null && text.isNotEmpty && !values.contains(text)) {
        values.add(text);
      }
    }

    final shareUriCandidates = _shareScopedUriCandidates(
      uri,
      shareId: shareId,
      password: password,
    );

    // 官方页面进入的是 cloudreve://{shareId}@share 文件系统；
    // 如果 /file 返回了 cloudreve://my/... 或 owner@my/...，
    // 转存/下载时也要先折算成 share 文件系统里的相对路径。
    for (final item in shareUriCandidates) {
      add(item);
    }

    final name = fileName?.trim();
    final id = shareId?.trim();
    if (id != null && id.isNotEmpty && name != null && name.isNotEmpty) {
      final root = shareRootUri(
        shareId: id,
        password: password,
        trailingSlash: false,
      );
      add('$root/${Uri.encodeComponent(name)}');
      add('$root/${_encodeCloudrevePath(name)}');
    }

    add(_withSharePassword(uri, shareId: shareId, password: password));
    add(uri);

    if (uri.startsWith('cloudreve://')) {
      final withPassword = _withSharePassword(uri, shareId: shareId, password: password);
      if (withPassword != uri) add(withPassword);

      final slash = uri.indexOf('/', 'cloudreve://'.length);
      if (slash > 0) {
        final prefix = uri.substring(0, slash + 1);
        final path = slash < uri.length - 1 ? uri.substring(slash + 1) : '';
        if (path.isNotEmpty) {
          final encodedPath = _encodeCloudrevePath(path);
          add(_withSharePassword('$prefix$encodedPath', shareId: shareId, password: password));
          add('$prefix$encodedPath');
        }
        if (!uri.endsWith('/')) {
          add(_withSharePassword('$uri/', shareId: shareId, password: password));
          add('$uri/');
        }
      }
    }

    if (includeRootFallback && shareId != null && shareId.trim().isNotEmpty) {
      add(shareRootUri(shareId: shareId, password: password, trailingSlash: true));
      add(shareRootUri(shareId: shareId, password: password, trailingSlash: false));
    }

    return values;
  }

  static List<String> _shareScopedUriCandidates(
    String uri, {
    String? shareId,
    String? password,
  }) {
    final id = shareId?.trim();
    if (id == null || id.isEmpty || !uri.startsWith('cloudreve://')) {
      return const <String>[];
    }

    final values = <String>[];
    void add(String? value) {
      final text = value?.trim();
      if (text != null && text.isNotEmpty && !values.contains(text)) {
        values.add(text);
      }
    }

    final authorityStart = 'cloudreve://'.length;
    final slash = uri.indexOf('/', authorityStart);
    final authority = slash >= 0 ? uri.substring(authorityStart, slash) : uri.substring(authorityStart);
    final rawPath = slash >= 0 && slash < uri.length - 1 ? uri.substring(slash + 1) : '';
    final decodedPath = rawPath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map((segment) => Uri.decodeComponent(segment))
        .join('/');

    final isShareAuthority = authority.endsWith('@share');
    if (isShareAuthority) {
      add(_withSharePassword(uri, shareId: id, password: password));
      add(uri);
      return values;
    }

    if (decodedPath.isEmpty) return values;

    final pathParts = decodedPath.split('/').where((e) => e.isNotEmpty).toList();
    final root = shareRootUri(shareId: id, password: password, trailingSlash: false);

    // 完整路径候选：cloudreve://id@share/folder/file.ext
    add('$root/${_encodeCloudrevePath(decodedPath)}');

    // 单文件分享或列表返回 owner 的 my 路径时，官方 share 根目录下通常就是文件本身，
    // 因此还要尝试 basename 候选：cloudreve://id@share/file.ext
    if (pathParts.isNotEmpty) {
      add('$root/${Uri.encodeComponent(pathParts.last)}');
    }

    // 如果原 path 形如 Folder/Sub/File，分享根可能是 Folder，子项在 share 中应为 Sub/File。
    if (pathParts.length > 1) {
      final withoutFirst = pathParts.skip(1).join('/');
      add('$root/${_encodeCloudrevePath(withoutFirst)}');
    }

    return values;
  }

  static String _encodeCloudrevePath(String path) {
    return path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map((segment) => Uri.encodeComponent(Uri.decodeComponent(segment)))
        .join('/');
  }

  static String _withSharePassword(String uri, {String? shareId, String? password}) {
    final pw = password?.trim();
    final id = shareId?.trim();
    if (pw == null || pw.isEmpty || id == null || id.isEmpty) return uri;
    if (!uri.startsWith('cloudreve://')) return uri;

    final authorityStart = 'cloudreve://'.length;
    final slash = uri.indexOf('/', authorityStart);
    final authority = slash >= 0 ? uri.substring(authorityStart, slash) : uri.substring(authorityStart);
    final rest = slash >= 0 ? uri.substring(slash) : '';
    if (!authority.endsWith('@share')) return uri;
    if (authority.contains(':')) return uri;

    final encodedId = Uri.encodeComponent(id);
    final encodedPw = Uri.encodeComponent(pw);
    if (authority != '$encodedId@share' && authority != '$id@share') return uri;
    return 'cloudreve://$encodedId:$encodedPw@share$rest';
  }

  static String shareRootUri({
    required String shareId,
    String? password,
    bool trailingSlash = true,
  }) {
    final id = Uri.encodeComponent(shareId.trim());
    final pw = password?.trim();
    final userInfo = pw == null || pw.isEmpty
        ? id
        : '$id:${Uri.encodeComponent(pw)}';
    return 'cloudreve://$userInfo@share${trailingSlash ? '/' : ''}';
  }

  static bool isShareRootUri(String uri, {String? shareId}) {
    final text = uri.trim();
    const prefix = 'cloudreve://';
    if (!text.startsWith(prefix)) return false;

    final authorityStart = prefix.length;
    final slash = text.indexOf('/', authorityStart);
    final authority = slash >= 0
        ? text.substring(authorityStart, slash)
        : text.substring(authorityStart);
    if (!authority.endsWith('@share')) return false;

    final path = slash >= 0 ? text.substring(slash) : '';
    if (path.isNotEmpty && path != '/') return false;

    final expectedId = shareId?.trim();
    if (expectedId == null || expectedId.isEmpty) return true;

    final userInfo = authority.substring(0, authority.length - '@share'.length);
    final rawId = userInfo.split(':').first;
    return Uri.decodeComponent(rawId) == expectedId || rawId == expectedId;
  }


  static String? _extractDownloadUrl(Map<String, dynamic> data) {
    final direct = data['url'] ??
        data['download_url'] ??
        data['downloadUrl'] ??
        data['src'] ??
        data['href'];
    if (direct is String && direct.trim().isNotEmpty) return direct.trim();

    final rawUrls = data['urls'];
    if (rawUrls is String && rawUrls.trim().isNotEmpty) return rawUrls.trim();
    if (rawUrls is List) {
      for (final item in rawUrls) {
        if (item is String && item.trim().isNotEmpty) return item.trim();
        final map = _asMap(item);
        if (map == null) continue;
        final url = _extractDownloadUrl(map);
        if (url != null && url.isNotEmpty) return url;
      }
    }
    if (rawUrls is Map) {
      for (final item in rawUrls.values) {
        if (item is String && item.trim().isNotEmpty) return item.trim();
        final map = _asMap(item);
        if (map == null) continue;
        final url = _extractDownloadUrl(map);
        if (url != null && url.isNotEmpty) return url;
      }
    }
    return null;
  }

  static List<List<String>> _cartesianUriCandidates(List<List<String>> sets) {
    if (sets.isEmpty) return const [[]];

    var result = <List<String>>[const []];
    for (final set in sets) {
      final next = <List<String>>[];
      for (final prefix in result) {
        for (final item in set) {
          next.add(<String>[...prefix, item]);
        }
      }
      result = next;
    }
    return result;
  }

  static String _firstContextHint(String? contextHint) {
    final value = contextHint?.trim();
    return value == null || value.isEmpty ? 'share' : value;
  }

  static List<String> _contextHintCandidates(String? contextHint, {String? shareId}) {
    final values = <String>[];
    void add(String? value) {
      final text = value?.trim();
      if (text != null && text.isNotEmpty && !values.contains(text)) {
        values.add(text);
      }
    }

    add(contextHint);
    add(shareId);
    if (shareId != null && shareId.trim().isNotEmpty) {
      add('share:${shareId.trim()}');
      add('share_${shareId.trim()}');
    }
    add('share');
    return values;
  }

  static String? _headerValue(Headers headers, String name) {
    final direct = headers.value(name) ?? headers.value(name.toLowerCase());
    if (direct != null && direct.isNotEmpty) return direct;

    final lower = name.toLowerCase();
    for (final entry in headers.map.entries) {
      if (entry.key.toLowerCase() == lower && entry.value.isNotEmpty) {
        return entry.value.first;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }
}
