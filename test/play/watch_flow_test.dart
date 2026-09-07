import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/app.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/engine/engine_controller.dart';
import 'package:miaogo/engine/gtp_client.dart';
import 'package:miaogo/engine/katago_engine.dart';
import 'package:miaogo/storage/record_store.dart';
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

/// 引擎已就绪的假控制器：挂载脚本化引擎（应手一律 E4）。
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

KataGoEngine _scriptedEngine() {
  final io = MockGtpIo({
    'boardsize 9': ['= '],
    'kata-set-rules chinese': ['= '],
    'kata-set-rules japanese': ['= '],
    'kata-set-rules korean': ['= '],
    'komi 7.5': ['= '],
    'komi 6.5': ['= '],
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
  ];
  return KataGoEngine(GtpClient(io));
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
        engineStatusProvider.overrideWith(
          () => _ReadyEngineController(_scriptedEngine()),
        ),
        danEngineStatusProvider.overrideWith(
          () => _ReadyEngineController(_scriptedEngine()),
        ),
      ],
      child: const MiaoGoApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  /// 从首页进入观赛设置页；pace 可选「立即/3秒/5秒/8秒/10秒/15秒」，
  /// 测试默认不点选落子时间（默认「立即」），需要慢节奏时再点选。
  Future<void> goSetup(WidgetTester tester, {String? pace}) async {
    await tester.tap(find.byKey(const ValueKey('home_watch_button')));
    await tester.pumpAndSettle();
    if (pace != null && pace != '立即') {
      await tester.tap(find.text(pace));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('首页观赛入口 → 休闲观赛设置页渲染', (tester) async {
    await pumpApp(tester);

    expect(find.byKey(const ValueKey('home_watch_button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home_watch_button')));
    await tester.pumpAndSettle();

    expect(find.text('休闲观赛'), findsOneWidget);
    expect(find.text('棋手等级'), findsOneWidget);
    expect(find.text('棋盘尺寸'), findsOneWidget);
    expect(find.text('对弈规则'), findsOneWidget);
    expect(find.text('棋手落子时间'), findsOneWidget);
    expect(find.byKey(const ValueKey('watch_rank_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('watch_start_button')), findsOneWidget);
    expect(find.text('开始观赛'), findsOneWidget);
    expect(find.byKey(const ValueKey('watch_back_home')), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('默认配置（9段·立即）：开始观赛自动互弈快速终局，退出不保存回首页',
      (tester) async {
    await pumpApp(tester);
    // 默认不调整任何配置，直接开始观赛。
    await tester.tap(find.byKey(const ValueKey('home_watch_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('watch_start_button')));
    await tester.pumpAndSettle();

    // 观赛页：顶栏仅分析/退出，棋盘与状态栏就绪。
    expect(find.byType(GoBoardWidget), findsOneWidget);
    expect(find.byKey(const ValueKey('watch_analysis')), findsOneWidget);
    expect(find.byKey(const ValueKey('watch_exit')), findsOneWidget);

    // 默认「立即」落子：AI 自动互弈快速推进并终局。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.pumpAndSettle();

    // 终局弹窗：胜负信息 + 保存/退出。
    expect(find.text('对局结束'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('watch_result_save')), findsOneWidget);
    expect(find.byKey(const ValueKey('watch_result_exit')), findsOneWidget);

    // 退出（不保存）→ 回到首页。
    await tester.tap(find.byKey(const ValueKey('watch_result_exit')));
    await tester.pumpAndSettle();
    expect(find.byType(GoBoardWidget), findsNothing);
    expect(find.byKey(const ValueKey('home_watch_button')), findsOneWidget);

    // 未保存：棋谱库为空。
    final homeCtx = tester.element(
        find.byKey(const ValueKey('home_watch_button')));
    final records =
        ProviderScope.containerOf(homeCtx).read(recordStoreProvider);
    expect(records, isEmpty);
  });

  testWidgets('选 3 秒落子节奏：AI 互弈自动走子并终局，保存到棋谱回首页',
      (tester) async {
    await pumpApp(tester);
    await goSetup(tester, pace: '3秒');
    await tester.tap(find.byKey(const ValueKey('watch_start_button')));
    await tester.pumpAndSettle();
    expect(find.text('第 0 手'), findsOneWidget);

    // 每手间隔 3 秒：黑(第1手) / 白停一手 / 黑停一手 → 终局。
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('watch_result_save')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('watch_result_save')));
    await tester.pumpAndSettle();

    // 先返回首页；保存为异步落库。
    expect(find.byKey(const ValueKey('home_watch_button')), findsOneWidget);
    expect(find.byType(GoBoardWidget), findsNothing);

    // 让真实事件循环完成棋谱写入（测试环境 path_provider 无宿主实现）。
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    await tester.pumpAndSettle();

    final homeCtx = tester.element(
        find.byKey(const ValueKey('home_watch_button')));
    final records =
        ProviderScope.containerOf(homeCtx).read(recordStoreProvider);
    expect(records, hasLength(1));
    expect(records.first.source, GameSource.watch);
    expect(records.first.moveCount, greaterThan(0));

    // 冲刷首页保存提示 SnackBar 计时器。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('连按两次返回：首次仅提示，再次返回弹提前终止确认', (tester) async {
    await pumpApp(tester);
    await goSetup(tester, pace: '3秒');
    await tester.tap(find.byKey(const ValueKey('watch_start_button')));
    await tester.pumpAndSettle();
    expect(find.byType(GoBoardWidget), findsOneWidget);

    // 首次返回：仅提示，不弹窗。
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('提前终止观赛'), findsNothing);
    expect(find.text('再按一次返回可提前终止观赛并回到首页'), findsOneWidget);

    // 紧随第二次返回：弹提前终止确认。
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('提前终止观赛'), findsOneWidget);

    // 取消：留在观赛页。
    await tester.tap(find.byKey(const ValueKey('watch_abort_cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(GoBoardWidget), findsOneWidget);
    expect(find.text('提前终止观赛'), findsNothing);

    // 顶栏「退出」直接回首页（不保存）。
    await tester.tap(find.byKey(const ValueKey('watch_exit')));
    await tester.pumpAndSettle();
    expect(find.byType(GoBoardWidget), findsNothing);
    expect(find.byKey(const ValueKey('home_watch_button')), findsOneWidget);

    // 冲刷提示 SnackBar 与在途自动行棋计时器。
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
  });

  testWidgets('连按两次返回：确认提前终止退出回首页（不保存）', (tester) async {
    await pumpApp(tester);
    await goSetup(tester, pace: '3秒');
    await tester.tap(find.byKey(const ValueKey('watch_start_button')));
    await tester.pumpAndSettle();
    expect(find.byType(GoBoardWidget), findsOneWidget);

    // 首次返回：仅提示；第二次返回：弹确认。
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('提前终止观赛'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('提前终止观赛'), findsOneWidget);

    // 确认退出 → 回首页（不保存）。
    await tester.tap(find.byKey(const ValueKey('watch_abort_confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(GoBoardWidget), findsNothing);
    expect(find.byKey(const ValueKey('home_watch_button')), findsOneWidget);

    // 冲刷提示 SnackBar 与在途自动行棋计时器。
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
  });
}
