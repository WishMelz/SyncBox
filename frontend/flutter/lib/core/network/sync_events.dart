import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_client.dart';

/// A separately cancellable SSE connection. It uses its own HTTP client so
/// closing it never aborts an upload or another API request.
class SyncEventConnection {
  SyncEventConnection(this._client, this._request, this._onClose) {
    _events = StreamController<Map<String, dynamic>>(
      onListen: () => unawaited(_listen()),
      onCancel: close,
    );
  }

  final http.Client _client;
  final http.Request _request;
  final void Function() _onClose;
  late final StreamController<Map<String, dynamic>> _events;
  StreamSubscription<String>? _lines;
  bool _closed = false;
  Stream<Map<String, dynamic>> get stream => _events.stream;

  Future<void> _listen() async {
    try {
      final response = await _client
          .send(_request)
          .timeout(const Duration(seconds: 15));
      if (_closed) return;
      if (response.statusCode != 200) {
        throw ApiException('实时同步连接失败', response.statusCode);
      }
      if (!(response.headers['content-type'] ?? '').startsWith(
        'text/event-stream',
      )) {
        throw const ApiException('服务未提供实时同步');
      }
      _events.add({'type': 'connected'});
      final parser = SyncEventParser();
      _lines = response.stream
          .timeout(const Duration(seconds: 45))
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              try {
                final event = parser.add(line);
                if (!_closed && event != null) _events.add(event);
              } catch (error) {
                _fail(error);
              }
            },
            onError: _fail,
            onDone: close,
          );
    } catch (error) {
      _fail(error);
    }
  }

  void _fail(Object error) {
    if (!_closed) _events.addError(error);
    close();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    unawaited(_events.close());
    unawaited(_lines?.cancel());
    _client.close();
    _onClose();
  }
}

class SyncEventParser {
  final List<String> _data = [];
  String _event = '';
  int _size = 0;

  Map<String, dynamic>? add(String line) {
    if (line.isEmpty) {
      final data = _data.join('\n');
      final event = _event;
      _data.clear();
      _event = '';
      _size = 0;
      if (data.isEmpty || (event.isNotEmpty && event != 'sync')) return null;
      final decoded = jsonDecode(data);
      return decoded is Map<String, dynamic> && decoded['type'] == 'invalidate'
          ? decoded
          : null;
    }
    _size += line.length;
    if (_size > 65536) throw const FormatException('实时同步事件过大');
    if (line.startsWith(':')) return null;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'data') _data.add(value);
    if (field == 'event') _event = value;
    return null;
  }
}
