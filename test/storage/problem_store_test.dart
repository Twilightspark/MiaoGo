import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/storage/problem_store.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> makeContainer() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('默认无进度', () async {
    final container = await makeContainer();
    expect(container.read(problemStoreProvider), isEmpty);
  });

  test('记录作答：解出 / 尝试次数累积', () async {
    final container = await makeContainer();
    final notifier = container.read(problemStoreProvider.notifier);

    notifier.recordAttempt('easy-ggg-easy-01', solved: false);
    notifier.recordAttempt('easy-ggg-easy-01', solved: false);
    expect(container.read(problemStoreProvider)['easy-ggg-easy-01']!.solved,
        isFalse);
    expect(container.read(problemStoreProvider)['easy-ggg-easy-01']!.attempts,
        2);

    notifier.recordAttempt('easy-ggg-easy-01', solved: true);
    final st = container.read(problemStoreProvider)['easy-ggg-easy-01']!;
    expect(st.solved, isTrue);
    expect(st.attempts, 3);
    expect(notifier.isSolved('easy-ggg-easy-01'), isTrue);

    notifier.recordAttempt('hard-ggg-hard-05', solved: true);
    expect(container.read(problemStoreProvider).length, 2);
  });

  test('已解出题不会因后续答错变回未解', () async {
    final container = await makeContainer();
    final notifier = container.read(problemStoreProvider.notifier);
    notifier.recordAttempt('x', solved: true);
    notifier.recordAttempt('x', solved: false);
    expect(notifier.isSolved('x'), isTrue);
  });

  test('进度持久化往返', () async {
    final container = await makeContainer();
    final notifier = container.read(problemStoreProvider.notifier);
    notifier.recordAttempt('easy-1', solved: true, attempts: 2);

    // 新建容器（同一 mock prefs）重新读取。
    final prefs = await SharedPreferences.getInstance();
    final container2 = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container2.dispose);
    final restored = container2.read(problemStoreProvider);
    expect(restored['easy-1']!.solved, isTrue);
    expect(restored['easy-1']!.attempts, 2);
  });
}
