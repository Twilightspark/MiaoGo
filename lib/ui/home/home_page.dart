import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/core/rank.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/game/career.dart';
import 'package:miaogo/game/career_controller.dart';
import 'package:miaogo/storage/checkin_store.dart';
import 'package:miaogo/storage/record_store.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/study/daily_problems.dart';
import 'package:miaogo/ui/common/app_icon.dart';
import 'package:miaogo/ui/common/avatar.dart';
import 'package:miaogo/ui/home/daily_session_page.dart';
import 'package:miaogo/ui/play/ai_setup_page.dart';
import 'package:miaogo/ui/play/tournament_bracket_page.dart';
import 'package:miaogo/ui/record/record_home_page.dart';
import 'package:miaogo/ui/record/review_page.dart';
import 'package:miaogo/ui/settings/settings_page.dart';
import 'package:miaogo/ui/study/joseki_list_page.dart';
import 'package:miaogo/ui/study/lessons_page.dart';
import 'package:miaogo/ui/study/problem_list_page.dart';

/// 首页：顶栏（头像/名称/设置）→ 统计卡 → 每日一题 → 快速对弈 → 当前赛事
/// → 快捷入口 → 懒加载历史记录（人机对弈 / 竞赛排名）。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final records = ref.watch(recordStoreProvider);
    final career = ref.watch(careerControllerProvider);
    final checkin = ref.watch(checkinStoreProvider);
    final daily = ref.watch(todayDailyProgressProvider);

    // 今日 5 题全部解出 → 记录打卡（幂等）。
    ref.listen<({int solved, int total})>(todayDailyProgressProvider,
        (prev, next) {
      if (next.total > 0 && next.solved >= next.total) {
        ref.read(checkinStoreProvider.notifier).markToday();
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部用户区固定不动，仅下方内容随历史记录一起滚动。
            _HomeHeader(profile: profile),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _StatsCard(
                            checkinDays: checkin.count,
                            gameCount: records.length,
                            careerPoints: profile.careerPoints,
                            rankName: RankSystem.rankName(profile.rankIndex),
                          ),
                          const SizedBox(height: 14),
                          _DailyProblemCard(
                            solved: daily.total == 0 ? 0 : daily.solved,
                            total: daily.total,
                            onStart: () =>
                                _push(context, const DailySessionPage()),
                          ),
                          const SizedBox(height: 14),
                          _QuickPlayCard(
                            onStart: () => _push(context, const AISetupPage()),
                          ),
                          const SizedBox(height: 14),
                          _CurrentTournamentCard(
                            career: career,
                            onContinue: () => _push(
                                context, const TournamentBracketPage()),
                            onSignUp: () => _showSignUpDialog(context, ref),
                          ),
                          const SizedBox(height: 20),
                          const _SectionLabel('快捷入口'),
                          const SizedBox(height: 10),
                          _QuickEntryRow(),
                          const SizedBox(height: 20),
                          const _SectionLabel('历史记录'),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),
                  _HistorySliver(
                    records: records,
                    history: career.history,
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  void _showSignUpDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _SignUpDialog(
        tournaments: ref.read(careerControllerProvider).upcoming,
        onSignUp: (id) {
          ref.read(careerControllerProvider.notifier).signUp(id);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }
}

/// 顶部用户区：头像 + 名称（展示）+ 设置按钮，三者同一水平线居中。
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AvatarView(
            key: const ValueKey('home_avatar'),
            avatarPath: profile.avatarPath,
            name: profile.name,
            radius: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                profile.name,
                key: const ValueKey('home_username'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('home_settings'),
            icon: Icon(Icons.settings_outlined,
                color: theme.colorScheme.onSurfaceVariant),
            tooltip: '设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
    );
  }
}

/// 统计卡：打卡天数 / 对局数量 / 棋手积分 / 当前棋力。
class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.checkinDays,
    required this.gameCount,
    required this.careerPoints,
    required this.rankName,
  });

  final int checkinDays;
  final int gameCount;
  final int careerPoints;
  final String rankName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Row(
          children: [
            _StatCell(
              key: const ValueKey('home_stat_checkin'),
              label: '打卡天数',
              value: '$checkinDays',
              color: GoColors.pine,
            ),
            _StatCell(
              key: const ValueKey('home_stat_games'),
              label: '对局数量',
              value: '$gameCount',
              color: GoColors.pineDark,
            ),
            _StatCell(
              key: const ValueKey('home_stat_points'),
              label: '棋手积分',
              value: '$careerPoints',
              color: GoColors.wood,
            ),
            _StatCell(
              key: const ValueKey('home_stat_rank'),
              label: '当前棋力',
              value: rankName,
              color: GoColors.woodDark,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              )),
          const SizedBox(height: 2),
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// 功能卡统一结构：左侧 SVG 圆形图标 + 中间（上标题/下描述）+ 右侧按钮。
/// 每日一题 / 快速对弈 / 赛事生涯 共用，保证样式一致。
class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.asset,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.button,
  });

  final String asset;
  final Color color;
  final String title;
  final String subtitle;
  final Widget button;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            AppIconTile(asset: asset, color: color, tile: 44, iconSize: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: GoColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 12),
            button,
          ],
        ),
      ),
    );
  }
}

