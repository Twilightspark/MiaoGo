import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/engine/analysis.dart';

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
  test('bestCandidateWinrate 跳过 pass 取最优候选胜率', () {
    final u = AnalysisUpdate(moves: [
      _m('pass', 0.9, 0),
      _m('E4', 0.56, 1),
      _m('C3', 0.52, 2),
    ]);
    expect(bestCandidateWinrate(u), 0.56);
    expect(bestCandidateWinrate(null), isNull);
    expect(bestCandidateWinrate(const AnalysisUpdate(moves: [])), isNull);
  });

  test('blackPerspectiveWinrate 换算黑方视角', () {
    expect(blackPerspectiveWinrate(0.7, PlayerColor.black), 0.7);
    expect(blackPerspectiveWinrate(0.7, PlayerColor.white),
        closeTo(0.3, 1e-9));
  });
}
