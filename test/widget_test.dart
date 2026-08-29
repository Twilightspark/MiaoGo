import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/app.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MiaoGoApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('首页渲染用户区与功能入口（默认 18级 / 0 积分，无底部导航栏）',
      (tester) async {
    await pumpApp(tester);

    expect(find.byType(NavigationBar), findsNothing);

    // 用户区：头像、名称 棋手、等级 18级、设置按钮
    expect(find.byKey(const ValueKey('home_avatar')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_username')), findsOneWidget);
    expect(find.text('棋手'), findsWidgets);
    expect(find.text('18级'), findsWidgets);
    expect(find.byKey(const ValueKey('home_settings')), findsOneWidget);

    // 功能入口
    for (final title in ['快速对局', '参加竞赛', '今日学习', '棋谱', '功课']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('0 分'), findsNothing);
  });

  testWidgets('点击首页入口跳转对应页面', (tester) async {
    await pumpApp(tester);

    Future<void> tapKey(String key) async {
      final finder = find.byKey(ValueKey(key));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    // 快速对局 → 对弈页
    await tapKey('home_card_quick_play');
    expect(find.text('生涯模式'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 参加竞赛 → 对弈页
    await tapKey('home_card_tournament');
    expect(find.text('人机模式'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 今日学习 → 功课页
    await tapKey('home_card_daily_study');
    expect(find.text('入门基础'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 棋谱按钮 → 棋谱页
    await tapKey('home_button_record');
    expect(find.text('个人棋谱'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 功课按钮 → 功课页
    await tapKey('home_button_study');
    expect(find.text('定式布局'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 设置按钮 → 设置页
    await tapKey('home_settings');
    expect(find.text('棋盘大小'), findsOneWidget);
  });

  testWidgets('点击头像弹出头像弹窗', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('home_avatar')));
    await tester.pumpAndSettle();
    expect(find.text('更换头像'), findsOneWidget);

    // 关闭弹窗
    await tester.tap(find.text('更换头像'));
    await tester.pumpAndSettle();
    expect(find.text('更换头像'), findsNothing);
  });

  testWidgets('点击用户名弹出用户详情弹窗：改名与统计', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('home_username')));
    await tester.pumpAndSettle();

    expect(find.text('改名'), findsOneWidget);
    expect(find.text('重生'), findsOneWidget);
    expect(find.text('当前等级'), findsOneWidget);
    expect(find.text('积分'), findsOneWidget);
    expect(find.text('参赛次数'), findsOneWidget);
    expect(find.text('冠军次数'), findsOneWidget);
    expect(find.text('胜率'), findsOneWidget);
    expect(find.text('18级'), findsWidgets);
    expect(find.text('0'), findsWidgets);

    // 改名
    await tester.tap(find.text('改名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '喵棋大师');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('喵棋大师'), findsWidgets);

    // 重生：二次确认后初始化用户信息
    await tester.tap(find.text('重生'));
    await tester.pumpAndSettle();
    expect(find.text('重生将初始化用户信息（名称、段位、积分与全部统计），确定继续？'),
        findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('棋手'), findsWidgets);
  });
}
