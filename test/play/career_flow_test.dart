import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/ui/play/career_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首页不再直连生涯页，故直接以生涯主页启动（对退出/报名/赛程的子系统测试）。
Future<void> pumpToCareer(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: CareerPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('生涯页：三区渲染，初始无当前赛事，三场待报名', (tester) async {
    await pumpToCareer(tester);

    expect(find.text('生涯大赛'), findsOneWidget);
    expect(find.text('当前参加的比赛'), findsOneWidget);
    expect(find.text('即将举行的比赛'), findsOneWidget);
    expect(find.text('历史竞赛成绩'), findsOneWidget);
    expect(find.textContaining('尚未报名任何大赛'), findsOneWidget);

    expect(find.byKey(const ValueKey('career_signup_9')), findsOneWidget);
    expect(find.byKey(const ValueKey('career_signup_13')), findsOneWidget);
    expect(find.byKey(const ValueKey('career_signup_19')), findsOneWidget);
  });

  testWidgets('报名 9 路：确认后成为当前赛事，其余报名禁用，可查看赛程', (tester) async {
    await pumpToCareer(tester);

    await tester.tap(find.byKey(const ValueKey('career_signup_9')));
    await tester.pumpAndSettle();
    expect(find.text('报名大赛'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('career_confirm_signup')));
    await tester.pumpAndSettle();
    // 等待「报名成功」提示过期，避免遮挡后续 SnackBar 断言。
    await tester.pump(const Duration(seconds: 5));

    expect(find.byKey(const ValueKey('career_open_bracket')), findsOneWidget);
    // 其余两场不可报名（进行中）
    final btn13 = tester.widget<FilledButton>(
        find.byKey(const ValueKey('career_signup_13')));
    expect(btn13.onPressed, isNull);

    // 进入路线图页
    await tester.tap(find.byKey(const ValueKey('career_open_bracket')));
    await tester.pumpAndSettle();
    expect(find.text('1/4 决赛'), findsOneWidget);
    expect(find.text('半决赛'), findsOneWidget);
    expect(find.text('决赛'), findsOneWidget);
    expect(find.text('冠军'), findsOneWidget);
    expect(find.byKey(const ValueKey('bracket_play')), findsOneWidget);

    // 引擎未就绪：点击开始对局给出提示，不进入对局
    await tester.tap(find.byKey(const ValueKey('bracket_play')));
    await tester.pumpAndSettle();
    expect(find.textContaining('未就绪'), findsOneWidget);
  });

  testWidgets('退赛：二次确认后清空当前赛事并记入历史', (tester) async {
    await pumpToCareer(tester);

    await tester.tap(find.byKey(const ValueKey('career_signup_19')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('career_confirm_signup')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('career_open_bracket')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('career_withdraw')));
    await tester.pumpAndSettle();
    expect(find.text('退赛将无法获得本场大赛的任何积分奖励，确定退赛吗？'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('career_confirm_withdraw')));
    await tester.pumpAndSettle();

    expect(find.textContaining('尚未报名任何大赛'), findsOneWidget);
    expect(find.text('退赛'), findsWidgets);
  });
}
