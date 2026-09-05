import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/storage/record_store.dart';
import 'package:miaogo/storage/settings_store.dart';
import 'package:miaogo/storage/user_store.dart';

/// 待续对局快照：保存对局按钮把「进行中的一局」落盘，供日后续弈。
///
/// - 快速对弈（[GameSource.ai]）：至多一份，替代上一份快照；
/// - 赛事（[GameSource.career]）：按 [tournamentId] 关联，每赛至多一份。
/// 对局终局/弃局后由 [PendingGameStore.removeFor] 清除。
class PendingGame {
  const PendingGame({
    required this.source,
    required this.size,
    required this.rule,
    required this.komi,
    required this.humanColor,
    required this.difficulty,
    required this.opponentName,
    required this.sgf,
    required this.savedAt,
    this.tournamentId,
    this.moveStyle = MoveStyle.confirm,
    this.winrateHistory = const [],
  });

  final GameSource source;
  final int size;
  final GoRule rule;
  final double komi;
  final PlayerColor humanColor;
  final int difficulty;

  /// 对手段位展示名（空 = 默认 `AI · 段位`）。
  final String opponentName;

  /// 所属生涯大赛 id（人机为空）。
  final String? tournamentId;

  /// 本局落子方式（双击 / 确认）。
  final MoveStyle moveStyle;

  /// 已采集的黑方胜率历史：(手数, 胜率 0..1)，按手数升序。
  /// 续弈时载入以延续曲线。
  final List<(int, double)> winrateHistory;

  /// 已走棋步的 SGF 主变化文本（含 PASS）。
  final String sgf;
  final DateTime savedAt;

  /// 已走棋步（含 PASS；解析失败返回空）。
  List<Move> get moves => Sgf.parseMoves(sgf);

  /// 轮到行棋方（无棋步默认黑；否则上一手之对方）。
  PlayerColor get toMove =>
      moves.isEmpty ? PlayerColor.black : moves.last.color.opposite;

  Map<String, dynamic> toJson() => {
        'source': source.name,
        'size': size,
        'rule': rule.name,
        'komi': komi,
        'humanColor': humanColor.name,
        'difficulty': difficulty,
        'opponentName': opponentName,
        'tournamentId': tournamentId,
        'moveStyle': moveStyle.name,
        'winrateHistory': [
          for (final p in winrateHistory) [p.$1, p.$2],
        ],
        'sgf': sgf,
        'savedAt': savedAt.millisecondsSinceEpoch,
      };

  factory PendingGame.fromJson(Map<String, dynamic> json) => PendingGame(
        source: GameSource.values.firstWhere(
            (e) => e.name == json['source'],
            orElse: () => GameSource.ai),
        size: (json['size'] as num?)?.toInt() ?? 9,
        rule: GoRule.values.firstWhere((e) => e.name == json['rule'],
            orElse: () => GoRule.chinese),
        komi: (json['komi'] as num?)?.toDouble() ?? 7.5,
        humanColor: PlayerColor.values.firstWhere(
            (e) => e.name == json['humanColor'],
            orElse: () => PlayerColor.black),
        difficulty: (json['difficulty'] as num?)?.toInt() ?? 0,
        opponentName: json['opponentName'] as String? ?? '',
        tournamentId: json['tournamentId'] as String?,
        moveStyle: MoveStyle.values.firstWhere(
            (e) => e.name == json['moveStyle'],
            orElse: () => MoveStyle.confirm),
        winrateHistory: [
          for (final e in (json['winrateHistory'] as List<dynamic>? ??
              const []))
            if (e is List && e.length >= 2 && e[0] is num && e[1] is num)
              ((e[0] as num).toInt(), (e[1] as num).toDouble()),
        ],
        sgf: json['sgf'] as String? ?? '',
        savedAt: DateTime.fromMillisecondsSinceEpoch(
            (json['savedAt'] as num?)?.toInt() ?? 0),
      );
}

/// 待续对局存储：shared_preferences 持 JSON 列表（至多各模式一份）。
class PendingGameStore extends Notifier<List<PendingGame>> {
  static const _key = 'pending_games';

  @override
  List<PendingGame> build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(PendingGame.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 快速对弈待续快照（无则 null）。
  PendingGame? get quick {
    for (final p in state) {
      if (p.source == GameSource.ai) return p;
    }
    return null;
  }

  /// 指定赛事的待续快照（无则 null）。
  PendingGame? forTournament(String tournamentId) {
    for (final p in state) {
      if (p.source == GameSource.career && p.tournamentId == tournamentId) {
        return p;
      }
    }
    return null;
  }

  /// 写入一份快照（同槽位覆盖：人机唯一 / 赛事按 tournamentId）。
  Future<void> save(PendingGame pending) async {
    state = [
      for (final p in state)
        if (!_sameSlot(p, pending.source, pending.tournamentId)) p,
      pending,
    ];
    _persist();
  }

  /// 清除与 (source, tournamentId) 同槽位的快照（人机忽略 tournamentId）。
  Future<void> removeFor({
    required GameSource source,
    String? tournamentId,
  }) async {
    state = [
      for (final p in state)
        if (!_sameSlot(p, source, tournamentId)) p,
    ];
    _persist();
  }

  /// 清空全部待续快照（清除数据用）。
  void clear() {
    state = const [];
    _persist();
  }

  bool _sameSlot(PendingGame p, GameSource source, String? tournamentId) =>
      p.source == source &&
      (source == GameSource.career
          ? p.tournamentId == tournamentId
          : true);

  void _persist() {
    ref.read(sharedPreferencesProvider).setString(
          _key,
          jsonEncode(state.map((p) => p.toJson()).toList()),
        );
  }
}

final pendingGameStoreProvider =
    NotifierProvider<PendingGameStore, List<PendingGame>>(
        PendingGameStore.new);
