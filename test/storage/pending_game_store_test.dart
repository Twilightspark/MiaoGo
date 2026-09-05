import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/storage/pending_game_store.dart';
import 'package:miaogo/storage/record_store.dart';
import 'package:miaogo/storage/settings_store.dart';

void main() {
  PendingGame sample({
    MoveStyle style = MoveStyle.confirm,
    List<(int, double)> history = const [],
  }) =>
      PendingGame(
        source: GameSource.ai,
        size: 9,
        rule: GoRule.chinese,
        komi: 7.5,
        humanColor: PlayerColor.black,
        difficulty: 0,
        opponentName: '张三',
        tournamentId: null,
        moveStyle: style,
        winrateHistory: history,
        sgf: '(;GM[1]SZ[9])',
        savedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );

  test('PendingGame moveStyle 随 JSON 往返', () {
    final back =
        PendingGame.fromJson(sample(style: MoveStyle.doubleTap).toJson());
    expect(back.moveStyle, MoveStyle.doubleTap);
    expect(back.opponentName, '张三');
  });

  test('PendingGame winrateHistory 随 JSON 往返（含缺省回退空）', () {
    final back = PendingGame.fromJson(sample(history: const [
      (0, 0.52),
      (1, 0.48),
    ]).toJson());
    expect(back.winrateHistory, const [(0, 0.52), (1, 0.48)]);

    final empty = PendingGame.fromJson(const {
      'source': 'ai',
      'size': 9,
      'rule': 'chinese',
      'komi': 7.5,
      'humanColor': 'black',
      'difficulty': 0,
      'opponentName': '',
      'tournamentId': null,
      'sgf': '',
      'savedAt': 0,
    });
    expect(empty.winrateHistory, isEmpty);
  });

  test('旧快照缺 moveStyle 时默认确认落子', () {
    final back = PendingGame.fromJson(const {
      'source': 'ai',
      'size': 9,
      'rule': 'chinese',
      'komi': 7.5,
      'humanColor': 'black',
      'difficulty': 0,
      'opponentName': '',
      'tournamentId': null,
      'sgf': '',
      'savedAt': 0,
    });
    expect(back.moveStyle, MoveStyle.confirm);
  });
}
