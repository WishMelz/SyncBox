import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:file_selector/file_selector.dart';

import 'sync_events.dart';

class ApiException implements Exception {
  const ApiException(this.message, [this.status, this.code]);
  final String message;
  final int? status;
  final String? code;
  @override
  String toString() => message;
}

/// Accepts the server origin, never a token-bearing URL or an API endpoint.
Uri normalizeServer(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const ApiException('请输入服务地址，例如 https://sync.example.com（不含 /api）');
  }
  return uri.replace(path: '');
}

class ApiClient {
  ApiClient(
    this.server, {
    http.Client? client,
    http.Client Function()? eventClientFactory,
  }) : _client = client ?? http.Client(),
       _eventClientFactory = eventClientFactory ?? http.Client.new;
  final Uri server;
  final http.Client _client;
  final http.Client Function() _eventClientFactory;
  final Set<SyncEventConnection> _eventConnections = {};
  String? token;
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, String>? query,
    Object? body,
  }) async {
    final uri = server.replace(path: '/api/v1$path', queryParameters: query);
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(const Duration(seconds: 15));
      if (response.statusCode == 204) return null;
      dynamic data;
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        throw ApiException('服务响应格式错误，请确认地址与反向代理配置', response.statusCode);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = data is Map ? data['message'] : null;
        throw ApiException(
          message is List ? message.join('；') : message?.toString() ?? '请求失败',
          response.statusCode,
          data is Map ? data['code']?.toString() : null,
        );
      }
      return data;
    } on TimeoutException {
      throw const ApiException('连接超时，请检查服务地址和网络');
    } on SocketException {
      throw const ApiException('无法连接服务，请检查网络');
    } on http.ClientException {
      throw const ApiException('网络连接失败，请稍后重试');
    }
  }

  /// Opens the authenticated server event stream. The stream only carries
  /// invalidation metadata, so callers should reload the affected resource.
  SyncEventConnection events() {
    final request = http.Request('GET', server.replace(path: '/api/v1/events'))
      ..followRedirects = false;
    request.headers['Accept'] = 'text/event-stream';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    late final SyncEventConnection connection;
    connection = SyncEventConnection(
      _eventClientFactory(),
      request,
      () => _eventConnections.remove(connection),
    );
    _eventConnections.add(connection);
    return connection;
  }

  Future<Uint8List> imageBytes(String messageId) async {
    final request = http.Request(
      'GET',
      server.replace(path: '/api/v1/messages/$messageId/image'),
    )..followRedirects = false;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    final response = await http.Response.fromStream(await _client.send(request))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw ApiException('图片加载失败', response.statusCode);
    }
    return response.bodyBytes;
  }

  Future<void> sendImage(
    String conversationId,
    Uint8List bytes,
    String content, [
    String? clientId,
  ]) async {
    final request = http.MultipartRequest(
      'POST',
      server.replace(path: '/api/v1/conversations/$conversationId/images'),
    )..followRedirects = false;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.fields['content'] = content;
    if (clientId != null) request.fields['clientId'] = clientId;
    request.files.add(
      http.MultipartFile.fromBytes('image', bytes, filename: 'image'),
    );
    final response = await http.Response.fromStream(await _client.send(request))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      dynamic message;
      try {
        message = (jsonDecode(response.body) as Map)['message'];
      } catch (_) {}
      throw ApiException(message?.toString() ?? '图片发送失败', response.statusCode);
    }
  }

  Future<Uint8List> attachmentBytes(
    String messageId,
    String attachmentId, {
    bool preview = false,
  }) async {
    final request = http.Request(
      'GET',
      server.replace(
        path:
            '/api/v1/messages/$messageId/attachments/$attachmentId${preview ? '/preview' : ''}',
      ),
    )..followRedirects = false;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    final response = await http.Response.fromStream(await _client.send(request))
        .timeout(const Duration(seconds: 120));
    if (response.statusCode != 200) {
      throw ApiException('文件读取失败或已被清理', response.statusCode);
    }
    return response.bodyBytes;
  }

  Future<void> sendFiles(
    String conversationId,
    List<XFile> files,
    String content, [
    String? clientId,
  ]) async {
    var total = 0;
    if (files.isEmpty || files.length > 5) {
      throw const ApiException('请选择 1–5 个文件');
    }
    for (final file in files) {
      final size = await file.length();
      if (size == 0) throw const ApiException('不能发送空文件');
      total += size;
    }
    if (total > 20 * 1024 * 1024) throw const ApiException('附件合计不能超过 20 MB');
    final request = http.MultipartRequest(
      'POST',
      server.replace(path: '/api/v1/conversations/$conversationId/attachments'),
    )..followRedirects = false;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.fields['content'] = content;
    if (clientId != null) request.fields['clientId'] = clientId;
    request.fields['names'] = jsonEncode(files.map((f) => f.name).toList());
    for (final file in files) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'files',
          await file.readAsBytes(),
          // Keep the multipart filename as a fallback for older servers. The
          // UTF-8 names field remains the canonical value.
          filename: file.name,
        ),
      );
    }
    final response = await http.Response.fromStream(await _client.send(request))
        .timeout(const Duration(seconds: 120));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      dynamic message;
      try {
        message = (jsonDecode(response.body) as Map)['message'];
      } catch (_) {}
      throw ApiException(message?.toString() ?? '附件发送失败', response.statusCode);
    }
  }

  void close() {
    for (final connection in _eventConnections.toList()) {
      connection.close();
    }
    _client.close();
  }
}
