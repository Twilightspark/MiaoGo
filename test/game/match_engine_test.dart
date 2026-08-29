import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/engine/difficulty.dart';
import 'package:miaogo/engine/gtp_client.dart';
import 'package:miaogo/engine/katago_engine.dart';
import 'package:miaogo/game/match_engine.dart';

import '../engine/mock_gtp_io.dart';

/// 构造 D4 黑 / E5 白 的 9 路棋盘。
GoBoard _midBoard() {
  final b = GoBoard(size: 9);
  b.play(PlayerColor.black, 3, 3);
  b.play(PlayerColor.white, 4, 4);
  return b;
}

/// 按难度档生成匹配的脚本。
Map<String, List<String>> _script(int rankIndex) {
  final d = DifficultyTable.forRank(rankIndex);
  final t = d.maxTimeMs / 1000.0;
  return {
    'boardsize 9': ['= '],
    'kata-set-rules chinese': ['= '],
    'kata-set-rules japanese': ['= '],
    'komi 7.5': ['= '],
    'komi 6.5': ['= '],
    'set_position b D4 w E5': ['= '],
    'kata-set-param maxVisits ${d.maxVisits}': ['= '],
    'kata-set-param maxTime ${t == t.roundToDouble() ? t.toInt() : t}': ['= '],
    'kata-search_analyze b 100': [
      '',
      '=',
      'info move E4 visits 456 winrate 0.488 utility -0.013 scoreLead -0.041 '
          'scoreMean -0.041 scoreSelfplay 0.106 prior 0.397 lcb 0.473 order 0 pv E4 F5 '
          'info move D5 visits 456 winrate 0.488 order 1 isSymmetryOf E4 pv D5 '
          'info move F3 visits 20 winrate 0.437 order 2 pv F3',
      'play E4',
      '',
    ],
  };
}

KataGoEngine _engineWith(MockGtpIo io) => KataGoEngine(GtpClient(io));

void main() {
  test('高段位（topK=1）：取最优 E4', () async {
    final io = MockGtpIo(_script(26));
    final provider = KataGoMoveProvider(
      kyuEngine: _engineWith(io),
      danEngine: _engineWith(io),
      random: math.Random(0),
    );
    final move = await provider.chooseMove(_midBoard(), PlayerColor.black,
        rankIndex: 26);
    expect(move.isPass, isFalse);
    expect((move.row, move.col), (3, 4)); // E4
    expect(io.sent, contains('set_position b D4 w E5'));
  });

  test('低段位（topK=6，温度 1.5）：多次采样覆盖 E4/F3（选点容错）', () async {
    final moves = <(int, int)>{};
    for (var seed = 0; seed < 40; seed++) {
      final io = MockGtpIo(_script(0));
      final provider = KataGoMoveProvider(
        kyuEngine: _engineWith(io),
      danEngine: _engineWith(io),
        random: math.Random(seed),
      );
      final move =
          await provider.chooseMove(_midBoard(), PlayerColor.black, rankIndex: 0);
      expect(move.isPass, isFalse);
      moves.add((move.row!, move.col!));
    }
    expect(moves, contains((3, 4))); // E4
    expect(moves, contains((2, 5))); // F3：次优也会被抽中
    expect(moves.length, greaterThan(1));
  });

  test('引擎异常：chooseMove 上抛（不做 Dart AI 降级）', () async {
    final io = MockGtpIo();
    io.writeError = StateError('engine down');
    final provider = KataGoMoveProvider(
      kyuEngine: _engineWith(io),
      danEngine: _engineWith(io),
      random: math.Random(0),
    );
    await expectLater(
      provider.chooseMove(_midBoard(), PlayerColor.black, rankIndex: 18),
      throwsA(isA<StateError>()),
    );
  });

  test('候选为空时回退引擎自选着法', () async {
    // 分析无候选行（空 update），仅 play 行给出 E4。
    final script = _script(18);
    script['kata-search_analyze b 100'] = ['', '=', 'play E4', ''];
    final io = MockGtpIo(script);
    final provider = KataGoMoveProvider(
      kyuEngine: _engineWith(io),
      danEngine: _engineWith(io),
      random: math.Random(0),
    );
    final move =
        await provider.chooseMove(_midBoard(), PlayerColor.black, rankIndex: 18);
    expect((move.row, move.col), (3, 4));
  });

  test('updateRule 同步引擎规则与贴目', () async {
    final io = MockGtpIo(_script(18));
    final provider = KataGoMoveProvider(
      kyuEngine: _engineWith(io),
      danEngine: _engineWith(io),
      random: math.Random(0),
    );
    await provider.updateRule(GoRule.japanese, 6.5);
    expect(provider.rule, GoRule.japanese);
    expect(provider.komi, 6.5);
    expect(io.sent, contains('kata-set-rules japanese'));
    expect(io.sent, contains('komi 6.5'));
  });
}
