import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/app.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/study/problem_engine.dart';
import 'package:miaogo/ui/board_widget.dart';
import 'package:miaogo/ui/common/responsive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 小型题库：10 题（每轮抽 5 题），保证每日打卡可进入。
Future<ProblemLibrary> _fakeLibrary() async {
  const sgf =
      '(;SZ[9]AW[ee][ff]AB[ed][fe]C[Black to play];B[dd]C[Correct 捕获两子])';
  return ProblemLibrary([
    for (var i = 1; i <= 10; i++)
      Problem.fromGame(
        id: 'daily$i',
        title: '每日 第 $i 题',
        difficulty: ProblemDifficulty.beginner,
        asset: 'x$i.sgf',
        game: Sgf.parse(sgf),
      ),
  ]);
}

/// 以逻辑像素设置窗口尺寸（dpr = 1.0）。
void _setLogicalSize(WidgetTester tester, Size logical) {
  tester.view.physicalSize = logical;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        problemLibraryProvider.overrideWith((ref) => _fakeLibrary()),
      ],
      child: const MiaoGoApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('AdaptiveBoardLayout 竖屏：上下堆叠（top/board/bottom 纵向）', (
    tester,
  ) async {
    _setLogicalSize(tester, const Size(360, 800));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AdaptiveBoardLayout(
            board: SizedBox.square(dimension: 100, key: ValueKey('board')),
            top: Text('TOP', key: ValueKey('top')),
            bottom: Text('BOTTOM', key: ValueKey('bottom')),
          ),
        ),
      ),
    );

    final top = tester.getCenter(find.byKey(const ValueKey('top')));
    final board = tester.getCenter(find.byKey(const ValueKey('board')));
    final bottom = tester.getCenter(find.byKey(const ValueKey('bottom')));
    expect(top.dy, lessThan(board.dy));
    expect(bottom.dy, greaterThan(board.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AdaptiveBoardLayout 横屏：左右两栏（棋盘在左，面板在右）', (tester) async {
    _setLogicalSize(tester, const Size(800, 360));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AdaptiveBoardLayout(
            board: SizedBox.square(dimension: 100, key: ValueKey('board')),
            top: Text('TOP', key: ValueKey('top')),
            bottom: Text('BOTTOM', key: ValueKey('bottom')),
          ),
        ),
      ),
    );

    final board = tester.getCenter(find.byKey(const ValueKey('board')));
    final bottom = tester.getCenter(find.byKey(const ValueKey('bottom')));
    expect(bottom.dx, greaterThan(board.dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页横屏：通栏顶栏 + 左功能卡 / 右快捷入口同屏且不溢出', (tester) async {
    _setLogicalSize(tester, const Size(900, 420));
    await _pumpApp(tester);

    expect(find.byKey(const ValueKey('home_username')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_stat_checkin')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_quick_entry_入门')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页竖屏：单列仍渲染功能卡与快捷入口', (tester) async {
    _setLogicalSize(tester, const Size(360, 800));
    await _pumpApp(tester);

    expect(find.byKey(const ValueKey('home_stat_checkin')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_quick_entry_入门')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('死活题横屏：棋盘与操作按钮同屏且不溢出', (tester) async {
    _setLogicalSize(tester, const Size(900, 420));
    await _pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('home_daily_start')));
    await tester.pumpAndSettle();

    expect(find.byType(GoBoardWidget), findsOneWidget);
    expect(find.text('上一题'), findsOneWidget);
    expect(find.text('下一题'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
