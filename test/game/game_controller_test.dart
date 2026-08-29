import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/game/game_controller.dart';
import 'package:miaogo/game/move_provider.dart';
import 'package:miaogo/storage/record_store.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 始终 PASS 的假 AI，用于双 PASS 终局测试。
class _PassAi implements MoveProvider {
  @override
  Future<Move> chooseMove(GoBoard board, PlayerColor toMove,
          {required int rankIndex}) async =>
      Move.pass(toMove);
}

/// 依序落子的假 AI（悔棋重放提子计数测试用）。
class _ScriptAi implements MoveProvider {
  _ScriptAi(this.moves);

  final List<Move> moves;
  int _i = 0;

  @override
  Future<Move> chooseMove(GoBoard board, PlayerColor toMove,
          {required int rankIndex}) async =>
      moves[_i++];
}

/// 首次失败、随后正常的假 AI（模拟引擎崩溃后重启恢复）。
class _FlakyAi implements MoveProvider {
  int calls = 0;

  @override
  Future<Move> chooseMove(GoBoard board, PlayerColor toMove,
          {required int rankIndex}) async {
    calls++;
    if (calls == 1) throw StateError('engine down');
    return Move.pass(toMove);
  }
}

/// 构造带提子的棋盘：黑围提白 (4,4)，capturesBlack = 1。
GoBoard captureBoard() {
  final b = GoBoard(size: 9);
  b.play(PlayerColor.black, 3, 4);
  b.play(PlayerColor.white, 4, 4);
  b.play(PlayerColor.black, 5, 4);
  b.play(PlayerColor.white, 1, 1);
  b.play(PlayerColor.black, 4, 3);
  b.play(PlayerColor.white, 1, 3);
  b.play(PlayerColor.black, 4, 5); // 提 (4,4)
  return b;
}

GameState stateWith({required GoBoard board, PlayerColor humanColor = PlayerColor.black}) {
  return GameState(
    boardSize: board.size,
    rule: GoRule.chinese,
    komi: 7.5,
    humanColor: humanColor,
    aiColor: humanColor.opposite,
    difficulty: 8,
    board: board,
    moves: const [],
    turn: humanColor,
    aiThinking: false,
    finished: false,
    result: null,
    winner: null,
    resignedBy: null,
    consecutivePasses: 0,
    suggestScoring: false,
    aiError: null,
  );
}

Future<ProviderContainer> makeContainer({
  MoveProvider? ai,
  Duration delay = Duration.zero,
  SettlednessCheck? isSettled,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    gameControllerProvider.overrideWith(
      () => GameController(ai: ai, thinkingDelay: delay, isSettled: isSettled),
    ),
  ]);
  addTearDown(container.dispose);
  return container;
}

