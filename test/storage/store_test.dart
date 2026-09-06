import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/rank.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/game/career.dart';
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

    test('胜率计算（快速对弈即时结算）', () async {
      final container = await makeContainer();
      final notifier = container.read(userProfileProvider.notifier);
      notifier.applyQuickMatch(
        won: true,
        draw: false,
        pointsDelta:
            CareerPoints.quickDelta(won: true, playerRank: 0, opponentRank: 0),
      );
      notifier.applyQuickMatch(
        won: false,
        draw: false,
        pointsDelta:
            CareerPoints.quickDelta(won: false, playerRank: 0, opponentRank: 0),
      );
      final after = container.read(userProfileProvider);
      expect(after.careerPoints, 2); // +4 再 −2
      expect(after.totalGames, 2);
      expect(after.wins, 1);
      expect(after.losses, 1);
      expect(after.winRate, closeTo(0.5, 0.001));
    });

    test('快速对弈扣分可降级：连胜升入 17级，连输跌回 18级', () async {
      final container = await makeContainer();
      final notifier = container.read(userProfileProvider.notifier);
      // 同档 +4 ×3 → 12 ≥ 10 升入 17级。
      for (var i = 0; i < 3; i++) {
        notifier.applyQuickMatch(
          won: true,
          draw: false,
          pointsDelta:
              CareerPoints.quickDelta(won: true, playerRank: 0, opponentRank: 0),
        );
      }
      var after = container.read(userProfileProvider);
      expect(after.careerPoints, 12);
      expect(after.rankIndex, 1);
      // 同档 −2 ×3 → 6 < 10 跌破 17级底线，跌回 18级。
      for (var i = 0; i < 3; i++) {
        notifier.applyQuickMatch(
          won: false,
          draw: false,
          pointsDelta:
              CareerPoints.quickDelta(won: false, playerRank: 0, opponentRank: 0),
        );
      }
      after = container.read(userProfileProvider);
      expect(after.careerPoints, 6);
      expect(after.rankIndex, 0);
    });

    test('和棋：计一局但不增减积分', () async {
      final container = await makeContainer();
      final notifier = container.read(userProfileProvider.notifier);
      notifier.applyQuickMatch(won: false, draw: true, pointsDelta: 0);
      final after = container.read(userProfileProvider);
      expect(after.totalGames, 1);
      expect(after.wins, 0);
      expect(after.losses, 0);
      expect(after.careerPoints, 0);
      expect(after.rankIndex, 0);
    });

    test('大赛完结统一结算：冠军 +10 升至 17级', () async {
      final container = await makeContainer();
      final notifier = container.read(userProfileProvider.notifier);
      notifier.settleTournament(
        wins: 3,
        losses: 0,
        points: CareerPoints.tournamentReward(
            placement: 1, topOpponentRank: 0), // 冠军 X=10
        champion: true,
      );
      final after = container.read(userProfileProvider);
      expect(after.careerPoints, 10);
      expect(after.rankIndex, 1);
      expect(after.totalGames, 3);
      expect(after.wins, 3);
      expect(after.participations, 1);
      expect(after.championships, 1);
    });

    test('大赛完结统一结算：八强 0 分只计负局', () async {
      final container = await makeContainer();
      final notifier = container.read(userProfileProvider.notifier);
      notifier.settleTournament(
        wins: 0,
        losses: 1,
        points: 0, // 八强无积分
        champion: false,
      );
      final after = container.read(userProfileProvider);
      expect(after.careerPoints, 0);
      expect(after.rankIndex, 0);
      expect(after.losses, 1);
      expect(after.participations, 1);
      expect(after.championships, 0);
    });

    test('持久化往返：重建容器后数据保留', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c1 = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      c1.read(userProfileProvider.notifier).updateName('往返测试');
      c1.read(userProfileProvider.notifier).updateAvatar('/data/avatar.png');
      c1.read(userProfileProvider.notifier).applyQuickMatch(
            won: true,
            draw: false,
            pointsDelta:
                CareerPoints.quickDelta(won: true, playerRank: 0, opponentRank: 0),
          );
      c1.read(userProfileProvider.notifier).recordParticipation(champion: true);
      c1.dispose();

      final c2 = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(c2.dispose);
      final restored = c2.read(userProfileProvider);
      expect(restored.name, '往返测试');
      expect(restored.avatarPath, '/data/avatar.png');
      expect(restored.wins, 1);
      expect(restored.totalGames, 1);
      expect(restored.participations, 1);
      expect(restored.championships, 1);
      expect(restored.careerPoints, 4);
      expect(restored.rankIndex, 0);
    });

    test('重生重置为默认档案', () async {
      final container = await makeContainer();
      final notifier = container.read(userProfileProvider.notifier);
      notifier.updateName('大师');
      notifier.updateAvatar('/data/a.png');
      notifier.applyQuickMatch(
        won: true,
        draw: false,
        pointsDelta:
            CareerPoints.quickDelta(won: true, playerRank: 0, opponentRank: 0),
      );
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
      expect(settings.moveStyle, MoveStyle.confirm);
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

    test('设置落子方式', () async {
      final container = await makeContainer();
      container.read(settingsProvider.notifier).setMoveStyle(MoveStyle.doubleTap);
      expect(container.read(settingsProvider).moveStyle, MoveStyle.doubleTap);
    });

    test('恢复默认', () async {
      final container = await makeContainer();
      final notifier = container.read(settingsProvider.notifier);
      notifier.setRule(GoRule.korean);
      notifier.setBoardSize(BoardSize.thirteen);
      notifier.setMoveStyle(MoveStyle.doubleTap);
      notifier.reset();
      expect(container.read(settingsProvider).rule, GoRule.chinese);
      expect(container.read(settingsProvider).boardSize, BoardSize.nine);
      expect(container.read(settingsProvider).moveStyle, MoveStyle.confirm);
    });

    test('持久化往返', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c1 = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      c1.read(settingsProvider.notifier).setRule(GoRule.korean);
      c1.read(settingsProvider.notifier).setMoveStyle(MoveStyle.doubleTap);
      c1.dispose();

      final c2 = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(c2.dispose);
      final restored = c2.read(settingsProvider);
      expect(restored.rule, GoRule.korean);
      expect(restored.komi, 6.5);
      expect(restored.moveStyle, MoveStyle.doubleTap);
    });
  });
}
