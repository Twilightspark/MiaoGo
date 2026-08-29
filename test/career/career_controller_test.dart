import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/game/career.dart';
import 'package:miaogo/game/career_controller.dart';
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

void main() {
  test('初始：生成 9/13/19 三场待报名大赛，无当前赛事与历史', () async {
    final c = await makeContainer();
    final s = c.read(careerControllerProvider);
    expect(s.active, isNull);
    expect(s.upcoming, hasLength(3));
    expect(s.upcoming.map((t) => t.boardSize).toSet(), {9, 13, 19});
    expect(s.history, isEmpty);
    // 玩家已种入（名/段位来自 UserProfile 默认 棋手/18级）
    for (final t in s.upcoming) {
      expect(t.players.where((p) => p.isPlayer), hasLength(1));
    }
  });

  test('报名：无进行中赛事才可；报名后当前大赛就绪并从待报名移除', () async {
    final c = await makeContainer();
    final t9 = c
        .read(careerControllerProvider)
        .upcoming
        .firstWhere((t) => t.boardSize == 9);

    expect(c.read(careerControllerProvider.notifier).signUp(t9.id), isTrue);
    var s = c.read(careerControllerProvider);
    expect(s.active, isNotNull);
    expect(s.active!.boardSize, 9);
    expect(s.active!.status, CareerTournamentStatus.active);
    expect(s.upcoming.any((t) => t.id == t9.id), isFalse);
    expect(s.upcoming, hasLength(2));

    // 有进行中赛事：不可再报名
    final t13 = s.upcoming.firstWhere((t) => t.boardSize == 13);
    expect(c.read(careerControllerProvider.notifier).signUp(t13.id), isFalse);
  });

  test('夺冠：三连胜完结结算，积分90/冠军/参赛+1，历史与新9路大赛', () async {
    final c = await makeContainer();
    final notifier = c.read(careerControllerProvider.notifier);
    final t9 = c
        .read(careerControllerProvider)
        .upcoming
        .firstWhere((t) => t.boardSize == 9);
    notifier.signUp(t9.id);

    final r1 = notifier.resolveMatch(won: true);
    expect(r1.complete, isFalse);
    expect(c.read(careerControllerProvider).active!.currentRound, 1);

    final r2 = notifier.resolveMatch(won: true);
    expect(r2.complete, isFalse);
    expect(c.read(careerControllerProvider).active!.currentRound, 2);

    final r3 = notifier.resolveMatch(won: true);
    expect(r3.complete, isTrue);
    expect(r3.champion, isTrue);

    final s = c.read(careerControllerProvider);
    expect(s.active, isNull);
    expect(s.history, hasLength(1));
    final rec = s.history.first;
    expect(rec.champion, isTrue);
    expect(rec.placement, 1);
    expect(rec.points, 90); // 3×20 + 冠军30
    expect(s.upcoming.where((t) => t.boardSize == 9), hasLength(1)); // 已补齐

    final user = c.read(userProfileProvider);
    expect(user.careerPoints, 90);
    expect(user.participations, 1);
    expect(user.championships, 1);
    expect(user.wins, 3);
    expect(user.totalGames, 3);
  });

  test('淘汰：8强失利自动模拟完结，名次八强、积分5', () async {
    final c = await makeContainer();
    final notifier = c.read(careerControllerProvider.notifier);
    final t = c
        .read(careerControllerProvider)
        .upcoming
        .firstWhere((t) => t.boardSize == 9);
    notifier.signUp(t.id);

    final r = notifier.resolveMatch(won: false);
    expect(r.complete, isTrue);
    expect(r.champion, isFalse);

    final s = c.read(careerControllerProvider);
    expect(s.active, isNull);
    final rec = s.history.first;
    expect(rec.withdrawn, isFalse);
    expect(rec.placement, 5);
    expect(rec.points, 5); // 一负

    final user = c.read(userProfileProvider);
    expect(user.careerPoints, 5);
    expect(user.participations, 1);
    expect(user.losses, 1);
  });

  test('退赛：不产生任何积分/胜负/参赛结算，历史记退赛0分', () async {
    final c = await makeContainer();
    final notifier = c.read(careerControllerProvider.notifier);
    final t = c
        .read(careerControllerProvider)
        .upcoming
        .firstWhere((t) => t.boardSize == 9);
    notifier.signUp(t.id);
    notifier.resolveMatch(won: true); // 先赢一场再退赛
    notifier.withdraw();

    final s = c.read(careerControllerProvider);
    expect(s.active, isNull);
    expect(s.history, hasLength(1));
    final rec = s.history.first;
    expect(rec.withdrawn, isTrue);
    expect(rec.placement, 0);
    expect(rec.points, 0);
    expect(s.upcoming.where((t) => t.boardSize == 9), hasLength(1));

    final user = c.read(userProfileProvider);
    expect(user.careerPoints, 0);
    expect(user.participations, 0);
    expect(user.championships, 0);
    expect(user.wins, 0);
    expect(user.totalGames, 0);
  });

  test('持久化：状态跨重建恢复（重启载入）', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    final notifier = container.read(careerControllerProvider.notifier);
    final t9 = container
        .read(careerControllerProvider)
        .upcoming
        .firstWhere((t) => t.boardSize == 9);
    notifier.signUp(t9.id);
    notifier.resolveMatch(won: true); // 晋级半决赛
    final activeId = container.read(careerControllerProvider).active!.id;
    container.dispose();

    // 模拟重启：新容器读同一 prefs。
    container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    final restored = container.read(careerControllerProvider);
    expect(restored.active, isNotNull);
    expect(restored.active!.id, activeId);
    expect(restored.active!.currentRound, 1);
    expect(restored.upcoming, hasLength(2));
  });

  test('段位升降联动：积分达阈值自动晋升', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    final notifier = container.read(careerControllerProvider.notifier);
    final t = container
        .read(careerControllerProvider)
        .upcoming
        .firstWhere((t) => t.boardSize == 9);
    notifier.signUp(t.id);

    // 连赢三场得 90 分：18级→升入17级（阈值 stepForRank(0)=100 需100分，不够则再赢）
    notifier.resolveMatch(won: true);
    notifier.resolveMatch(won: true);
    final r = notifier.resolveMatch(won: true);
    expect(r.complete, isTrue);
    final user = container.read(userProfileProvider);
    expect(user.careerPoints, 90);
    expect(user.rankIndex, 0); // 90 < 100，未升级
    expect(user.participations, 1);
  });
}
