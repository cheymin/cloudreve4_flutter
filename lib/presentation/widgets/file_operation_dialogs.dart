import 'package:cloudreve4_flutter/data/models/file_model.dart';
import 'package:cloudreve4_flutter/services/share_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../providers/file_manager_provider.dart';
import 'folder_picker.dart';
import 'glassmorphism_container.dart';
import 'toast_helper.dart';

/// 文件操作对话框工具类
class FileOperationDialogs {
  /// 显示创建文件夹对话框（毛玻璃风格）
  static Future<void> showCreateDialog(
    BuildContext context,
    FileManagerProvider fileManager,
  ) async {
    final controller = TextEditingController();

    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '创建文件夹',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 250),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final scaleAnim = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        ).drive(Tween(begin: 0.92, end: 1.0));
        final fadeAnim = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        ).drive(Tween(begin: 0.0, end: 1.0));
        return ScaleTransition(
          scale: scaleAnim,
          child: FadeTransition(opacity: fadeAnim, child: child),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        final screenWidth = MediaQuery.of(context).size.width;
        final dialogWidth = screenWidth >= 600 ? 400.0 : screenWidth - 48.0;
        return Center(
          child: SizedBox(
            width: dialogWidth,
            child: GlassmorphismContainer(
              borderRadius: 16,
              sigmaX: 20,
              sigmaY: 20,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDialogTitle(context, LucideIcons.folderPlus, '创建文件夹'),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                        child: TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            hintText: '文件夹名称',
                            prefixIcon: const Icon(LucideIcons.folder, size: 20),
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          autofocus: true,
                          onSubmitted: (_) => Navigator.of(context).pop(true),
                        ),
                      ),
                      _buildDialogActions(
                        context,
                        onCancel: () => Navigator.of(context).pop(false),
                        onConfirm: () => Navigator.of(context).pop(true),
                        confirmLabel: '创建',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (confirmed == true && controller.text.isNotEmpty) {
      final error = await fileManager.createFolder(controller.text);
      if (error != null && context.mounted) {
        ToastHelper.failure('创建文件夹失败: $error');
      } else if (context.mounted) {
        ToastHelper.success('文件夹创建成功');
      }
    }
  }

  /// 显示重命名对话框（毛玻璃风格）
  static Future<void> showRenameDialog(
    BuildContext context,
    FileManagerProvider fileManager,
    FileModel file,
  ) async {
    final controller = TextEditingController(text: file.name);

    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '重命名',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 250),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final scaleAnim = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        ).drive(Tween(begin: 0.92, end: 1.0));
        final fadeAnim = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        ).drive(Tween(begin: 0.0, end: 1.0));
        return ScaleTransition(
          scale: scaleAnim,
          child: FadeTransition(opacity: fadeAnim, child: child),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        final screenWidth = MediaQuery.of(context).size.width;
        final dialogWidth = screenWidth >= 600 ? 400.0 : screenWidth - 48.0;

        return Center(
          child: SizedBox(
            width: dialogWidth,
            child: GlassmorphismContainer(
              borderRadius: 16,
              sigmaX: 20,
              sigmaY: 20,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDialogTitle(context, LucideIcons.pencil, '重命名'),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                        child: TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            hintText: '新名称',
                            prefixIcon: const Icon(LucideIcons.edit3, size: 20),
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          autofocus: true,
                          onSubmitted: (_) => Navigator.of(context).pop(true),
                        ),
                      ),
                      _buildDialogActions(
                        context,
                        onCancel: () => Navigator.of(context).pop(false),
                        onConfirm: () => Navigator.of(context).pop(true),
                        confirmLabel: '确定',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (confirmed == true && controller.text.isNotEmpty) {
      await fileManager.renameFile(file.path, controller.text);
    }
  }

  /// 显示删除确认对话框（多个文件，毛玻璃风格）
  static Future<void> showDeleteConfirmation(
    BuildContext context,
    FileManagerProvider fileManager,
    List<String> filePaths,
  ) async {
    final confirmed = await _showConfirmDialog(
      context,
      icon: LucideIcons.trash2,
      title: '删除确认',
      message: '确定删除这 ${filePaths.length} 个文件吗？',
      confirmLabel: '删除',
      isDestructive: true,
    );

    if (confirmed == true) {
      final error = await fileManager.deleteSelectedFiles();
      if (error != null && context.mounted) {
        ToastHelper.failure('删除失败: $error');
      } else if (context.mounted) {
        ToastHelper.success('删除成功');
      }
    }
  }

  /// 显示删除确认对话框（单个文件，毛玻璃风格）
  static Future<void> showDeleteSingleConfirmation(
    BuildContext context,
    FileManagerProvider fileManager,
    FileModel file,
  ) async {
    final confirmed = await _showConfirmDialog(
      context,
      icon: LucideIcons.trash2,
      title: '删除确认',
      message: '确定删除文件 "${file.name}" 吗？',
      confirmLabel: '删除',
      isDestructive: true,
    );

    if (confirmed == true) {
      final error = await fileManager.deleteFile(file.path);
      if (context.mounted) {
        if (error != null) {
          ToastHelper.failure('删除失败: $error');
        } else {
          ToastHelper.success('删除成功');
        }
      }
    }
  }

  /// 显示移动/复制文件对话框
  static Future<void> showMoveDialog(
    BuildContext context,
    FileManagerProvider fileManager,
    FileModel file,
    bool copy,
  ) async {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(copy ? '复制文件' : '移动文件'),
        contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.95,
          height: 400,
          child: FolderPicker(
            currentPath: fileManager.currentPath,
            onFolderSelected: (selectedPath) async {
              Navigator.of(dialogContext).pop();
              final error = await fileManager.moveFiles(
                [file.path],
                selectedPath,
                copy: copy,
              );
              if (context.mounted) {
                if (error != null) {
                  ToastHelper.failure('${copy ? '复制' : '移动'}失败: $error');
                } else {
                  ToastHelper.success(copy ? '复制成功' : '移动成功');
                }
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// 显示多选移动/复制文件对话框
  static Future<void> showBatchMoveDialog(
    BuildContext context,
    FileManagerProvider fileManager,
    List<String> uris,
    bool copy,
  ) async {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(copy ? '复制 ${uris.length} 个文件' : '移动 ${uris.length} 个文件'),
        contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.95,
          height: 400,
          child: FolderPicker(
            currentPath: fileManager.currentPath,
            onFolderSelected: (selectedPath) async {
              Navigator.of(dialogContext).pop();
              final error = await fileManager.moveFiles(
                uris,
                selectedPath,
                copy: copy,
              );
              if (context.mounted) {
                if (error != null) {
                  ToastHelper.failure('${copy ? '复制' : '移动'}失败: $error');
                } else {
                  ToastHelper.success(copy ? '复制成功' : '移动成功');
                }
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// 显示创建分享对话框。
  ///
  /// 贴近 Cloudreve V4 Web 端原生创建分享面板：
  /// - 搜索框可添加内置集合、用户组、用户；
  /// - 权限使用「查看 / 创建 / 修改 / 删除」四项；
  /// - 颜色跟随当前应用主题。
  static Future<void> showShareDialog(
    BuildContext context,
    FileModel file,
  ) async {
    final service = ShareService();
    final searchController = TextEditingController();
    final passwordController = TextEditingController();
    final expireDaysController = TextEditingController(text: '7');
    final downloadLimitController = TextEditingController(text: '1');
    final priceController = TextEditingController(text: '20');

    var showAdvanced = false;
    var isCreating = false;
    var isSearching = false;
    var searchOpen = false;
    var groupsLoaded = false;
    String? searchError;

    var passwordProtected = false;
    var timeoutExpire = false;
    var downloadExpire = false;
    var paidDownload = false;
    var shareView = true;
    var showReadme = file.isFolder;

    var searchEntries = <_SharePermissionEntry>[];
    var groups = <SharePrincipal>[];

    var dialogAlive = true;
    var searchGeneration = 0;

    void safeUpdate(StateSetter update, VoidCallback change) {
      if (!dialogAlive) return;
      update(change);
    }

    void dismissShareDialog(BuildContext dialogContext, [_ShareCreationResult? result]) {
      if (!dialogAlive) return;
      dialogAlive = false;
      searchGeneration++;
      FocusManager.instance.primaryFocus?.unfocus();
      Navigator.of(dialogContext).pop(result);
    }

    final entries = <_SharePermissionEntry>[
      _SharePermissionEntry.regular(
        id: 'anonymous',
        title: '匿名访客',
        subtitle: '无需登录即可访问',
        icon: Icons.account_circle,
        color: Colors.grey,
        mask: _SharePermissionMask.read,
        removable: true,
      ),
      _SharePermissionEntry.regular(
        id: 'everyone',
        title: '其他所有人',
        subtitle: '已登录用户',
        icon: Icons.public,
        color: Theme.of(context).colorScheme.primary,
        mask: _SharePermissionMask.read,
        removable: false,
      ),
    ];

    List<_SharePermissionEntry> builtInEntries() {
      return <_SharePermissionEntry>[
        _SharePermissionEntry.builtin(
          id: 'same_group',
          title: '和我同一用户组',
          subtitle: '当前用户组内成员',
          icon: Icons.group_add,
          color: Colors.green,
        ),
        _SharePermissionEntry.builtin(
          id: 'other_group',
          title: '其他用户组',
          subtitle: '其他已登录用户组',
          icon: Icons.groups,
          color: Colors.orange,
        ),
      ];
    }

    bool alreadyAdded(_SharePermissionEntry candidate) {
      return entries.any((entry) => entry.kind == candidate.kind && entry.id == candidate.id);
    }

    Map<String, dynamic> buildPermissions() {
      final permissions = <String, dynamic>{};
      final userExplicit = <String, String>{};
      final groupExplicit = <String, String>{};

      for (final entry in entries) {
        final encoded = entry.encodedPermission;
        if (entry.kind == _SharePermissionKind.anonymous) {
          permissions['anonymous'] = encoded;
        } else if (entry.kind == _SharePermissionKind.everyone) {
          permissions['everyone'] = encoded;
        } else if (entry.kind == _SharePermissionKind.sameGroup) {
          permissions['same_group'] = encoded;
        } else if (entry.kind == _SharePermissionKind.otherGroup) {
          permissions['other_group'] = encoded;
        } else if (entry.kind == _SharePermissionKind.user) {
          userExplicit[entry.id] = encoded;
        } else if (entry.kind == _SharePermissionKind.group) {
          groupExplicit[entry.id] = encoded;
        }
      }

      if (userExplicit.isNotEmpty) permissions['user_explicit'] = userExplicit;
      if (groupExplicit.isNotEmpty) permissions['group_explicit'] = groupExplicit;
      return permissions;
    }

    int? parsePositiveInt(TextEditingController controller) {
      final value = int.tryParse(controller.text.trim());
      if (value == null || value <= 0) return null;
      return value;
    }

    void closeSearchPanel(StateSetter update) {
      searchGeneration++;
      FocusManager.instance.primaryFocus?.unfocus();
      if (searchOpen || searchEntries.isNotEmpty || searchError != null) {
        safeUpdate(update, () {
          searchOpen = false;
          searchEntries = [];
          searchError = null;
          isSearching = false;
        });
      }
    }

    void addEntry(_SharePermissionEntry candidate, StateSetter update) {
      if (!dialogAlive) return;
      if (alreadyAdded(candidate)) {
        ToastHelper.info('已添加过 ${candidate.title}');
        closeSearchPanel(update);
        return;
      }

      searchGeneration++;
      safeUpdate(update, () {
        entries.add(candidate.copyForEntry());
        searchController.clear();
        searchEntries = [];
        searchOpen = false;
        searchError = null;
        isSearching = false;
      });
      FocusManager.instance.primaryFocus?.unfocus();
    }

    Future<void> performSearch(StateSetter update) async {
      if (!dialogAlive) return;
      final currentGeneration = ++searchGeneration;
      final keyword = searchController.text.trim().toLowerCase();
      safeUpdate(update, () {
        isSearching = true;
        searchOpen = true;
        searchError = null;
      });

      try {
        final usersFuture = keyword.isEmpty
            ? Future<List<SharePrincipal>>.value(const [])
            : service.searchUsers(keyword);
        List<SharePrincipal>? groupsResult;
        if (groupsLoaded) {
          groupsResult = groups;
        } else {
          groupsResult = await service.listGroups();
          if (groupsResult == null) {
            groupsLoaded = true;
            ToastHelper.info('用户组功能为 Pro 专属，当前站点不可用');
          }
        }

        final users = await usersFuture;
        if (!dialogAlive || currentGeneration != searchGeneration) return;

        final loadedGroups = groupsResult ?? const <SharePrincipal>[];

        final builtIns = builtInEntries()
            .where((item) => keyword.isEmpty || item.title.toLowerCase().contains(keyword))
            .where((item) => !alreadyAdded(item))
            .toList();
        final filteredGroups = loadedGroups
            .where((g) => keyword.isEmpty || g.name.toLowerCase().contains(keyword))
            .map(_SharePermissionEntry.principal)
            .where((item) => !alreadyAdded(item))
            .toList();
        final filteredUsers = users
            .map(_SharePermissionEntry.principal)
            .where((item) => !alreadyAdded(item))
            .toList();

        safeUpdate(update, () {
          searchEntries = <_SharePermissionEntry>[
            ...builtIns,
            ...filteredGroups,
            ...filteredUsers,
          ];
          groups = loadedGroups;
          groupsLoaded = true;
          isSearching = false;
          searchError = searchEntries.isEmpty && keyword.isNotEmpty ? '没有找到用户或用户组' : null;
        });
      } catch (e) {
        if (!dialogAlive || currentGeneration != searchGeneration) return;
        safeUpdate(update, () {
          searchEntries = [];
          isSearching = false;
          searchError = e.toString();
        });
      }
    }

    Future<void> createShare(StateSetter update, BuildContext dialogContext) async {
      if (isCreating) return;

      final expireDays = timeoutExpire ? parsePositiveInt(expireDaysController) : null;
      final downloads = downloadExpire ? parsePositiveInt(downloadLimitController) : null;
      final price = paidDownload ? parsePositiveInt(priceController) : null;

      if (timeoutExpire && expireDays == null) {
        ToastHelper.failure('请输入有效的过期天数');
        return;
      }
      if (downloadExpire && downloads == null) {
        ToastHelper.failure('请输入有效的下载次数');
        return;
      }
      if (paidDownload && price == null) {
        ToastHelper.failure('请输入有效的付费金额');
        return;
      }

      safeUpdate(update, () => isCreating = true);
      try {
        final shareUrl = await service.createShare(
          uri: file.path,
          permissions: buildPermissions(),
          isPrivate: passwordProtected,
          password: passwordProtected && passwordController.text.trim().isNotEmpty
              ? passwordController.text.trim()
              : null,
          shareView: shareView,
          expire: expireDays == null ? null : expireDays * 24 * 60 * 60,
          downloads: downloads,
          price: price,
          showReadme: showReadme,
        );

        if (dialogContext.mounted) {
          dismissShareDialog(dialogContext, _ShareCreationResult(shareUrl));
        }
      } catch (e) {
        safeUpdate(update, () => isCreating = false);
        if (context.mounted) {
          ToastHelper.failure('分享创建失败: $e');
        }
      }
    }

    Future<void> editPermission(_SharePermissionEntry entry, StateSetter update) async {
      var mask = entry.mask | _SharePermissionMask.read;
      final result = await showModalBottomSheet<int>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) {
          final theme = Theme.of(sheetContext);
          return StatefulBuilder(
            builder: (sheetContext, sheetUpdate) {
              Widget option({
                required int bit,
                required String title,
                required String subtitle,
                bool locked = false,
              }) {
                final checked = (mask & bit) != 0;
                return CheckboxListTile(
                  value: checked,
                  onChanged: locked
                      ? null
                      : (value) {
                          sheetUpdate(() {
                            if (value == true) {
                              mask |= bit;
                            } else {
                              mask &= ~bit;
                            }
                            mask |= _SharePermissionMask.read;
                          });
                        },
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: theme.colorScheme.primary,
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(subtitle),
                );
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SingleChildScrollView(
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('权限：${entry.title}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    option(
                      bit: _SharePermissionMask.read,
                      title: '查看',
                      subtitle: '对于文件，可查看其内容、元数据等详细信息；对于目录，可查看其下的子文件列表及其元数据。',
                      locked: true,
                    ),
                    option(
                      bit: _SharePermissionMask.create,
                      title: '创建',
                      subtitle: '只对目录有效，可在其下创建或上传新文件，可将文件移动或复制到其下。',
                    ),
                    option(
                      bit: _SharePermissionMask.update,
                      title: '修改',
                      subtitle: '可修改元数据、重命名对象、查看活动记录；对于文件，可更新其内容。',
                    ),
                    option(
                      bit: _SharePermissionMask.delete,
                      title: '删除',
                      subtitle: '可删除对象或将其移动到别处。',
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(mask),
                      child: const Text('完成'),
                    ),
                  ],
                ),
                ),
              );
            },
          );
        },
      );

      if (result != null) {
        update(() => entry.mask = result | _SharePermissionMask.read);
      }
    }

    Widget buildPermissionButton(_SharePermissionEntry entry, StateSetter update) {
      final theme = Theme.of(context);
      return InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => editPermission(entry, update),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry.permissionLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 16, color: theme.colorScheme.primary),
            ],
          ),
        ),
      );
    }

    Widget buildPermissionRow(_SharePermissionEntry entry, StateSetter update) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: entry.color.withValues(alpha: isDark ? 0.2 : 0.15),
              child: Icon(entry.icon, color: entry.color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      buildPermissionButton(entry, update),
                    ],
                  ),
                ],
              ),
            ),
            if (entry.removable)
              IconButton(
                icon: const Icon(Icons.close, size: 24),
                color: Colors.grey.shade600,
                onPressed: () => update(() => entries.remove(entry)),
              ),
          ],
        ),
      );
    }

    Widget buildSearchBox(StateSetter update) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      return Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: TextField(
              controller: searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索用户或用户组...',
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                suffixIcon: isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: Icon(searchOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down),
                        onPressed: () {
                          if (searchOpen) {
                            closeSearchPanel(update);
                          } else {
                            performSearch(update);
                          }
                        },
                      ),
              ),
              onTap: () => performSearch(update),
              onChanged: (_) => performSearch(update),
              onSubmitted: (_) => performSearch(update),
            ),
          ),
          if (searchError != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(searchError!, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ),
          ],
          if (searchOpen && searchEntries.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 260),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: searchEntries.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.2)),
                itemBuilder: (context, index) {
                  final item = searchEntries[index];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundColor: item.color.withValues(alpha: isDark ? 0.2 : 0.15),
                      child: Icon(item.icon, color: item.color),
                    ),
                    title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      item.searchSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: () => addEntry(item, update),
                  );
                },
              ),
            ),
          ],
        ],
      );
    }

    Widget buildGeneralPage(StateSetter update) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSearchBox(update),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => closeSearchPanel(update),
            child: Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('常规访问权限', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 10),
                  ...entries.map((entry) => buildPermissionRow(entry, update)),
                ],
              ),
            ),
          ),
        ],
      );
    }

    Widget buildAdvancedSwitch({
      required IconData icon,
      required String title,
      required bool value,
      required ValueChanged<bool> onChanged,
      Widget? child,
    }) {
      return Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onChanged(!value),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  SizedBox(width: 42, child: Icon(icon, color: Colors.grey.shade600, size: 24)),
                  Expanded(
                    child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  Checkbox(value: value, onChanged: (checked) => onChanged(checked ?? false)),
                ],
              ),
            ),
          ),
          if (value && child != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(42, 0, 0, 12),
              child: child,
            ),
        ],
      );
    }

    Widget buildCompactField({
      required TextEditingController controller,
      required String hint,
      String? suffix,
      bool obscure = false,
    }) {
      return TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: suffix == null ? TextInputType.text : TextInputType.number,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          suffixText: suffix,
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      );
    }

    Widget buildAdvancedPage(StateSetter update) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildAdvancedSwitch(
            icon: Icons.remove_red_eye_outlined,
            title: '使用密码保护链接',
            value: passwordProtected,
            onChanged: (value) => update(() => passwordProtected = value),
            child: buildCompactField(
              controller: passwordController,
              hint: '分享密码，留空则自动生成',
              obscure: false,
            ),
          ),
          buildAdvancedSwitch(
            icon: Icons.timer_outlined,
            title: '超时自动过期',
            value: timeoutExpire,
            onChanged: (value) => update(() => timeoutExpire = value),
            child: buildCompactField(
              controller: expireDaysController,
              hint: '有效期',
              suffix: '天',
            ),
          ),
          buildAdvancedSwitch(
            icon: Icons.download_outlined,
            title: '下载后自动过期',
            value: downloadExpire,
            onChanged: (value) => update(() => downloadExpire = value),
            child: buildCompactField(
              controller: downloadLimitController,
              hint: '下载次数',
              suffix: '次',
            ),
          ),
          buildAdvancedSwitch(
            icon: Icons.account_balance_wallet_outlined,
            title: '付费下载',
            value: paidDownload,
            onChanged: (value) => update(() => paidDownload = value),
            child: buildCompactField(
              controller: priceController,
              hint: '价格',
              suffix: '积分',
            ),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.only(left: 42, right: 0),
            title: const Text('启用分享视图'),
            subtitle: const Text('允许使用分享页面预览文件'),
            value: shareView,
            onChanged: (value) => update(() => shareView = value),
          ),
          if (file.isFolder)
            SwitchListTile(
              contentPadding: const EdgeInsets.only(left: 42, right: 0),
              title: const Text('显示 README'),
              subtitle: const Text('文件夹分享中展示说明文件'),
              value: showReadme,
              onChanged: (value) => update(() => showReadme = value),
            ),
        ],
      );
    }

    Widget buildFooter(StateSetter update, BuildContext dialogContext) {
      final theme = Theme.of(dialogContext);
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
        child: Row(
          children: [
            IconButton(
              icon: Icon(showAdvanced ? Icons.arrow_back : Icons.settings),
              color: theme.colorScheme.primary,
              onPressed: isCreating ? null : () => update(() => showAdvanced = !showAdvanced),
            ),
            const Spacer(),
            TextButton(
              onPressed: isCreating ? null : () => dismissShareDialog(dialogContext),
              child: const Text('取消', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: isCreating ? null : () => createShare(update, dialogContext),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
              child: isCreating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('确定', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
    }

    final result = await showGeneralDialog<_ShareCreationResult>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '创建分享链接',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final screenWidth = MediaQuery.of(dialogContext).size.width;
        final screenHeight = MediaQuery.of(dialogContext).size.height;
        final dialogWidth = screenWidth >= 720 ? 640.0 : screenWidth - 16.0;
        final maxHeight = screenHeight * 0.88;

        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && dialogAlive) {
              dialogAlive = false;
              searchGeneration++;
              FocusManager.instance.primaryFocus?.unfocus();
            }
          },
          child: Center(
            child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: dialogWidth, maxHeight: maxHeight),
            child: Material(
              color: Theme.of(dialogContext).colorScheme.surface,
              elevation: 24,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: StatefulBuilder(
                builder: (dialogContext, update) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 20, 18, 12),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '创建分享链接',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 28),
                              onPressed: isCreating ? null : () => dismissShareDialog(dialogContext),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: showAdvanced
                                ? KeyedSubtree(key: const ValueKey('advanced'), child: buildAdvancedPage(update))
                                : KeyedSubtree(key: const ValueKey('general'), child: buildGeneralPage(update)),
                          ),
                        ),
                      ),
                      buildFooter(update, dialogContext),
                    ],
                  );
                },
              ),
              ),
            ),
          ),
        );
      },
    );

    dialogAlive = false;
    searchGeneration++;
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    passwordController.dispose();
    expireDaysController.dispose();
    downloadLimitController.dispose();
    priceController.dispose();
    searchController.dispose();

    if (result == null || !context.mounted) return;

    ToastHelper.success('分享创建成功');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('分享链接'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(result.url, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('复制到剪贴板'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: result.url));
                Navigator.of(dialogContext).pop();
                ToastHelper.success('已复制到剪贴板');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // ─── 内部工具方法 ───

  static Widget _buildDialogTitle(BuildContext context, IconData icon, String title) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 10),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  static Widget _buildDialogActions(
    BuildContext context, {
    required VoidCallback onCancel,
    required VoidCallback onConfirm,
    required String confirmLabel,
    bool isDestructive = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: isDestructive ? colorScheme.error : null,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  static Future<bool?> _showConfirmDialog(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
    required String confirmLabel,
    bool isDestructive = false,
  }) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: title,
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 250),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final scaleAnim = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        ).drive(Tween(begin: 0.92, end: 1.0));
        final fadeAnim = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        ).drive(Tween(begin: 0.0, end: 1.0));
        return ScaleTransition(
          scale: scaleAnim,
          child: FadeTransition(opacity: fadeAnim, child: child),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        final screenWidth = MediaQuery.of(context).size.width;
        final dialogWidth = screenWidth >= 600 ? 400.0 : screenWidth - 48.0;
        final theme = Theme.of(context);

        return Center(
          child: SizedBox(
            width: dialogWidth,
            child: GlassmorphismContainer(
              borderRadius: 16,
              sigmaX: 20,
              sigmaY: 20,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDialogTitle(context, icon, title),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                        child: Text(message, style: theme.textTheme.bodyMedium),
                      ),
                      _buildDialogActions(
                        context,
                        onCancel: () => Navigator.of(context).pop(false),
                        onConfirm: () => Navigator.of(context).pop(true),
                        confirmLabel: confirmLabel,
                        isDestructive: isDestructive,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _SharePermissionKind { anonymous, everyone, sameGroup, otherGroup, user, group }

class _SharePermissionMask {
  static const int read = 1;
  static const int create = 2;
  static const int update = 4;
  static const int delete = 8;

  static String encode(int mask) {
    final normalized = ((mask | read).clamp(1, 15));
    const values = <int, String>{
      1: 'AQ==',
      2: 'Ag==',
      3: 'Aw==',
      4: 'BA==',
      5: 'BQ==',
      6: 'Bg==',
      7: 'Bw==',
      8: 'CA==',
      9: 'CQ==',
      10: 'Cg==',
      11: 'Cw==',
      12: 'DA==',
      13: 'DQ==',
      14: 'Dg==',
      15: 'Dw==',
    };
    return values[normalized] ?? 'AQ==';
  }

  static String label(int mask) {
    final parts = <String>['查看'];
    if ((mask & create) != 0) parts.add('创建');
    if ((mask & update) != 0) parts.add('修改');
    if ((mask & delete) != 0) parts.add('删除');
    return parts.join('、');
  }
}

class _SharePermissionEntry {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final _SharePermissionKind kind;
  final bool removable;
  int mask;

  _SharePermissionEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.kind,
    required this.mask,
    required this.removable,
  });

  String get encodedPermission => _SharePermissionMask.encode(mask);
  String get permissionLabel => _SharePermissionMask.label(mask);
  String get searchSubtitle {
    if (kind == _SharePermissionKind.sameGroup || kind == _SharePermissionKind.otherGroup) {
      return '内置集合';
    }
    if (kind == _SharePermissionKind.group) return '用户组';
    if (kind == _SharePermissionKind.user) return subtitle;
    return subtitle;
  }

  factory _SharePermissionEntry.regular({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required int mask,
    required bool removable,
  }) {
    return _SharePermissionEntry(
      id: id,
      title: title,
      subtitle: subtitle,
      icon: icon,
      color: color,
      kind: id == 'anonymous'
          ? _SharePermissionKind.anonymous
          : _SharePermissionKind.everyone,
      mask: mask | _SharePermissionMask.read,
      removable: removable,
    );
  }

  factory _SharePermissionEntry.builtin({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return _SharePermissionEntry(
      id: id,
      title: title,
      subtitle: subtitle,
      icon: icon,
      color: color,
      kind: id == 'same_group'
          ? _SharePermissionKind.sameGroup
          : _SharePermissionKind.otherGroup,
      mask: _SharePermissionMask.read,
      removable: true,
    );
  }

  factory _SharePermissionEntry.principal(SharePrincipal principal) {
    final isGroup = principal.type == SharePrincipalType.group;
    return _SharePermissionEntry(
      id: principal.id,
      title: principal.name,
      subtitle: isGroup ? '用户组' : (principal.email ?? principal.groupName ?? '用户'),
      icon: isGroup ? Icons.group : Icons.person,
      color: isGroup ? Colors.deepPurple : Colors.blue,
      kind: isGroup ? _SharePermissionKind.group : _SharePermissionKind.user,
      mask: _SharePermissionMask.read,
      removable: true,
    );
  }

  _SharePermissionEntry copyForEntry() {
    return _SharePermissionEntry(
      id: id,
      title: title,
      subtitle: subtitle,
      icon: icon,
      color: color,
      kind: kind,
      mask: mask | _SharePermissionMask.read,
      removable: removable,
    );
  }
}

class _ShareCreationResult {
  final String url;

  const _ShareCreationResult(this.url);
}
