import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/app.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/engine/engine_controller.dart';
import 'package:miaogo/engine/gtp_client.dart';
import 'package:miaogo/engine/katago_engine.dart';
import 'package:miaogo/storage/pending_game_store.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/study/problem_engine.dart';
import 'package:miaogo/ui/board_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/mock_gtp_io.dart';

/// 小型题库（避免首页每日一题加载全量资产）。
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

/// 引擎已就绪的假控制器：挂载脚本化引擎，供 KataGo 选点/分析全链路走通。
class _ReadyEngineController extends EngineController {
  _ReadyEngineController(this.scripted);

  final KataGoEngine scripted;

  @override
  EngineStatus build() => EngineStatus.ready;

  @override
  KataGoEngine? get engine => scripted;

  @override
  Future<void> start() async {}
}

/// 脚本化引擎：AI 一律应手 E4，实时分析输出带 ownership 的 info 行。
KataGoEngine _scriptedEngine() {
  final io = MockGtpIo({
    'boardsize 9': ['= '],
    'kata-set-rules chinese': ['= '],
    'kata-set-rules japanese': ['= '],
    'kata-set-rules korean': ['= '],
    'komi 7.5': ['= '],
    'komi 6.5': ['= '],
    'komi 5.5': ['= '],
  });
  io.scriptPrefixes = [
    (prefix: 'set_position', lines: ['= ']),
    (prefix: 'kata-set-param', lines: ['= ']),
    (
      prefix: 'kata-search_analyze',
      lines: [
        '',
        '=',
        'info move E4 visits 456 winrate 0.5 utility 0 scoreLead 0 '
            'scoreMean 0 order 0 pv E4',
        'play E4',
        '',
      ],
    ),
    (
      prefix: 'kata-analyze',
      lines: [
        '',
        '=',
        'info move E4 visits 456 winrate 0.5 utility 0 scoreLead 0 '
            'scoreMean 0 order 0 pv E4 ownership '
            '${List.filled(81, '0.2').join(' ')}',
      ],
    ),
  ];
  return KataGoEngine(GtpClient(io));
}

