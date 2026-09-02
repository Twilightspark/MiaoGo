import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/app.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/engine/engine_controller.dart';
import 'package:miaogo/engine/gtp_client.dart';
import 'package:miaogo/engine/katago_engine.dart';
import 'package:miaogo/game/game_controller.dart';
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

  // 首页「快速对弈 + 开始」→ 直接进入人机对弈设置页。
  await tester.tap(find.byKey(const ValueKey('home_quick_play_button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('对弈设置页：默认段位/尺寸/规则渲染', (tester) async {
    await pumpToGame(tester);
    expect(find.text('对手段位'), findsOneWidget);
    expect(find.text('棋盘尺寸'), findsOneWidget);
    expect(find.text('对弈规则'), findsOneWidget);
    expect(find.text('执子'), findsOneWidget);
    expect(find.byKey(const ValueKey('rank_option_0')), findsOneWidget);
    expect(find.text('开始对弈'), findsOneWidget);
  });

  testWidgets('对局页渲染棋盘与控制栏，PASS 后 AI 应手', (tester) async {
    await pumpToGame(tester);
    await tester.tap(find.byKey(const ValueKey('ai_start_button')));
    await tester.pumpAndSettle();

    expect(find.byType(GoBoardWidget), findsOneWidget);
    expect(find.byKey(const ValueKey('game_undo')), findsOneWidget);
    expect(find.byKey(const ValueKey('game_pass')), findsOneWidget);
    expect(find.byKey(const ValueKey('game_resign')), findsOneWidget);
    expect(find.text('第 0 手'), findsOneWidget);

    // 玩家 PASS → AI 应手 E4 → 手数 2
    await tester.tap(find.byKey(const ValueKey('game_pass')));
    await tester.pumpAndSettle();
    expect(find.text('第 2 手'), findsOneWidget);
  });

  testWidgets('玩家执白时开局 AI 先落子', (tester) async {
    await pumpToGame(tester);
    await tester.tap(find.text('后手（执白）'));
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
    expect(find.textContaining('已选'), findsOneWidget);

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
    expect(find.textContaining('已选 e5'), findsOneWidget);

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
    expect(find.textContaining('已选 f5'), findsOneWidget);
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

  testWidgets('对局页：切换规则弹窗可选择并生效', (tester) async {
    await pumpToGame(tester);
    await tester.tap(find.byKey(const ValueKey('ai_start_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('game_rule')));
    await tester.pumpAndSettle();
    expect(find.text('切换规则'), findsOneWidget);
    expect(find.textContaining('中国'), findsOneWidget);
    expect(find.textContaining('韩国'), findsOneWidget);
    expect(find.textContaining('日本'), findsOneWidget);

    await tester.tap(find.textContaining('韩国'));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(GoBoardWidget));
    final rule = ProviderScope.containerOf(context)
        .read(gameControllerProvider)
        .rule;
    expect(rule.name, 'korean');
  });
}