/// 每日一题：进度 + 开始做题按钮。
class _DailyProblemCard extends StatelessWidget {
  const _DailyProblemCard({
    required this.solved,
    required this.total,
    required this.onStart,
  });

  final int solved;
  final int total;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final allDone = total > 0 && solved >= total;
    return _FeatureCard(
      asset: AppIcon.daily,
      color: GoColors.pine,
      title: '每日一题',
      subtitle: allDone ? '今日完成，明天继续' : '今日进度 $solved/$total',
      button: FilledButton.icon(
        key: const ValueKey('home_daily_start'),
        onPressed: onStart,
        icon: const Icon(Icons.play_arrow, size: 18),
        label: Text(allDone ? '再练一题' : '做题'),
      ),
    );
  }
}

/// 快速对弈卡：左侧标题 + 右侧开始按钮。
class _QuickPlayCard extends StatelessWidget {
  const _QuickPlayCard({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return _FeatureCard(
      asset: AppIcon.play,
      color: GoColors.pineDark,
      title: '快速对弈',
      subtitle: '人机对弈 · 随时开局',
      button: FilledButton.icon(
        key: const ValueKey('home_quick_play_button'),
        onPressed: onStart,
        icon: const Icon(Icons.play_arrow, size: 18),
        label: const Text('开始'),
      ),
    );
  }
}

/// 当前赛事卡：已报名展示赛事信息+继续比赛；未报名展示提示+去报名。
class _CurrentTournamentCard extends StatelessWidget {
  const _CurrentTournamentCard({
    required this.career,
    required this.onContinue,
    required this.onSignUp,
  });

  final CareerState career;
  final VoidCallback onContinue;
  final VoidCallback onSignUp;

  @override
  Widget build(BuildContext context) {
    final active = career.active;
    if (active == null) {
      return _FeatureCard(
        asset: AppIcon.tournament,
        color: GoColors.wood,
        title: '赛事生涯',
        subtitle: '尚未报名',
        button: FilledButton.icon(
          key: const ValueKey('home_tournament_signup'),
          onPressed: onSignUp,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('报名'),
        ),
      );
    }

    return _FeatureCard(
      asset: AppIcon.tournament,
      color: GoColors.wood,
      title: '赛事生涯',
      subtitle: active.name,
      button: FilledButton.icon(
        key: const ValueKey('home_tournament_continue'),
        onPressed: onContinue,
        icon: const Icon(Icons.play_arrow, size: 18),
        label: const Text('比赛'),
      ),
    );
  }
}

/// 报名弹窗：列出待报名赛事。
class _SignUpDialog extends StatelessWidget {
  const _SignUpDialog({required this.tournaments, required this.onSignUp});

