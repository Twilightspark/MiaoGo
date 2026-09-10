/// 段位 → KataGo Human SL 参数映射（AGENTS.md §7）。
///
/// 采用 Human SL 模型（`b18c384nbt-humanv0.bin.gz`，经 `-human-model` 传入），
/// 按段位设置 `humanSLProfile`（`rank_18k`~`rank_9d`），由引擎自身按人类棋风选点：
/// - 级位（18级~1级）：纯人类策略（[piklLambda] 极大、根探索为 0），
///   [maxVisits] 仅用于 pass/认输判断，突破纯引擎的棋力地板。
/// - 段位（1段~9段）：逐步混入搜索（[piklLambda] 减小、[rootExploreProbWeightless]
///   增大），高段位靠搜索补足原始 human 网的强度上限。
///
/// 连续参数在锚点档间分段线性插值；[humanSLProfile] 按档位直接生成。
/// 锚点为出厂默认（参考 KataGo `gtp_human5k_example.cfg` /
/// `gtp_human9d_search_example.cfg`），真机校准后写回。
library;

import 'package:miaogo/core/rank.dart';

/// 单档 Human SL 难度参数。
class EngineDifficulty {
  const EngineDifficulty({
    required this.rankIndex,
    required this.humanSLProfile,
    required this.maxVisits,
    required this.maxTimeMs,
    required this.piklLambda,
    required this.chosenMoveTemperatureEarly,
    required this.chosenMoveTemperature,
    required this.chosenMoveTemperatureHalflife,
    required this.chosenMoveTemperatureOnlyBelowProb,
    required this.rootExploreProbWeightless,
    required this.cpuctPermanent,
  });

  final int rankIndex;

  /// Human SL 画像：`rank_18k`~`rank_1k`、`rank_1d`~`rank_9d`。
  final String humanSLProfile;

  /// 最大搜索访问数（`kata-set-param maxVisits`）。
  final int maxVisits;

  /// 最大思考毫秒数（`kata-set-param maxTime`）。
  final int maxTimeMs;

  /// `humanSLChosenMovePiklLambda`：越大越"纯人类"，越小越靠搜索增强棋力。
  final double piklLambda;

  /// `chosenMoveTemperatureEarly`：前若干手的选点温度。
  final double chosenMoveTemperatureEarly;

  /// `chosenMoveTemperature`：中后盘选点温度。
  final double chosenMoveTemperature;

  /// `chosenMoveTemperatureHalflife`：温度衰减半衰期（手数）。
  final double chosenMoveTemperatureHalflife;

  /// `chosenMoveTemperatureOnlyBelowProb`：温度仅作用于低于该先验概率的着法。
  final double chosenMoveTemperatureOnlyBelowProb;

  /// `humanSLRootExploreProbWeightless`：根节点用于评估人类候选的访问占比。
  final double rootExploreProbWeightless;

  /// `humanSLCpuctPermanent`：人类策略探索的永久 PUCT 系数。
  final double cpuctPermanent;
}

/// 27 档 Human SL 映射表。
class DifficultyTable {
  DifficultyTable._();

