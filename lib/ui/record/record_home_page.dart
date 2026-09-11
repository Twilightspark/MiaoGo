import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/storage/record_store.dart';
import 'package:miaogo/ui/common/app_icon.dart';
import 'package:miaogo/ui/common/responsive.dart';
import 'package:miaogo/ui/record/review_page.dart';
import 'package:miaogo/ui/record/sgf_import.dart';

/// 棋谱页：观赛保存 + 本地导入的棋谱库，点击进入回看页。
///
/// 个人对局（生涯/人机）仍保存在记录库中，但不再于此展示
/// （回看入口在首页「历史记录」）。历史名谱/研究棋谱入口已移除。
class RecordHomePage extends ConsumerStatefulWidget {
  const RecordHomePage({super.key});

  @override
  ConsumerState<RecordHomePage> createState() => _RecordHomePageState();
}

class _RecordHomePageState extends ConsumerState<RecordHomePage> {
  /// 读取棋谱 SGF 并进入回看。
  Future<void> _openRecord(GameRecord record) async {
    final content = await ref
        .read(recordStoreProvider.notifier)
        .sgfContentOf(record);
    if (!mounted) return;
    if (content == null || content.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('该棋谱文件缺失，无法回看')));
      return;
    }
    try {
      final game = Sgf.parse(content);
      if (!mounted) return;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => ReviewPage(game: game)));
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('棋谱解析失败')));
      }
    }
  }

  /// 从本地导入 SGF：解析成功后作为新条目存入列表，不自动跳转。
  Future<void> _importSgf() async {
    final content = await ref.read(sgfPickerProvider)();
    if (!mounted || content == null) return;
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final record = importedRecordFromContent(
        id: newImportedRecordId(),
        content: trimmed,
      );
      await ref.read(recordStoreProvider.notifier).add(record);
      if (mounted) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('棋谱已导入')));
      }
    } on FormatException {
      if (mounted) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('SGF 文件解析失败')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(recordStoreProvider);
    final library = _libraryOf(records);
    return Scaffold(
      appBar: AppBar(
        title: const Text('棋谱'),
        actions: [
          IconButton(
            key: const ValueKey('record_import'),
            tooltip: '导入 SGF',
            icon: const Icon(Icons.file_open_outlined),
            onPressed: _importSgf,
          ),
        ],
      ),
      body: CenteredContent(
        maxWidth: 720,
        child: library.isEmpty
            ? const _EmptyPlaceholder(text: '暂无棋谱，观赛后保存或点右上角导入')
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: library.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) =>
                    _RecordCard(record: library[i], onTap: _openRecord),
              ),
      ),
    );
  }

  /// 仅取「观赛保存」与「导入」棋谱，按日期倒序。
  static List<GameRecord> _libraryOf(List<GameRecord> all) {
    final list =
        all
            .where(
              (r) =>
                  r.source == GameSource.watch ||
                  r.source == GameSource.imported,
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record, required this.onTap});

  final GameRecord record;
  final void Function(GameRecord) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWatch = record.source == GameSource.watch;
    final (black, white) = (record.blackName, record.whiteName);
    final title = (black != null && white != null)
        ? '$black 对 $white'
        : record.opponentName;
    final date = record.date;
    final dateText =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final resultColor = switch (record.result) {
      GameResult.win => GoColors.pine,
      GameResult.loss => GoColors.textSecondary,
      GameResult.draw => GoColors.wood,
      GameResult.abandoned => GoColors.textSecondary,
    };
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: AppIconTile(
          asset: isWatch ? AppIcon.watch : AppIcon.record,
          color: isWatch ? GoColors.pine : GoColors.wood,
          tile: 40,
          iconSize: 22,
        ),
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '$dateText · ${record.boardSize} 路 · ${record.rule.label} · '
          '${record.source.label} · ${record.moveCount} 手',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _resultLabel(record.result),
              style: theme.textTheme.titleMedium?.copyWith(
                color: resultColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
        onTap: () => onTap(record),
      ),
    );
  }

  /// 观赛 / 导入棋谱按棋盘视角呈现胜负（黑方胜 → 黑胜）。
  static String _resultLabel(GameResult r) => switch (r) {
    GameResult.win => '黑胜',
    GameResult.loss => '白胜',
    GameResult.draw => '和棋',
    GameResult.abandoned => '未下完',
  };
}

class _EmptyPlaceholder extends StatelessWidget {
  const _EmptyPlaceholder({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.filter_none, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
