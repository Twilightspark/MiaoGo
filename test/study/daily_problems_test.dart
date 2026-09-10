import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/storage/problem_store.dart';
import 'package:miaogo/study/daily_problems.dart';
import 'package:miaogo/study/problem_engine.dart';

Problem _p(String id, ProblemDifficulty d) => Problem.fromGame(
      id: id,
      title: id,
      difficulty: d,
      asset: '$id.sgf',
      game: Sgf.parse('(;SZ[9]AW[dd];B[cc]C[Correct])'),
    );

ProblemStatus _wrong() => const ProblemStatus(solved: false, attempts: 1);

ProblemStatus _solved() => const ProblemStatus(solved: true, attempts: 1);

void main() {
  group('每日一题抽题', () {
    test('优先抽未做过的题', () {
      final lib = <Problem>[
        for (var i = 0; i < 5; i++) _p('new$i', ProblemDifficulty.beginner),
        for (var i = 0; i < 3; i++) _p('wrong$i', ProblemDifficulty.beginner),
        for (var i = 0; i < 2; i++) _p('solved$i', ProblemDifficulty.beginner),
      ];
      final progress = <String, ProblemStatus>{
        for (var i = 0; i < 3; i++) 'wrong$i': _wrong(),
        for (var i = 0; i < 2; i++) 'solved$i': _solved(),
      };
      final ids = selectDailyProblemIds(
        library: lib,
        rankIndex: 0,
        progress: progress,
        now: DateTime(2026, 1, 1),
      );
      expect(ids.length, 5);
      expect(ids.toSet(), {for (var i = 0; i < 5; i++) 'new$i'});
    });

    test('未做题不足时补错题，不抽已做对的题', () {
      final lib = <Problem>[
        for (var i = 0; i < 2; i++) _p('new$i', ProblemDifficulty.beginner),
        for (var i = 0; i < 8; i++) _p('wrong$i', ProblemDifficulty.beginner),
        for (var i = 0; i < 5; i++) _p('solved$i', ProblemDifficulty.beginner),
      ];
      final progress = <String, ProblemStatus>{
        for (var i = 0; i < 8; i++) 'wrong$i': _wrong(),
        for (var i = 0; i < 5; i++) 'solved$i': _solved(),
      };
      final ids = selectDailyProblemIds(
        library: lib,
        rankIndex: 0,
        progress: progress,
        now: DateTime(2026, 1, 1),
      );
      expect(ids.length, 5);
      expect(ids.where((id) => id.startsWith('solved')), isEmpty);
      expect(ids.where((id) => id.startsWith('new')).length, 2);
    });

    test('低段位（18级~10级）不会抽到高级题', () {
      final lib = <Problem>[
        for (var i = 0; i < 5; i++) _p('b$i', ProblemDifficulty.beginner),
        for (var i = 0; i < 5; i++) _p('m$i', ProblemDifficulty.intermediate),
        for (var i = 0; i < 5; i++) _p('a$i', ProblemDifficulty.advanced),
      ];
      for (var day = 1; day <= 30; day++) {
        final ids = selectDailyProblemIds(
          library: lib,
          rankIndex: 0,
          progress: const {},
          now: DateTime(2026, 1, day),
        );
        expect(ids.any((id) => id.startsWith('a')), isFalse);
      }
    });

    test('高段位（1段~9段）以高级题为主', () {
      final lib = <Problem>[
        for (var i = 0; i < 20; i++) _p('b$i', ProblemDifficulty.beginner),
        for (var i = 0; i < 20; i++) _p('m$i', ProblemDifficulty.intermediate),
        for (var i = 0; i < 20; i++) _p('a$i', ProblemDifficulty.advanced),
      ];
      var advanced = 0, beginner = 0;
      for (var day = 1; day <= 120; day++) {
        final ids = selectDailyProblemIds(
          library: lib,
          rankIndex: 26,
          progress: const {},
          now: DateTime(2026, 1, day),
        );
        for (final id in ids) {
          if (id.startsWith('a')) advanced++;
          if (id.startsWith('b')) beginner++;
        }
      }
      expect(advanced, greaterThan(beginner));
    });

    test('同日同段位结果稳定，数量不超过题量', () {
      final lib = <Problem>[
        for (var i = 0; i < 3; i++) _p('b$i', ProblemDifficulty.beginner),
      ];
      final a = selectDailyProblemIds(
        library: lib,
        rankIndex: 5,
        progress: const {},
        now: DateTime(2026, 5, 1),
      );
      final b = selectDailyProblemIds(
        library: lib,
        rankIndex: 5,
        progress: const {},
        now: DateTime(2026, 5, 1),
      );
      expect(a, b);
      expect(a.length, 3);
      expect(a.toSet().length, 3);
    });

    test('空题库返回空', () {
      expect(
        selectDailyProblemIds(
          library: const [],
          rankIndex: 0,
          progress: const {},
          now: DateTime(2026, 1, 1),
        ),
        isEmpty,
      );
    });
  });
}
