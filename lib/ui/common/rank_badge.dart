import 'package:flutter/material.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/core/rank.dart';

/// 段位徽章：级为松柏青（等级）、段为棋盘木色（段位）；对弈/棋谱/首页复用。
///
/// 紧凑横向胶囊：宽度随文本自适应，[size] 表示徽章高度。
class RankBadge extends StatelessWidget {
  const RankBadge({super.key, required this.rankIndex, this.size = 20});

  final int rankIndex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDan = rankIndex >= RankSystem.kNumKyuRanks;
    final bg = isDan ? GoColors.wood : GoColors.pine;
    return Container(
      height: size,
      padding: EdgeInsets.symmetric(horizontal: size * 0.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Text(
        RankSystem.rankName(rankIndex),
        style: TextStyle(
          color: GoColors.white,
          fontSize: size * 0.5,
          fontWeight: FontWeight.bold,
          height: 2.0,
        ),
        textAlign: TextAlign.center,
        maxLines: 1,
      ),
    );
  }
}
