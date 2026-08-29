import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/engine/analysis.dart';
import 'package:miaogo/engine/difficulty.dart';
import 'package:miaogo/engine/katago_engine.dart';

/// 真实引擎端到端（依赖 tools/katago-dev 下的开发机二进制，缺失则跳过）：
/// set_position → kata-search_analyze → 解析 → 返回自选着法。
void main() {
  const binary = 'tools/katago-dev/katago.exe';
  const model = 'assets/katago/kata1-b6c96-s175395328-d26788732.txt.gz';
  const model18 =
      'assets/katago/kata1-b18c384nbt-s9996604416-d4316597426.bin.gz';
  const config = 'assets/katago/gtp.cfg';

  test('真实 KataGo：搜索返回合法着法并解析 top 候选', () async {
    if (!File(binary).existsSync()) {
      markTestSkipped('缺少开发机引擎二进制 $binary（tools/fetch_katago.ps1 -Mode WindowsDev）');
      return;
    }
    final engine = await KataGoEngine.launch(
      binaryPath: binary,
      modelPath: model,
      configPath: config,
    );
    addTearDown(engine.close);

    final board = GoBoard(size: 9);
    board.play(PlayerColor.black, 3, 3); // D4
    board.play(PlayerColor.white, 4, 4); // E5

    final r = await engine.searchAndAnalyze(
      board: board,
      toMove: PlayerColor.black,
      rule: GoRule.chinese,
      komi: 7.5,
      difficulty: DifficultyTable.forRank(18),
      intervalMs: 100,
    );
    // ignore: avoid_print
    print('chosen=${r.chosen} updateMoves=${r.update?.moves.length}');
    expect(r.chosen, isNotNull);
    expect(r.update, isNotNull);
    expect(r.update!.moves, isNotEmpty);
    expect(r.update!.orderedMoves.first.order, 0);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('真实 KataGo：startAnalysis 流式热力图可中断', () async {
    if (!File(binary).existsSync()) {
      markTestSkipped('缺少开发机引擎二进制 $binary');
      return;
    }
    final engine = await KataGoEngine.launch(
      binaryPath: binary,
      modelPath: model,
      configPath: config,
    );
    addTearDown(engine.close);

    final board = GoBoard(size: 9);
    board.play(PlayerColor.black, 3, 3);
    board.play(PlayerColor.white, 4, 4);

    AnalysisUpdate? last;
    final session = engine.startAnalysis(
      board: board,
      toMove: PlayerColor.black,
      rule: GoRule.chinese,
      komi: 7.5,
      intervalMs: 50,
    );
    session.updates.listen((u) => last = u);
    await Future<void>.delayed(const Duration(seconds: 3));
    await session.stop();
    expect(last, isNotNull);
    expect(last!.ownership, hasLength(81));
    // 中断后引擎协议状态干净：可继续发命令。
    final score = await engine.finalScore();
    expect(score, isNotEmpty);
    // ignore: avoid_print
    print('analysis ownership head=${last!.ownership!.take(3).toList()} score=$score');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('真实 KataGo（大模型 b18c384）：段位搜索返回合法着法', () async {
    if (!File(binary).existsSync()) {
      markTestSkipped('缺少开发机引擎二进制 $binary（tools/fetch_katago.ps1 -Mode WindowsDev）');
      return;
    }
    if (!File(model18).existsSync()) {
      markTestSkipped('缺少大模型 $model18（从 katagotraining.org 下载，体积红线不入库）');
      return;
    }
    final engine = await KataGoEngine.launch(
      binaryPath: binary,
      modelPath: model18,
      configPath: config,
      // 大模型冷启动较慢（约 98MB gz / CPU 加载）。
      initialTimeout: const Duration(minutes: 5),
    );
    addTearDown(engine.close);

    final board = GoBoard(size: 9);
    board.play(PlayerColor.black, 3, 3); // D4
    board.play(PlayerColor.white, 4, 4); // E5

    final r = await engine.searchAndAnalyze(
      board: board,
      toMove: PlayerColor.black,
      rule: GoRule.chinese,
      komi: 7.5,
      difficulty: DifficultyTable.forRank(26),
      intervalMs: 100,
    );
    // ignore: avoid_print
    print('b18 chosen=${r.chosen} updateMoves=${r.update?.moves.length}');
    expect(r.chosen, isNotNull);
    expect(r.update, isNotNull);
    expect(r.update!.moves, isNotEmpty);
    expect(r.update!.orderedMoves.first.order, 0);
  }, timeout: const Timeout(Duration(minutes: 8)));
}