  final List<CareerTournament> tournaments;
  final void Function(String id) onSignUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('报名大赛'),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final t in tournaments)
              ListTile(
                key: ValueKey('signup_option_${t.boardSize}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.emoji_events, color: GoColors.wood),
                title: Text(t.name,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${t.boardSize} 路 · ${t.rule.label}规则 · 8 人淘汰赛',
                  style: theme.textTheme.bodySmall,
                ),
                trailing: FilledButton(
                  key: ValueKey('signup_button_${t.boardSize}'),
                  onPressed: () => onSignUp(t.id),
                  child: const Text('报名'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

/// 快捷入口：横向可滚动区域（数据驱动，便于扩充）。
class _QuickEntryRow extends StatelessWidget {
  const _QuickEntryRow();

  static const _entries = <_QuickEntry>[
    _QuickEntry(AppIcon.basics, '入门', GoColors.pine, LessonsPage.new),
    _QuickEntry(AppIcon.joseki, '定式', GoColors.wood, JosekiListPage.new),
    _QuickEntry(
        AppIcon.library, '题库', GoColors.pineDark, ProblemListPage.new),
    _QuickEntry(
        AppIcon.record, '棋谱', GoColors.woodDark, RecordHomePage.new),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 20),
        itemBuilder: (context, i) {
          final e = _entries[i];
          return InkWell(
            key: ValueKey('home_quick_entry_${e.label}'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => e.builder()),
            ),
            child: SizedBox(
              width: 72,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIconTile(
                      asset: e.asset, color: e.color, tile: 48, iconSize: 26),
                  const SizedBox(height: 8),
                  Text(e.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: GoColors.textPrimary,
                      )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _QuickEntry {
  const _QuickEntry(this.asset, this.label, this.color, this.builder);
  final String asset;
  final String label;
  final Color color;
  final Widget Function() builder;
}

/// 历史记录懒加载列表：人机对弈 + 竞赛排名（按日期倒序混合）。
class _HistorySliver extends ConsumerWidget {
  const _HistorySliver({required this.records, required this.history});

  final List<GameRecord> records;
  final List<CareerResult> history;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = records.where((r) => r.source == GameSource.ai).toList();
    final items = <_HistoryItem>[
      for (final g in games) _HistoryGameItem(g),
      for (final c in history) _HistoryCompItem(c, records),
    ]..sort((a, b) => b.date.compareTo(a.date));

    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
          child: Center(
            child: Text(
              '暂无对局与竞赛记录，去下一盘棋吧',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: GoColors.textSecondary),
            ),
          ),
        ),
      );
    }
    return SliverList.builder(
      itemCount: items.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: items[i].build(context, ref),
      ),
    );
  }
}

sealed class _HistoryItem {
  DateTime get date;
  Widget build(BuildContext context, WidgetRef ref);
}

class _HistoryGameItem extends _HistoryItem {
  _HistoryGameItem(this.record);
  final GameRecord record;
  @override
  DateTime get date => record.date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _GameHistoryCard(record: record);
  }
}

class _HistoryCompItem extends _HistoryItem {
  _HistoryCompItem(this.result, this.records);
  final CareerResult result;
  final List<GameRecord> records;
  @override
  DateTime get date => result.date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = records
        .where((r) =>
            r.tournamentId == result.tournamentId &&
            r.source == GameSource.career)
        .toList();
    return _CompHistoryCard(result: result, games: games);
  }
}

/// 单局人机对弈卡片：点击复盘。
class _GameHistoryCard extends ConsumerWidget {
  const _GameHistoryCard({required this.record});

