import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;

import '../crypto/sha256.dart';
import 'media_cache.dart';
import 'sync_events.dart';

class UploadFile {
  UploadFile.bytes({required this.name, required Uint8List bytes})
    : size = bytes.length,
      _bytes = bytes,
      file = null;

  const UploadFile.xfile({
    required this.name,
    required this.size,
    required XFile this.file,
  }) : _bytes = null;

  final String name;
  final int size;
  final Uint8List? _bytes;
  final XFile? file;

  Stream<List<int>> openRead() {
    if (file != null) return file!.openRead();
    return Stream<List<int>>.value(_bytes ?? Uint8List(0));
  }
}

class UploadProgress {
  const UploadProgress({required this.loaded, required this.total});
  final int loaded;
  final int total;
  int get percent =>
      total <= 0 ? 100 : ((loaded * 100) ~/ total).clamp(0, 100);
}

class UploadCancelledException implements Exception {
  const UploadCancelledException();
  @override
  String toString() => '已取消上传';
}

class UploadCancelToken {
  bool _cancelled = false;
  http.Client? _client;
  bool get isCancelled => _cancelled;

  void _bind(http.Client client) {
    _client = client;
    if (_cancelled) client.close();
  }

  void cancel() {
    _cancelled = true;
    _client?.close();
  }
}

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
    this.uploadClientFactory,
  }) : _client = client ?? http.Client(),
       _usesCustomClient = client != null,
       _eventClientFactory = eventClientFactory ?? http.Client.new;

  final Uri server;
  final http.Client _client;
  final bool _usesCustomClient;
  final http.Client Function() _eventClientFactory;
  final http.Client Function()? uploadClientFactory;
  final Set<SyncEventConnection> _eventConnections = {};
  final MemoryMediaCache mediaCache = MemoryMediaCache();
  String? _token;

  String? get token => _token;
  set token(String? value) {
    if (_token != value) {
      mediaCache.clear();
      _token = value;
    }
  }

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

  Future<Uint8List> imageBytes(String messageId) {
    final path = '/messages/$messageId/image';
    return mediaCache.getOrFetch(server, token, path, () async {
      final request = http.Request('GET', server.replace(path: '/api/v1$path'))
        ..followRedirects = false;
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      final response = await http.Response.fromStream(
        await _client.send(request),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw ApiException('图片加载失败', response.statusCode);
      }
      return response.bodyBytes;
    });
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
    final response = await http.Response.fromStream(
      await _client.send(request),
    ).timeout(const Duration(seconds: 30));
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
  }) {
    final path =
        '/messages/$messageId/attachments/$attachmentId${preview ? '/preview' : ''}';
    Future<Uint8List> fetch() async {
      final request = http.Request('GET', server.replace(path: '/api/v1$path'))
        ..followRedirects = false;
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      final response = await http.Response.fromStream(
        await _client.send(request),
      ).timeout(const Duration(seconds: 120));
      if (response.statusCode != 200) {
        throw ApiException('文件读取失败或已被清理', response.statusCode);
      }
      return response.bodyBytes;
    }

    if (preview) {
      return mediaCache.getOrFetch(server, token, path, fetch);
    }
    return fetch();
  }

  Future<void> removeAttachment(String messageId, String attachmentId) async {
    await request(
      '/messages/$messageId/attachments/$attachmentId',
      method: 'DELETE',
    );
    mediaCache.invalidatePath('/messages/$messageId/attachments/$attachmentId');
  }

  Future<void> removeImage(String messageId) async {
    await request('/messages/$messageId/image', method: 'DELETE');
    mediaCache.invalidatePath('/messages/$messageId/image');
  }

  Future<void> sendFiles(
    String conversationId,
    List<UploadFile> files,
    String content, [
    String? clientId,
    void Function(UploadProgress)? onProgress,
    UploadCancelToken? cancelToken,
  ]) async {
    var total = 0;
    if (files.isEmpty || files.length > 5) {
      throw const ApiException('请选择 1–5 个文件');
    }
    for (final file in files) {
      if (file.size == 0) throw const ApiException('不能发送空文件');
      total += file.size;
    }
    if (total > 20 * 1024 * 1024) {
      throw const ApiException('附件合计不能超过 20 MB');
    }
    if (cancelToken?.isCancelled == true) {
      throw const UploadCancelledException();
    }

    final request = http.MultipartRequest(
      'POST',
      server.replace(path: '/api/v1/conversations/$conversationId/attachments'),
    )..followRedirects = false;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.fields['content'] = content;
    if (clientId != null) request.fields['clientId'] = clientId;
    request.fields['names'] = jsonEncode(files.map((f) => f.name).toList());

    var loaded = 0;
    onProgress?.call(UploadProgress(loaded: 0, total: total));
    for (final file in files) {
      Stream<List<int>> progressStream() async* {
        await for (final chunk in file.openRead()) {
          if (cancelToken?.isCancelled == true) {
            throw const UploadCancelledException();
          }
          loaded += chunk.length;
          onProgress?.call(UploadProgress(loaded: loaded, total: total));
          yield chunk;
        }
      }

      request.files.add(
        http.MultipartFile(
          'files',
          http.ByteStream(progressStream()),
          file.size,
          // Keep the multipart filename as a fallback for older servers. The
          // UTF-8 names field remains the canonical value.
          filename: file.name,
        ),
      );
    }

    final ownsClient = uploadClientFactory != null || !_usesCustomClient;
    final uploadClient = uploadClientFactory != null
        ? uploadClientFactory!()
        : (ownsClient ? http.Client() : _client);
    cancelToken?._bind(uploadClient);

    try {
      final response = await http.Response.fromStream(
        await uploadClient.send(request),
      ).timeout(const Duration(seconds: 120));
      if (cancelToken?.isCancelled == true) {
        throw const UploadCancelledException();
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        dynamic message;
        try {
          message = (jsonDecode(response.body) as Map)['message'];
        } catch (_) {}
        throw ApiException(message?.toString() ?? '附件发送失败', response.statusCode);
      }
    } on UploadCancelledException {
      rethrow;
    } on http.ClientException {
      if (cancelToken?.isCancelled == true) {
        throw const UploadCancelledException();
      }
      throw const ApiException('网络连接失败，请稍后重试');
    } on TimeoutException {
      throw const ApiException('上传超时，附件已保留');
    } on SocketException {
      if (cancelToken?.isCancelled == true) {
        throw const UploadCancelledException();
      }
      throw const ApiException('无法连接服务，请检查网络');
    } finally {
      if (ownsClient) uploadClient.close();
    }
  }

  Future<({Uint8List bytes, String sha256, String filename, int size})>
  downloadBackup() async {
    final request = http.Request(
      'GET',
      server.replace(path: '/api/v1/settings/backup'),
    )..followRedirects = false;
    request.headers['Accept'] = 'application/x-sqlite3';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    try {
      final response = await http.Response.fromStream(
        await _client.send(request),
      ).timeout(const Duration(seconds: 120));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        dynamic message;
        try {
          message = (jsonDecode(utf8.decode(response.bodyBytes)) as Map)['message'];
        } catch (_) {}
        throw ApiException(
          message?.toString() ?? '备份下载失败，请重试',
          response.statusCode,
        );
      }
      final expected = response.headers['x-syncbox-backup-sha256']
          ?.toLowerCase();
      if (expected == null || expected.isEmpty) {
        throw const ApiException('备份缺少完整性校验信息，未保存文件');
      }
      final actual = sha256Hex(response.bodyBytes);
      if (actual != expected) {
        throw const ApiException('备份校验失败，未保存文件');
      }
      final disposition = response.headers['content-disposition'] ?? '';
      final match = RegExp(r'filename="([^"]+)"').firstMatch(disposition);
      final filename =
          match?.group(1) ??
          'syncbox-backup-${DateTime.now().toIso8601String().substring(0, 10)}.sqlite';
      return (
        bytes: response.bodyBytes,
        sha256: actual,
        filename: filename,
        size: response.bodyBytes.length,
      );
    } on TimeoutException {
      throw const ApiException('备份下载超时，请重试');
    } on SocketException {
      throw const ApiException('无法连接服务，请检查网络');
    } on http.ClientException {
      throw const ApiException('网络连接失败，请稍后重试');
    }
  }

  void close() {
    for (final connection in _eventConnections.toList()) {
      connection.close();
    }
    mediaCache.clear();
    _client.close();
  }
}
