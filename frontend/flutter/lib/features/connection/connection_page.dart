import 'package:flutter/material.dart';

import 'connection_controller.dart';
import '../../shared/widgets/syncbox_logo.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key, required this.connection});
  final ConnectionController connection;
  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final _form = GlobalKey<FormState>();
  bool _allowHttp = false;
  late final TextEditingController _server;
  late final TextEditingController _device;
  final _username = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController(),
      _code = TextEditingController();
  @override
  void initState() {
    super.initState();
    _allowHttp = widget.connection.allowHttp;
    _server = TextEditingController(text: widget.connection.serverText);
    _device = TextEditingController(
      text: widget.connection.deviceName.isEmpty
          ? (widget.connection.platform == 'windows'
                ? 'Windows 电脑'
                : 'Android 手机')
          : widget.connection.deviceName,
    );
  }

  @override
  void dispose() {
    for (final c in [_server, _device, _username, _password, _confirm, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!_form.currentState!.validate()) return;
    final c = widget.connection;
    if (c.stage == ConnectionStage.server) {
      await c.connect(_server.text, allowInsecure: _allowHttp);
    } else {
      await c.authenticate(
        _username.text,
        _password.text,
        _device.text,
        code: _code.text,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.connection, isServer = c.stage == ConnectionStage.server;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: SyncBoxLogo(size: 64)),
                    const SizedBox(height: 18),
                    const Text(
                      'SyncBox',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      isServer
                          ? '连接你的私人服务'
                          : c.initialized
                          ? '登录个人空间'
                          : '首次设置私人空间',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isServer
                          ? '所有设备连接同一个服务，即可共享会话和内容。'
                          : c.initialized
                          ? '使用首次设置的唯一账号登录。'
                          : '仅设置一次。所有设备使用这组用户名和密码。',
                    ),
                    const SizedBox(height: 24),
                    if (isServer) ...[
                      TextFormField(
                        controller: _server,
                        enabled: !c.busy,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: '服务地址',
                          hintText: 'https://sync.example.com',
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? '请输入服务地址' : null,
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _allowHttp,
                        onChanged: c.busy
                            ? null
                            : (value) =>
                                  setState(() => _allowHttp = value ?? false),
                        title: const Text(
                          '允许局域网 HTTP',
                          style: TextStyle(fontSize: 13),
                        ),
                        subtitle: const Text(
                          'HTTP 不加密，仅用于受信任的本地网络。',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '填写站点地址，不含 /api。Android 模拟器访问本机可用 http://10.0.2.2:3000；真机需使用可访问的局域网地址。',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ] else ...[
                      Text(
                        c.serverText,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _username,
                        enabled: !c.busy && !c.requiresTwoFactor,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(labelText: '用户名'),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? '请输入用户名' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        enabled: !c.busy && !c.requiresTwoFactor,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: '密码（至少 6 位）',
                        ),
                        validator: (v) =>
                            v == null || v.length < 6 || v.length > 128
                            ? '密码需为 6–128 位'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      if (c.initialized && c.requiresTwoFactor) ...[
                        TextFormField(
                          controller: _code,
                          enabled: !c.busy,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: '两步验证码',
                            helperText: '密码已验证，请输入 6 位动态码或恢复码',
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (!c.initialized) ...[
                        TextFormField(
                          controller: _confirm,
                          enabled: !c.busy,
                          obscureText: true,
                          decoration: const InputDecoration(labelText: '确认密码'),
                          validator: (v) =>
                              v != _password.text ? '两次密码不一致' : null,
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _device,
                        enabled: !c.busy,
                        maxLength: 80,
                        decoration: const InputDecoration(labelText: '本设备名称'),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? '请输入设备名称' : null,
                      ),
                    ],
                    if (c.error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          c.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: c.busy ? null : submit,
                      child: Text(
                        c.busy
                            ? '正在连接…'
                            : isServer
                            ? '连接服务'
                            : c.initialized
                            ? c.requiresTwoFactor ? '验证并登录' : '登录'
                            : '完成首次设置',
                      ),
                    ),
                    if (!isServer)
                      TextButton(
                        onPressed: c.busy ? null : c.editServer,
                        child: const Text('更换服务地址'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
