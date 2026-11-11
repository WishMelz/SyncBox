import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/session_store.dart';

enum ConnectionStage { server, credentials, workspace }

class ConnectionController extends ChangeNotifier {
  ConnectionController({
    required this.store,
    required this.platform,
    ApiClient Function(Uri)? factory,
  }) : _factory = factory ?? ApiClient.new;
  final SessionStore store;
  final String platform;
  final ApiClient Function(Uri) _factory;
  ConnectionStage stage = ConnectionStage.server;
  bool busy = false, initialized = true, allowHttp = false;
  bool requiresTwoFactor = false;
  String? error;
  String serverText = '', username = '', deviceName = '';
  String? _deviceId;
  String? get deviceId => _deviceId;
  ApiClient? api;

  Future<void> restore() => _run(() async {
    final saved = await store.read();
    if (saved == null) return;
    serverText = saved['server'] as String;
    allowHttp = saved['allowHttp'] == true;
    deviceName = saved['deviceName'] as String? ?? '';
    _deviceId = saved['deviceId'] as String?;
    final uri = normalizeServer(serverText);
    if (uri.scheme == 'http' && !allowHttp) {
      throw const ApiException('请确认是否允许连接不加密的 HTTP 服务');
    }
    api = _factory(uri)..token = saved['token'] as String?;
    try {
      if (api!.token != null) {
        final user = await api!.request('/auth/me');
        username = user['username'] as String;
        _deviceId = user['deviceId'] as String? ?? _deviceId;
        await _registerDevice();
        await _persist();
        stage = ConnectionStage.workspace;
        return;
      }
      await _status();
    } on ApiException catch (e) {
      if (e.status == 401) {
        api!.token = null;
        await _persist();
        await _status();
      } else {
        rethrow;
      }
    }
  });
  Future<void> connect(String address, {bool allowInsecure = false}) =>
      _run(() async {
        final uri = normalizeServer(address);
        if (uri.scheme == 'http' && !allowInsecure) {
          throw const ApiException('HTTP 不加密，请勾选仅在受信任局域网使用');
        }
        allowHttp = allowInsecure;
        api?.close();
        // Credentials and device IDs must never follow a server change.
        if (serverText != uri.toString()) {
          _deviceId = null;
          username = '';
        }
        serverText = uri.toString();
        api = _factory(uri);
        await _status();
        await _persist();
      });
  Future<void> _status() async {
    final status = await api!.request('/auth/status');
    initialized = status['initialized'] as bool;
    requiresTwoFactor = false;
    stage = ConnectionStage.credentials;
  }

  Future<void> authenticate(
    String name,
    String password,
    String label, {
    String code = '',
  }) => _run(() async {
    try {
      final session = await api!.request(
        initialized ? '/auth/login' : '/auth/setup',
        method: 'POST',
        body: {
          'username': name.trim(),
          'password': password,
          if (initialized && code.trim().isNotEmpty) 'code': code.trim(),
        },
      );
      initialized = true;
      requiresTwoFactor = false;
      api!.token = session['accessToken'] as String;
      username = session['user']['username'] as String;
      deviceName = label.trim();
      try {
        await _registerDevice();
        await _persist();
        stage = ConnectionStage.workspace;
      } catch (_) {
        try {
          await api!.request('/auth/logout', method: 'POST');
        } catch (_) {}
        api!.token = null;
        rethrow;
      }
    } on ApiException catch (e) {
      if (e.status == 409) initialized = true;
      if (e.code == 'TWO_FACTOR_REQUIRED') {
        requiresTwoFactor = true;
        error = '密码已验证，请输入验证器动态码或恢复码';
      }
      rethrow;
    }
  });
  Future<void> _registerDevice() async {
    final identity = await store.installationId();
    final body = <String, dynamic>{
      'name': deviceName.isEmpty ? 'SyncBox $platform' : deviceName,
      'platform': platform,
      'installationId': identity,
      if (_deviceId != null) 'id': _deviceId,
    };
    dynamic device;
    try {
      device = await api!.request('/devices', method: 'POST', body: body);
    } on ApiException catch (e) {
      if (e.status != 404 && e.status != 409) rethrow;
      body.remove('id');
      device = await api!.request('/devices', method: 'POST', body: body);
    }
    _deviceId = device['id'] as String;
    deviceName = device['name'] as String? ?? deviceName;
  }

  Future<void> renameDevice(String value) async {
    final name = value.trim();
    if (name.isEmpty || name.length > 80 || _deviceId == null) {
      throw const ApiException('设备名称需要为 1–80 个字符');
    }
    final result = await api!.request(
      '/devices/$_deviceId',
      method: 'PATCH',
      body: {'name': name},
    );
    deviceName = result['name'];
    await _persist();
    notifyListeners();
  }

  Future<void> logout() => _run(() async {
    await api!.request('/auth/logout', method: 'POST');
    api!.token = null;
    await _persist();
    stage = ConnectionStage.credentials;
  });
  Future<void> resetLocalSession() async {
    api?.token = null;
    _deviceId = null;
    username = '';
    initialized = false;
    requiresTwoFactor = false;
    error = null;
    await _persist();
    stage = ConnectionStage.credentials;
    notifyListeners();
  }

  Future<void> expire() => _run(() async {
    api?.token = null;
    await _persist();
    initialized = true;
    stage = ConnectionStage.credentials;
    error = '登录已失效，请重新登录';
  });
  void editServer() {
    api?.close();
    api = null;
    stage = ConnectionStage.server;
    error = null;
    notifyListeners();
  }

  Future<void> _persist() => store.save({
    'server': serverText,
    'allowHttp': allowHttp,
    'token': api?.token,
    'deviceId': _deviceId,
    'deviceName': deviceName,
  });
  Future<void> _run(Future<void> Function() work) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await work();
    } catch (e) {
      error = e is ApiException ? e.message : '操作失败，请检查网络或设备安全存储后重试';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    api?.close();
    super.dispose();
  }
}