  final GameRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final resultColor = switch (record.result) {
      GameResult.win => GoColors.pine,
      GameResult.loss => GoColors.textSecondary,
      GameResult.draw => GoColors.wood,
    };
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: AppIconTile(
            asset: AppIcon.history,
            color: GoColors.pineDark,
            tile: 40,
            iconSize: 22),
        title: Text(record.opponentName,
            style:
                theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${_fmtShortDate(record.date)} · ${record.boardSize} 路 · '
          '${record.rule.label} · ${record.moveCount} 手',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(record.result.label,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: resultColor,
                  fontWeight: FontWeight.bold,
                )),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
        onTap: () => _openReview(context, ref),
      ),
    );
  }

  Future<void> _openReview(BuildContext context, WidgetRef ref) async {
    final content =
        await ref.read(recordStoreProvider.notifier).sgfContentOf(record);
    if (content == null || content.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该棋谱文件缺失，无法复盘')),
        );
      }
      return;
    }
    try {
      final game = Sgf.parse(content);
      if (!context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ReviewPage(game: game, title: record.opponentName),
      ));
    } on FormatException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('棋谱解析失败')),
        );
      }
    }
  }
}

/// 竞赛排名卡片：点击展开该赛事个人对局列表，再点击单局复盘。
class _CompHistoryCard extends ConsumerStatefulWidget {
  const _CompHistoryCard({required this.result, required this.games});

  final CareerResult result;
  final List<GameRecord> games;

  @override
  ConsumerState<_CompHistoryCard> createState() => _CompHistoryCardState();
}

class _CompHistoryCardState extends ConsumerState<_CompHistoryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = widget.result;
    final games = widget.games;
    final withdrawn = result.withdrawn;
    final label = withdrawn
        ? '退赛'
        : (result.champion
            ? '冠军'
            : careerPlacementLabel(result.placement));
    final color = withdrawn
        ? GoColors.textSecondary
        : (result.champion ? GoColors.wood : GoColors.pine);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            onTap: () => setState(() => _expanded = !_expanded),
            leading: AppIconTile(
                asset: AppIcon.competition,
                color: GoColors.wood,
                tile: 40,
                iconSize: 22),
            title: Text(result.tournamentName,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text(
              '${result.boardSize} 路 · ${_fmtShortDate(result.date)}'
              '${withdrawn ? '' : ' · +${result.points} 分'}'
              '${games.isEmpty ? '' : ' · ${games.length} 局'}',
              style: theme.textTheme.bodySmall,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(label,
                      style: const TextStyle(
                        color: GoColors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      )),
                ),
                const SizedBox(width: 6),
                Icon(_expanded
                    ? Icons.expand_less
                    : Icons.expand_more),
              ],
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            if (games.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('暂无本赛事对局记录',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: GoColors.textSecondary)),
              )
            else
              for (final g in games)
                ListTile(
                  contentPadding: const EdgeInsets.only(
                      left: 44, right: 16, top: 2, bottom: 2),
                  dense: true,
                  leading: SvgPicture.asset(AppIcon.history,
                      width: 16, height: 16),
                  title: Text(g.opponentName,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${_fmtShortDate(g.date)} · ${g.rule.label} · '
                    '${g.moveCount} 手',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: Text(
                    g.result.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: g.result == GameResult.win
                          ? GoColors.pine
                          : (g.result == GameResult.draw
                              ? GoColors.wood
                              : GoColors.textSecondary),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () => _openReview(context, g),
                ),
          ],
        ],
      ),
    );
  }

  Future<void> _openReview(BuildContext context, GameRecord record) async {
    final content =
        await ref.read(recordStoreProvider.notifier).sgfContentOf(record);
    if (!context.mounted) return;
    if (content == null || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该棋谱文件缺失，无法复盘')),
      );
      return;
    }
    try {
      final game = Sgf.parse(content);
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ReviewPage(game: game, title: record.opponentName),
      ));
    } on FormatException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('棋谱解析失败')),
        );
      }
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

String _fmtShortDate(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

