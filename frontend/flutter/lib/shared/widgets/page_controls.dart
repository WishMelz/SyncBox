import 'package:flutter/material.dart';

class PageControls extends StatelessWidget {
  const PageControls({
    super.key,
    required this.page,
    required this.pages,
    required this.onChanged,
    required this.enabled,
  });
  final int page, pages;
  final bool enabled;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => pages <= 1
      ? const SizedBox.shrink()
      : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: '上一页',
              onPressed: enabled && page > 1 ? () => onChanged(page - 1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text('$page / $pages'),
            IconButton(
              tooltip: '下一页',
              onPressed: enabled && page < pages
                  ? () => onChanged(page + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        );
}
