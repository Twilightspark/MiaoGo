import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/game/career.dart';
import 'package:miaogo/game/career_controller.dart';
import 'package:miaogo/ui/play/tournament_bracket_page.dart';

/// 生涯模式主页（P3）：
/// 顶部「当前参加的比赛」→ 中部 9/13/19 三场待报名大赛 → 底部历史竞赛成绩。
class CareerPage extends ConsumerWidget {
  const CareerPage({super.key});

  static const _roundNames = ['1/4 决赛', '半决赛', '决赛'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final career = ref.watch(careerControllerProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('生涯大赛')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionLabel('当前参加的比赛'),
          _ActiveTournamentCard(career: career, onOpen: () {
            final active = career.active;
            if (active == null) return;
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const TournamentBracketPage()),
            );
          }, onWithdraw: () async {
            if (!context.mounted) return;
            await _confirmWithdraw(context, ref);
          }),
          const SizedBox(height: 20),
          const _SectionLabel('即将举行的比赛'),
          ...career.upcoming.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _UpcomingCard(
                  tournament: t,
                  canSignUp: career.active == null,
                  onSignUp: () async {
                    if (!context.mounted) return;
                    await _confirmSignUp(context, ref, t);
                  },
                ),
              )),
          const SizedBox(height: 12),
          const _SectionLabel('历史竞赛成绩'),
          if (career.history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '暂无历史成绩，报名参加一场大赛吧',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: GoColors.textSecondary),
              ),
            )
          else
            ...career.history.map((h) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _HistoryCard(record: h),
                )),
        ],
      ),
    );
  }

  Future<void> _confirmSignUp(
      BuildContext context, WidgetRef ref, CareerTournament t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('报名大赛'),
        content: Text('确认报名「${t.name}」吗？\n'
            '${t.boardSize} 路 · ${t.rule.label}规则 · 8 人淘汰赛'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('career_confirm_signup'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('报名'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      final signed = ref.read(careerControllerProvider.notifier).signUp(t.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(signed ? '报名成功，已加入赛程' : '当前已有一场进行中的大赛'),
        ));
      }
    }
  }

  Future<void> _confirmWithdraw(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退赛'),
        content: const Text('退赛将无法获得本场大赛的任何积分奖励，确定退赛吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('career_confirm_withdraw'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退赛'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      ref.read(careerControllerProvider.notifier).withdraw();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已退赛，本场无积分')));
      }
    }
  }
}

/// 「当前参加的比赛」卡片。
class _ActiveTournamentCard extends StatelessWidget {
  const _ActiveTournamentCard({
    required this.career,
    required this.onOpen,
    required this.onWithdraw,
  });

  final CareerState career;
  final VoidCallback onOpen;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = career.active;
    if (active == null) {
      return Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: GoColors.pine.withValues(alpha: 0.12),
                child: const Icon(Icons.emoji_events_outlined,
                    color: GoColors.wood),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '尚未报名任何大赛，请在下方向比赛中报名',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final round = active.currentRound;
    final player = active.player!;
    var wins = 0;
    for (final m in active.matches) {
      if (m.decided && m.involves(player.id) && m.winnerId == player.id) {
        wins++;
      }
    }
    return Card(
      elevation: 0,
      color: GoColors.woodContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_events, color: GoColors.wood, size: 26),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    active.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: GoColors.pine,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    active.status.label,
                    style: const TextStyle(
                      color: GoColors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${active.boardSize} 路 · ${active.rule.label}规则 · 已胜 $wins 场'
              '${round == null ? '' : ' · 当前 ${CareerPage._roundNames[round]}'}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('career_open_bracket'),
                    onPressed: onOpen,
                    icon: const Icon(Icons.account_tree_outlined),
                    label: const Text('查看赛程'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const ValueKey('career_withdraw'),
                  onPressed: onWithdraw,
                  child: const Text('退赛'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 待报名大赛卡（9/13/19 路）。
class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({
    required this.tournament,
    required this.canSignUp,
    required this.onSignUp,
  });

  final CareerTournament tournament;
  final bool canSignUp;
  final VoidCallback onSignUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = tournament.players
        .where((p) => !p.isPlayer)
        .take(3)
        .map((p) => p.name)
        .join('、');
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: GoColors.pine.withValues(alpha: 0.12),
              child: Text(
                '${tournament.boardSize}',
                style: const TextStyle(
                  color: GoColors.pineDark,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          tournament.name,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${tournament.boardSize} 路',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: GoColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${tournament.rule.label}规则 · 8 人 · 如 $preview',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: ValueKey('career_signup_${tournament.boardSize}'),
              onPressed: canSignUp ? onSignUp : null,
              child: Text(canSignUp ? '报名' : '进行中'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 历史竞赛成绩卡。
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.record});

  final CareerResult record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final withdrawn = record.withdrawn;
    final label = withdrawn
        ? '退赛'
        : (record.champion
            ? '冠军'
            : careerPlacementLabel(record.placement));
    final color = withdrawn
        ? GoColors.textSecondary
        : (record.champion ? GoColors.wood : GoColors.pine);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: color.withValues(alpha: 0.14),
          child: Icon(
            record.champion ? Icons.emoji_events : Icons.flag_outlined,
            color: color,
            size: 22,
          ),
        ),
        title: Text(record.tournamentName,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${record.boardSize} 路 · ${_fmtDate(record.date)}'
          '${withdrawn ? '' : ' · +${record.points} 分'}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: GoColors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.'
      '${d.day.toString().padLeft(2, '0')}';
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
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
