import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/joseki.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/study/joseki_library.dart';
import 'package:miaogo/study/problem_engine.dart';
import 'package:miaogo/ui/board_widget.dart';
import 'package:miaogo/ui/study/beginner_guide_page.dart';
import 'package:miaogo/ui/study/joseki_practice_page.dart';
import 'package:miaogo/ui/study/problem_list_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<List<Override>> baseOverrides() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final overrides = <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      // 轻量定式库，避免加载全量资产拖慢冒烟测试。
      josekiLibraryProvider.overrideWith(
          (ref) async => JosekiLibrary([], JosekiMatcher([]))),
    ];
    return overrides;
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

  testWidgets('功课页：新手指引与定式练习直接渲染', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final overrides = await baseOverrides();

    // 基础规则新手指引 → 引导页控件齐全。
    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: BeginnerGuidePage()),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide_step_index')), findsOneWidget);
    expect(find.byKey(const ValueKey('guide_prev')), findsOneWidget);
    expect(find.byKey(const ValueKey('guide_retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('guide_next')), findsOneWidget);

    // 定式练习：二次返回弹出退出确认框，确认后回宿主页。
    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const JosekiPracticePage()),
                ),
                child: const Text('open_joseki'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open_joseki'));
    await tester.pumpAndSettle();
    expect(find.byType(JosekiPracticePage), findsOneWidget);
    await tester.pageBack();
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('退出定式查询'), findsOneWidget);
    await tester.tap(find.text('退出'));
    await tester.pumpAndSettle();
    expect(find.byType(JosekiPracticePage), findsNothing);
  });

  testWidgets('题库：作答后状态更新并归类', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final overrides = await baseOverrides();
    overrides.add(problemLibraryProvider.overrideWith((ref) => fakeLibrary()));

    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: ProblemListPage()),
    ));
    await tester.pumpAndSettle();

    // 入门 → 未做 → 进入作答页。
    await tester.tap(find.text('入门'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('未做'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('入门 第 1 题'));
    await tester.pumpAndSettle();

    // 确认落子模式：点 dd=(3,3) 后点「落子」即答对。
    final rect = tester.getRect(find.byType(GoBoardWidget));
    final margin = rect.width * 0.06;
    final cell = (rect.width - rect.width * 0.12) / (9 - 1);
    await tester.tapAt(Offset(
      rect.left + margin + 3 * cell,
      rect.top + margin + 3 * cell,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('落子'));
    await tester.pumpAndSettle();

    // 返回类别页：切到「已做」应能看到该题。
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('已做'));
    await tester.pumpAndSettle();
    expect(find.text('入门 第 1 题'), findsOneWidget);
  });
}
