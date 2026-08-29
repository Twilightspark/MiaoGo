import 'package:flutter/material.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/game/game_controller.dart';

/// 成绩面板动作。
enum ScoreSheetAction { restart, exit }

/// 终局成绩面板：胜负 / 目差 / 分项明细 / 规则信息。
class ScoreSheetDialog extends StatelessWidget {
  const ScoreSheetDialog({super.key, required this.game});

  final GameState game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resigned = game.resignedBy != null;
    final result = game.result;
    final winner = game.winner;

    String headline;
    Color headlineColor;
    if (resigned) {
      headline = '${winner!.label}胜（中盘）';
      headlineColor = winner == game.humanColor
          ? GoColors.pine
          : GoColors.textSecondary;
    } else if (winner == null) {
      headline = '和棋';
      headlineColor = GoColors.wood;
    } else {
      headline = '${winner.label}胜';
      headlineColor = winner == game.humanColor
          ? GoColors.pine
          : GoColors.textSecondary;
    }

    return AlertDialog(
      title: const Text('对局结束'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              headline,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: headlineColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (result != null) ...[
            const SizedBox(height: 6),
            Center(
              child: Text(
                result.description,
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: GoColors.textSecondary),
              ),
            ),
            const SizedBox(height: 14),
            for (final line in result.details)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(line, style: theme.textTheme.bodySmall),
              ),
          ] else if (resigned) ...[
            const SizedBox(height: 6),
            Center(
              child: Text(
                '${game.resignedBy!.label}方认输',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: GoColors.textSecondary),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Divider(color: theme.colorScheme.outlineVariant),
          Text(
            '${game.rule.label}规则 · 贴目 ${game.komi} · ${game.boardSize} 路 · '
            '共 ${game.moves.length} 手',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: GoColors.textSecondary),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.pop(context, ScoreSheetAction.exit),
          icon: const Icon(Icons.exit_to_app),
          label: const Text('返回'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, ScoreSheetAction.restart),
          icon: const Icon(Icons.replay),
          label: const Text('再来一局'),
        ),
      ],
    );
  }
}
