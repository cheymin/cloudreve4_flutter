import 'package:dio/dio.dart';
import 'api_service.dart';
import '../core/exceptions/app_exception.dart';
import '../data/models/share_model.dart';
import '../core/utils/app_logger.dart';

/// 分享授权对象类型。
enum SharePrincipalType { user, group }

/// 分享弹窗中搜索并加入的用户/用户组。
class SharePrincipal {
  final String id;
  final String name;
  final String? email;
  final String? groupName;
  final SharePrincipalType type;

  const SharePrincipal({
    required this.id,
    required this.name,
    required this.type,
    this.email,
    this.groupName,
  });

  factory SharePrincipal.userFromJson(Map<String, dynamic> json) {
    final group = _asMap(json['group']);
    return SharePrincipal(
      id: json['id']?.toString() ?? '',
      name: (json['nickname'] ?? json['email'] ?? json['id'] ?? '用户').toString(),
      email: json['email']?.toString(),
      groupName: group?['name']?.toString(),
      type: SharePrincipalType.user,
    );
  }

  factory SharePrincipal.groupFromJson(Map<String, dynamic> json) {
    return SharePrincipal(
      id: json['id']?.toString() ?? '',
      name: (json['name'] ?? json['id'] ?? '用户组').toString(),
      type: SharePrincipalType.group,
    );
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }
}

/// 分享服务
class ShareService {
  /// 将文件系统路径转换为 cloudreve URI 格式
  String _toCloudreveUri(String path) {
    if (path.startsWith('cloudreve://')) {
      return path;
    }

    if (path == '/' || path.isEmpty) {
      return 'cloudreve://my';
    }
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return 'cloudreve://my/$cleanPath';
  }

  /// 创建分享链接。
  ///
  /// Cloudreve V4 接口为 PUT /share，核心字段包括 permissions、uri、
  /// is_private、share_view、expire、price、password、show_readme。
  Future<String> createShare({
    required String uri,
    Map<String, dynamic>? permissions,
    bool? isPrivate,
    bool? shareView,
    int? expire,
    int? downloads,
    int? price,
    String? password,
    bool? showReadme,
  }) async {
    final data = <String, dynamic>{
      'permissions': permissions ?? {'anonymous': 'BQ==', 'everyone': 'AQ=='},
      'uri': _toCloudreveUri(uri),
    };

    if (isPrivate != null) data['is_private'] = isPrivate;
    if (shareView != null) data['share_view'] = shareView;
    if (expire != null) data['expire'] = expire;
    if (downloads != null) data['downloads'] = downloads;
    if (price != null) data['price'] = price;
    if (password != null && password.isNotEmpty) data['password'] = password;
    if (showReadme != null) data['show_readme'] = showReadme;

    final response = await ApiService.instance.put<Map<String, dynamic>>(
      '/share',
      data: data,
      isNoData: true,
    );
    final raw = response['data'];
    return raw?.toString() ?? '';
  }

  /// 搜索用户，用于分享权限显式授权。
  Future<List<SharePrincipal>> searchUsers(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return const [];

    final response = await ApiService.instance.get<dynamic>(
      '/user/search',
      queryParameters: {'keyword': trimmed},
    );

    return _extractList(response)
        .whereType<Map>()
        .map((e) => SharePrincipal.userFromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id.isNotEmpty)
        .toList();
  }

  /// 列出用户组，用于分享权限显式授权。
  ///
  /// Cloudreve Pro 才支持 /group/list，非 Pro 或无权限时返回 null。
  /// 调用方据此决定是否提示用户。
  Future<List<SharePrincipal>?> listGroups() async {
    try {
      final response = await ApiService.instance.get<dynamic>(
        '/group/list',
        silent404: true,
      );

      return _extractList(response)
          .whereType<Map>()
          .map((e) => SharePrincipal.groupFromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty)
          .toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    } on AppException catch (e) {
      if (e.code == 404) return null;
      rethrow;
    }
  }

  List<dynamic> _extractList(dynamic value) {
    if (value is List) return value;
    if (value is Map) {
      final data = value['data'];
      if (data is List) return data;
      final items = value['items'];
      if (items is List) return items;
      final groups = value['groups'];
      if (groups is List) return groups;
      final users = value['users'];
      if (users is List) return users;
    }
    return const [];
  }

  /// 获取我的分享列表
  Future<Map<String, dynamic>> listShares({
    required int pageSize,
    String? orderBy,
    String? orderDirection,
    String? nextPageToken,
  }) async {
    final queryParams = <String, dynamic>{
      'page_size': pageSize,
    };
    if (orderBy != null) queryParams['order_by'] = orderBy;
    if (orderDirection != null) queryParams['order_direction'] = orderDirection;
    if (nextPageToken != null) queryParams['next_page_token'] = nextPageToken;

    return await ApiService.instance.get<Map<String, dynamic>>(
      '/share',
      queryParameters: queryParams,
    );
  }

  /// 获取分享详情
  Future<ShareModel> getShareInfo({
    required String id,
    String? password,
    bool? countViews,
    bool? ownerExtended,
  }) async {
    final queryParams = <String, dynamic>{};
    if (password != null) queryParams['password'] = password;
    if (countViews != null) queryParams['count_views'] = countViews.toString();
    if (ownerExtended != null) {
      queryParams['owner_extended'] = ownerExtended.toString();
    }
    final response = await ApiService.instance.get<Map<String, dynamic>>(
      '/share/info/$id',
      queryParameters: queryParams,
    );
    return ShareModel.fromJson(response);
  }

  /// 编辑分享
  Future<String> editShare({
    required String id,
    required String uri,
    Map<String, dynamic>? permissions,
    bool? isPrivate,
    String? password,
    bool? shareView,
    int? downloads,
    int? expire,
    int? price,
    bool? showReadme,
  }) async {
    final data = <String, dynamic>{
      'uri': uri,
    };

    if (permissions != null) data['permissions'] = permissions;
    if (isPrivate != null) data['is_private'] = isPrivate;
    if (shareView != null) data['share_view'] = shareView;
    if (downloads != null) data['downloads'] = downloads;
    if (expire != null) data['expire'] = expire;
    if (price != null) data['price'] = price;
    if (showReadme != null) data['show_readme'] = showReadme;
    if (password != null && password.isNotEmpty) {
      data['password'] = password;
    }

    AppLogger.d('editShare response ---> : response');
    final response = await ApiService.instance.post<Map<String, dynamic>>(
      '/share/$id',
      data: data,
      isNoData: true,
    );
    final raw = response['data'];
    return raw?.toString() ?? '';
  }

  /// 删除分享
  Future<void> deleteShare({required String id}) async {
    await ApiService.instance.delete<void>('/share/$id');
  }
}
