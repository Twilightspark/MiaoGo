import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/app.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/study/problem_engine.dart';
import 'package:miaogo/ui/board_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 小型题库：10 题（每轮抽 5 题，保证可继续抽下一轮）且加载迅速。
Future<ProblemLibrary> _fakeLibrary() async {
  const sgf = '(;SZ[9]AW[ee][ff]AB[ed][fe]C[Black to play];B[dd]C[Correct 捕获两子])';
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

/// 每日打卡页棋盘落子：9 路整盘视图，按交叉点坐标点击（确认落子模式）。
Future<void> _tapBoardPoint(WidgetTester tester, int row, int col) async {
  final rect = tester.getRect(find.byType(GoBoardWidget));
  final margin = rect.width * 0.06;
  final cell = (rect.width - rect.width * 0.12) / 8; // 9 路 → 8 格
  await tester.tapAt(Offset(
    rect.left + margin + col * cell,
    rect.top + margin + row * cell,
  ));
  await tester.pumpAndSettle();
}

/// 确认落子：选点后点「落子」。
Future<void> _placeStone(WidgetTester tester, int row, int col) async {
  await _tapBoardPoint(tester, row, col);
  await tester.tap(find.text('落子'));
  await tester.pumpAndSettle();
}

/// 取进度卡中题号圆点的背景色。
Color? _dotColor(WidgetTester tester, String number) {
  final container = tester.widget<Container>(
    find
        .ancestor(of: find.text(number), matching: find.byType(Container))
        .first,
  );
  return (container.decoration as BoxDecoration?)?.color;
}

/// 重做按钮是否可点击。
bool _redoEnabled(WidgetTester tester) {
  final button = tester.widget<OutlinedButton>(
    find.widgetWithText(OutlinedButton, '重做'),
  );
  return button.onPressed != null;
}

/// 看正解按钮是否可点击。
bool _revealEnabled(WidgetTester tester) {
  final button = tester.widget<OutlinedButton>(
    find.widgetWithText(OutlinedButton, '看正解'),
  );
  return button.onPressed != null;
}

/// 用满 3 次做题机会（连下三手错棋）。
Future<void> _exhaustAttempts(WidgetTester tester) async {
  await _placeStone(tester, 0, 0);
  await _placeStone(tester, 0, 1);
  await _placeStone(tester, 0, 2);
}

/// 在 5 道题上各用满三次错误机会（使本轮全部判错）。
Future<void> _wrongAllFive(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await _exhaustAttempts(tester);
    if (i < 4) {
      await tester.tap(find.text('下一题'));
      await tester.pumpAndSettle();
    }
  }
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

    // 每日一题 / 快速对弈 / 赛事生涯 / 休闲观赛
    expect(find.text('每日一题'), findsOneWidget);
    expect(find.text('做题'), findsOneWidget);
    expect(find.text('快速对弈'), findsOneWidget);
    expect(find.text('赛事生涯'), findsOneWidget);
    expect(find.text('休闲观赛'), findsOneWidget);
    expect(find.byKey(const ValueKey('home_watch_button')), findsOneWidget);

    // 快捷入口
    for (final label in ['入门', '定式', '题库', '棋谱']) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('点击首页入口跳转对应页面', (tester) async {
    await pumpApp(tester);

    // 快捷入口「入门」→ 基础规则新手指引页
    await tester.tap(find.byKey(const ValueKey('home_quick_entry_入门')));
    await tester.pumpAndSettle();
    expect(find.text('基础规则新手指引'), findsOneWidget);
    expect(find.byKey(const ValueKey('guide_step_index')), findsOneWidget);

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

  testWidgets('每日一题「做题」进入每日打卡页', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('home_daily_start')));
    await tester.pumpAndSettle();
    expect(find.text('每日打卡'), findsOneWidget);
    expect(find.text('今日做题进度'), findsOneWidget);
    expect(find.text('0 / 5'), findsOneWidget);
    // 提示卡：执子方与总步数。
    expect(find.text('轮到 黑方落子'), findsOneWidget);
    expect(find.text('共 1 步'), findsOneWidget);
  });

  testWidgets('每日打卡：看正解需用满做题机会', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('home_daily_start')));
    await tester.pumpAndSettle();

    // 一排四个操作按钮；未用满机会时看正解不可点击。
    for (final label in ['上一题', '下一题', '看正解', '重做']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(_revealEnabled(tester), isFalse);

    // 下错两手：机会未用满，看正解仍不可点击。
    await _placeStone(tester, 0, 0);
    await _placeStone(tester, 0, 1);
    expect(_revealEnabled(tester), isFalse);

    // 第三手错棋用满机会 → 看正解可点击。
    await _placeStone(tester, 0, 2);
    expect(_revealEnabled(tester), isTrue);

    // 看正解 → 隐藏四个按钮，显示「下一步」。
    await tester.tap(find.text('看正解'));
    await tester.pumpAndSettle();
    expect(find.text('下一步'), findsOneWidget);
    for (final label in ['上一题', '下一题', '看正解', '重做']) {
      expect(find.text(label), findsNothing);
    }

    // 单步正解：点下一步后演示完成，操作按钮恢复，重做不可点击。
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('下一步'), findsNothing);
    expect(find.text('上一题'), findsOneWidget);
    expect(_redoEnabled(tester), isFalse);
  });

  testWidgets('每日打卡：确认落子时双击不落子', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('home_daily_start')));
    await tester.pumpAndSettle();

    // 连续两次点同一交叉点（模拟双击）：仅选点，不落子。
    await _tapBoardPoint(tester, 3, 3);
    await _tapBoardPoint(tester, 3, 3);

    // 仍处于未落子状态：题号无底色，且出现选点确认栏。
    expect(_dotColor(tester, '1'), Colors.transparent);
    expect(find.text('落子'), findsOneWidget);
  });

  testWidgets('每日打卡：用满三次机会判错后题号浅红且重做不可点击', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('home_daily_start')));
    await tester.pumpAndSettle();

    final red = const Color(0xFFB3261E).withValues(alpha: 0.14);
    // 未做：题号无底色、重做可点击。
    expect(_dotColor(tester, '1'), Colors.transparent);
    expect(_redoEnabled(tester), isTrue);

    // 错误一次、两次均不判错。
    await _placeStone(tester, 0, 0);
    expect(_dotColor(tester, '1'), Colors.transparent);
    expect(_redoEnabled(tester), isTrue);
    await _placeStone(tester, 0, 1);
    expect(_dotColor(tester, '1'), Colors.transparent);
    expect(_redoEnabled(tester), isTrue);

    // 用满三次机会 → 判错（浅红）且重做不可点击。
    await _placeStone(tester, 0, 2);
    expect(_dotColor(tester, '1'), red);
    expect(_redoEnabled(tester), isFalse);
  });

  testWidgets('每日打卡：做对后题号浅绿且重做不可点击', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('home_daily_start')));
    await tester.pumpAndSettle();

    // dd=(3,3) 为正解。
    await _placeStone(tester, 3, 3);

    expect(_dotColor(tester, '1'), GoColors.pineContainer);
    expect(_redoEnabled(tester), isFalse);
  });

  testWidgets('每日打卡：看正解后题号标记为做错', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('home_daily_start')));
    await tester.pumpAndSettle();

    // 用满机会后看正解。
    await _exhaustAttempts(tester);
    await tester.tap(find.text('看正解'));
    await tester.pumpAndSettle();

    final red = const Color(0xFFB3261E).withValues(alpha: 0.14);
    expect(_dotColor(tester, '1'), red);

    // 演示完成后重做不可点击。
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(_redoEnabled(tester), isFalse);
  });

  testWidgets('每日打卡：全部做完弹打卡完成，回首页变继续并可抽新题', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('home_daily_start')));
    await tester.pumpAndSettle();

    await _wrongAllFive(tester);
    expect(find.text('今日打卡完成'), findsOneWidget);

    await tester.tap(find.text('退出'));
    await tester.pumpAndSettle();

    // 回首页：按钮变「继续」。
    expect(find.text('每日一题'), findsOneWidget);
    expect(find.text('继续'), findsOneWidget);

    // 继续 → 重新抽 5 题（新一轮从 0/5 开始）。
    await tester.tap(find.byKey(const ValueKey('home_daily_start')));
    await tester.pumpAndSettle();
    expect(find.text('每日打卡'), findsOneWidget);
    expect(find.text('0 / 5'), findsOneWidget);

    // 完成补充一轮 → 「补充功课完成」。
    await _wrongAllFive(tester);
    expect(find.text('补充功课完成'), findsOneWidget);
  });

  testWidgets('每日打卡：未做完返回再进入恢复进度', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('home_daily_start')));
    await tester.pumpAndSettle();

    final red = const Color(0xFFB3261E).withValues(alpha: 0.14);
    await _exhaustAttempts(tester); // 第 1 题用满三次判错。
    expect(_dotColor(tester, '1'), red);
    expect(find.text('1 / 5'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home_daily_start')));
    await tester.pumpAndSettle();

    // 恢复到上次状态：题 1 仍判错，进度 1/5。
    expect(_dotColor(tester, '1'), red);
    expect(find.text('1 / 5'), findsOneWidget);
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
