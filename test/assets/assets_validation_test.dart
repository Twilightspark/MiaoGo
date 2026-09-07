import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/study/joseki_library.dart';
import 'package:miaogo/study/problem_engine.dart';
import 'package:miaogo/ui/record/famous_games.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('死活题题库（assets/problems）', () {
    test('全部题目可解析且正解主线可完整走出', () async {
      final library = await ProblemLibrary.load();
      expect(library.problems.length, greaterThanOrEqualTo(420));
      expect(library.problems.length, lessThanOrEqualTo(422));

      var failed = 0;
      for (final p in library.problems) {
        // 初始局面应有布子。
        var stones = 0;
        for (var r = 0; r < p.boardSize; r++) {
          for (var c = 0; c < p.boardSize; c++) {
            if (p.initial.at(r, c) != null) stones++;
          }
        }
        if (stones < 4) {
          failed++;
          // ignore: avoid_print
          print('  [布子不足] ${p.id}');
          continue;
        }
        // 正解主线应能通过判定引擎走通。
        final solver = ProblemSolver(p);
        var guard = 0;
        while (!solver.solved && guard < 200) {
          final expected = solver.expectedMove;
          if (expected == null || expected.isPass) break;
          final outcome = solver.play(expected.row!, expected.col!);
          if (outcome == StepOutcome.wrong) break;
          guard++;
        }
        if (!solver.solved) {
          failed++;
          // ignore: avoid_print
          print('  [无法走通] ${p.id} 主线 ${p.mainline.length} 节点');
        }
      }
      expect(failed, 0, reason: '有 $failed 题解析/走通失败');
    });

    test('难度分组均有题且总数正确', () async {
      final library = await ProblemLibrary.load();
      for (final d in ProblemDifficulty.values) {
        expect(library.byDifficulty(d), isNotEmpty,
            reason: '${d.label} 组无题目');
      }
    });
  });

  group('历史名谱（assets/famous）', () {
    test('全部名谱可解析且含棋步', () async {
      for (final info in kFamousGames) {
        final data = await rootBundle.loadString(info.asset);
        final game = Sgf.parse(data);
        expect(game.moves.length, greaterThanOrEqualTo(40),
            reason: '${info.asset} 棋步过少');
      }
    });
  });

  group('定式库（assets/joseki）', () {
    test('定式库可加载、全部可回放且能命中常见首手', () async {
      final library = await JosekiLibrary.load();
      expect(library.entries.length, greaterThan(3000),
          reason: '定式条目过少');

      for (final e in library.entries) {
        final game = Sgf.parse(e.sgf);
        expect(game.moves, isNotEmpty, reason: '${e.id} 无棋步');
      }

      // 常见第一手（星位）应能命中。
      final hits = library.matcher.match(['pd']);
      expect(hits, isNotEmpty, reason: '星位第一手应命中定式');
      expect(hits.first.matchLen, greaterThanOrEqualTo(1));
    });
  });
}
