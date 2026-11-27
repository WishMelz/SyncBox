import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_client.dart';
import '../../../models/file_item.dart';
import '../../../shared/widgets/highlight_text.dart';
import '../../../shared/widgets/page_controls.dart';
import '../workspace_controller.dart';
import 'message_card.dart';

class FilesView extends StatefulWidget {
  const FilesView({
    super.key,
    required this.controller,
    required this.compact,
  });

  final WorkspaceController controller;
  final bool compact;

  @override
  State<FilesView> createState() => _FilesViewState();
}

class _FilesViewState extends State<FilesView> {
  final TextEditingController _searchController = TextEditingController();
  List<FileItem> _items = const [];
  int _page = 1;
  int _totalPages = 0;
  String _query = '';
  String _category = 'all';
  String _sort = 'newest';
  bool _loading = false;
  String? _error;
  String? _savingId;
  String? _deletingId;
  int _filesRevision = 0;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _filesRevision = widget.controller.filesRevision;
    widget.controller.addListener(_onControllerChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (widget.controller.filesRevision != _filesRevision) {
      _filesRevision = widget.controller.filesRevision;
      unawaited(_load(silent: true));
    }
  }

  Future<void> _load({bool silent = false}) async {
    final generation = ++_loadGeneration;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await widget.controller.repository.files(
        search: _query,
        category: _category == 'all' ? null : _category,
        sort: _sort,
        page: _page,
      );
      if (!mounted || generation != _loadGeneration) return;
      final maxPages = result.totalPages < 1 ? 1 : result.totalPages;
      if (_page > maxPages) {
        _page = maxPages;
        unawaited(_load(silent: silent));
        return;
      }
      setState(() {
        _items = result.items;
        _totalPages = result.totalPages;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      if (e.status == 401) {
        await widget.controller.onExpired();
        return;
      }
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = '加载文件列表失败，请重试';
      });
    }
  }

  Future<void> _saveFile(FileItem item) async {
    if (_savingId != null) return;
    setState(() => _savingId = item.id);
    try {
      final api = widget.controller.repository.api;
      final data = item.kind == 'image'
          ? await api.imageBytes(item.messageId)
          : await api.attachmentBytes(item.messageId, item.id);
      var saved = false;
      if (Platform.isAndroid) {
        saved =
            await const MethodChannel('syncbox/files').invokeMethod<bool>(
              'save',
              {'name': item.name, 'bytes': data},
            ) ??
            false;
      } else {
        final location = await getSaveLocation(suggestedName: item.name);
        if (location != null) {
          await XFile.fromData(data).saveTo(location.path);
          saved = true;
        }
      }
      if (mounted && saved) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文件已保存')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文件保存失败，请重试。')));
      }
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  Future<void> _deleteFile(FileItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这个文件？'),
        content: Text('“${item.name}”将从所有设备永久删除，消息文字会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingId = item.id);
    try {
      await widget.controller.repository.deleteFile(item);
      await _load();
      unawaited(widget.controller.refresh(reconcile: false));
    } on ApiException catch (e) {
      if (e.status == 401) {
        await widget.controller.onExpired();
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final api = widget.controller.repository.api;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (widget.compact)
                IconButton(
                  tooltip: '返回会话列表',
                  onPressed: () => widget.controller.select(null),
                  icon: const Icon(Icons.arrow_back),
                ),
              Text('文件', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(
                tooltip: '刷新文件',
                onPressed: _loading ? null : () => _load(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: '搜索文件名或会话名称',
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          tooltip: '清空搜索',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _query = '';
                              _page = 1;
                            });
                            unawaited(_load());
                          },
                          icon: const Icon(Icons.clear),
                        )
                      : null,
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (value) {
                  setState(() {
                    _query = value.trim();
                    _page = 1;
                  });
                  unawaited(_load());
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('全部')),
                      ButtonSegment(value: 'image', label: Text('图片')),
                      ButtonSegment(value: 'file', label: Text('文件')),
                    ],
                    selected: {_category},
                    onSelectionChanged: _loading
                        ? null
                        : (selected) {
                            setState(() {
                              _category = selected.first;
                              _page = 1;
                            });
                            unawaited(_load());
                          },
                  ),
                  DropdownButton<String>(
                    value: _sort,
                    onChanged: _loading
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              _sort = value;
                              _page = 1;
                            });
                            unawaited(_load());
                          },
                    items: const [
                      DropdownMenuItem(value: 'newest', child: Text('最新优先')),
                      DropdownMenuItem(value: 'largest', child: Text('体积最大')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_loading && _items.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                TextButton(onPressed: () => _load(), child: const Text('重试')),
              ],
            ),
          ),
        Expanded(
          child: _loading && _items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
              ? Center(
                  child: Text(
                    _query.isEmpty ? '暂无已上传的图片或附件' : '没有匹配的文件',
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final isSaving = _savingId == item.id;
                    final isDeleting = _deletingId == item.id;
                    return Card(
                      color: Colors.white,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item.hasPreview)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: PrivateMessageImage(
                                  key: ValueKey('file-${item.kind}-${item.id}'),
                                  load: () => item.kind == 'image'
                                      ? api.imageBytes(item.messageId)
                                      : api.attachmentBytes(
                                          item.messageId,
                                          item.id,
                                          preview: true,
                                        ),
                                ),
                              ),
                            Row(
                              children: [
                                Icon(
                                  item.category == 'image'
                                      ? Icons.image_outlined
                                      : Icons.insert_drive_file_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      HighlightText(
                                        item.name,
                                        query: _query,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${_formatSize(item.size)} · ${item.conversationTitle} · ${_formatDate(item.createdAt)}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  onPressed: () =>
                                      widget.controller.openConversation(
                                        item.asMessageShell(),
                                      ),
                                  icon: const Icon(
                                    Icons.forum_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('定位会话'),
                                ),
                                TextButton.icon(
                                  onPressed: isSaving || isDeleting
                                      ? null
                                      : () => _saveFile(item),
                                  icon: isSaving
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.download_outlined,
                                          size: 18,
                                        ),
                                  label: const Text('保存'),
                                ),
                                TextButton.icon(
                                  onPressed: isSaving || isDeleting
                                      ? null
                                      : () => _deleteFile(item),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                  label: const Text('删除'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        PageControls(
          page: _page,
          pages: _totalPages,
          enabled: !_loading,
          onChanged: (nextPage) {
            setState(() => _page = nextPage);
            unawaited(_load());
          },
        ),
      ],
    );
  }
}
