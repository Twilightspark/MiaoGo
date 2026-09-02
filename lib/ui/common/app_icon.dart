import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 首页 SVG 图标资产路径（颜色已烤进文件，与 GoColors 语义色一致）。
///
/// 命名映射：
/// - daily      做题 → 每日一题
/// - play       对弈 → 快速对弈
/// - tournament 竞赛 → 赛事生涯
/// - basics     入门 → 入门
/// - joseki     定式 → 定式
/// - library    题库 → 题库
/// - record     棋谱 → 棋谱
/// - history    历史 → 历史记录的对弈记录
/// - competition 比赛 → 历史记录的竞赛
abstract final class AppIcon {
  static const daily = 'assets/icons/daily.svg';
  static const play = 'assets/icons/play.svg';
  static const tournament = 'assets/icons/tournament.svg';
  static const basics = 'assets/icons/basics.svg';
  static const joseki = 'assets/icons/joseki.svg';
  static const library = 'assets/icons/library.svg';
  static const record = 'assets/icons/record.svg';
  static const history = 'assets/icons/history.svg';
  static const competition = 'assets/icons/competition.svg';
}

/// 统一「圆形浅色底 + 居中 SVG」图标瓦片，首页卡片/入口/历史项复用。
class AppIconTile extends StatelessWidget {
  const AppIconTile({
    super.key,
    required this.asset,
    required this.color,
    this.tile = 48,
    this.iconSize,
  });

  /// 图标资产路径（[AppIcon]）。
  final String asset;

  /// 语义色：用于圆形底色（浅色调），与文件内烤入的图标色保持一致。
  final Color color;

  /// 瓦片直径。
  final double tile;

  /// 图标绘制边长，默认取瓦片的 52%。
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final size = iconSize ?? tile * 0.52;
    return Container(
      width: tile,
      height: tile,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
      ),
      child: SvgPicture.asset(asset, width: size, height: size),
    );
  }
}
