import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/storage/record_store.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> makeContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
  ]);
  addTearDown(container.dispose);
  return container;
}

GameRecord makeRecord(String id, {GameResult result = GameResult.win}) {
  return GameRecord(
    id: id,
    date: DateTime(2026, 8, 27),
    opponentName: 'AI · 5级',
    opponentRank: 13,
    result: result,
    boardSize: 9,
    rule: GoRule.chinese,
    komi: 7.5,
    sgfPath: '',
    source: GameSource.ai,
    moveCount: 120,
    sgfContent: '(;GM[1]FF[4]SZ[9]RU[chinese]KM[7.5];B[dd])',
  );
}

void main() {
  test('默认无棋谱', () async {
    final container = await makeContainer();
    expect(container.read(recordStoreProvider), isEmpty);
  });

  test('新增棋谱：最新在前', () async {
    final container = await makeContainer();
    await container.read(recordStoreProvider.notifier).add(makeRecord('1'));
    await container.read(recordStoreProvider.notifier).add(makeRecord('2'));
    final records = container.read(recordStoreProvider);
    expect(records, hasLength(2));
    expect(records.first.id, '2');
    expect(records.last.id, '1');
  });

  test('删除棋谱', () async {
    final container = await makeContainer();
    final notifier = container.read(recordStoreProvider.notifier);
    await notifier.add(makeRecord('a'));
    await notifier.add(makeRecord('b'));
    notifier.delete('a');
    final records = container.read(recordStoreProvider);
    expect(records, hasLength(1));
    expect(records.single.id, 'b');
  });

  test('清空棋谱', () async {
    final container = await makeContainer();
    final notifier = container.read(recordStoreProvider.notifier);
    await notifier.add(makeRecord('a'));
    notifier.clear();
    expect(container.read(recordStoreProvider), isEmpty);
  });

  test('持久化往返：重建容器后保留', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c1 = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    await c1.read(recordStoreProvider.notifier).add(makeRecord('1'));
    await c1.read(recordStoreProvider.notifier).add(makeRecord('2'));
    c1.dispose();

    final c2 = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(c2.dispose);
    final records = c2.read(recordStoreProvider);
    expect(records, hasLength(2));
    expect(records.first.opponentRank, 13);
    expect(records.first.rule, GoRule.chinese);
    expect(records.first.komi, 7.5);
    expect(records.first.result, GameResult.win);
    expect(records.first.source, GameSource.ai);
    // SGF 内容不落入索引
    expect(records.first.sgfContent, isNull);
  });
}
