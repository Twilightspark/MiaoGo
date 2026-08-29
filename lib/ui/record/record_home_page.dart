import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/storage/record_store.dart';
import 'package:miaogo/ui/common/rank_badge.dart';
import 'package:miaogo/ui/record/famous_games.dart';
import 'package:miaogo/ui/record/review_page.dart';

/// 棋谱页：个人棋谱 / 历史名谱 / 研究棋谱 三类 Tab。
class RecordHomePage extends ConsumerStatefulWidget {
  const RecordHomePage({super.key});

  @override
  ConsumerState<RecordHomePage> createState() => _RecordHomePageState();
}

class _RecordHomePageState extends ConsumerState<RecordHomePage> {
  /// 读取个人棋谱 SGF 并进入复盘。
  Future<void> _openRecord(GameRecord record) async {
    final content =
        await ref.read(recordStoreProvider.notifier).sgfContentOf(record);
    if (!mounted) return;
    if (content == null || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该棋谱文件缺失，无法复盘')),
      );
      return;
    }
    try {
      final game = Sgf.parse(content);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ReviewPage(game: game, title: record.opponentName),
      ));
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('棋谱解析失败')),
        );
      }
    }
  }

  void _openFamous(FamousGame game) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReviewPage(game: game.game, title: game.info.title),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(recordStoreProvider);
    final famous = ref.watch(famousGamesProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('棋谱'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '个人棋谱'),
              Tab(text: '历史名谱'),
              Tab(text: '研究棋谱'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            records.isEmpty
                ? const _EmptyPlaceholder(text: '暂无个人棋谱，对弈后自动保存')
                : _RecordList(records: records, onTap: _openRecord),
            _FamousList(
              famous: famous,
              onTap: _openFamous,
            ),
            const _EmptyPlaceholder(text: '创建空白棋盘自由研究（开发中）'),
          ],
        ),
      ),
    );
  }
}

class _RecordList extends StatelessWidget {
  const _RecordList({required this.records, required this.onTap});

  final List<GameRecord> records;
  final void Function(GameRecord) onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: records.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _RecordCard(record: records[i], onTap: onTap),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record, required this.onTap});

  final GameRecord record;
  final void Function(GameRecord) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resultColor = switch (record.result) {
      GameResult.win => GoColors.pine,
      GameResult.loss => GoColors.textSecondary,
      GameResult.draw => GoColors.wood,
    };
    final date = record.date;
    final dateText =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: RankBadge(rankIndex: record.opponentRank, size: 22),
        title: Text(
          record.opponentName,
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
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
              record.result.label,
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
}

/// 历史名谱列表（加载中/失败/内容三态）。
class _FamousList extends StatelessWidget {
  const _FamousList({required this.famous, required this.onTap});

  final AsyncValue<List<FamousGame>> famous;
  final void Function(FamousGame) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return famous.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _EmptyPlaceholder(text: '名谱加载失败：$e'),
      data: (games) => games.isEmpty
          ? const _EmptyPlaceholder(text: '暂无内置名谱')
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: games.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final g = games[i];
                return Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: GoColors.woodContainer,
                      child: const Icon(Icons.emoji_events,
                          color: GoColors.wood),
                    ),
                    title: Text(
                      g.info.title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${g.blackName} 对 ${g.whiteName}'
                      '${g.result.isEmpty ? '' : ' · ${g.result}'}'
                      '${g.date.isEmpty ? '' : ' · ${g.date}'}\n${g.info.subtitle}',
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => onTap(g),
                  ),
                );
              },
            ),
    );
  }
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
          Text(text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
