/// 生涯模式（P3）领域模型与赛程逻辑（纯 Dart，不依赖 Flutter，便于单测）。
///
/// 8 人单败淘汰：8强（round 0）→ 4强（round 1）→ 决赛（round 2）→ 冠军。
/// - 赛事名/选手名随机生成（中国/韩国/日本）。
/// - AI 段位在玩家 ±2 档内（AGENTS.md §6），AI 间胜负按段位差加权随机。
/// - 玩家完成一轮后同轮其余场次自动模拟；玩家被淘汰则自动模拟剩余赛程并产生冠军。
/// - 积分：按名次一次性结算——冠军 = 最强对手上一档档差 X，亚军 X/2，四强 X/4，
///   八强 0（赛事完结统一结算，退赛无积分）。
library;

import 'dart:math' as math;

import 'package:miaogo/core/rank.dart';
import 'package:miaogo/core/rules.dart';

/// 玩家在大赛中的固定 id。
const String kPlayerId = 'player';

/// 大赛人数（8 强淘汰赛）。
const int kTournamentPlayers = 8;

/// 个人积分结算常量与纯函数（AGENTS.md §6，集中可调校准；所有取整向下）。
///
/// 档差：见 [RankSystem.stepForRank]（级内 10/档，段位区域逐档 ×1.3）。
/// - 快速对弈（人机）：同档基础胜分 W = ceil(step/3)（约连赢 3 场晋级），
///   负分 = floor(W/2)（约连输 6 场降级）；按对手相对档差 d = 对手档−自己档 加权：
///   胜分 ×clamp(1+0.2d, 0, 2)（对手低自己 5 档不得分），
///   负分 ×clamp(1−0.2d, 0, 2)（对手高自己 5 档不扣分）。
/// - 大赛（生涯）：封顶 X = 赛事最强对手「上一档」档差；冠军 X / 亚军 floor(X/2) /
///   四强 floor(X/4) / 八强 0，赛事完结统一结算。
class CareerPoints {
  CareerPoints._();

  /// 档差加权：每档差异 ±20%。
  static const double _weightPerStep = 0.2;

  /// 加权 clamp 上限（5 档封顶）。
  static const double _weightCap = 2.0;

  /// 归零档差：对手低自己 ≥5 档获胜不得分；对手高自己 ≥5 档失利不扣分。
  static const int _zeroRankSpread = 5;

  /// AI 对手段位区间：玩家 ± 该档。
  static const int rankSpread = 2;

  /// 胜分加权系数：自己越弱（d>0）越加。
  static double _gainWeight(int d) =>
      (1 + _weightPerStep * d).clamp(0.0, _weightCap);

  /// 负分加权系数：对手越强（d>0）扣得越少。
  static double _lossWeight(int d) =>
      (1 - _weightPerStep * d).clamp(0.0, _weightCap);

  /// [rank] 升到下一档的档差（9 段兜底用上一档差）。
  static int _rankStep(int rank) {
    if (rank >= RankSystem.kMaxRankIndex) {
      return RankSystem.stepForRank(RankSystem.kMaxRankIndex - 1);
    }
    return RankSystem.stepForRank(rank);
  }

  /// 同档基础胜分 W：保证约连赢 3 场可晋级。
  static int baseWin(int playerRank) {
    final step = _rankStep(playerRank);
    return (step + 2) ~/ 3; // ceil(step/3)
  }

  /// 同档基础负分：获取分速度的一半，约连输 6 场降级。
  static int baseLoss(int playerRank) {
    return math.max(1, baseWin(playerRank) ~/ 2);
  }

  /// 一局快速对弈（人机）净积分：胜为正、负为负（和/弃由调用方按 0 处理）。
  static int quickDelta({
    required bool won,
    required int playerRank,
    required int opponentRank,
  }) {
    final d = opponentRank - playerRank;
    if (won) {
      if (d <= -_zeroRankSpread) return 0;
      return (baseWin(playerRank) * _gainWeight(d)).floor();
    }
    if (d >= _zeroRankSpread) return 0;
    return -(baseLoss(playerRank) * _lossWeight(d)).floor();
  }

  /// 大赛封顶 X = 最强对手档的「上一档」档差。
  static int tournamentCap(int topOpponentRank) {
    final r = topOpponentRank < RankSystem.kMaxRankIndex
        ? topOpponentRank
        : RankSystem.kMaxRankIndex - 1;
    return RankSystem.stepForRank(r);
  }

