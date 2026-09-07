import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/storage/record_store.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/ui/record/record_home_page.dart';
import 'package:miaogo/ui/record/review_page.dart';
import 'package:miaogo/ui/record/sgf_import.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 假记录仓库：跳过 path_provider 落盘（widget 测试中平台通道不可用）。
class _FakeRecordStore extends RecordStore {
  _FakeRecordStore(this.records);

  final List<GameRecord> records;

  @override
  List<GameRecord> build() => records;

  @override
  Future<String?> sgfContentOf(GameRecord r) async => r.sgfContent;
}

const _watchSgf = '(;GM[1]FF[4]SZ[9]RU[chinese]KM[7.5]PB[喵喵]PW[旺旺]'
    'RE[B+2.5];B[dd];W[ee];B[ff])';
const _importSgf = '(;GM[1]SZ[19]RU[Chinese]KM[7.5]PB[AlphaGo]PW[Lee Sedol]'
    'DT[2016-03-09]RE[W+R];B[pd];W[dd];B[dp];W[pp])';

GameRecord _watchSeed() => GameRecord(
      id: 'w1',
      date: DateTime(2026, 8, 1),
      opponentName: '喵喵 对 旺旺',
      opponentRank: 8,
      result: GameResult.win,
      boardSize: 9,
      rule: GoRule.chinese,
      komi: 7.5,
      sgfPath: '',
      source: GameSource.watch,
      moveCount: 3,
      blackName: '喵喵',
      whiteName: '旺旺',
      sgfContent: _watchSgf,
    );

GameRecord _importSeed() => GameRecord(
      id: 'i1',
      date: DateTime(2026, 8, 2),
      opponentName: 'AlphaGo 对 Lee Sedol',
      opponentRank: 0,
      result: GameResult.loss,
      boardSize: 19,
      rule: GoRule.chinese,
      komi: 7.5,
      sgfPath: '',
      source: GameSource.imported,
      moveCount: 4,
      blackName: 'AlphaGo',
      whiteName: 'Lee Sedol',
      sgfContent: _importSgf,
    );

GameRecord _hiddenAiSeed() => GameRecord(
      id: 'a1',
      date: DateTime(2026, 7, 1),
      opponentName: 'AI · 10级',
      opponentRank: 8,
      result: GameResult.win,
      boardSize: 9,
      rule: GoRule.chinese,
      komi: 7.5,
      sgfPath: '',
      source: GameSource.ai,
      moveCount: 3,
      sgfContent:
          '(;GM[1]FF[4]SZ[9]RU[chinese]KM[7.5]PB[棋手]PW[AI]RE[B+1.5]'
          ';B[dd];W[ee];B[ff])',
    );

GameRecord _hiddenCareerSeed() => GameRecord(
      id: 'c1',
      date: DateTime(2026, 7, 2),
      opponentName: '生涯对手',
      opponentRank: 18,
      result: GameResult.loss,
      boardSize: 13,
      rule: GoRule.korean,
      komi: 6.5,
      sgfPath: '',
      source: GameSource.career,
      moveCount: 2,
      sgfContent:
          '(;GM[1]SZ[13]RU[korean]KM[6.5]PB[对手]PW[棋手]RE[W+R]'
          ';B[dd];W[ee])',
    );

