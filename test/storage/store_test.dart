import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/rank.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/storage/settings_store.dart';
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

  group('UserStore', () {
    test('默认档案：18级 / 0 积分 / 无头像 / 统计归零', () async {
      final container = await makeContainer();
      final profile = container.read(userProfileProvider);
      expect(profile.name, '棋手');
      expect(profile.avatarPath, '');
      expect(profile.rankIndex, RankSystem.kDefaultRankIndex);
      expect(profile.rankIndex, 0);
      expect(profile.careerPoints, 0);
      expect(profile.totalGames, 0);
      expect(profile.participations, 0);
      expect(profile.championships, 0);
      expect(profile.winRate, 0);
    });

    test('更新名称', () async {
      final container = await makeContainer();
      container.read(userProfileProvider.notifier).updateName('喵棋大师');
      expect(container.read(userProfileProvider).name, '喵棋大师');
    });

    test('空名称不生效', () async {
      final container = await makeContainer();
      container.read(userProfileProvider.notifier).updateName('   ');
      expect(container.read(userProfileProvider).name, '棋手');
    });

    test('更新头像路径', () async {
      final container = await makeContainer();
      container.read(userProfileProvider.notifier).updateAvatar('/tmp/avatar.png');
      expect(container.read(userProfileProvider).avatarPath, '/tmp/avatar.png');
    });

    test('记录参赛结果：冠军计数', () async {
      final container = await makeContainer();
      final notifier = container.read(userProfileProvider.notifier);
      notifier.recordParticipation(champion: true);
      notifier.recordParticipation(champion: false);
      final after = container.read(userProfileProvider);
      expect(after.participations, 2);
      expect(after.championships, 1);
    });

    test('胜率计算', () async {
      final container = await makeContainer();
      final notifier = container.read(userProfileProvider.notifier);
      notifier.recordCareerResult(won: true, pointsDelta: 20);
      notifier.recordCareerResult(won: false, pointsDelta: 5);
      final after = container.read(userProfileProvider);
      expect(after.winRate, closeTo(0.5, 0.001));
    });

    test('生涯对局结算：积分+段位联动', () async {
      final container = await makeContainer();
      final notifier = container.read(userProfileProvider.notifier);
      final before = container.read(userProfileProvider);
      notifier.recordCareerResult(won: true, pointsDelta: 20);
      final after = container.read(userProfileProvider);
      expect(after.totalGames, before.totalGames + 1);
      expect(after.wins, before.wins + 1);
      expect(after.losses, before.losses);
      expect(after.careerPoints, before.careerPoints + 20);
      expect(after.rankIndex, before.rankIndex);
    });

    test('持久化往返：重建容器后数据保留', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c1 = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      c1.read(userProfileProvider.notifier).updateName('往返测试');
      c1.read(userProfileProvider.notifier).updateAvatar('/data/avatar.png');
      c1.read(userProfileProvider.notifier)
          .recordCareerResult(won: true, pointsDelta: 100);
      c1.read(userProfileProvider.notifier).recordParticipation(champion: true);
      c1.dispose();

      final c2 = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(c2.dispose);
      final restored = c2.read(userProfileProvider);
      expect(restored.name, '往返测试');
      expect(restored.avatarPath, '/data/avatar.png');
      expect(restored.wins, 1);
      expect(restored.participations, 1);
      expect(restored.championships, 1);
      expect(restored.careerPoints, 100);
    });

    test('重生重置为默认档案', () async {
      final container = await makeContainer();
      final notifier = container.read(userProfileProvider.notifier);
      notifier.updateName('大师');
      notifier.updateAvatar('/data/a.png');
      notifier.recordCareerResult(won: true, pointsDelta: 300);
      notifier.recordParticipation(champion: true);
      notifier.reset();
      final after = container.read(userProfileProvider);
      expect(after.name, '棋手');
      expect(after.avatarPath, '');
      expect(after.rankIndex, 0);
      expect(after.careerPoints, 0);
      expect(after.totalGames, 0);
      expect(after.participations, 0);
      expect(after.championships, 0);
    });
  });

  group('SettingsStore', () {
    test('默认设置：9 路 / 中国规则 / 7.5 贴目', () async {
      final container = await makeContainer();
      final settings = container.read(settingsProvider);
      expect(settings.boardSize, BoardSize.nine);
      expect(settings.rule, GoRule.chinese);
      expect(settings.komi, 7.5);
      expect(settings.soundEnabled, isTrue);
    });

    test('切换规则联动贴目', () async {
      final container = await makeContainer();
      container.read(settingsProvider.notifier).setRule(GoRule.japanese);
      final settings = container.read(settingsProvider);
      expect(settings.rule, GoRule.japanese);
      expect(settings.komi, 6.5);
    });

    test('设置棋盘大小', () async {
      final container = await makeContainer();
      container.read(settingsProvider.notifier).setBoardSize(BoardSize.nineteen);
      expect(container.read(settingsProvider).boardSize, BoardSize.nineteen);
    });

    test('恢复默认', () async {
      final container = await makeContainer();
      final notifier = container.read(settingsProvider.notifier);
      notifier.setRule(GoRule.korean);
      notifier.setBoardSize(BoardSize.thirteen);
      notifier.reset();
      expect(container.read(settingsProvider).rule, GoRule.chinese);
      expect(container.read(settingsProvider).boardSize, BoardSize.nine);
    });

    test('持久化往返', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c1 = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      c1.read(settingsProvider.notifier).setRule(GoRule.korean);
      c1.dispose();

      final c2 = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(c2.dispose);
      final restored = c2.read(settingsProvider);
      expect(restored.rule, GoRule.korean);
      expect(restored.komi, 6.5);
    });
  });
}
