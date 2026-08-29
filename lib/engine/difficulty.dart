/// 段位 → KataGo 引擎参数与选点容错映射（AGENTS.md §7）。
///
/// KataGo 在低 visit 下仍远超人类，弱化需"引擎参数 + 选点容错"双轴：
/// - [EngineDifficulty] 描述单档：搜索量、思考时长、温度、根噪声、topK 容错。
/// - 连续参数（visits/time/temperature/rootNoise）在锚点档间分段线性插值；
///   [topK]（取前 N 候选做加权采样的宽度）四舍五入取整。
/// - 高段位 temperature→0、topK→1 即"取最优"；低段位高温度 + 大 topK
///   制造明显漏招，突破纯引擎的棋力地板。
///
/// 锚点表为出厂默认（§7 参考值），真机校准工具（P6）会写回调整。
library;

/// 单档难度参数。
class EngineDifficulty {
  const EngineDifficulty({
    required this.rankIndex,
    required this.maxVisits,
    required this.maxTimeMs,
    required this.temperature,
    required this.rootNoise,
    required this.topK,
  });

  final int rankIndex;

  /// 最大搜索访问数（`kata-set-param maxVisits`）。
  final int maxVisits;

  /// 最大思考毫秒数（`kata-set-param maxTime`）。
  final int maxTimeMs;

  /// 采样温度：越高选点越随机（低段位漏招用）。
  final double temperature;

  /// 根噪声幅度（`kata-set-param rootNoise`），高段位趋于 0。
  final double rootNoise;

  /// 选点容错宽度：从前 [topK] 候选按温度加权采样（1 = 取最优）。
  final int topK;
}

/// 27 档难度映射表。
class DifficultyTable {
  DifficultyTable._();

  /// 锚点档：(rankIndex, maxVisits, maxTimeMs, temperature, rootNoise, topK)。
  static const List<(int, int, int, double, double, int)> anchors = [
    (0, 4, 100, 1.50, 0.150, 6), // 18级
    (8, 20, 400, 0.80, 0.120, 5), // 10级
    (17, 60, 600, 0.50, 0.080, 4), // 1级
    (18, 150, 1200, 0.30, 0.040, 3), // 1段
    (22, 500, 2500, 0.15, 0.020, 2), // 5段
    (26, 2500, 6000, 0.03, 0.000, 1), // 9段
  ];

  /// 取 [rankIndex] 档难度（0..26，越界自动夹紧）。
  static EngineDifficulty forRank(int rankIndex) {
    final r = rankIndex.clamp(0, 26);
    if (anchors.any((a) => a.$1 == r)) {
      final a = anchors.firstWhere((a) => a.$1 == r);
      return EngineDifficulty(
        rankIndex: r,
        maxVisits: a.$2,
        maxTimeMs: a.$3,
        temperature: a.$4,
        rootNoise: a.$5,
        topK: a.$6,
      );
    }
    // 找到 r 所在锚点区间，分段线性插值连续参数。
    final lower = anchors.lastWhere((a) => a.$1 <= r);
    final upper = anchors.firstWhere((a) => a.$1 > r);
    final t = (r - lower.$1) / (upper.$1 - lower.$1);
    double lerp(num lo, num hi) => lo + (hi - lo) * t;
    return EngineDifficulty(
      rankIndex: r,
      maxVisits: lerp(lower.$2, upper.$2).round(),
      maxTimeMs: lerp(lower.$3, upper.$3).round(),
      temperature: lerp(lower.$4, upper.$4),
      rootNoise: lerp(lower.$5, upper.$5),
      topK: lerp(lower.$6, upper.$6).round(),
    );
  }

  /// 映射单调性约束（测试用）：段位越高访问数/时长越多、温度/噪声/topK 越低。
  static bool isMonotonic(EngineDifficulty lo, EngineDifficulty hi) =>
      hi.maxVisits >= lo.maxVisits &&
      hi.maxTimeMs >= lo.maxTimeMs &&
      hi.temperature <= lo.temperature &&
      hi.rootNoise <= lo.rootNoise &&
      hi.topK <= lo.topK;
}
