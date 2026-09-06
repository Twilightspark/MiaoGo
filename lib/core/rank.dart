/// 段位体系：18级~1级（索引 0..17），1段~9段（索引 18..26），共 27 档。
///
/// 个人积分（careerPoints）为连续累计的绝对积分：跨过下一档阈值晋升，
/// 跌破当前档底线降级（带上下限保护；积分可增可减）。档差规则：
/// - 级内（18级..1级，索引 0..16）每档固定 10 分；
/// - 段位区域（1级->1段 起，索引 17..25）相邻档差在前一档差基础上 +30%。
///   即 step = floor(10 × 1.3^(rank−16))：级内固定 10，段位区依次 13/16/21/28/37/48/62/81/106。
class RankSystem {
  RankSystem._();

  static const int kMinRankIndex = 0;
  static const int kMaxRankIndex = 26;
  static const int kNumKyuRanks = 18; // 18级..1级
  static const int kNumDanRanks = 9; // 1段..9段
  static const int kTotalRanks = 27;
  static const int kDefaultRankIndex = 0; // 起始段位：18 级、0 积分（可调）

  // ---- 个人积分校准参数（档差） ----
  /// 级内（18级->..->1级）每档所需积分。
  static const int kPointsPerKyuStep = 10;

  /// 段位区域档差基准（1级->1段 = 10 × [kDanStepGrowth]^1）。
  static const double kDanStepBase = 10;

  /// 段位区域档差每档增幅（+30%）。
  static const double kDanStepGrowth = 1.3;

  static bool isValidRank(int rank) =>
      rank >= kMinRankIndex && rank <= kMaxRankIndex;

  /// 从 [rank] 升到 rank+1 所需积分步长（`rank` 为 9 段时无上一档，调用方需自行兜底）。
  static int stepForRank(int rank) {
    assert(isValidRank(rank) && rank < kMaxRankIndex,
        'stepForRank 仅对 rank < kMaxRankIndex 有效');
    if (rank < kNumKyuRanks - 1) {
      return kPointsPerKyuStep; // 0..16 级->级（固定 10）
    }
    // 17..25：段位区域，档差逐档 ×1.3。
    return (kDanStepBase *
            _pow(kDanStepGrowth, rank - (kNumKyuRanks - 2)))
        .floor();
  }

  static double _pow(double base, int exp) {
    var result = 1.0;
    for (var i = 0; i < exp; i++) {
      result *= base;
    }
    return result;
  }

  /// 晋升到 [rank] 档所需累计积分阈值（pointsForRank(0) == 0）。
  static int pointsForRank(int rank) {
    assert(isValidRank(rank), '非法段位索引 $rank');
    var total = 0;
    for (var i = 0; i < rank; i++) {
      total += stepForRank(i);
    }
    return total;
  }

  /// 段位文本：`18级`…`1级`、`1段`…`9段`。
  static String rankName(int rank) {
    assert(isValidRank(rank), '非法段位索引 $rank');
    if (rank < kNumKyuRanks) {
      return '${kNumKyuRanks - rank}级';
    }
    return '${rank - kNumKyuRanks + 1}段';
  }

  /// 按积分校准段位（绝对累计阈值模型）：积分连续累计，跨过下一档阈值晋升，
  /// 跌破当前档底线降级，带上下限保护。积分本身不变，仅校正段位。
  static ({int rank, int points}) reconcile(int points, int rank) {
    var r = rank;
    var p = points < 0 ? 0 : points;
    if (!isValidRank(r)) {
      r = r > kMaxRankIndex ? kMaxRankIndex : kMinRankIndex;
    }
    // 晋升：积分达到更高档阈值即升（保持绝对积分）
    while (r < kMaxRankIndex && p >= pointsForRank(r + 1)) {
      r += 1;
    }
    // 降级：跌破当前档底线（不低于 18级）
    while (r > kMinRankIndex && p < pointsForRank(r)) {
      r -= 1;
    }
    return (rank: r, points: p);
  }
}
