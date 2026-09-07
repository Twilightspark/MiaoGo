import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/joseki.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/study/joseki_library.dart';
import 'package:miaogo/ui/study/joseki_practice_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<List<Override>> overrides() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final entry = JosekiEntry(
      id: 't1',
      moves: const ['qd', 'qc'],
      label: '测试定式',
      sgf: '',
      frequency: 10,
    );
    final library = JosekiLibrary([entry], JosekiMatcher([entry]));
    return [
      sharedPreferencesProvider.overrideWithValue(prefs),
      josekiLibraryProvider.overrideWith((ref) async => library),
    ];
  }

  testWidgets('选中定式：保留当前局面，上下一步整条回放', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: await overrides(),
      child: const MaterialApp(home: JosekiPracticePage()),
    ));
    await tester.pumpAndSettle();

    // 默认确认落子方式：先点棋盘（TR 角 qd 点），再点「落子」。
    final board = find.byKey(const ValueKey('joseki_board'));
    expect(board, findsOneWidget);
    final rect = tester.getRect(board);
    const size = 19;
    final side = rect.width;
    final margin = side * 0.06;
    final cell = (side - side * 0.12) / (size - 1);
    Offset at(int r, int c) =>
        Offset(rect.left + margin + c * cell, rect.top + margin + r * cell);

    // 'qd' = 第 3 行、第 15 列（TR 规范角）。
    await tester.tapAt(at(3, 15));
    await tester.pumpAndSettle();
    await tester.tap(find.text('落子'));
    await tester.pumpAndSettle();

    // 查询态命中「测试定式」。
    expect(find.text('测试定式'), findsOneWidget);
    await tester.tap(find.text('测试定式'));
    await tester.pumpAndSettle();

    // 查看态：控制栏切换为上一手/下一手/退出，且停留在命中手数（第 1 手）。
    expect(find.text('上一手'), findsOneWidget);
    expect(find.text('下一手'), findsOneWidget);
    expect(find.text('退出'), findsOneWidget);
    expect(find.text('撤销'), findsNothing);
    expect(find.text('清空'), findsNothing);
    expect(find.textContaining('第 1/2 手'), findsOneWidget);

    // 下一手 -> 第 2 手；上一手 -> 回到第 1 手。
    await tester.tap(find.text('下一手'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2/2 手'), findsOneWidget);
    await tester.tap(find.text('上一手'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1/2 手'), findsOneWidget);

    // 退出返回查询态：棋盘保留已落之子（仍命中列表）。
    await tester.tap(find.text('退出'));
    await tester.pumpAndSettle();
    expect(find.text('测试定式'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);
  });
}
