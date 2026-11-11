import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../connection/connection_controller.dart';
import '../workspace_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.connection,
    required this.workspace,
    required this.onDevices,
    this.embedded = false,
    this.onNavigationLockChanged,
  });
  final ConnectionController connection;
  final WorkspaceController workspace;
  final Future<void> Function() onDevices;
  final bool embedded;
  final ValueChanged<bool>? onNavigationLockChanged;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, dynamic>? settings;
  final name = TextEditingController(),
      days = TextEditingController(),
      password = TextEditingController(),
      code = TextEditingController(),
      confirmation = TextEditingController();
  bool busy = false, cleanup = false;
  String? error, notice, secret;
  List<String> recovery = [];
  ApiClient get api => widget.connection.api!;
  void reportNavigationLock() {
    final locked = busy || recovery.isNotEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onNavigationLockChanged?.call(locked);
    });
  }

  @override
  void initState() {
    super.initState();
    name.text = widget.connection.deviceName;
    run(load);
  }

  @override
  void dispose() {
    for (final c in [name, days, password, code, confirmation]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    final data = await api.request('/settings') as Map<String, dynamic>;
    if (!mounted) return;
    settings = data;
    cleanup = data['cleanup']['enabled'] == true;
    days.text = '${data['cleanup']['idleDays']}';
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    reportNavigationLock();
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.status == 401) {
        if (!widget.embedded) Navigator.pop(context);
        await widget.connection.expire();
        return;
      }
      error = e.toString();
    } finally {
      if (mounted) {
        setState(() => busy = false);
        reportNavigationLock();
      }
    }
  }

  Map<String, String> get security => {
    'password': password.text,
    if (code.text.trim().isNotEmpty) 'code': code.text.trim(),
  };
  void clearSecurity() {
    password.clear();
    code.clear();
    secret = null;
  }

  Future<void> changeTwoFactor() async {
    if (settings!['twoFactorEnabled'] == true) {
      await api.request(
        '/settings/two-factor/disable',
        method: 'POST',
        body: security,
      );
      clearSecurity();
      notice = '两步认证已关闭';
      await load();
    } else if (secret == null) {
      final data = await api.request(
        '/settings/two-factor/setup',
        method: 'POST',
        body: security,
      );
      secret = data['secret'];
      code.clear();
    } else {
      final data = await api.request(
        '/settings/two-factor/enable',
        method: 'POST',
        body: security,
      );
      recovery = List<String>.from(data['recoveryCodes']);
      clearSecurity();
      await load();
    }
  }

  Future<void> reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('永久删除所有数据？'),
        content: const Text('账号、设备、会话、消息和附件全部删除，所有设备退出登录。此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await run(() async {
      await api.request(
        '/settings/data',
        method: 'DELETE',
        body: {...security, 'confirmation': confirmation.text},
      );
      if (mounted && !widget.embedded) Navigator.pop(context);
      await widget.connection.resetLocalSession();
    });
  }

  Widget heading(String title, String description) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(description, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && recovery.isEmpty,
    child: widget.embedded
        ? content(context)
        : Scaffold(
            appBar: AppBar(title: const Text('设置')),
            body: content(context),
          ),
  );

  Widget content(BuildContext context) => SafeArea(
    top: false,
    bottom: !widget.embedded,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (notice != null)
                Text(
                  notice!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              if (settings == null && !busy)
                TextButton(
                  onPressed: () => run(load),
                  child: const Text('重新加载'),
                ),
              heading('账号与连接', '查看当前登录账号和服务连接。'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: const Text('账号'),
                subtitle: Text(widget.connection.username),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.dns_outlined),
                title: const Text('服务地址'),
                subtitle: SelectableText(widget.connection.serverText),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  widget.workspace.error == null
                      ? Icons.sync
                      : Icons.sync_problem,
                ),
                title: Text(
                  widget.workspace.error != null
                      ? '连接中断'
                      : widget.workspace.lastSynced == null
                      ? '正在连接…'
                      : widget.workspace.realtimeConnected
                      ? '实时同步'
                      : '定时同步',
                ),
                trailing: IconButton(
                  tooltip: '刷新连接',
                  onPressed: busy || widget.workspace.refreshing
                      ? null
                      : widget.workspace.refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ),
              heading('当前设备', '名称用于标记消息来源，修改不会改变设备 ID。'),
              TextField(
                controller: name,
                enabled: !busy,
                maxLength: 80,
                decoration: const InputDecoration(labelText: '设备名称'),
              ),
              FilledButton.tonal(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        await widget.connection.renameDevice(name.text);
                        notice = '设备名称已保存';
                      }),
                child: const Text('保存名称'),
              ),
              const SizedBox(height: 8),
              SelectableText(
                '设备 ID：${widget.connection.deviceId ?? '未登记'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              TextButton.icon(
                onPressed: busy ? null : widget.onDevices,
                icon: const Icon(Icons.devices),
                label: const Text('管理设备'),
              ),
              if (settings != null) ...[
                heading('文件清理', '自动删除长期未访问的图片和附件，保留消息文字。'),
                Text(
                  '${settings!['storage']['fileCount']} 个文件 · ${(settings!['storage']['bytes'] / 1024 / 1024).toStringAsFixed(1)} MB',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自动清理闲置文件'),
                  value: cleanup,
                  onChanged: busy ? null : (v) => setState(() => cleanup = v),
                ),
                TextField(
                  controller: days,
                  enabled: !busy && cleanup,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '闲置天数',
                    suffixText: '天',
                    helperText: '1–3650 天；上传、预览、下载均计为访问',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          final value = int.tryParse(days.text);
                          if (value == null || value < 1 || value > 3650) {
                            throw const ApiException('请输入 1–3650 天');
                          }
                          await api.request(
                            '/settings/cleanup',
                            method: 'PATCH',
                            body: {'enabled': cleanup, 'idleDays': value},
                          );
                          await load();
                          notice = '清理设置已保存';
                        }),
                  child: const Text('保存清理设置'),
                ),
                heading(
                  '账号安全',
                  settings!['twoFactorEnabled'] == true
                      ? '两步认证已开启。关闭需要密码与验证码或恢复码。'
                      : '两步认证未开启。开启后，登录时需要额外输入验证码。',
                ),
                TextField(
                  controller: password,
                  enabled: !busy,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '当前密码'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: code,
                  enabled: !busy,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: '验证码或恢复码'),
                ),
                if (secret != null) ...[
                  const SizedBox(height: 12),
                  const Text('在验证器中手动添加下方密钥，再输入生成的 6 位验证码。密钥有效期 10 分钟。'),
                  SelectableText(
                    secret!,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => setState(clearSecurity),
                    child: const Text('取消设置'),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: busy || recovery.isNotEmpty
                      ? null
                      : () => run(changeTwoFactor),
                  child: Text(
                    settings!['twoFactorEnabled'] == true
                        ? '关闭两步认证'
                        : secret == null
                        ? '设置两步认证'
                        : '验证并开启',
                  ),
                ),
                if (recovery.isNotEmpty) ...[
                  heading('保存恢复码', '每个恢复码只能使用一次。请保存到安全位置，丢失验证器时可用于登录。'),
                  SelectableText(recovery.join('\n')),
                  FilledButton(
                    onPressed: () {
                      setState(() => recovery = []);
                      reportNavigationLock();
                    },
                    child: const Text('我已保存恢复码'),
                  ),
                ],
                heading('删除所有数据', '删除账号、设备、会话、消息和附件，恢复首次设置状态。无法撤销。'),
                TextField(
                  controller: confirmation,
                  enabled: !busy,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: '输入“删除所有数据”确认',
                    helperText: '使用上方当前密码及验证码验证身份',
                  ),
                ),
                TextButton(
                  onPressed:
                      busy ||
                          recovery.isNotEmpty ||
                          confirmation.text != '删除所有数据'
                      ? null
                      : reset,
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: const Text('删除所有数据'),
                ),
              ],
              const Divider(),
              TextButton(
                onPressed: busy || recovery.isNotEmpty
                    ? null
                    : () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('退出登录？'),
                            content: const Text('未发送的草稿不会保留。'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('退出登录'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true && mounted) {
                          await widget.connection.logout();
                          if (context.mounted &&
                              widget.connection.error == null &&
                              !widget.embedded) {
                            Navigator.pop(context);
                          }
                        }
                      },
                child: const Text('退出登录'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
