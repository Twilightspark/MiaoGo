import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/life_death.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rules.dart';

/// 终局数子/数目结果。
///
/// 领地通过连通空区 flood-fill 归属判定（P1 按全部棋子存活计，
/// 手动点死子与引擎 territory 校正留待 P2/P4）。
class ScoreResult {
  const ScoreResult({
    required this.blackPoints,
    required this.whitePoints,
    required this.komi,
    required this.blackTerritory,
    required this.whiteTerritory,
    required this.blackStones,
    required this.whiteStones,
    required this.blackCaptures,
    required this.whiteCaptures,
    required this.deadBlack,
    required this.deadWhite,
    required this.method,
  });

  final int blackPoints;
  final int whitePoints;
  final double komi;
  final int blackTerritory;
  final int whiteTerritory;
  final int blackStones;
  final int whiteStones;
  final int blackCaptures;
  final int whiteCaptures;

  /// 判死并移除的黑/白子数（数目法计入对方俘虏）。
  final int deadBlack;
  final int deadWhite;
  final ScoringMethod method;

  /// 白方贴目后的点数。
  double get whiteTotal => whitePoints + komi;

  double get blackTotal => blackPoints.toDouble();

  PlayerColor? get winner {
    if (blackTotal > whiteTotal) return PlayerColor.black;
    if (whiteTotal > blackTotal) return PlayerColor.white;
    return null;
  }

  double get margin => (blackTotal - whiteTotal).abs();

  /// 胜负描述：`黑胜 1.5 目` / `和棋`。
  String get description {
    final w = winner;
    if (w == null) return '和棋';
    final unit = method == ScoringMethod.area ? '点' : '目';
    final m = margin == margin.roundToDouble()
        ? margin.round()
        : margin.toStringAsFixed(1);
    return '${w.label}胜 $m$unit';
  }

  /// 分项明细，供成绩面板展示。
  List<String> get details {
    final dead = deadBlack + deadWhite;
    if (method == ScoringMethod.area) {
      return [
        '黑方：$blackStones 子 + $blackTerritory 空 = $blackPoints 点',
        '白方：$whiteStones 子 + $whiteTerritory 空 = $whitePoints 点',
        '白方另得贴目 $komi 点',
        if (dead > 0) '判死子：黑 $deadBlack / 白 $deadWhite',
      ];
    }
    return [
      '黑方：$blackTerritory 空 + 提 $blackCaptures = $blackPoints 目',
      '白方：$whiteTerritory 空 + 提 $whiteCaptures = $whitePoints 目',
      '白方另得贴目 $komi 目',
      if (dead > 0) '判死子：黑 $deadBlack / 白 $deadWhite（计入对方俘虏）',
    ];
  }
}

