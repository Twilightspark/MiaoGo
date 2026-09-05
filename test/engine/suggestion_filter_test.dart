import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/engine/analysis.dart';
import 'package:miaogo/ui/analysis_overlay.dart';

MoveAnalysis _m(String move, double win, int order) => MoveAnalysis(
      move: move,
      visits: 10,
      winrate: win,
      utility: 0,
      scoreLead: 0,
      prior: 0,
      lcb: 0,
      order: order,
      pv: const [],
    );

void main() {
  test('胜率差过滤：与最佳差 >10% 丢弃，跳过 pass 与非法点', () {
    final board = GoBoard(size: 9);
    board.play(PlayerColor.black, 0, 0); // 占 A1
    final u = AnalysisUpdate(moves: [
      _m('pass', 0.61, 0),
      _m('D5', 0.45, 4), // 距最佳 13% → 丢弃
      _m('E4', 0.58, 1), // 最佳
      _m('C3', 0.50, 2), // 差 8% → 保留
      _m('A1', 0.56, 3), // 占点非法 → 丢弃
    ]);
    final got = filterSuggestions(u, board, PlayerColor.black);
    expect(got.map((a) => a.move), ['E4', 'C3']);
  });

  test('候选过多时截断为最多 4 个', () {
    final board = GoBoard(size: 9);
    final moves = [
      for (var i = 0; i < 8; i++) _m('E${i + 1}', 0.52, i),
    ];
    final got = filterSuggestions(
      AnalysisUpdate(moves: moves),
      board,
      PlayerColor.black,
    );
    expect(got.length, 4);
    expect(got.first.move, 'E1');
  });
}
