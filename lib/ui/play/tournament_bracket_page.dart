import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rank.dart';
import 'package:miaogo/engine/engine_controller.dart';
import 'package:miaogo/engine/katago_engine.dart';
import 'package:miaogo/game/career.dart';
import 'package:miaogo/game/career_controller.dart';
import 'package:miaogo/game/game_controller.dart';
import 'package:miaogo/storage/record_store.dart';
import 'package:miaogo/ui/common/rank_badge.dart';
import 'package:miaogo/ui/play/game_page.dart';

/// 大赛路线图页：横向四列 8强→4强→决赛→冠军。
///
/// 玩家当前轮待赛场次可「进行对局」（推 [GamePage]）；结束后判定胜负，
/// 同轮其余场次自动模拟，晋级进入下一轮，淘汰/夺冠自动完结并结算。
class TournamentBracketPage extends ConsumerStatefulWidget {
  const TournamentBracketPage({super.key});

  @override
  ConsumerState<TournamentBracketPage> createState() =>
      _TournamentBracketPageState();
}

class _TournamentBracketPageState
    extends ConsumerState<TournamentBracketPage> {
  static const _roundNames = ['1/4 决赛', '半决赛', '决赛'];
  bool _dialogShown = false;

  Future<void> _playMatch() async {
    final tournament = ref.read(careerControllerProvider).active;
    if (tournament == null) return;
    final player = tournament.player!;
    final match = tournament.playerMatch;
    if (match == null || match.decided) return;
    final opponentId = match.opponentOf(player.id);
    if (opponentId == null) return;
    final opponent = tournament.playerById(opponentId)!;

    // 引擎门槛：对手段位对应模型（级位小模型 / 段位大模型）。
    final isDan = opponent.rankIndex >= RankSystem.kNumKyuRanks;
    final ready = isDan
        ? ref.read(danEngineStatusProvider) == EngineStatus.ready
        : ref.read(engineStatusProvider) == EngineStatus.ready;
    if (!ready) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${isDan ? '大模型（段位）' : '引擎'}未就绪，请稍后再试'),
      ));
      return;
    }

    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GamePage(
        size: tournament.boardSize,
        rule: tournament.rule,
        komi: tournament.komi,
        humanColor: PlayerColor.black,
        difficulty: opponent.rankIndex,
        opponentName: opponent.name,
        source: GameSource.career,
        tournamentId: tournament.id,
      ),
    ));
    if (!mounted) return;
    final game = ref.read(gameControllerProvider);
    if (!game.finished) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('本局未完成，未记录胜负')));
      return;
    }
    final won = game.winner == game.humanColor;
    final result = ref
        .read(careerControllerProvider.notifier)
        .resolveMatch(won: won);
    final placement = tournament.placementOf(player.id) ?? 0;
    final points = tournament.playerEarnedPoints();
    if (result.complete) {
      _showSettleDialog(result, placement, points);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.playerWon
            ? '晋级${_roundNames[result.round]}！'
            : '本局失利'),
      ));
    }
  }

  Future<void> _showSettleDialog(
      CareerAdvanceResult result, int placement, int points) async {
    if (_dialogShown) return;
    _dialogShown = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          result.champion ? Icons.emoji_events : Icons.flag,
          color: result.champion ? GoColors.wood : GoColors.pine,
          size: 40,
        ),
        title: Text(result.champion ? '恭喜夺冠！' : '本赛出局'),
        content: Text(
          result.champion
              ? '冠军奖励 +$points 积分'
              : '止步${careerPlacementLabel(placement)}，获得 +$points 积分',
          textAlign: TextAlign.center,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('好的'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop(); // 大赛已完结，返回生涯主页
  }

  @override
  Widget build(BuildContext context) {
    final tournament = ref.watch(careerControllerProvider).active;
    if (tournament == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('赛程')),
        body: const Center(child: Text('大赛已结束')),
      );
    }
    final player = tournament.player!;
    final currentRound = tournament.currentRound;
    return Scaffold(
      appBar: AppBar(title: Text(tournament.name, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        child: Column(
          children: [
            _TournamentHeader(tournament: tournament),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var round = 0; round < 3; round++)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _BracketRoundColumn(
                          name: _roundNames[round],
                          matches: tournament.matchesInRound(round),
                          tournament: tournament,
                          playerId: player.id,
                          onPlay: round == currentRound ? _playMatch : null,
                        ),
                      ),
                    _ChampionColumn(tournament: tournament),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部信息：尺寸/规则/当前轮/玩家胜场。
class _TournamentHeader extends StatelessWidget {
  const _TournamentHeader({required this.tournament});

  final CareerTournament tournament;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final player = tournament.player!;
    var wins = 0;
    for (final m in tournament.matches) {
      if (m.decided && m.involves(player.id) && m.winnerId == player.id) {
        wins++;
      }
    }
    final round = tournament.currentRound;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: GoColors.woodContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.sports_esports, color: GoColors.wood, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${tournament.boardSize} 路 · ${tournament.rule.label}规则 · '
              '已胜 $wins 场${round == null ? '' : ' · 当前 ${_TournamentBracketPageState._roundNames[round]}'}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// 一轮的对阵列。
class _BracketRoundColumn extends StatelessWidget {
  const _BracketRoundColumn({
    required this.name,
    required this.matches,
    required this.tournament,
    required this.playerId,
    this.onPlay,
  });

  final String name;
  final List<CareerMatch> matches;
  final CareerTournament tournament;
  final String playerId;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            name,
            style: theme.textTheme.titleSmall?.copyWith(
              color: GoColors.pine,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final m in matches)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _BracketMatchCard(
              match: m,
              tournament: tournament,
              playerId: playerId,
              onPlay: onPlay,
            ),
          ),
      ],
    );
  }
}

