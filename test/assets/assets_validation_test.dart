import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/study/joseki_library.dart';
import 'package:miaogo/study/problem_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('死活题题库（assets/problems）', () {
    test('全部题目可解析且正解主线可完整走出', () async {
      final library = await ProblemLibrary.load();
      // 422（gogameguru）+ 509（Gokyo）+ 887（Cho Elementary）+ 860（Cho Intermediate）
      // ≈ 2678。三档模型后总量大幅增加，此处仅校验数量级下限与上限（容忍个别源缺陷）。
      expect(library.problems.length, greaterThanOrEqualTo(2600),
          reason: '题库总数异常（疑漏加载 cho/gokyo/）');
      expect(library.problems.length, lessThanOrEqualTo(2800));

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
        while (!solver.solved && guard < 500) {
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

    test('难度分组均有题且入门/中级/高级三档扩容到位', () async {
      final library = await ProblemLibrary.load();
      for (final d in ProblemDifficulty.values) {
        expect(library.byDifficulty(d), isNotEmpty,
            reason: '${d.label} 组无题目');
      }
      // 三档模型：入门 = ggg easy+intermediate + Cho Elementary（≥1100）；
      // 中级 = ggg-hard + Gokyo + Cho Intermediate 前 2/3（≥1200）；
      // 高级 = ggg-other + Cho Intermediate 末 1/3（≥250）。
      expect(library.byDifficulty(ProblemDifficulty.beginner).length,
          greaterThanOrEqualTo(1100),
          reason: '入门题量未达三档扩容预期');
      expect(library.byDifficulty(ProblemDifficulty.intermediate).length,
          greaterThanOrEqualTo(1200),
          reason: '中级题量未达扩容预期');
      expect(library.byDifficulty(ProblemDifficulty.advanced).length,
          greaterThanOrEqualTo(250),
          reason: '高级题量未达扩容预期');
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
