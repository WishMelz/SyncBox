import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../message_presentation.dart';

class HighlightText extends StatefulWidget {
  const HighlightText(
    this.text, {
    super.key,
    this.query = '',
    this.links = false,
    this.style,
    this.maxLines,
    this.overflow,
  });
  final String text, query;
  final bool links;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  @override
  State<HighlightText> createState() => _HighlightTextState();
}

class _HighlightTextState extends State<HighlightText> {
  final _recognizers = <TapGestureRecognizer>[];
  void clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    clear();
    final highlights = highlightRanges(widget.text, widget.query);
    final links = widget.links ? messageLinks(widget.text) : <MessageLink>[];
    final boundaries = {
      0,
      widget.text.length,
      ...highlights.expand((r) => [r.start, r.end]),
      ...links.expand((r) => [r.start, r.end]),
    }.toList()..sort();
    final spans = <TextSpan>[];
    for (var i = 0; i < boundaries.length - 1; i++) {
      final start = boundaries[i], end = boundaries[i + 1];
      final highlighted = highlights.any(
        (r) => r.start <= start && r.end >= end,
      );
      final link = links
          .where((r) => r.start <= start && r.end >= end)
          .firstOrNull;
      TapGestureRecognizer? recognizer;
      if (link != null) {
        recognizer = TapGestureRecognizer()
          ..onTap = () async {
            try {
              await openMessageLink(link.url);
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('无法打开链接，请复制后在浏览器打开。')),
                );
              }
            }
          };
        _recognizers.add(recognizer);
      }
      spans.add(
        TextSpan(
          text: widget.text.substring(start, end),
          recognizer: recognizer,
          style: TextStyle(
            backgroundColor: highlighted ? const Color(0xffffe39a) : null,
            color: highlighted
                ? const Color(0xff513b08)
                : link != null
                ? const Color(0xff126c9d)
                : null,
            decoration: link != null ? TextDecoration.underline : null,
          ),
        ),
      );
    }
    return Text.rich(
      TextSpan(children: spans),
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}
