import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/engine/analysis.dart';
import 'package:miaogo/engine/engine_controller.dart';
import 'package:miaogo/engine/katago_engine.dart';

/// 引擎加载状态条：未就绪/失败时显示在棋盘上方。
class EngineStatusBanner extends ConsumerWidget {
  const EngineStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(engineStatusProvider);
    if (status == EngineStatus.ready || status == EngineStatus.idle) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final (icon, text, action) = switch (status) {
      EngineStatus.loading => (
          Icons.hourglass_top,
          'KataGo 引擎加载中…',
          null as VoidCallback?
        ),
      EngineStatus.failed => (
          Icons.error_outline,
          'KataGo 引擎不可用，无法对弈',
          () => ref.read(engineStatusProvider.notifier).start()
        ),
      _ => (Icons.info_outline, '引擎未就绪', null),
    };
    return Material(
      color: status == EngineStatus.failed
          ? GoColors.woodContainer
          : GoColors.pineContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: GoColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: GoColors.textPrimary),
              ),
            ),
            if (action != null)
              TextButton(
                onPressed: action,
                child: const Text('重试'),
              ),
          ],
        ),
      ),
    );
  }
}

/// AI 建议面板：显示建议着法与胜率/访问数。
class SuggestionPanel extends StatelessWidget {
  const SuggestionPanel({
    super.key,
    required this.boardSize,
    required this.suggestion,
    this.onDismiss,
  });

  final int boardSize;
  final MoveAnalysis? suggestion;
  final VoidCallback? onDismiss;

  String get _text {
    final s = suggestion;
    if (s == null) return 'AI 分析中…';
    final winrate = (s.winrate * 100).toStringAsFixed(1);
    return '建议 ${s.move} · 胜率 $winrate% · ${s.visits} 次访问';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: GoColors.pineContainer,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lightbulb_outline, size: 16, color: GoColors.pine),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _text,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: GoColors.onPineContainer),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onDismiss != null) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: onDismiss,
                child: const Icon(Icons.close, size: 16, color: GoColors.pineDark),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 分析更新 → 棋盘建议点（非法/无候选返回 null）。
(int, int)? suggestionPointFrom(
    AnalysisUpdate? update, GoBoard board, PlayerColor toMove) {
  if (update == null) return null;
  for (final a in update.orderedMoves) {
    if (a.move == 'pass') continue;
    final v = coordFromGtp(a.move);
    if (v == null) continue;
    final (r, c) = v;
    if (board.inBounds(r, c) && board.isLegal(toMove, r, c)) {
      return (r, c);
    }
  }
  return null;
}
