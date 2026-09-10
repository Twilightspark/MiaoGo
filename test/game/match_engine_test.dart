import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rules.dart';
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

/// 脚本化引擎：Human SL 参数走前缀匹配，搜索返回 [play] 着法。
MockGtpIo _mock({String? play = 'E4', bool withInfo = true}) {
  final io = MockGtpIo({
    'boardsize 9': ['= '],
    'kata-set-rules chinese': ['= '],
    'kata-set-rules japanese': ['= '],
    'komi 7.5': ['= '],
    'komi 6.5': ['= '],
  });
  io.scriptPrefixes = [
    (prefix: 'set_position', lines: ['= ']),
    (prefix: 'kata-set-params', lines: ['= ']),
    (
      prefix: 'kata-search_analyze',
      lines: [
        '',
        '=',
        if (withInfo)
          'info move E4 visits 456 winrate 0.488 order 0 pv E4 '
              'info move F3 visits 20 winrate 0.437 order 1 pv F3',
        if (play != null) 'play $play',
        '=',
        '',
      ],
    ),
  ];
  return io;
}

KataGoEngine _engineWith(MockGtpIo io) => KataGoEngine(GtpClient(io));

void main() {
  test('Human SL：直接采用引擎自选着法并下发对应画像', () async {
    final io = _mock(play: 'E4');
    final provider = KataGoMoveProvider(engine: _engineWith(io));
    final move = await provider.chooseMove(_midBoard(), PlayerColor.black,
        rankIndex: 0);
    expect((move.row, move.col), (3, 4)); // E4
    final paramCmd =
        io.sent.firstWhere((c) => c.startsWith('kata-set-params'));
    expect(paramCmd, contains('"humanSLProfile":"rank_18k"'));
    expect(paramCmd, contains('"humanSLChosenMoveProp":1.0'));
  });

  test('段位画像：rankIndex 26 下发 rank_9d 并启用根探索', () async {
    final io = _mock(play: 'E4');
    final provider = KataGoMoveProvider(engine: _engineWith(io));
    await provider.chooseMove(_midBoard(), PlayerColor.black, rankIndex: 26);
    final paramCmd =
        io.sent.firstWhere((c) => c.startsWith('kata-set-params'));
    expect(paramCmd, contains('"humanSLProfile":"rank_9d"'));
    expect(paramCmd, contains('"humanSLRootExploreProbWeightless":0.8'));
  });

  test('引擎 PASS 透传', () async {
    final io = _mock(play: 'pass');
    final provider = KataGoMoveProvider(engine: _engineWith(io));
    final move = await provider.chooseMove(_midBoard(), PlayerColor.black,
        rankIndex: 10);
    expect(move.isPass, isTrue);
  });

  test('引擎认输透传', () async {
    final io = _mock(play: 'resign');
    final provider = KataGoMoveProvider(engine: _engineWith(io));
    final move = await provider.chooseMove(_midBoard(), PlayerColor.black,
        rankIndex: 20);
    expect(move.isResign, isTrue);
  });

  test('无 play 行：回退分析候选最优合法点', () async {
    final io = _mock(play: null);
    final provider = KataGoMoveProvider(engine: _engineWith(io));
    final move = await provider.chooseMove(_midBoard(), PlayerColor.black,
        rankIndex: 18);
    expect((move.row, move.col), (3, 4)); // E4
  });

  test('引擎异常：chooseMove 上抛（不做 Dart AI 降级）', () async {
    final io = MockGtpIo();
    io.writeError = StateError('engine down');
    final provider = KataGoMoveProvider(engine: _engineWith(io));
    await expectLater(
      provider.chooseMove(_midBoard(), PlayerColor.black, rankIndex: 18),
      throwsA(isA<StateError>()),
    );
  });

  test('updateRule 同步引擎规则与贴目', () async {
    final io = _mock(play: 'E4');
    final provider = KataGoMoveProvider(engine: _engineWith(io));
    await provider.updateRule(GoRule.japanese, 6.5);
    expect(provider.rule, GoRule.japanese);
    expect(provider.komi, 6.5);
    expect(io.sent, contains('kata-set-rules japanese'));
    expect(io.sent, contains('komi 6.5'));
  });
}
