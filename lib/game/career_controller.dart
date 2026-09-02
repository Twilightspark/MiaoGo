import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/game/career.dart';
import 'package:miaogo/storage/settings_store.dart';
import 'package:miaogo/storage/user_store.dart';

/// 生涯模式控制器（P3）。
///
/// - 始终有 9/13/19 三场待报名大赛；玩家同一时刻至多参加一场（[CareerState.active]）。
/// - 玩家完成一轮 → [resolveMatch] 判定本场 + 自动模拟同轮其余场次 + 配对下一轮；
///   被淘汰则自动模拟剩余赛程并结算。
/// - 大赛完结（夺冠 / 淘汰 / 退赛）后为该尺寸自动生成新大赛。
/// - 积分：胜 +20 / 负 +5、冠军 +30，赛事完结统一结算；**提前退赛无任何积分**。
class CareerController extends Notifier<CareerState> {
  static const _key = 'career_state';

  final math.Random _rng = math.Random();

  @override
  CareerState build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_key);
    if (raw != null) {
      try {
        return _decode(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // 数据损坏：回退初始状态。
      }
    }
    final initial = _initialState();
    _write(initial);
    return initial;
  }

  // ---- 读取/持久化 ----

  CareerState _decode(Map<String, dynamic> map) => CareerState(
        active: map['active'] == null
            ? null
            : CareerTournament.fromJson(map['active'] as Map<String, dynamic>),
        upcoming: (map['upcoming'] as List<dynamic>? ?? const [])
            .map((e) => CareerTournament.fromJson(e as Map<String, dynamic>))
            .toList(),
        history: (map['history'] as List<dynamic>? ?? const [])
            .map((e) => CareerResult.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> _encode(CareerState s) => {
        'active': s.active?.toJson(),
        'upcoming': s.upcoming.map((t) => t.toJson()).toList(),
        'history': s.history.map((h) => h.toJson()).toList(),
      };

  void _persist(CareerState s) {
    state = s;
    _write(s);
  }

  /// 仅写盘（不触发 state 赋值；供 build 初始化用）。
  void _write(CareerState s) {
    ref
        .read(sharedPreferencesProvider)
        .setString(_key, jsonEncode(_encode(s)));
  }

  CareerState _initialState() {
    final user = ref.read(userProfileProvider);
    return CareerState(
      active: null,
      upcoming: [
        for (final size in const [9, 13, 19]) _newTournament(size, user),
      ],
      history: const [],
    );
  }

  CareerTournament _newTournament(int boardSize, UserProfile user) {
    final rule = ref.read(settingsProvider).rule;
    return createTournament(
      boardSize: boardSize,
      rule: rule,
      komi: rule.defaultKomi,
      playerName: user.name,
      playerRank: user.rankIndex,
      random: _rng,
    );
  }

  // ---- 报名 / 退赛 ----

  /// 报名：仅当无进行中赛事；成功后设为当前大赛。
  /// 以当前用户信息（名/段位）刷新玩家，防止生成后信息变化。
  bool signUp(String tournamentId) {
    final s = state;
    if (s.active != null) return false;
    final idx = s.upcoming.indexWhere((t) => t.id == tournamentId);
    if (idx < 0) return false;
    final tournament = s.upcoming[idx];
    _refreshPlayerInPlace(tournament, ref.read(userProfileProvider));
    tournament.status = CareerTournamentStatus.active;
    final upcoming = [...s.upcoming]..removeAt(idx);
    _persist(CareerState(active: tournament, upcoming: upcoming, history: s.history));
    return true;
  }

  /// 提前退赛：整个赛事作废，**不产生任何积分/胜负/参赛结算**，
  /// 历史记「退赛·0 分」，该尺寸自动生成新大赛。
  void withdraw() {
    final s = state;
    final active = s.active;
    if (active == null) return;
    final size = active.boardSize;
    final user = ref.read(userProfileProvider);
    final record = CareerResult(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      tournamentName: active.name,
      boardSize: size,
      date: DateTime.now(),
      placement: 0,
      points: 0,
      champion: false,
      withdrawn: true,
      tournamentId: active.id,
    );
    _persist(CareerState(
      active: null,
      upcoming: _withNewTournamentFor(s.upcoming, size, user),
      history: [record, ...s.history],
    ));
  }

  // ---- 对局推进 / 结算 ----

  /// 玩家完成一场后的推进（由赛程页在 GamePage 结束后调用）。
  ///
  /// 判定本场胜负 → 自动模拟同轮其余场次 → 晋级则配对下一轮；
  /// 淘汰则自动模拟剩余赛程；大赛完结时统一结算积分与统计。
  CareerAdvanceResult resolveMatch({required bool won}) {
    final active = state.active;
    if (active == null) {
      throw StateError('无进行中的赛事');
    }
    final match = active.playerMatch;
    if (match == null || match.decided) {
      throw StateError('当前轮次无玩家待赛');
    }
    final result =
        advanceAfterPlayerMatch(active, playerWon: won, random: _rng);
    if (result.complete) {
      _settle(active);
    } else {
      _persist(state);
    }
    return result;
  }

  /// 完结结算：积分（胜20/负5/冠军+30）+ 胜负局数 + 参赛/冠军统计 + 段位联动。
  void _settle(CareerTournament tournament) {
    final player = tournament.player!;
    var wins = 0;
    var losses = 0;
    for (final m in tournament.matches) {
      if (!m.involves(player.id)) continue;
      if (m.winnerId == player.id) {
        wins++;
      } else {
        losses++;
      }
    }
    final points = tournament.playerEarnedPoints();
    final champion = tournament.championId == player.id;
    ref.read(userProfileProvider.notifier).settleTournament(
          wins: wins,
          losses: losses,
          points: points,
          champion: champion,
        );
    _finishAndReplace(tournament,
        placement: tournament.placementOf(player.id) ?? 0,
        points: points,
        champion: champion,
        withdrawn: false);
  }

  /// 写入历史并生成同尺寸新大赛（完结/退赛共用）。
  ///
  /// 该尺寸名额在报名时已从待报名移除，这里**追加**一场新大赛，
  /// 保证 9/13/19 三场始终可选。
  void _finishAndReplace(
    CareerTournament tournament, {
    required int placement,
    required int points,
    required bool champion,
    required bool withdrawn,
  }) {
    final s = state;
    final size = tournament.boardSize;
    final user = ref.read(userProfileProvider);
    final record = CareerResult(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      tournamentName: tournament.name,
      boardSize: size,
      date: DateTime.now(),
      placement: placement,
      points: points,
      champion: champion,
      withdrawn: withdrawn,
      tournamentId: tournament.id,
    );
    _persist(CareerState(
      active: null,
      upcoming: _withNewTournamentFor(s.upcoming, size, user),
      history: [record, ...s.history],
    ));
  }

  List<CareerTournament> _withNewTournamentFor(
          List<CareerTournament> upcoming, int size, UserProfile user) =>
      [
        ...upcoming.where((t) => t.boardSize != size),
        _newTournament(size, user),
      ];

  void _refreshPlayerInPlace(CareerTournament tournament, UserProfile user) {
    final idx = tournament.players.indexWhere((p) => p.isPlayer);
    if (idx < 0) return;
    tournament.players[idx] = CareerPlayer(
      id: kPlayerId,
      name: user.name,
      nationality: Nationality.china,
      rankIndex: user.rankIndex,
      isPlayer: true,
    );
  }

  /// 清空生涯数据（设置页「清除数据」用）。
  void reset() {
    final initial = _initialState();
    _persist(initial);
  }
}

final careerControllerProvider =
    NotifierProvider<CareerController, CareerState>(CareerController.new);
