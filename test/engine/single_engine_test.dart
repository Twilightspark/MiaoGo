import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/engine/engine_controller.dart';
import 'package:miaogo/engine/gtp_client.dart';
import 'package:miaogo/engine/katago_engine.dart';
import 'package:miaogo/game/match_engine.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mock_gtp_io.dart';

/// 构造 D4 黑 / E5 白 的 9 路棋盘。
GoBoard _midBoard() {
  final b = GoBoard(size: 9);
  b.play(PlayerColor.black, 3, 3);
  b.play(PlayerColor.white, 4, 4);
  return b;
}

MockGtpIo _mock() {
  final io = MockGtpIo({
    'boardsize 9': ['= '],
    'kata-set-rules chinese': ['= '],
    'komi 7.5': ['= '],
  });
  io.scriptPrefixes = [
    (prefix: 'set_position', lines: ['= ']),
    (prefix: 'kata-set-params', lines: ['= ']),
    (
      prefix: 'kata-search_analyze',
      lines: [
        '',
        '=',
        'info move E4 visits 456 winrate 0.488 order 0 pv E4',
        'play E4',
        '=',
        '',
      ],
    ),
  ];
  return io;
}

KataGoEngine _engine(MockGtpIo io) => KataGoEngine(GtpClient(io));

void main() {
  test('单引擎：级位/段位均走同一引擎并下发对应 Human SL 画像', () async {
    final io = _mock();
    final provider = KataGoMoveProvider(engine: _engine(io));

    await provider.chooseMove(_midBoard(), PlayerColor.black, rankIndex: 0);
    expect(io.sent.any((c) => c.contains('"rank_18k"')), isTrue);

    await provider.chooseMove(_midBoard(), PlayerColor.black, rankIndex: 26);
    expect(io.sent.any((c) => c.contains('"rank_9d"')), isTrue);
    expect(io.sent, contains('kata-search_analyze b 100'));
  });

  test('kataGoMoveProvider 装配：引擎就绪即可用（级位/段位同源）', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final io = _mock();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      kataGoEngineProvider.overrideWithValue(_engine(io)),
    ]);
    addTearDown(container.dispose);

    final provider = container.read(kataGoMoveProvider);
    expect(provider, isNotNull);

    await provider!.chooseMove(_midBoard(), PlayerColor.black, rankIndex: 18);
    expect(io.sent.any((c) => c.contains('"rank_1d"')), isTrue);
    expect(io.sent, contains('kata-search_analyze b 100'));
  });

  test('kataGoMoveProvider：引擎未就绪返回 null', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      kataGoEngineProvider.overrideWithValue(null),
    ]);
    addTearDown(container.dispose);
    expect(container.read(kataGoMoveProvider), isNull);
  });
}
