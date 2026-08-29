import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/study/problem_engine.dart';

Problem _mk(String sgf,
    {String id = 'p1', ProblemDifficulty d = ProblemDifficulty.beginner}) {
  return Problem.fromGame(
    id: id,
    title: '入门 第 1 题',
    difficulty: d,
    asset: 'assets/problems/x.sgf',
    game: Sgf.parse(sgf),
  );
}

void main() {
  // 简化的 gogameguru 结构：根布子 → 首分支正解（含防守应手），其余错解。
  const sgf = '(;SZ[19]AW[pp][qp][rp][or][qr]AB[pq][rq][qq]C[Black to play]'
      '(;B[qs](;W[ps];B[rs]C[Correct])(;W[os]))'
      '(;B[os](;W[qs]))'
      '(;B[ps](;W[qs])))';
  // qs=(row17,col15), ps=(row17,col14), rs=(row17,col16), os=(row17,col13)

  group('Problem 解析', () {
    test('布子 / 执子方 / 题目说明 / 讲解', () {
      final p = _mk(sgf);
      expect(p.boardSize, 19);
      expect(p.toPlay, PlayerColor.black);
      expect(p.prompt, 'Black to play');
      // 布子：AW 5 子、AB 3 子。
      var whites = 0, blacks = 0;
      for (var r = 0; r < p.boardSize; r++) {
        for (var c = 0; c < p.boardSize; c++) {
          if (p.initial.at(r, c) == PlayerColor.white) whites++;
          if (p.initial.at(r, c) == PlayerColor.black) blacks++;
        }
      }
      expect(whites, 5);
      expect(blacks, 3);
      // 讲解取 C[Correct] 节点注释。
      expect(p.explanation, 'Correct');
      // 正解主线：B[qs] W[ps] B[rs]。
      expect(p.solutionMoves, [
        const Move.point(PlayerColor.black, 17, 15),
        const Move.point(PlayerColor.white, 17, 14),
        const Move.point(PlayerColor.black, 17, 16),
      ]);
    });

    test('无 C[Correct] 时讲解回退到主线末注释', () {
      const t = '(;SZ[9]AW[dd]AB[ee];B[cc];W[bb]C[happy end])';
      final p = _mk(t);
      expect(p.explanation, 'happy end');
      expect(p.toPlay, PlayerColor.black);
    });

    test('PL 指定白方执子', () {
      const t = '(;SZ[9]PL[W]AW[dd];W[cc];B[bb])';
      final p = _mk(t);
      expect(p.toPlay, PlayerColor.white);
      expect(p.solutionMoves.first, const Move.point(PlayerColor.white, 2, 2));
    });
  });

  group('ProblemSolver 判定', () {
    test('正解逐步推进，防守方自动应，终止即解', () {
      final p = _mk(sgf);
      final solver = ProblemSolver(p);
      expect(solver.expectedMove, const Move.point(PlayerColor.black, 17, 15));

      // 第 1 手：B[qs] 正确。
      expect(solver.play(17, 15), StepOutcome.correct);
      // 防守方自动应 W[ps]，轮到用户再下 B[rs]。
      expect(solver.board.at(17, 14), PlayerColor.white);
      expect(solver.expectedMove, const Move.point(PlayerColor.black, 17, 16));
      expect(solver.solved, isFalse);

      // 第 2 手：B[rs] 正确 → 到达 C[Correct]，解出。
      expect(solver.play(17, 16), StepOutcome.correct);
      expect(solver.solved, isTrue);
      expect(solver.board.at(17, 16), PlayerColor.black);
    });

    test('错解计入尝试次数，不推进', () {
      final p = _mk(sgf);
      final solver = ProblemSolver(p);
      expect(solver.play(17, 14), StepOutcome.wrong); // 走 B[ps]（错解分支）
      expect(solver.attempts, 1);
      expect(solver.solved, isFalse);
      // 之后仍可走正解。
      expect(solver.play(17, 15), StepOutcome.correct);
      expect(solver.board.at(17, 15), PlayerColor.black);
    });

    test('占点非法落子按错解处理', () {
      final p = _mk(sgf);
      final solver = ProblemSolver(p);
      // (17,15) 无子可落？（初始局面 qq=(15,15) 已占）——测试占点。
      expect(solver.play(15, 15), StepOutcome.wrong);
      expect(solver.attempts, 1);
    });

    test('解出后再落子返回 alreadySolved', () {
      final p = _mk(sgf);
      final solver = ProblemSolver(p);
      solver.play(17, 15);
      solver.play(17, 16);
      expect(solver.solved, isTrue);
      expect(solver.play(17, 14), StepOutcome.alreadySolved);
    });

    test('长正解（无分支主线）逐步推进', () {
      const t = '(;SZ[13]AW[dd][de]AB[ee];B[cc];W[fc];B[cf];W[ce]C[Correct])';
      final p = _mk(t);
      final solver = ProblemSolver(p);
      expect(solver.expectedMove, const Move.point(PlayerColor.black, 2, 2));
      expect(solver.play(2, 2), StepOutcome.correct);
      // 防守方 W[fc]=(2,5) 自动应。
      expect(solver.board.at(2, 5), PlayerColor.white);
      expect(solver.expectedMove, const Move.point(PlayerColor.black, 5, 2));
      expect(solver.play(5, 2), StepOutcome.correct);
      // W[ce]=(4,2) 防守自动应。
      expect(solver.board.at(4, 2), PlayerColor.white);
      // 主线到 C[Correct]，解出。
      expect(solver.solved, isTrue);
    });

    test('reset 恢复初始局面', () {
      final p = _mk(sgf);
      final solver = ProblemSolver(p);
      solver.play(17, 15);
      solver.play(17, 16);
      expect(solver.solved, isTrue);
      solver.reset();
      expect(solver.solved, isFalse);
      expect(solver.attempts, 0);
      expect(solver.board.at(17, 15), isNull);
      expect(solver.expectedMove, const Move.point(PlayerColor.black, 17, 15));
    });
  });
}