  /// 锚点档（出厂默认，真机校准写回）。
  static const List<EngineDifficulty> anchors = [
    EngineDifficulty(
      rankIndex: 0, // 18级
      humanSLProfile: 'rank_18k',
      maxVisits: 30,
      maxTimeMs: 500,
      piklLambda: 1e8,
      chosenMoveTemperatureEarly: 0.85,
      chosenMoveTemperature: 0.70,
      chosenMoveTemperatureHalflife: 80,
      chosenMoveTemperatureOnlyBelowProb: 0.01,
      rootExploreProbWeightless: 0.0,
      cpuctPermanent: 0.2,
    ),
    EngineDifficulty(
      rankIndex: 8, // 10级
      humanSLProfile: 'rank_10k',
      maxVisits: 30,
      maxTimeMs: 500,
      piklLambda: 1e8,
      chosenMoveTemperatureEarly: 0.85,
      chosenMoveTemperature: 0.70,
      chosenMoveTemperatureHalflife: 80,
      chosenMoveTemperatureOnlyBelowProb: 0.01,
      rootExploreProbWeightless: 0.0,
      cpuctPermanent: 0.2,
    ),
    EngineDifficulty(
      rankIndex: 17, // 1级
      humanSLProfile: 'rank_1k',
      maxVisits: 50,
      maxTimeMs: 800,
      piklLambda: 1e7,
      chosenMoveTemperatureEarly: 0.85,
      chosenMoveTemperature: 0.65,
      chosenMoveTemperatureHalflife: 80,
      chosenMoveTemperatureOnlyBelowProb: 0.05,
      rootExploreProbWeightless: 0.0,
      cpuctPermanent: 0.2,
    ),
    EngineDifficulty(
      rankIndex: 18, // 1段
      humanSLProfile: 'rank_1d',
      maxVisits: 120,
      maxTimeMs: 1200,
      piklLambda: 0.50,
      chosenMoveTemperatureEarly: 0.75,
      chosenMoveTemperature: 0.50,
      chosenMoveTemperatureHalflife: 60,
      chosenMoveTemperatureOnlyBelowProb: 0.30,
      rootExploreProbWeightless: 0.4,
      cpuctPermanent: 1.0,
    ),
    EngineDifficulty(
      rankIndex: 22, // 5段
      humanSLProfile: 'rank_5d',
      maxVisits: 350,
      maxTimeMs: 2500,
      piklLambda: 0.08,
      chosenMoveTemperatureEarly: 0.70,
      chosenMoveTemperature: 0.25,
      chosenMoveTemperatureHalflife: 30,
      chosenMoveTemperatureOnlyBelowProb: 1.00,
      rootExploreProbWeightless: 0.8,
      cpuctPermanent: 2.0,
    ),
    EngineDifficulty(
      rankIndex: 26, // 9段
      humanSLProfile: 'rank_9d',
      maxVisits: 700,
      maxTimeMs: 5000,
      piklLambda: 0.03,
      chosenMoveTemperatureEarly: 0.70,
      chosenMoveTemperature: 0.20,
      chosenMoveTemperatureHalflife: 30,
      chosenMoveTemperatureOnlyBelowProb: 1.00,
      rootExploreProbWeightless: 0.8,
      cpuctPermanent: 2.0,
    ),
  ];

  /// [rankIndex]（0..26）对应的 Human SL 画像名（越界夹紧）。
  static String profileForRank(int rankIndex) {
    final r = rankIndex.clamp(0, RankSystem.kMaxRankIndex);
    if (r < RankSystem.kNumKyuRanks) {
      return 'rank_${RankSystem.kNumKyuRanks - r}k'; // 18级..1级
    }
    return 'rank_${r - RankSystem.kNumKyuRanks + 1}d'; // 1段..9段
  }

  /// 取 [rankIndex] 档难度（0..26，越界自动夹紧）。
  static EngineDifficulty forRank(int rankIndex) {
    final r = rankIndex.clamp(0, RankSystem.kMaxRankIndex);
    for (final a in anchors) {
      if (a.rankIndex == r) return a;
    }
    final lower = anchors.lastWhere((a) => a.rankIndex <= r);
    final upper = anchors.firstWhere((a) => a.rankIndex > r);
    final t = (r - lower.rankIndex) / (upper.rankIndex - lower.rankIndex);
    double lerp(num lo, num hi) => lo + (hi - lo) * t;
    return EngineDifficulty(
      rankIndex: r,
      humanSLProfile: profileForRank(r),
      maxVisits: lerp(lower.maxVisits, upper.maxVisits).round(),
      maxTimeMs: lerp(lower.maxTimeMs, upper.maxTimeMs).round(),
      piklLambda: lerp(lower.piklLambda, upper.piklLambda),
      chosenMoveTemperatureEarly:
          lerp(lower.chosenMoveTemperatureEarly, upper.chosenMoveTemperatureEarly),
      chosenMoveTemperature:
          lerp(lower.chosenMoveTemperature, upper.chosenMoveTemperature),
      chosenMoveTemperatureHalflife: lerp(
          lower.chosenMoveTemperatureHalflife,
          upper.chosenMoveTemperatureHalflife),
      chosenMoveTemperatureOnlyBelowProb: lerp(
          lower.chosenMoveTemperatureOnlyBelowProb,
          upper.chosenMoveTemperatureOnlyBelowProb),
      rootExploreProbWeightless: lerp(
          lower.rootExploreProbWeightless, upper.rootExploreProbWeightless),
      cpuctPermanent: lerp(lower.cpuctPermanent, upper.cpuctPermanent),
    );
  }

  /// 映射单调性约束（测试用）：段位越高搜索量越大、越依赖搜索增强棋力。
  static bool isMonotonic(EngineDifficulty lo, EngineDifficulty hi) =>
      hi.maxVisits >= lo.maxVisits &&
      hi.maxTimeMs >= lo.maxTimeMs &&
      hi.piklLambda <= lo.piklLambda &&
      hi.rootExploreProbWeightless >= lo.rootExploreProbWeightless &&
      hi.cpuctPermanent >= lo.cpuctPermanent;
}
