import 'package:flutter/material.dart';

/// 设置页系列页面的统一顶栏。
///
/// 与列表项（如「音效」）标题字号一致（约 16），居中显示，返回箭头缩小。
/// [action] 可放置右上角操作（如选项页的「完成」确认钮）。
AppBar settingsAppBar(BuildContext context, String title, {Widget? action}) {
  final theme = Theme.of(context);
  return AppBar(
    centerTitle: true,
    leading: IconButton(
      onPressed: () => Navigator.of(context).maybePop(),
      tooltip: '返回',
      icon: Icon(
        Icons.arrow_back,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
    title: Text(
      title,
      style: theme.textTheme.bodyLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface,
      ),
    ),
    actions: [?action],
  );
}
