import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 响应式断点（逻辑像素宽度）。
///
/// 约定：`compact` 手机竖屏；`medium` 手机横屏 / 平板竖屏；`expanded` 平板横屏。
/// [twoPane] 为启用左右两栏布局的阈值，可覆盖手机横屏（约 800）与平板。
abstract final class Breakpoints {
  static const double compact = 600;
  static const double medium = 840;
  static const double expanded = 1200;

  /// 宽屏 / 横屏阈值：达到后启用左右两栏布局。
  static const double twoPane = 720;
}

/// 是否处于宽屏 / 横屏（可启用两栏布局）。
bool isWideLayout(BuildContext context, {double min = Breakpoints.twoPane}) =>
    MediaQuery.sizeOf(context).width >= min;

/// 大屏居中限宽容器：避免内容在平板 / 横屏被拉伸过宽。
class CenteredContent extends StatelessWidget {
  const CenteredContent({
    super.key,
    required this.child,
    this.maxWidth = 1100,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// 棋盘页自适应布局：竖屏上下堆叠（保持既有结构），宽屏 / 横屏左右两栏
/// （棋盘在左，状态卡 / 胜率 / 操作按钮等在右）。
///
/// [top] 与 [bottom] 在竖屏分别置于棋盘上、下方；宽屏并入右栏。
/// [panel] 为宽屏右栏自定义内容（如含 `Expanded` 列表）；为空时自动使用
/// [top] + [bottom] 组成的可滚动 [Column]。
class AdaptiveBoardLayout extends StatelessWidget {
  const AdaptiveBoardLayout({
    super.key,
    required this.board,
    this.top,
    this.bottom,
    this.panel,
    this.boardFlex = 1,
    this.panelFlex = 1,
    this.boardMaxSide = 640,
    this.maxWidth = 1200,
    this.gap = 12,
    this.breakpoint = Breakpoints.twoPane,
    this.bottomExpanded = false,
  });

  final Widget board;
  final Widget? top;
  final Widget? bottom;
  final Widget? panel;

  /// 棋盘与右栏宽度比（默认 1:1）。
  final int boardFlex;
  final int panelFlex;

  /// 棋盘最大边长（平板 / 大屏避免过大）。
  final double boardMaxSide;

  /// 两栏整体最大宽度（居中限宽）。
  final double maxWidth;
  final double gap;
  final double breakpoint;

  /// [bottom] 是否占据剩余空间（竖屏与棋盘均分高度，宽屏填满右栏）。
  /// 适用于底部含可滚动列表（如定式匹配列表）的页面。
  final bool bottomExpanded;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= breakpoint;
        if (!wide) {
          return Column(
            children: [
              ?top,
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: boardMaxSide),
                    child: board,
                  ),
                ),
              ),
              if (bottom != null)
                bottomExpanded ? Expanded(child: bottom!) : bottom!,
            ],
          );
        }
        final totalWidth = math.min(constraints.maxWidth, maxWidth);
        final boardArea =
            (totalWidth - gap) * boardFlex / (boardFlex + panelFlex);
        final side = math.min(
          constraints.maxHeight,
          math.min(boardArea, boardMaxSide),
        );
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: boardFlex,
                  child: Center(
                    child: SizedBox.square(dimension: side, child: board),
                  ),
                ),
                SizedBox(width: gap),
                Expanded(flex: panelFlex, child: panel ?? _defaultPanel()),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _defaultPanel() {
    if (bottomExpanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?top,
          if (bottom != null) Expanded(child: bottom!),
        ],
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [?top, ?bottom],
      ),
    );
  }
}
