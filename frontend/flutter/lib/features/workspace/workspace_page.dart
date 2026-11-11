import 'dart:async';

import 'package:flutter/material.dart';

import '../connection/connection_controller.dart';
import 'workspace_controller.dart';
import 'workspace_repository.dart';
import 'widgets/conversation_list.dart';
import 'widgets/conversation_detail.dart';
import 'widgets/favorites_view.dart';
import 'widgets/settings_page.dart';
import '../../models/conversation.dart';
import '../../shared/widgets/syncbox_logo.dart';

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key, required this.connection});
  final ConnectionController connection;
  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage>
    with WidgetsBindingObserver {
  late final WorkspaceController controller;
  int _section = 0;
  bool _settingsVisited = false, _settingsLocked = false;

  void selectSection(int section) {
    if (_settingsLocked || section == _section) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _section = section;
      if (section == 1) _settingsVisited = true;
    });
  }

  @override
  void initState() {
    super.initState();
    controller = WorkspaceController(
      WorkspaceRepository(widget.connection.api!),
      onExpired: widget.connection.expire,
    );
    WidgetsBinding.instance.addObserver(this);
    controller.currentDeviceId = widget.connection.deviceId;
    controller.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    controller.setActive(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  Future<void> edit({bool rename = false, Conversation? conversation}) async {
    final input = TextEditingController(
      text: rename
          ? (conversation ?? controller.selected!).title
          : '新建会话${DateTime.now().year.toString().substring(2)}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}',
    );
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(rename ? '重命名会话' : '新建会话'),
        content: TextField(
          controller: input,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: '会话名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (input.text.trim().isNotEmpty) {
                Navigator.pop(context, input.text.trim());
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // Dialog exit animations may still reference its text controller.
    Future<void>.delayed(const Duration(seconds: 1), input.dispose);
    if (title != null && mounted) {
      if (rename) {
        await controller.rename(title, conversation: conversation);
      } else {
        await controller.create(title);
      }
    }
  }

  Future<void> remove({Conversation? conversation}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除会话？'),
        content: const Text('会话及其中消息将从所有设备永久移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await controller.deleteConversation(conversation: conversation);
    }
  }

  Future<void> devices() async {
    try {
      final data = await widget.connection.api!.request('/devices') as List;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('我的设备'),
          content: SizedBox(
            width: 400,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final d in data)
                  ListTile(
                    leading: Icon(
                      d['online'] == true
                          ? Icons.circle
                          : Icons.circle_outlined,
                      size: 14,
                      color: d['online'] == true
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                    ),
                    title: Text(
                      '${d['name']}${d['id'] == widget.connection.deviceId ? ' · 当前设备' : ''}',
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${d['platform'] as String} · ${d['online'] == true ? '在线' : '离线'}',
                        ),
                        SelectableText(
                          d['id'] as String,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('读取设备失败，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, widget.connection]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) {
        final mobile = ['android', 'ios'].contains(widget.connection.platform);
        final wide = box.maxWidth >= 800;
        final detailOpen =
            controller.selected != null || controller.favoritesMode;
        final showTabs = mobile && (_section == 1 || wide || !detailOpen);
        final messages = Column(
          children: [
            if (controller.error != null || widget.connection.error != null)
              MaterialBanner(
                content: Text(controller.error ?? widget.connection.error!),
                actions: [
                  TextButton(
                    onPressed: controller.refresh,
                    child: const Text('刷新'),
                  ),
                ],
              ),
            if (controller.refreshing)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: messageWorkspace(wide: wide, mobile: mobile),
            ),
          ],
        );
        return PopScope(
          canPop: _section == 0 && !detailOpen && !_settingsLocked,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop || _settingsLocked) return;
            if (mobile && _section == 1) {
              selectSection(0);
            } else {
              controller.select(null);
            }
          },
          child: Scaffold(
            backgroundColor: Colors.white,
            appBar: mobile
                ? _section == 1
                      ? AppBar(
                          title: const Text('设置'),
                          backgroundColor: Colors.white,
                          scrolledUnderElevation: 0,
                        )
                      : !wide && detailOpen
                      ? null
                      : AppBar(
                          title: const Text('消息列表'),
                          backgroundColor: Colors.white,
                          scrolledUnderElevation: 0,
                          actions: [
                            IconButton(
                              tooltip: '新建会话',
                              onPressed: controller.busy ? null : edit,
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        )
                : AppBar(
                    title: Row(
                      children: [
                        const SyncBoxLogo(size: 30),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('SyncBox'),
                              Text(
                                controller.error != null
                                    ? '连接中断'
                                    : controller.lastSynced == null
                                    ? '正在连接…'
                                    : controller.realtimeConnected
                                    ? '实时同步'
                                    : '定时同步',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      IconButton(
                        tooltip: '刷新',
                        onPressed: controller.refreshing
                            ? null
                            : controller.refresh,
                        icon: const Icon(Icons.refresh),
                      ),
                      IconButton(
                        tooltip: '我的设备',
                        onPressed: devices,
                        icon: const Icon(Icons.devices),
                      ),
                      IconButton(
                        tooltip: '设置',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => SettingsPage(
                              connection: widget.connection,
                              workspace: controller,
                              onDevices: devices,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.settings_outlined),
                      ),
                    ],
                  ),
            body: SafeArea(
              bottom: !showTabs,
              child: mobile
                  ? IndexedStack(
                      index: _section,
                      children: [
                        messages,
                        if (_settingsVisited)
                          SettingsPage(
                            connection: widget.connection,
                            workspace: controller,
                            onDevices: devices,
                            embedded: true,
                            onNavigationLockChanged: (locked) {
                              if (mounted && locked != _settingsLocked) {
                                setState(() => _settingsLocked = locked);
                              }
                            },
                          )
                        else
                          const SizedBox.shrink(),
                      ],
                    )
                  : messages,
            ),
            bottomNavigationBar: showTabs
                ? NavigationBar(
                    selectedIndex: _section,
                    onDestinationSelected: _settingsLocked
                        ? null
                        : selectSection,
                    height: 68,
                    backgroundColor: Colors.white,
                    surfaceTintColor: Colors.transparent,
                    indicatorColor: const Color(0xffdceef9),
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.chat_bubble_outline),
                        selectedIcon: Icon(Icons.chat_bubble),
                        label: '消息',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings),
                        label: '设置',
                      ),
                    ],
                  )
                : null,
          ),
        );
      },
    ),
  );

  Widget messageWorkspace({required bool wide, required bool mobile}) {
    final list = ConversationList(
      controller: controller,
      onCreate: edit,
      onRename: (c) => edit(rename: true, conversation: c),
      onDelete: (c) => remove(conversation: c),
      showHeader: !mobile,
    );
    final detail = ColoredBox(
      color: const Color(0xffe7eef3),
      child: controller.favoritesMode
          ? FavoritesView(controller: controller, compact: !wide)
          : controller.selected == null
          ? const Center(child: Text('选择或创建一个会话，开始跨设备共享'))
          : ConversationDetail(
              key: ValueKey(controller.selected!.id),
              controller: controller,
              onRename: () => edit(rename: true),
              onDelete: remove,
              compact: !wide,
            ),
    );
    return wide
        ? Row(
            children: [
              SizedBox(width: 300, child: list),
              const VerticalDivider(width: 1),
              Expanded(child: detail),
            ],
          )
        : controller.selected == null && !controller.favoritesMode
        ? list
        : detail;
  }
}