/// 单场对阵卡：双方名字/段位/国籍，胜者高亮，败者置灰，玩家待赛场次可开始。
class _BracketMatchCard extends StatelessWidget {
  const _BracketMatchCard({
    required this.match,
    required this.tournament,
    required this.playerId,
    this.onPlay,
  });

  final CareerMatch match;
  final CareerTournament tournament;
  final String playerId;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = match.playerAId.isEmpty
        ? null
        : tournament.playerById(match.playerAId);
    final b = match.playerBId.isEmpty
        ? null
        : tournament.playerById(match.playerBId);
    final canPlay = !match.decided && match.involves(playerId) && onPlay != null;
    return SizedBox(
      width: 200,
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              _PlayerRow(player: a, winnerId: match.winnerId),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Divider(color: GoColors.outlineVariant)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'VS',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: GoColors.textSecondary),
                      ),
                    ),
                    Expanded(child: Divider(color: GoColors.outlineVariant)),
                  ],
                ),
              ),
              _PlayerRow(player: b, winnerId: match.winnerId),
              if (canPlay) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const ValueKey('bracket_play'),
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('进行对局'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 38),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 单个选手行：名字 + 段位徽章 + 国籍；胜者高亮，败者置灰，待定灰字。
class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player, required this.winnerId});

  final CareerPlayer? player;
  final String? winnerId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = player;
    if (p == null) {
      return SizedBox(
        height: 24,
        child: Text(
          '待定',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: GoColors.textSecondary),
        ),
      );
    }
    final isWinner = p.id == winnerId;
    final decided = winnerId != null;
    final color = isWinner
        ? GoColors.wood
        : (decided ? GoColors.textSecondary : GoColors.textPrimary);
    final weight = isWinner ? FontWeight.bold : FontWeight.w500;
    return SizedBox(
      height: 24,
      child: Row(
        children: [
          Expanded(
            child: Text(
              p.name,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: color, fontWeight: weight),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isWinner)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.check_circle, color: GoColors.wood, size: 14),
            ),
          const SizedBox(width: 6),
          RankBadge(rankIndex: p.rankIndex, size: 18),
          const SizedBox(width: 6),
          Text(
            p.nationality.label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: GoColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 冠军列。
class _ChampionColumn extends StatelessWidget {
  const _ChampionColumn({required this.tournament});

  final CareerTournament tournament;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final champion =
        tournament.championId == null ? null : tournament.playerById(tournament.championId!);
    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '冠军',
              style: theme.textTheme.titleSmall?.copyWith(
                color: GoColors.wood,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            color: champion == null
                ? theme.colorScheme.surfaceContainerHighest
                : GoColors.woodContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.emoji_events,
                    color: GoColors.wood,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: champion == null
                        ? Text('待定',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: GoColors.textSecondary))
                        : Text(
                            champion.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: GoColors.woodDark,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