void main() {
  Future<List<Override>> baseOverrides() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return [sharedPreferencesProvider.overrideWithValue(prefs)];
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    List<Override> overrides = const [],
    List<GameRecord>? seeds,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final list = [...overrides];
    if (seeds != null) {
      list.add(recordStoreProvider.overrideWith(
          () => _FakeRecordStore(List.of(seeds))));
    }
    await tester.pumpWidget(ProviderScope(
      overrides: list,
      child: const MaterialApp(home: RecordHomePage()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('复盘页渲染：逐步跳转 / 手数 / 试下点目 / 双停手终局', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final game = Sgf.parse('(;GM[1]SZ[9]RU[chinese]KM[7.5]PB[黑]PW[白]'
        ';B[dd];W[ee];B[ff];W[gg])');

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: ReviewPage(game: game)),
    ));
    await tester.pump(); // 处理 post-frame load
    await tester.pump();

    // 初始：开局手位，棋盘空；回看模式无「点目」。
    expect(find.text('开局'), findsOneWidget);
    expect(find.textContaining('共 4 手'), findsOneWidget);
    expect(find.byKey(const ValueKey('review_score')), findsNothing);
    expect(find.byKey(const ValueKey('review_try')), findsOneWidget);
    expect(find.byKey(const ValueKey('review_exit')), findsOneWidget);
    // 顶栏无返回箭头/标题；胜率曲线按钮在（引擎未就绪时禁用）。
    final winrateBtn =
        tester.widget<IconButton>(find.byKey(const ValueKey('review_winrate')));
    expect(winrateBtn.onPressed, isNull);
    expect(find.byIcon(Icons.show_chart), findsOneWidget);

    // 下一手：棋盘出现黑子 dd。
    await tester.tap(find.byKey(const ValueKey('review_next')));
    await tester.pump();
    expect(find.text('第 1 手'), findsOneWidget);

    // 跳到末手。
    await tester.tap(find.byKey(const ValueKey('review_last')));
    await tester.pump();
    expect(find.text('第 4 手'), findsOneWidget);

    // 首手。
    await tester.tap(find.byKey(const ValueKey('review_first')));
    await tester.pump();
    expect(find.text('开局'), findsOneWidget);

    // 跳到末手后进入试下：导航键替换为试下工具。
    await tester.tap(find.byKey(const ValueKey('review_last')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('review_try')));
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review_first')), findsNothing);
    expect(find.byKey(const ValueKey('review_undo')), findsOneWidget);
    expect(find.byKey(const ValueKey('review_pass')), findsOneWidget);

    // 点目：弹出结果对话框；关闭后仍在试下。
    await tester.tap(find.byKey(const ValueKey('review_score')));
    await tester.pumpAndSettle();
    expect(find.text('当前局面点目'), findsOneWidget);
    expect(find.textContaining('规则'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review_undo')), findsOneWidget);

    // 连续两次停手 → 试下终局自动弹点目。
    await tester.tap(find.byKey(const ValueKey('review_pass')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('review_pass')));
    await tester.pumpAndSettle();
    expect(find.text('当前局面点目'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    // 返回：恢复进入试下前的历史末手（回看态）。
    await tester.tap(find.byKey(const ValueKey('review_back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review_first')), findsOneWidget);
    expect(find.text('第 4 手'), findsOneWidget);
  });

  testWidgets('棋谱页仅展示观赛/导入棋谱，点击进入回看', (tester) async {
    await pumpPage(tester,
        seeds: [
          _watchSeed(),
          _importSeed(),
          _hiddenAiSeed(),
          _hiddenCareerSeed(),
        ]);

    // 观赛与导入条目展示。
    expect(find.text('喵喵 对 旺旺'), findsOneWidget);
    expect(find.text('AlphaGo 对 Lee Sedol'), findsOneWidget);
    // 结果按棋盘视角：黑胜（观赛）/ 白胜（导入 W+R）。
    expect(find.text('黑胜'), findsOneWidget);
    expect(find.text('白胜'), findsOneWidget);

    // 个人对局不出现在本页。
    expect(find.text('AI · 10级'), findsNothing);
    expect(find.text('生涯对手'), findsNothing);

    // 点击观赛条目进入回看页。
    await tester.tap(find.text('喵喵 对 旺旺'));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewPage), findsOneWidget);
    expect(find.byKey(const ValueKey('review_next')), findsOneWidget);
  });

  testWidgets('导入 SGF：解析成功保存列表并提示，不自动跳转', (tester) async {
    final overrides = await baseOverrides();
    overrides.add(sgfPickerProvider.overrideWithValue(() async => _importSgf));
    await pumpPage(tester, overrides: overrides);

    // 初始为空态。
    expect(find.textContaining('暂无棋谱'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('record_import')));
    await tester.pump();
    // 让真实事件循环完成记录落库（path_provider 无宿主实现被 store 容错）。
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pumpAndSettle();

    expect(find.text('棋谱已导入'), findsOneWidget);
    expect(find.text('AlphaGo 对 Lee Sedol'), findsOneWidget);
    expect(find.textContaining('导入 ·'), findsOneWidget);
    // 仅保存不跳转回看。
    expect(find.byType(ReviewPage), findsNothing);
  });

  testWidgets('导入无效 SGF：提示失败且不入列表', (tester) async {
    final overrides = await baseOverrides();
    overrides.add(
        sgfPickerProvider.overrideWithValue(() async => '(;GM[1]'));
    await pumpPage(tester, overrides: overrides);

    await tester.tap(find.byKey(const ValueKey('record_import')));
    await tester.pumpAndSettle();

    expect(find.text('SGF 文件解析失败'), findsOneWidget);
    expect(find.textContaining('暂无棋谱'), findsOneWidget);
    expect(find.byType(ReviewPage), findsNothing);
  });
}