Future<void> pumpToGame(WidgetTester tester) async {
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
        engineStatusProvider.overrideWith(
          () => _ReadyEngineController(_scriptedEngine()),
        ),
        // 分析走大模型（P3 双模型）：测试中同样以脚本化引擎就绪。
        danEngineStatusProvider.overrideWith(
          () => _ReadyEngineController(_scriptedEngine()),
        ),
      ],
      child: const MiaoGoApp(),
    ),
  );
  await tester.pumpAndSettle();

  // 首页「快速对弈 + 开始」→ 直接进入快速匹配设置页。
  await tester.tap(find.byKey(const ValueKey('home_quick_play_button')));
  await tester.pumpAndSettle();

  // 进入对局页的用例默认选「先手」，跳过默认「猜先」的弹窗交互，
  // 点「匹配对手」后会穿过老虎机匹配页再进入对局页。
  await tester.tap(find.text('先手'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('对弈设置页：默认段位/尺寸/规则渲染', (tester) async {
    await pumpToGame(tester);
    expect(find.text('快速匹配'), findsOneWidget);
    expect(find.text('对手段位'), findsOneWidget);
    expect(find.text('棋盘尺寸'), findsOneWidget);
    expect(find.text('对弈规则'), findsOneWidget);
    expect(find.text('下棋顺序'), findsOneWidget);
    expect(find.text('落子方式'), findsOneWidget);
    expect(find.byKey(const ValueKey('rank_option_0')), findsOneWidget);
    expect(find.text('匹配对手'), findsOneWidget);
    expect(find.text('返回首页'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('匹配：居中老虎机弹窗出现并自动进入对局', (tester) async {
    await pumpToGame(tester);
    await tester.tap(find.byKey(const ValueKey('ai_start_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    // 弹窗居中展示，滚动中显示等待文案；设置页仍在后台。
    expect(find.byKey(const ValueKey('match_dialog')), findsOneWidget);
    expect(find.text('匹配中，请稍候…'), findsOneWidget);
    expect(find.text('快速匹配'), findsOneWidget);

    // 定格展示后弹窗自动关闭并进入对局页。
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('match_dialog')), findsNothing);
    expect(find.byType(GoBoardWidget), findsOneWidget);
  });

  testWidgets('对局页渲染棋盘与控制栏，PASS 后 AI 应手', (tester) async {
    await pumpToGame(tester);
    await tester.tap(find.byKey(const ValueKey('ai_start_button')));
    await tester.pumpAndSettle();

    expect(find.byType(GoBoardWidget), findsOneWidget);
    expect(find.byKey(const ValueKey('game_undo')), findsOneWidget);
    expect(find.byKey(const ValueKey('game_pass')), findsOneWidget);
    expect(find.text('停手'), findsOneWidget);
    expect(find.byKey(const ValueKey('game_resign')), findsOneWidget);
    expect(find.text('第 0 手'), findsOneWidget);

    // 玩家 PASS → AI 应手 E4 → 手数 2
    await tester.tap(find.byKey(const ValueKey('game_pass')));
    await tester.pumpAndSettle();
    expect(find.text('第 2 手'), findsOneWidget);
  });

  testWidgets('玩家执白时开局 AI 先落子', (tester) async {
    await pumpToGame(tester);
    await tester.tap(find.text('后手'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai_start_button')));
    await tester.pumpAndSettle();
    expect(find.byType(GoBoardWidget), findsOneWidget);
    expect(find.text('第 1 手'), findsOneWidget);
  });

  testWidgets('两步落子：点选→落子按钮→确认落子', (tester) async {
    await pumpToGame(tester);
    await tester.tap(find.byKey(const ValueKey('ai_start_button')));
    await tester.pumpAndSettle();

    // 第一步：点棋盘中心选点
    final rect = tester.getRect(find.byType(GoBoardWidget));
    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('game_place')), findsOneWidget);
    expect(find.text('e5'), findsOneWidget);

    // 第二步：点击落子按钮
    await tester.tap(find.byKey(const ValueKey('game_place')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('game_place')), findsNothing);
    expect(find.text('第 2 手'), findsOneWidget);
  });

  testWidgets('两步落子：拖拽移动选中点', (tester) async {
    await pumpToGame(tester);
    await tester.tap(find.byKey(const ValueKey('ai_start_button')));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(GoBoardWidget));
    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();
    expect(find.text('e5'), findsOneWidget);

    // 选点栏出现后棋盘会缩小，重新取棋盘位置再拖拽
    final rect2 = tester.getRect(find.byType(GoBoardWidget));
    final cell = rect2.width * 0.88 / 8;
    final gesture = await tester.startGesture(rect2.center);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(rect2.center + Offset(cell * 0.5, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(rect2.center + Offset(cell, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('f5'), findsOneWidget);
  });

  testWidgets('两步落子：取消选点', (tester) async {
    await pumpToGame(tester);
    await tester.tap(find.byKey(const ValueKey('ai_start_button')));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(GoBoardWidget));
    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('game_place')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('game_sel_cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('game_place')), findsNothing);
    expect(find.text('第 0 手'), findsOneWidget);
  });

  testWidgets('点目按钮：直接终局并展示成绩面板', (tester) async {
    await pumpToGame(tester);
    await tester.tap(find.byKey(const ValueKey('ai_start_button')));
    await tester.pumpAndSettle();

    // 先走一手，点目才可用
    final rect = tester.getRect(find.byType(GoBoardWidget));
    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('game_place')));
    await tester.pumpAndSettle();
    expect(find.text('第 2 手'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('game_score')));
    await tester.pumpAndSettle();
    expect(find.text('对局结束'), findsNWidgets(2)); // 状态栏 + 成绩面板标题
    expect(find.text('再来一局'), findsOneWidget);
  });

  testWidgets('实时分析：按钮开启热力图，再点关闭', (tester) async {
    await pumpToGame(tester);
    await tester.tap(find.byKey(const ValueKey('ai_start_button')));
    await tester.pumpAndSettle();

    GoBoardWidget board() =>
        tester.widget<GoBoardWidget>(find.byType(GoBoardWidget));
    expect(board().influence, isNull);

    // 开启（引擎就绪 → 实时分析，热力图来自 ownership）
    await tester.tap(find.byKey(const ValueKey('game_influence')));
    await tester.pumpAndSettle();
    expect(board().influence, isNotNull);

    // 再点一次关闭
    await tester.tap(find.byKey(const ValueKey('game_influence')));
    await tester.pumpAndSettle();
    expect(board().influence, isNull);
  });

  testWidgets('保存对局：保存后回首页，快速对弈变「继续」并可续弈', (tester) async {
    await pumpToGame(tester);
    await tester.tap(find.byKey(const ValueKey('ai_start_button')));
    await tester.pumpAndSettle();
    expect(find.byType(GoBoardWidget), findsOneWidget);

    // 玩家落一手 → AI 应手，共 2 手
    final rect = tester.getRect(find.byType(GoBoardWidget));
    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('game_place')));
    await tester.pumpAndSettle();
    expect(find.text('第 2 手'), findsOneWidget);

    // 保存（弹确认后中断并回首页）
    await tester.tap(find.byKey(const ValueKey('game_save')));
    await tester.pumpAndSettle();
    expect(find.text('保存对局'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('game_save_confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(GoBoardWidget), findsNothing);
    expect(find.text('快速对弈'), findsOneWidget);

    // 快速对弈按钮变「继续」
    expect(find.text('继续'), findsOneWidget);

    // 胜率曲线数据自开局常开采集：快照里已带 (手数, 黑胜率) 历史。
    final homeCtx = tester.element(
        find.byKey(const ValueKey('home_quick_play_button')));
    final pending =
        ProviderScope.containerOf(homeCtx).read(pendingGameStoreProvider);
    expect(pending, hasLength(1));
    expect(pending.first.winrateHistory, isNotEmpty);

    // 直接续弈：跳设置进棋盘，恢复到原手数
    await tester.tap(find.byKey(const ValueKey('home_quick_play_button')));
    await tester.pumpAndSettle();
    expect(find.byType(GoBoardWidget), findsOneWidget);
    expect(find.text('第 2 手'), findsOneWidget);

    // 冲刷首页提示 SnackBar 计时器，避免测试残留定时器。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('连按两次返回：弹放弃确认，确认弃局并回首页（按钮恢复「开始」）',
      (tester) async {
    await pumpToGame(tester);
    await tester.tap(find.byKey(const ValueKey('ai_start_button')));
    await tester.pumpAndSettle();
    expect(find.byType(GoBoardWidget), findsOneWidget);

    final rect = tester.getRect(find.byType(GoBoardWidget));
    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('game_place')));
    await tester.pumpAndSettle();
    expect(find.text('第 2 手'), findsOneWidget);

    // 首次返回：仅提示，不弹窗
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('放弃对局'), findsNothing);

    // 紧随第二次返回：弹放弃确认
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放弃对局'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('abandon_confirm')));
    await tester.pumpAndSettle();

    // 回到首页
    expect(find.byType(GoBoardWidget), findsNothing);
    expect(find.text('快速对弈'), findsOneWidget);

    // 弃局即终止：待续快照已清除，快速对弈按钮恢复「开始」
    expect(find.text('开始'), findsOneWidget);

    // 冲刷返回提示 SnackBar 计时器。
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('双击落子：同一点再次点击落子，不同点仅换选点', (tester) async {
    await pumpToGame(tester);
    await tester.tap(find.text('双击'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai_start_button')));
    await tester.pumpAndSettle();
    expect(find.byType(GoBoardWidget), findsOneWidget);

    final rect = tester.getRect(find.byType(GoBoardWidget));
    // 第一次点选：只显示选中，不出现确认栏，也未落子。
    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('game_place')), findsNothing);
    expect(find.text('第 0 手'), findsOneWidget);

    // 点另一交叉点：仅切换选点，仍不落子。
    final cell = rect.width * 0.88 / 8;
    await tester.tapAt(rect.center + Offset(cell, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('game_place')), findsNothing);
    expect(find.text('第 0 手'), findsOneWidget);

    // 再次点击同一交叉点：直接落子，随后 AI 应手。
    await tester.tapAt(rect.center + Offset(cell, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('game_place')), findsNothing);
    expect(find.text('第 2 手'), findsOneWidget);
  });

  testWidgets('顶部卡片：轮到玩家显示思考中，AI 对手不再显示 AI', (tester) async {
    await pumpToGame(tester);
    await tester.tap(find.byKey(const ValueKey('ai_start_button')));
    await tester.pumpAndSettle();
    expect(find.byType(GoBoardWidget), findsOneWidget);
    // 玩家先手：玩家卡旁出现「思考中」tag。
    expect(find.text('思考中'), findsOneWidget);
    // 玩家卡显示档案姓名（默认「棋手」），不再硬编码「玩家」。
    expect(find.text('棋手'), findsOneWidget);
    expect(find.text('玩家'), findsNothing);
    // 硬编码「AI」不再作为对手名展示。
    expect(find.text('AI'), findsNothing);
  });

  testWidgets('实时分析：底部「取消」可关闭分析显示', (tester) async {
    await pumpToGame(tester);
    await tester.tap(find.byKey(const ValueKey('ai_start_button')));
    await tester.pumpAndSettle();

    GoBoardWidget board() =>
        tester.widget<GoBoardWidget>(find.byType(GoBoardWidget));
    expect(find.byKey(const ValueKey('game_analysis_cancel')), findsNothing);

    // 开启实时分析：热力图显示 + 底部出现「取消」。
    await tester.tap(find.byKey(const ValueKey('game_influence')));
    await tester.pumpAndSettle();
    expect(board().influence, isNotNull);
    expect(find.byKey(const ValueKey('game_analysis_cancel')), findsOneWidget);

    // 底部「取消」关闭分析：热力图消失、按钮恢复。
    await tester.tap(find.byKey(const ValueKey('game_analysis_cancel')));
    await tester.pumpAndSettle();
    expect(board().influence, isNull);
    expect(find.byKey(const ValueKey('game_analysis_cancel')), findsNothing);

    // 冲刷分析会话退出的读线计时器。
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
  });

  testWidgets('胜率曲线：按钮开启面板并可关闭', (tester) async {
    await pumpToGame(tester);
    await tester.tap(find.byKey(const ValueKey('ai_start_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('game_winrate')), findsOneWidget);
    expect(find.byKey(const ValueKey('winrate_panel')), findsNothing);

    // 开启：面板出现在棋盘下方。
    await tester.tap(find.byKey(const ValueKey('game_winrate')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('winrate_panel')), findsOneWidget);

    // 再点关闭：面板消失。
    await tester.tap(find.byKey(const ValueKey('game_winrate')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('winrate_panel')), findsNothing);

    // 冲刷采样评估的读线计时器。
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
  });
}