  /// 大赛按名次一次性奖励：1 冠军 X / 2 亚军 floor(X/2) /
  /// 3 四强 floor(X/4) / 其余名次（含八强）0。
  static int tournamentReward({
    required int placement,
    required int topOpponentRank,
  }) {
    final x = tournamentCap(topOpponentRank);
    return switch (placement) {
      1 => x,
      2 => x ~/ 2,
      3 => x ~/ 4,
      _ => 0,
    };
  }

  /// 该赛事最强对手（非玩家）档位；无对手返回 0。
  static int strongestOpponentRank(CareerTournament tournament) {
    var top = 0;
    for (final p in tournament.players) {
      if (p.isPlayer) continue;
      if (p.rankIndex > top) top = p.rankIndex;
    }
    return top;
  }
}

/// 选手国籍（随机中文名来源）。
enum Nationality {
  china('中国'),
  korea('韩国'),
  japan('日本');

  const Nationality(this.label);
  final String label;
}

/// 大赛状态。
enum CareerTournamentStatus {
  upcoming('待报名'),
  active('进行中'),
  completed('已结束'),
  withdrawn('已退赛');

  const CareerTournamentStatus(this.label);
  final String label;
}

/// 大赛参赛选手。
class CareerPlayer {
  const CareerPlayer({
    required this.id,
    required this.name,
    required this.nationality,
    required this.rankIndex,
    this.isPlayer = false,
  });

  /// 玩家固定为 [kPlayerId]，AI 为 `p<i>`。
  final String id;
  final String name;
  final Nationality nationality;
  final int rankIndex;
  final bool isPlayer;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nationality': nationality.name,
        'rankIndex': rankIndex,
        'isPlayer': isPlayer,
      };

  factory CareerPlayer.fromJson(Map<String, dynamic> json) => CareerPlayer(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        nationality: Nationality.values.firstWhere(
            (e) => e.name == json['nationality'],
            orElse: () => Nationality.china),
        rankIndex: (json['rankIndex'] as num?)?.toInt() ?? 0,
        isPlayer: json['isPlayer'] as bool? ?? false,
      );
}

/// 一场淘汰赛。
///
/// 可变模型（非不可变快照）：决定胜负/配对时直接写字段，序列化读写当前状态。
class CareerMatch {
  CareerMatch({
    required this.roundIndex,
    this.playerAId = '',
    this.playerBId = '',
    this.winnerId,
  });

  /// 0=8强, 1=4强, 2=决赛。
  final int roundIndex;

  /// 对阵双方（未来轮次未配对前为空串）。
  String playerAId;
  String playerBId;

  /// 胜者 id；null = 未决。
  String? winnerId;

  bool get decided => winnerId != null;

  /// 败者 id（未决返回 null）。
  String? get loserId {
    if (!decided) return null;
    return winnerId == playerAId ? playerBId : playerAId;
  }

  /// 是否含指定选手。
  bool involves(String playerId) =>
      playerAId == playerId || playerBId == playerId;

  /// 对手（该场另一人；未配对方返回 null）。
  String? opponentOf(String playerId) {
    if (playerAId == playerId) return playerBId;
    if (playerBId == playerId) return playerAId;
    return null;
  }

  void setPair(String aId, String bId) {
    playerAId = aId;
    playerBId = bId;
  }

  void decide(String id) => winnerId = id;

  Map<String, dynamic> toJson() => {
        'roundIndex': roundIndex,
        'playerAId': playerAId,
        'playerBId': playerBId,
        'winnerId': winnerId,
      };

  factory CareerMatch.fromJson(Map<String, dynamic> json) => CareerMatch(
        roundIndex: (json['roundIndex'] as num?)?.toInt() ?? 0,
        playerAId: json['playerAId'] as String? ?? '',
        playerBId: json['playerBId'] as String? ?? '',
        winnerId: json['winnerId'] as String?,
      );
}

/// 一场大赛（8 人淘汰赛，7 场对局）。
class CareerTournament {
  CareerTournament({
    required this.id,
    required this.name,
    required this.boardSize,
    required this.rule,
    required this.komi,
    required this.players,
    required this.matches,
    this.championId,
    this.status = CareerTournamentStatus.upcoming,
  });

  final String id;
  final String name;

  /// 棋盘尺寸：9 / 13 / 19。
  final int boardSize;
  final GoRule rule;
  final double komi;
  final List<CareerPlayer> players;
  final List<CareerMatch> matches;
  String? championId;
  CareerTournamentStatus status;

  /// 玩家选手（无则 null）。
  CareerPlayer? get player {
    for (final p in players) {
      if (p.isPlayer) return p;
    }
    return null;
  }

