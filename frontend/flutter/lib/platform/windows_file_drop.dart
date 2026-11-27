import 'dart:async';

import 'package:flutter/services.dart';

typedef WindowFileDrop = ({Offset pixels, List<String> paths});

// Coordinates from Explorer are client pixels, independent of Flutter's DPI.
final windowsFileDrops = _listen();

Stream<WindowFileDrop> _listen() {
  final events = StreamController<WindowFileDrop>.broadcast(sync: true);
  const MethodChannel('syncbox/file-drop').setMethodCallHandler((call) async {
    if (call.method != 'drop') return;
    final args = call.arguments as List;
    events.add((
      pixels: Offset((args[0] as int).toDouble(), (args[1] as int).toDouble()),
      paths: (args[2] as List).cast<String>(),
    ));
  });
  return events.stream;
}
