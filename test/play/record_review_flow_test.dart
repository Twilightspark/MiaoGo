import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/storage/record_store.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/ui/record/famous_games.dart';
import 'package:miaogo/ui/record/record_home_page.dart';
import 'package:miaogo/ui/record/review_page.dart';
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

GameRecord _seedRecord() => GameRecord(
      id: 'r1',
      date: DateTime(2026, 8, 1),
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

void main() {
  Future<List<Override>> baseOverrides() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return [sharedPreferencesProvider.overrideWithValue(prefs)];
  }

  testWidgets('复盘页渲染：逐步跳转 / 手数 / 点目对话框', (tester) async {
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

    // 初始：开局手位，棋盘空。
    expect(find.text('开局'), findsOneWidget);
    expect(find.textContaining('共 4 手'), findsOneWidget);

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

    // 点目：弹出结果对话框。
    await tester.tap(find.byKey(const ValueKey('review_last')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('review_score')));
    await tester.pumpAndSettle();
    expect(find.text('当前局面点目'), findsOneWidget);
    expect(find.textContaining('规则'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  });

  testWidgets('个人棋谱点击进入复盘', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final overrides = await baseOverrides();
    overrides.add(recordStoreProvider.overrideWith(
        () => _FakeRecordStore([_seedRecord()])));

    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: RecordHomePage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('AI · 10级'), findsOneWidget);
    await tester.tap(find.text('AI · 10级'));
    await tester.pumpAndSettle();

    // 复盘页出现。
    expect(find.byType(ReviewPage), findsOneWidget);
    expect(find.byKey(const ValueKey('review_next')), findsOneWidget);
  });

  testWidgets('历史名谱 Tab 渲染内置名局', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final overrides = await baseOverrides();
    // 用内嵌数据替代资产加载（真实资产由 assets_validation_test 覆盖）。
    overrides.add(famousGamesProvider.overrideWith((ref) async => [
          FamousGame(
            info: kFamousGames.first,
            game: Sgf.parse('(;GM[1]SZ[19]PB[AlphaGo]PW[Lee Sedol]'
                'DT[2016]RE[B+R];B[dd];W[ee];B[ff])'),
          ),
        ]));

    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: RecordHomePage()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('历史名谱'));
    await tester.pumpAndSettle();

    // 内置名谱条目加载。
    expect(find.text('AlphaGo 对 李世石 第 1 局'), findsOneWidget);
    expect(find.textContaining('AlphaGo 对 Lee Sedol'), findsOneWidget);
  });
}
