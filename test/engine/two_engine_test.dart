import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/engine/difficulty.dart';
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

/// 按难度档生成脚本（与 match_engine_test 同构）。
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
      'info move E4 visits 456 winrate 0.488 order 0 pv E4 '
          'info move F3 visits 20 winrate 0.437 order 1 pv F3',
      'play E4',
      '',
    ],
  };
}

KataGoEngine _engine(MockGtpIo io) => KataGoEngine(GtpClient(io));

void main() {
  test('双模型选型：级位（rank 0）走小模型，段位（rank 26）走大模型', () async {
    final kyuIo = MockGtpIo(_script(0));
    final danIo = MockGtpIo(_script(26));
    final provider = KataGoMoveProvider(
      kyuEngine: _engine(kyuIo),
      danEngine: _engine(danIo),
      random: math.Random(0),
    );

    await provider.chooseMove(_midBoard(), PlayerColor.black, rankIndex: 0);
    expect(kyuIo.sent, contains('kata-search_analyze b 100'));
    expect(danIo.sent, isEmpty);

    await provider.chooseMove(_midBoard(), PlayerColor.black, rankIndex: 26);
    expect(danIo.sent, contains('kata-search_analyze b 100'));
  });

  test('大模型缺失：段位对弈抛 GtpEngineException（不降级）', () async {
    final kyuIo = MockGtpIo(_script(0));
    final provider = KataGoMoveProvider(
      kyuEngine: _engine(kyuIo),
      danEngine: null,
      random: math.Random(0),
    );
    // 级位不受影响（小模型在）。
    await provider.chooseMove(_midBoard(), PlayerColor.black, rankIndex: 0);
    await expectLater(
      provider.chooseMove(_midBoard(), PlayerColor.black, rankIndex: 18),
      throwsA(isA<GtpEngineException>()),
    );
  });

  test('updateRule 同步两个引擎的规则与贴目', () async {
    final kyuIo = MockGtpIo(_script(0));
    final danIo = MockGtpIo(_script(26));
    final provider = KataGoMoveProvider(
      kyuEngine: _engine(kyuIo),
      danEngine: _engine(danIo),
      random: math.Random(0),
    );
    await provider.updateRule(GoRule.japanese, 6.5);
    expect(provider.rule, GoRule.japanese);
    expect(provider.komi, 6.5);
    expect(kyuIo.sent, contains('kata-set-rules japanese'));
    expect(kyuIo.sent, contains('komi 6.5'));
    expect(danIo.sent, contains('kata-set-rules japanese'));
    expect(danIo.sent, contains('komi 6.5'));
  });

  test('kataGoMoveProvider 装配：按段位自动选型（小模型就绪即可用）', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final kyuIo = MockGtpIo(_script(0));
    final danIo = MockGtpIo(_script(18));
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      kataGoEngineProvider.overrideWithValue(_engine(kyuIo)),
      kataGoDanEngineProvider.overrideWithValue(_engine(danIo)),
    ]);
    addTearDown(container.dispose);

    final provider = container.read(kataGoMoveProvider);
    expect(provider, isNotNull);

    await provider!.chooseMove(_midBoard(), PlayerColor.black, rankIndex: 0);
    expect(kyuIo.sent, contains('kata-search_analyze b 100'));
    expect(danIo.sent, isEmpty);

    await provider.chooseMove(_midBoard(), PlayerColor.black, rankIndex: 18);
    expect(danIo.sent, contains('kata-search_analyze b 100'));
  });
}