Future<void> flush() =>
    Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  test('开局：黑先玩家执黑，无 AI 思考', () async {
    final container = await makeContainer();
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewGame(
      size: 9,
      rule: GoRule.chinese,
      komi: 7.5,
      humanColor: PlayerColor.black,
      difficulty: 8,
    );
    final s = container.read(gameControllerProvider);
    expect(s.boardSize, 9);
    expect(s.humanColor, PlayerColor.black);
    expect(s.aiColor, PlayerColor.white);
    expect(s.difficulty, 8);
    expect(s.turn, PlayerColor.black);
    expect(s.aiThinking, isFalse);
    expect(s.moves, isEmpty);
  });

  test('玩家执白：AI 先手自动落子', () async {
    final container = await makeContainer(ai: _PassAi());
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewGame(
      size: 9,
      rule: GoRule.chinese,
      komi: 7.5,
      humanColor: PlayerColor.white,
      difficulty: 8,
    );
    expect(container.read(gameControllerProvider).aiThinking, isTrue);
    await flush();
    final s = container.read(gameControllerProvider);
    expect(s.aiThinking, isFalse);
    expect(s.moves, hasLength(1));
    expect(s.moves.first.color, PlayerColor.black);
    expect(s.turn, PlayerColor.white);
  });

  test('玩家落子 → AI 应手 → 回到玩家回合', () async {
    final container = await makeContainer(ai: _PassAi());
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewGame(
      size: 9,
      rule: GoRule.chinese,
      komi: 7.5,
      humanColor: PlayerColor.black,
      difficulty: 8,
    );
    expect(notifier.placeStone(0, 0), isTrue);
    expect(container.read(gameControllerProvider).aiThinking, isTrue);
    await flush();
    final s = container.read(gameControllerProvider);
    expect(s.moves, hasLength(2));
    expect(s.moves[1].color, PlayerColor.white);
    expect(s.turn, PlayerColor.black);
  });

  test('非法落子：占点或非玩家回合均无效', () async {
    final container = await makeContainer(ai: _PassAi());
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewGame(
      size: 9,
      rule: GoRule.chinese,
      komi: 7.5,
      humanColor: PlayerColor.black,
      difficulty: 8,
    );
    expect(notifier.placeStone(0, 0), isTrue);
    await flush();
    expect(notifier.placeStone(0, 0), isFalse); // AI 应手前占点
    final s = container.read(gameControllerProvider);
    expect(s.moves, hasLength(2));
  });

  test('悔棋：撤销 AI 应手 + 玩家一手，回到玩家回合', () async {
    final container = await makeContainer(ai: _PassAi());
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewGame(
      size: 9,
      rule: GoRule.chinese,
      komi: 7.5,
      humanColor: PlayerColor.black,
      difficulty: 8,
    );
    notifier.placeStone(0, 0);
    await flush();
    expect(container.read(gameControllerProvider).moves, hasLength(2));

    notifier.undo();
    final s = container.read(gameControllerProvider);
    expect(s.moves, isEmpty);
    expect(s.turn, PlayerColor.black);
    expect(s.board.at(0, 0), isNull);
  });

  test('悔棋取消进行中的 AI 思考', () async {
    final container = await makeContainer(ai: _PassAi());
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewGame(
      size: 9,
      rule: GoRule.chinese,
      komi: 7.5,
      humanColor: PlayerColor.black,
      difficulty: 8,
    );
    notifier.placeStone(0, 0);
    expect(container.read(gameControllerProvider).aiThinking, isTrue);
    notifier.undo();
    expect(container.read(gameControllerProvider).aiThinking, isFalse);
    expect(container.read(gameControllerProvider).moves, isEmpty);
    await flush();
    expect(container.read(gameControllerProvider).moves, isEmpty); // AI 不再落子
  });

  test('认输：AI 获胜，无计分', () async {
    final container = await makeContainer();
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewGame(
      size: 9,
      rule: GoRule.chinese,
      komi: 7.5,
      humanColor: PlayerColor.black,
      difficulty: 8,
    );
    notifier.resign();
    final s = container.read(gameControllerProvider);
    expect(s.finished, isTrue);
    expect(s.resignedBy, PlayerColor.black);
    expect(s.winner, PlayerColor.white);
    expect(s.result, isNull);
  });

  test('双 PASS 终局：计分并保存棋谱', () async {
    final container = await makeContainer(ai: _PassAi());
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewGame(
      size: 9,
      rule: GoRule.chinese,
      komi: 7.5,
      humanColor: PlayerColor.black,
      difficulty: 8,
    );
    notifier.pass();
    expect(container.read(gameControllerProvider).moves, hasLength(1));
    expect(container.read(gameControllerProvider).turn, PlayerColor.white);
    await flush();
    final s = container.read(gameControllerProvider);
    expect(s.finished, isTrue);
    expect(s.result, isNotNull);
    expect(s.winner, isNotNull); // 空棋盘白贴目胜

    // 棋谱已保存
    final records = container.read(recordStoreProvider);
    expect(records, hasLength(1));
    expect(records.first.moveCount, 2);
    expect(records.first.source, GameSource.ai);
    expect(records.first.rule, GoRule.chinese);
    expect(records.first.boardSize, 9);
  });

  test('终局后不可再悔棋/落子', () async {
    final container = await makeContainer(ai: _PassAi());
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewGame(
      size: 9,
      rule: GoRule.chinese,
      komi: 7.5,
      humanColor: PlayerColor.black,
      difficulty: 8,
    );
    notifier.pass();
    await flush();
    final s = container.read(gameControllerProvider);
    expect(s.finished, isTrue);
    expect(notifier.placeStone(4, 4), isFalse);
    notifier.undo();
    expect(container.read(gameControllerProvider).moves, hasLength(2));
  });

  test('humanCaptured/aiCaptured：按执子色取各自提子数（防显示反转回归）', () {
    final b = captureBoard();
    final blackHuman = stateWith(board: b); // 玩家执黑
    expect(blackHuman.humanCaptured, 1);
    expect(blackHuman.aiCaptured, 0);

    final whiteHuman = stateWith(board: b, humanColor: PlayerColor.white);
    expect(whiteHuman.humanCaptured, 0); // 白方玩家未提子
    expect(whiteHuman.aiCaptured, 1); // AI（黑）提了 1 子
  });

  test('点目：直接计分终局并保存棋谱', () async {
    final container = await makeContainer(ai: _PassAi());
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewGame(
      size: 9,
      rule: GoRule.chinese,
      komi: 7.5,
      humanColor: PlayerColor.black,
      difficulty: 8,
    );
    notifier.placeStone(0, 0);
    await flush();
    expect(container.read(gameControllerProvider).moves, hasLength(2));

    notifier.scoreAndFinish();
    await flush(); // 棋谱异步落盘
    final s = container.read(gameControllerProvider);
    expect(s.finished, isTrue);
    expect(s.result, isNotNull);
    expect(s.winner, isNotNull);
    expect(s.suggestScoring, isFalse);
    final records = container.read(recordStoreProvider);
    expect(records, hasLength(1));
    expect(records.first.moveCount, 2);
  });

  test('主动点目：三次拒绝后不再申请', () async {
    final container = await makeContainer(
      ai: _PassAi(),
      isSettled: (b, m) => true,
    );
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewGame(
      size: 9,
      rule: GoRule.chinese,
      komi: 7.5,
      humanColor: PlayerColor.black,
      difficulty: 8,
    );
    expect(container.read(gameControllerProvider).suggestScoring, isFalse);

    for (var i = 0; i < 3; i++) {
      notifier.placeStone(0, i);
      await flush();
      expect(
        container.read(gameControllerProvider).suggestScoring,
        isTrue,
        reason: '第 ${i + 1} 次应弹出点目申请',
      );
      notifier.refuseScoring();
      expect(container.read(gameControllerProvider).suggestScoring, isFalse);
    }
    // 第四次不再申请
    notifier.placeStone(0, 3);
    await flush();
    expect(container.read(gameControllerProvider).suggestScoring, isFalse);
  });

  test('悔棋重放后提子计数一致', () async {    final ai = _ScriptAi([
      Move.point(PlayerColor.black, 3, 4),
      Move.point(PlayerColor.black, 5, 4),
      Move.point(PlayerColor.black, 4, 3),
      Move.point(PlayerColor.black, 4, 5),
    ]);
    final container = await makeContainer(ai: ai);
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewGame(
      size: 9,
      rule: GoRule.chinese,
      komi: 7.5,
      humanColor: PlayerColor.white,
      difficulty: 8,
    );
    await flush(); // AI (3,4)
    expect(container.read(gameControllerProvider).moves, hasLength(1));
    notifier.placeStone(4, 4);
    await flush();
    expect(container.read(gameControllerProvider).moves, hasLength(3));
    notifier.placeStone(1, 1);
    await flush();
    expect(container.read(gameControllerProvider).moves, hasLength(5));
    notifier.placeStone(1, 3);
    await flush();
    // AI (4,5) 提白 (4,4)
    var s = container.read(gameControllerProvider);
    expect(s.moves, hasLength(7));
    expect(s.board.capturesBlack, 1);
    expect(s.board.at(4, 4), isNull);

    notifier.undo();
    s = container.read(gameControllerProvider);
    expect(s.moves, hasLength(5)); // 撤掉 AI (4,5) + 玩家 (1,3)
    expect(s.board.capturesBlack, 0); // 提子计数随重放归零
    expect(s.board.at(4, 4), PlayerColor.white);
  });

  test('引擎不可用：AI 思考失败置 aiError，对局中止且不终局不存谱', () async {
    final container = await makeContainer(); // 无显式 AI → 引擎 provider 为空
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewGame(
      size: 9,
      rule: GoRule.chinese,
      komi: 7.5,
      humanColor: PlayerColor.white,
      difficulty: 8,
    );
    await flush(); // AI 先手 → 抛 StateError
    final s = container.read(gameControllerProvider);
    expect(s.aiError, isNotNull);
    expect(s.finished, isFalse);
    expect(s.aiThinking, isFalse);
    expect(s.isHumanTurn, isFalse);
    expect(container.read(recordStoreProvider), isEmpty);
  });

  test('引擎重启恢复：resumeAfterEngineRestart 清 aiError 并重发 AI 一手', () async {
    final ai = _FlakyAi();
    final container = await makeContainer(ai: ai);
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewGame(
      size: 9,
      rule: GoRule.chinese,
      komi: 7.5,
      humanColor: PlayerColor.white,
      difficulty: 8,
    );
    await flush(); // 首次调用失败
    expect(container.read(gameControllerProvider).aiError, isNotNull);
    expect(container.read(gameControllerProvider).moves, isEmpty);

    notifier.resumeAfterEngineRestart();
    await flush(); // 第二次调用正常应手
    final s = container.read(gameControllerProvider);
    expect(s.aiError, isNull);
    expect(s.moves, hasLength(1));
    expect(s.isHumanTurn, isTrue);
  });
}