  CareerPlayer? playerById(String id) {
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<CareerMatch> matchesInRound(int round) =>
      matches.where((m) => m.roundIndex == round).toList();

  /// 当前轮（含未决场次的最小轮）；全部决出返回 null。
  int? get currentRound {
    for (var r = 0; r < 3; r++) {
      if (matchesInRound(r).any((m) => !m.decided)) return r;
    }
    return null;
  }

  /// 玩家当前待赛的一场（未决且含玩家）；无则 null。
  CareerMatch? get playerMatch {
    final pid = player?.id;
    if (pid == null) return null;
    for (final m in matches) {
      if (!m.decided && m.involves(pid)) return m;
    }
    return null;
  }

  /// 玩家名次：1 冠军 / 2 亚军 / 3 四强 / 5 八强；未决返回 null。
  int? placementOf(String playerId) {
    if (championId == playerId) return 1;
    final finalMatch = matchesInRound(2).first;
    if (finalMatch.loserId == playerId) return 2;
    for (final m in matchesInRound(1)) {
      if (m.loserId == playerId) return 3;
    }
    for (final m in matchesInRound(0)) {
      if (m.loserId == playerId) return 5;
    }
    return null;
  }

  /// 玩家本赛事可结算积分：按名次一次性结算
  /// （冠军 X / 亚军 X/2 / 四强 X/4 / 八强 0；未决返回 0，退赛不走本方法）。
  int playerEarnedPoints() {
    final pid = player?.id;
    if (pid == null) return 0;
    final placement = placementOf(pid);
    if (placement == null) return 0;
    return CareerPoints.tournamentReward(
      placement: placement,
      topOpponentRank: CareerPoints.strongestOpponentRank(this),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'boardSize': boardSize,
        'rule': rule.name,
        'komi': komi,
        'players': players.map((p) => p.toJson()).toList(),
        'matches': matches.map((m) => m.toJson()).toList(),
        'championId': championId,
        'status': status.name,
      };

  factory CareerTournament.fromJson(Map<String, dynamic> json) =>
      CareerTournament(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        boardSize: (json['boardSize'] as num?)?.toInt() ?? 9,
        rule: GoRule.values.firstWhere((e) => e.name == json['rule'],
            orElse: () => GoRule.chinese),
        komi: (json['komi'] as num?)?.toDouble() ?? 7.5,
        players: (json['players'] as List<dynamic>?)
                ?.map((e) => CareerPlayer.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        matches: (json['matches'] as List<dynamic>?)
                ?.map((e) => CareerMatch.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        championId: json['championId'] as String?,
        status: CareerTournamentStatus.values.firstWhere(
            (e) => e.name == json['status'],
            orElse: () => CareerTournamentStatus.upcoming),
      );
}

/// 历史竞赛成绩（玩家视角）。
class CareerResult {
  const CareerResult({
    required this.id,
    required this.tournamentName,
    required this.boardSize,
    required this.date,
    required this.placement,
    required this.points,
    required this.tournamentId,
    this.champion = false,
    this.withdrawn = false,
  });

  final String id;
  final String tournamentName;
  final int boardSize;
  final DateTime date;

  /// 名次：1 冠军 / 2 亚军 / 3 四强 / 5 八强；退赛 = 0。
  final int placement;
  final int points;
  final bool champion;

  /// 提前退赛（无任何积分）。
  final bool withdrawn;

  /// 该赛事 id（用于关联本赛个人对局）。
  final String tournamentId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'tournamentName': tournamentName,
        'boardSize': boardSize,
        'date': date.millisecondsSinceEpoch,
        'placement': placement,
        'points': points,
        'champion': champion,
        'withdrawn': withdrawn,
        'tournamentId': tournamentId,
      };

  factory CareerResult.fromJson(Map<String, dynamic> json) => CareerResult(
        id: json['id'] as String? ?? '',
        tournamentName: json['tournamentName'] as String? ?? '',
        boardSize: (json['boardSize'] as num?)?.toInt() ?? 9,
        date: DateTime.fromMillisecondsSinceEpoch(
            (json['date'] as num?)?.toInt() ?? 0),
        placement: (json['placement'] as num?)?.toInt() ?? 0,
        points: (json['points'] as num?)?.toInt() ?? 0,
        champion: json['champion'] as bool? ?? false,
        withdrawn: json['withdrawn'] as bool? ?? false,
        tournamentId: json['tournamentId'] as String? ?? '',
      );
}

/// 生涯状态：当前大赛 + 待报名赛事 + 历史成绩。
class CareerState {
  const CareerState({
    required this.active,
    required this.upcoming,
    required this.history,
  });

  final CareerTournament? active;
  final List<CareerTournament> upcoming;
  final List<CareerResult> history;
}

/// 玩家完成一轮后的推进结果（UI 展示用）。
class CareerAdvanceResult {
  const CareerAdvanceResult({
    required this.round,
    required this.playerWon,
    required this.complete,
    this.champion = false,
  });

  /// 推进后的当前轮（0..2；淘汰时 = 本场轮）。
  final int round;
  final bool playerWon;

  /// 大赛是否已完结（淘汰自动模拟完毕 / 夺冠）。
  final bool complete;
  final bool champion;
}

/// 随机赛事名 / 人名生成器（中国/韩国/日本）。
class CareerNames {
  CareerNames._();

  static const List<String> _tournamentNames = [
    '桃李杯', '凌云杯', '喵星人杯', '天元杯', '星罗杯', '梅花杯', '清风杯',
    '烂柯杯', '玄素杯', '望海杯', '松风杯', '弈秋杯', '青竹杯', '金秋杯',
    '春江杯', '石语杯',
  ];

  static const List<String> _tournamentSuffixes = [
    '', '', '', '大师赛', '公开赛', '挑战赛',
  ];

  static String tournamentName(math.Random random) {
    final base = _tournamentNames[random.nextInt(_tournamentNames.length)];
    final suffix =
        _tournamentSuffixes[random.nextInt(_tournamentSuffixes.length)];
    final withEdition = random.nextBool();
    final name = withEdition
        ? '第${1 + random.nextInt(20)}届$base$suffix'
        : '$base$suffix';
    return name;
  }

  static const Map<Nationality, (List<String>, List<String>)> _namePools = {
    Nationality.china: (
      ['张', '王', '李', '赵', '陈', '杨', '黄', '周', '吴', '徐', '孙', '马', '刘', '胡', '郭', '何'],
      ['伟', '磊', '静', '娜', '敏', '军', '洋', '勇', '杰', '涛', '明', '辉', '霞', '丽', '强', '斌'],
    ),
    Nationality.korea: (
      ['金', '李', '朴', '崔', '郑', '姜', '赵', '林', '韩', '申'],
      ['炫彬', '志勋', '尚宪', '东勋', '泰熙', '敏贞', '成勋', '勇洙', '贞焕', '贤珠', '钟勋', '承恩', '在贤', '正仁'],
    ),
    Nationality.japan: (
      ['井山', '一力', '芝野', '藤田', '小林', '大竹', '加藤', '高尾', '山下', '河野', '村川', '羽根', '平田', '余'],
      ['裕太', '辽', '虎丸', '善哉', '康人', '秀行', '正夫', '邦夫', '春芳', '秀策', '文裕', '宏杰', '修平', '直人'],
    ),
  };

  static String playerName(Nationality nationality, math.Random random) {
    final pool = _namePools[nationality]!;
    return '${pool.$1[random.nextInt(pool.$1.length)]}'
        '${pool.$2[random.nextInt(pool.$2.length)]}';
  }

  /// 随机国籍下随机生成一位 AI 对手名（竞赛命名同源，人机对局复用）。
  static String aiPlayerName(math.Random random) {
    final nat = Nationality.values[random.nextInt(Nationality.values.length)];
    return playerName(nat, random);
  }
}

/// 名次 → 文本（0 退赛）。
String careerPlacementLabel(int placement) => switch (placement) {
      0 => '退赛',
      1 => '冠军',
      2 => '亚军',
      3 => '四强',
      5 => '八强',
      _ => '未决',
    };

/// 生成一场大赛：8 人（玩家 + 7 AI 随机中/韩/日），8 强随机种子位，
/// AI 段位在玩家 ±[CareerPoints.rankSpread] 档（夹紧 0..26）。
CareerTournament createTournament({
  required int boardSize,
  required GoRule rule,
  required double komi,
  required String playerName,
  required int playerRank,
  String? id,
  math.Random? random,
}) {
  final rng = random ?? math.Random();
  final seed = rng.nextInt(kTournamentPlayers);
  final usedNames = <String>{playerName};
  final players = <CareerPlayer>[];
  for (var i = 0; i < kTournamentPlayers; i++) {
    if (i == seed) {
      players.add(CareerPlayer(
        id: kPlayerId,
        name: playerName,
        nationality: Nationality.china,
        rankIndex: playerRank,
        isPlayer: true,
      ));
      continue;
    }
    final nat = Nationality.values[rng.nextInt(Nationality.values.length)];
    String name;
    do {
      name = CareerNames.playerName(nat, rng);
    } while (usedNames.contains(name));
    usedNames.add(name);
    players.add(CareerPlayer(
      id: 'p$i',
      name: name,
      nationality: nat,
      rankIndex: _randomAiRank(playerRank, rng),
    ));
  }

  // 7 场：8强 4 + 4强 2 + 决赛 1（未来轮次配对前留空）。
  final matches = <CareerMatch>[];
  for (var r = 0; r < 3; r++) {
    final count = 4 >> r;
    for (var i = 0; i < count; i++) {
      matches.add(CareerMatch(roundIndex: r));
    }
  }

  final tournament = CareerTournament(
    id: id ??
        't${DateTime.now().millisecondsSinceEpoch}_${rng.nextInt(99999)}',
    name: CareerNames.tournamentName(rng),
    boardSize: boardSize,
    rule: rule,
    komi: komi,
    players: players,
    matches: matches,
  );
  _pairRound0(tournament);
  return tournament;
}

/// 玩家完成一轮后的推进：判定本场 → 自动模拟同轮其余场次 → 配对下一轮；
/// 玩家被淘汰则自动模拟剩余赛程并产生冠军。
CareerAdvanceResult advanceAfterPlayerMatch(
  CareerTournament tournament, {
  required bool playerWon,
  required math.Random random,
}) {
  final player = tournament.player!;
  final match = tournament.playerMatch!;
  final opponentId = match.opponentOf(player.id)!;
  match.decide(playerWon ? player.id : opponentId);
  _simulateRound(tournament, match.roundIndex, random);

  if (!playerWon) {
    // 淘汰：自动模拟全部剩余赛程。
    simulateAllRemaining(tournament, random);
    return CareerAdvanceResult(
      round: match.roundIndex,
      playerWon: false,
      complete: true,
    );
  }
  if (match.roundIndex == 2) {
    // 决赛胜出 → 冠军。
    tournament.championId = player.id;
    tournament.status = CareerTournamentStatus.completed;
    return CareerAdvanceResult(
      round: 2,
      playerWon: true,
      complete: true,
      champion: true,
    );
  }
  pairNextRound(tournament, match.roundIndex);
  return CareerAdvanceResult(
    round: match.roundIndex + 1,
    playerWon: true,
    complete: false,
  );
}

/// 自动模拟全部剩余赛程直至产生冠军（玩家淘汰后调用）。
void simulateAllRemaining(CareerTournament tournament, math.Random random) {
  for (var round = 0; round < 3; round++) {
    if (round > 0) pairNextRound(tournament, round - 1);
    _simulateRound(tournament, round, random);
  }
  tournament.championId = tournament.matchesInRound(2).first.winnerId;
  tournament.status = CareerTournamentStatus.completed;
}

/// 配对下一轮：[fromRound] 的胜者按序填入 round+1 的对阵。
void pairNextRound(CareerTournament tournament, int fromRound) {
  final winners = tournament.matchesInRound(fromRound).map((m) => m.winnerId!);
  final next = tournament.matchesInRound(fromRound + 1);
  for (var i = 0; i < next.length; i++) {
    next[i].setPair(winners.elementAt(i * 2), winners.elementAt(i * 2 + 1));
  }
}

void _pairRound0(CareerTournament tournament) {
  final ids = tournament.players.map((p) => p.id).toList();
  final round0 = tournament.matchesInRound(0);
  for (var i = 0; i < round0.length; i++) {
    round0[i].setPair(ids[i * 2], ids[i * 2 + 1]);
  }
}

void _simulateRound(CareerTournament tournament, int round, math.Random random) {
  for (final m in tournament.matchesInRound(round)) {
    if (m.decided) continue;
    m.decide(_pickWinner(m, tournament, random));
  }
}

/// AI 间胜负：按段位差加权（p = 0.5 + 0.06×段位差，夹紧 0.1~0.9）。
String _pickWinner(CareerMatch match, CareerTournament tournament, math.Random rng) {
  final a = tournament.playerById(match.playerAId)!;
  final b = tournament.playerById(match.playerBId)!;
  final diff = a.rankIndex - b.rankIndex;
  final prob = (0.5 + 0.06 * diff).clamp(0.1, 0.9);
  return rng.nextDouble() < prob ? a.id : b.id;
}

int _randomAiRank(int center, math.Random rng) {
  final lo = math.max(0, center - CareerPoints.rankSpread);
  final hi = math.min(RankSystem.kMaxRankIndex, center + CareerPoints.rankSpread);
  return lo + rng.nextInt(hi - lo + 1);
}
