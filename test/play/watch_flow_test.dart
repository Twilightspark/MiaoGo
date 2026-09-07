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
  testWidgets('首页观赛入口 → 休闲观赛设置页渲染', (tester) async {
    await pumpApp(tester);

    expect(find.byKey(const ValueKey('home_watch_button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home_watch_button')));
    await tester.pumpAndSettle();

    expect(find.text('休闲观赛'), findsOneWidget);
    expect(find.text('棋手等级'), findsOneWidget);
    expect(find.text('棋盘尺寸'), findsOneWidget);
    expect(find.text('对弈规则'), findsOneWidget);
    expect(find.byKey(const ValueKey('watch_rank_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('watch_start_button')), findsOneWidget);
    expect(find.text('开始观赛'), findsOneWidget);
    expect(find.byKey(const ValueKey('watch_back_home')), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('开始观赛：AI 互弈自动走子并终局，退出不保存返回首页', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('home_watch_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('watch_start_button')));
    await tester.pumpAndSettle();

    // 观赛页：顶栏仅分析/退出，棋盘与状态栏就绪。
    expect(find.byType(GoBoardWidget), findsOneWidget);
    expect(find.byKey(const ValueKey('watch_analysis')), findsOneWidget);
    expect(find.byKey(const ValueKey('watch_exit')), findsOneWidget);
    expect(find.text('第 0 手'), findsOneWidget);

    // 每手展示间隔 10 秒：黑(第1手) / 白停一手 / 黑停一手 → 终局。
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 11));
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

    // 未保存：个人棋谱为空。
    final homeCtx = tester.element(
        find.byKey(const ValueKey('home_watch_button')));
    final records =
        ProviderScope.containerOf(homeCtx).read(recordStoreProvider);
    expect(records, isEmpty);
  });

  testWidgets('终局「保存到棋谱」写入个人棋谱并回首页', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('home_watch_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('watch_start_button')));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 11));
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
}