/// 终局计分：先做死活分析（移除死子、识别双活），再按规则选用数子/数目。
///
/// 规则对齐 KataGo `docs/rules.html`：
/// - 数子（中国）= `scoringArea + taxNone`：存活子 + 单色围空；双活眼也计分。
/// - 数目（日/韩）= `scoringTerritory + taxSeki`：空 + 俘虏（含死子），双活眼不计。
ScoreResult scoreGame(GoBoard board, {required GoRule rule, double? komi}) {
  final method = rule.scoring;
  final komiValue = komi ?? rule.defaultKomi;

  // 死活分析：移除死子（计对方俘虏）、识别双活眼区。
  final analysis = analyzeLifeDeath(board);
  final b = board.clone(superko: false);
  int deadBlack = 0, deadWhite = 0;
  for (final k in analysis.deadPoints) {
    final r = k ~/ 64, c = k % 64;
    final cell = b.at(r, c);
    if (cell == PlayerColor.black) {
      deadBlack++;
    } else if (cell == PlayerColor.white) {
      deadWhite++;
    }
    b.clearPoint(r, c);
  }

  // 领地：空区单色归属；数目法剔除双活眼。
  final sekiEyes = analysis.sekiEyes;
  int blackTerritory = 0, whiteTerritory = 0;
  for (final region in b.emptyRegionsDetailed()) {
    if (region.borders.length != 1) continue;
    if (method == ScoringMethod.territory &&
        sekiEyes.any((e) => e.length == region.points.length &&
            e.difference(region.points).isEmpty)) {
      continue; // 双活眼：数目法不计
    }
    if (region.borders.first == PlayerColor.black) {
      blackTerritory += region.points.length;
    } else {
      whiteTerritory += region.points.length;
    }
  }

  int blackStones = 0, whiteStones = 0;
  for (var r = 0; r < b.size; r++) {
    for (var c = 0; c < b.size; c++) {
      final cell = b.at(r, c);
      if (cell == PlayerColor.black) {
        blackStones++;
      } else if (cell == PlayerColor.white) {
        whiteStones++;
      }
    }
  }

  final blackCaptures = method == ScoringMethod.territory
      ? b.capturesBlack + deadWhite
      : b.capturesBlack;
  final whiteCaptures = method == ScoringMethod.territory
      ? b.capturesWhite + deadBlack
      : b.capturesWhite;

  final blackPoints = method == ScoringMethod.area
      ? blackStones + blackTerritory
      : blackTerritory + blackCaptures;
  final whitePoints = method == ScoringMethod.area
      ? whiteStones + whiteTerritory
      : whiteTerritory + whiteCaptures;

  return ScoreResult(
    blackPoints: blackPoints,
    whitePoints: whitePoints,
    komi: komiValue,
    blackTerritory: blackTerritory,
    whiteTerritory: whiteTerritory,
    blackStones: blackStones,
    whiteStones: whiteStones,
    blackCaptures: blackCaptures,
    whiteCaptures: whiteCaptures,
    deadBlack: deadBlack,
    deadWhite: deadWhite,
    method: method,
  );
}

/// 地盘定型分析结果。
class Settledness {
  const Settledness({
    required this.ownedEmpty,
    required this.neutralEmpty,
    required this.maxNeutralRegion,
    required this.ownedRatio,
    required this.basicallySettled,
  });

  /// 单色包围（已确定归属）的空点数。
  final int ownedEmpty;

  /// 双色/无边包围（未定地盘）的空点数。
  final int neutralEmpty;

  /// 最大未定连通区面积。
  final int maxNeutralRegion;

  /// 已确定空点占比：ownedEmpty / (ownedEmpty + neutralEmpty)。
  final double ownedRatio;

  /// 是否已基本定型：占比达阈值、无大型未定区、且已走足够手数。
  final bool basicallySettled;
}

/// 判断局面是否已基本定型（用于主动申请点目）。
///
/// 通过空白连通区归属分析：占多数的空区已被单方完全包围视为定型；
/// 若残留大型未定区或手数过少则不主动申请，避免开局误判。
Settledness analyzeSettledness(
  GoBoard board, {
  required int moveCount,
  double ownedThreshold = 0.8,
  int maxNeutralRegion = 2,
  int minMoves = 6,
}) {
  var ownedEmpty = 0, neutralEmpty = 0, maxNeutral = 0;
  for (final region in board.emptyRegions()) {
    if (region.borders.length == 1) {
      ownedEmpty += region.area;
    } else {
      neutralEmpty += region.area;
      if (region.area > maxNeutral) maxNeutral = region.area;
    }
  }
  final total = ownedEmpty + neutralEmpty;
  final ratio = total == 0 ? 0.0 : ownedEmpty / total;
  return Settledness(
    ownedEmpty: ownedEmpty,
    neutralEmpty: neutralEmpty,
    maxNeutralRegion: maxNeutral,
    ownedRatio: ratio,
    basicallySettled: moveCount >= minMoves &&
        ratio >= ownedThreshold &&
        maxNeutral <= maxNeutralRegion,
  );
}
