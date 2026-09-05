import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/app.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/study/problem_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 小型题库：5 题，保证每日一题进度「0/5」且加载迅速。
Future<ProblemLibrary> _fakeLibrary() async {
  const sgf = '(;SZ[9]AW[ee][ff]AB[ed][fe]C[Black to play];B[dd]C[Correct 捕获两子])';
  return ProblemLibrary([
    for (var i = 1; i <= 5; i++)
      Problem.fromGame(
        id: 'daily$i',
        title: '每日 第 $i 题',
        difficulty: ProblemDifficulty.beginner,
        asset: 'x$i.sgf',
        game: Sgf.parse(sgf),
      ),
  ]);
}

Future<void> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
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
  testWidgets('首页渲染用户区与统计卡（默认 18级 / 0 积分，无底部导航栏）',
      (tester) async {
    await pumpApp(tester);

    expect(find.byType(NavigationBar), findsNothing);

    // 用户区：头像、名称，无等级徽章；设置按钮
    expect(find.byKey(const ValueKey('home_avatar')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_username')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_settings')), findsOneWidget);
    expect(find.text('棋手'), findsWidgets);

    // 统计卡四栏
    expect(find.text('打卡天数'), findsOneWidget);
    expect(find.text('对局数量'), findsOneWidget);
    expect(find.text('棋手积分'), findsOneWidget);
    expect(find.text('当前棋力'), findsOneWidget);
    expect(find.text('18级'), findsWidgets);

    // 每日一题 / 快速对弈 / 赛事生涯
    expect(find.text('每日一题'), findsOneWidget);
    expect(find.text('做题'), findsOneWidget);
    expect(find.text('快速对弈'), findsOneWidget);
    expect(find.text('赛事生涯'), findsOneWidget);

    // 快捷入口
    for (final label in ['入门', '定式', '题库', '棋谱']) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('点击首页入口跳转对应页面', (tester) async {
    await pumpApp(tester);

    // 快捷入口「入门」→ 入门基础页
    await tester.tap(find.byKey(const ValueKey('home_quick_entry_入门')));
    await tester.pumpAndSettle();
    expect(find.text('入门基础'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 当前赛事「报名」→ 弹窗列出待报名赛事
    await tester.tap(find.byKey(const ValueKey('home_tournament_signup')));
    await tester.pumpAndSettle();
    expect(find.text('报名大赛'), findsOneWidget);
    expect(find.byKey(const ValueKey('signup_option_9')), findsOneWidget);
    expect(find.byKey(const ValueKey('signup_option_13')), findsOneWidget);
    expect(find.byKey(const ValueKey('signup_option_19')), findsOneWidget);

    // 报名 9 路 → 卡片切换为「比赛」
    await tester.tap(find.byKey(const ValueKey('signup_button_9')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home_tournament_continue')), findsOneWidget);

    // 设置按钮 → 设置页
    await tester.tap(find.byKey(const ValueKey('home_settings')));
    await tester.pumpAndSettle();
    expect(find.text('棋盘大小'), findsOneWidget);
  });

  testWidgets('每日一题「做题」进入每日一题会话页', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('home_daily_start')));
    await tester.pumpAndSettle();
    expect(find.text('今日 5 题 · 已解 0'), findsOneWidget);
  });

  testWidgets('设置页点击头像弹出头像修改框', (tester) async {
    await pumpApp(tester);

    // 首页头像不可点击，进入设置页点击头像弹出修改框
    await tester.tap(find.byKey(const ValueKey('home_settings')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings_avatar')));
    await tester.pumpAndSettle();
    expect(find.text('更换头像'), findsOneWidget);

    // 点击更换头像（测试环境无相册 → 关闭弹窗）
    await tester.tap(find.text('更换头像'));
    await tester.pumpAndSettle();
    expect(find.text('更换头像'), findsNothing);
  });

  testWidgets('设置页底部「重生棋手」二次确认后重置用户', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('home_settings')));
    await tester.pumpAndSettle();

    // 改名便于校验重生重置：设置列表变高后，用户卡为页首首个 ListTile
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '喵棋大师');
    await tester.tap(find.byKey(const ValueKey('edit_name_save')));
    await tester.pumpAndSettle();
    expect(find.text('喵棋大师'), findsWidgets);

    // 重生：滚动到底部按钮后二次确认初始化全部进度
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings_rebirth')),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings_rebirth')));
    await tester.pumpAndSettle();
    expect(
        find.text(
            '重生将初始化棋手信息与全部进度（名称、段位、积分、对局记录、赛事、打卡与做题进度），确定继续？'),
        findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings_avatar')),
      -100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('喵棋大师'), findsNothing);
    expect(find.text('棋手'), findsWidgets);
  });
}
