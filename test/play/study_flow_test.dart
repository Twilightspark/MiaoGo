import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/study/problem_engine.dart';
import 'package:miaogo/ui/board_widget.dart';
import 'package:miaogo/ui/study/joseki_list_page.dart';
import 'package:miaogo/ui/study/lessons_page.dart';
import 'package:miaogo/ui/study/problem_list_page.dart';
import 'package:miaogo/ui/study/problem_page.dart';
import 'package:miaogo/ui/study/study_home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<List<Override>> baseOverrides() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return [sharedPreferencesProvider.overrideWithValue(prefs)];
  }

  /// 小型题库（避免全量资产加载拖慢冒烟测试）。
  Future<ProblemLibrary> fakeLibrary() async {
    const sgf = '(;SZ[9]AW[ee][ff]AB[ed][fe]C[Black to play];B[dd]C[Correct 捕获两子])';
    return ProblemLibrary([
      Problem.fromGame(
        id: 'easy-1',
        title: '入门 第 1 题',
        difficulty: ProblemDifficulty.beginner,
        asset: 'x.sgf',
        game: Sgf.parse(sgf),
      ),
    ]);
  }

  testWidgets('功课页三入口导航', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final overrides = await baseOverrides();
    overrides.add(problemLibraryProvider.overrideWith((ref) => fakeLibrary()));

    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: StudyHomePage()),
    ));

    // 入门基础 → 课程列表。
    await tester.tap(find.text('入门基础'));
    await tester.pumpAndSettle();
    expect(find.byType(LessonsPage), findsOneWidget);
    expect(find.text('棋具与基本规则'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 定式布局 → 定式列表。
    await tester.tap(find.text('定式布局'));
    await tester.pumpAndSettle();
    expect(find.byType(JosekiListPage), findsOneWidget);
    expect(find.text('星位·小飞挂·一间跳'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 死活题 → 列表页（小题库）。
    await tester.tap(find.text('死活题'));
    await tester.pumpAndSettle();
    expect(find.byType(ProblemListPage), findsOneWidget);
    expect(find.text('入门 第 1 题'), findsOneWidget);
  });

  testWidgets('答题页：答对判定并弹出正解讲解', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final overrides = await baseOverrides();

    // 9 路单步题：黑走 dd=(3,3) 即解。
    const sgf = '(;SZ[9]AW[ee][ff]AB[ed][fe]C[Black to play]'
        ';B[dd]C[Correct 捕获两子])';
    final problem = Problem.fromGame(
      id: 'easy-1',
      title: '入门 第 1 题',
      difficulty: ProblemDifficulty.beginner,
      asset: 'assets/problems/x.sgf',
      game: Sgf.parse(sgf),
    );

    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: ProblemPage(problem: problem)),
    ));
    await tester.pump();

    // 棋盘渲染。
    expect(find.byType(GoBoardWidget), findsOneWidget);
    expect(find.textContaining('轮到 黑方'), findsOneWidget);

    // 点击 dd=(3,3) 即答对 → 弹出对话框。
    final rect = tester.getRect(find.byType(GoBoardWidget));
    final n = problem.boardSize;
    final margin = rect.width * 0.06;
    final cell = (rect.width - rect.width * 0.12) / (n - 1);
    final center = Offset(
      rect.left + margin + 3 * cell,
      rect.top + margin + 3 * cell,
    );
    await tester.tapAt(center);
    await tester.pumpAndSettle();

    expect(find.text('解答正确'), findsOneWidget);
    expect(find.textContaining('Correct'), findsOneWidget);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    // 已解出状态显示。
    expect(find.text('已解出'), findsOneWidget);
  });
}
