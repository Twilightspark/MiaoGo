import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/rank.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/game/career.dart';

void main() {
  CareerTournament build({int playerRank = 0, int? seed}) =>
      createTournament(
        boardSize: 9,
        rule: GoRule.chinese,
        komi: 7.5,
        playerName: '棋手',
        playerRank: playerRank,
        random: math.Random(seed ?? 42),
      );

  group('大赛生成', () {
    test('8 人（玩家 + 7 AI），玩家随机种子位', () {
      final t = build();
      expect(t.players, hasLength(kTournamentPlayers));
      expect(t.players.where((p) => p.isPlayer), hasLength(1));
      expect(t.player!.id, kPlayerId);
      expect(t.player!.name, '棋手');
    });

    test('AI 段位在玩家 ±2 档（夹紧 0..26）', () {
      final t = build(playerRank: 26); // 9段
      for (final p in t.players.where((p) => !p.isPlayer)) {
        expect(p.rankIndex, inInclusiveRange(24, 26));
      }
      final t2 = build(playerRank: 0); // 18级
      for (final p in t2.players.where((p) => !p.isPlayer)) {
        expect(p.rankIndex, inInclusiveRange(0, 2));
      }
    });

    test('AI 名字非空且不重复（含不与玩家同名）', () {
      for (var seed = 0; seed < 20; seed++) {
        final t = build(seed: seed);
        final names = t.players.map((p) => p.name).toList();
        expect(names.toSet().length, names.length, reason: 'seed=$seed 重名');
        expect(names.every((n) => n.isNotEmpty), isTrue);
      }
    });

    test('7 场：8强4 + 4强2 + 决赛1；8强已配对未决', () {
      final t = build();
      expect(t.matches, hasLength(7));
      expect(t.matchesInRound(0), hasLength(4));
      expect(t.matchesInRound(1), hasLength(2));
      expect(t.matchesInRound(2), hasLength(1));
      for (final m in t.matchesInRound(0)) {
        expect(m.playerAId, isNotEmpty);
        expect(m.playerBId, isNotEmpty);
        expect(m.decided, isFalse);
      }
      for (final m in t.matchesInRound(1)) {
        expect(m.playerAId, isEmpty); // 尚未配对
      }
      expect(t.currentRound, 0);
    });
  });

  group('赛程推进', () {
    test('8强获胜：同轮其余场次自动模拟，晋级4强并配对', () {
      final t = build();
      final r = advanceAfterPlayerMatch(t, playerWon: true, random: math.Random(1));
      expect(r.round, 1);
      expect(r.playerWon, isTrue);
      expect(r.complete, isFalse);

      final qf = t.matchesInRound(0);
      final playerMatch = qf.firstWhere((m) => m.involves(kPlayerId));
      expect(playerMatch.winnerId, kPlayerId);
      expect(qf.every((m) => m.decided), isTrue); // 同轮全部决出

      final sf = t.matchesInRound(1);
      expect(sf.every((m) => m.playerAId.isNotEmpty && m.playerBId.isNotEmpty),
          isTrue);
      expect(t.playerMatch, isNotNull);
      expect(t.playerMatch!.roundIndex, 1);
      expect(t.currentRound, 1);
    });

    test('8强失利：自动模拟全部剩余赛程并结算，名次八强', () {
      final t = build();
      final r = advanceAfterPlayerMatch(t, playerWon: false, random: math.Random(1));
      expect(r.complete, isTrue);
      expect(r.playerWon, isFalse);
      expect(t.status, CareerTournamentStatus.completed);
      expect(t.championId, isNotNull);
      expect(t.matches.every((m) => m.decided), isTrue);
      expect(t.placementOf(kPlayerId), 5);
      expect(t.placementOf(t.championId!), 1);
    });

    test('全胜夺冠：三连胜 → 冠军，积分 3×20+30=90', () {
      final t = build();
      advanceAfterPlayerMatch(t, playerWon: true, random: math.Random(1));
      advanceAfterPlayerMatch(t, playerWon: true, random: math.Random(2));
      final r = advanceAfterPlayerMatch(t, playerWon: true, random: math.Random(3));
      expect(r.round, 2);
      expect(r.complete, isTrue);
      expect(r.champion, isTrue);
      expect(t.championId, kPlayerId);
      expect(t.placementOf(kPlayerId), 1);
      expect(t.playerEarnedPoints(), 90);
      expect(t.status, CareerTournamentStatus.completed);
    });

    test('亚军：决赛失利 → 名次2', () {
      final t = build();
      advanceAfterPlayerMatch(t, playerWon: true, random: math.Random(1));
      advanceAfterPlayerMatch(t, playerWon: true, random: math.Random(2));
      final r = advanceAfterPlayerMatch(t, playerWon: false, random: math.Random(3));
      expect(r.complete, isTrue);
      expect(t.placementOf(kPlayerId), 2);
      expect(t.championId, isNotNull);
    });
  });

  group('序列化', () {
    test('大赛 JSON 往返一致', () {
      final t = build(playerRank: 8);
      advanceAfterPlayerMatch(t, playerWon: true, random: math.Random(1));
      final t2 = CareerTournament.fromJson(t.toJson());
      expect(t2.id, t.id);
      expect(t2.name, t.name);
      expect(t2.boardSize, t.boardSize);
      expect(t2.rule, t.rule);
      expect(t2.komi, t.komi);
      expect(t2.players, hasLength(8));
      expect(t2.player!.name, t.player!.name);
      expect(t2.matches, hasLength(7));
      expect(t2.matchesInRound(0).first.playerAId,
          t.matchesInRound(0).first.playerAId);
      expect(t2.matchesInRound(0).first.winnerId,
          t.matchesInRound(0).first.winnerId);
      expect(t2.championId, t.championId);
      expect(t2.status, t.status);
    });

    test('历史成绩 JSON 往返一致', () {
      final r = CareerResult(
        id: 'h1',
        tournamentName: '桃李杯',
        boardSize: 13,
        date: DateTime(2026, 1, 1),
        placement: 1,
        points: 90,
        champion: true,
      );
      final r2 = CareerResult.fromJson(r.toJson());
      expect(r2.id, r.id);
      expect(r2.tournamentName, r.tournamentName);
      expect(r2.boardSize, r.boardSize);
      expect(r2.date, r.date);
      expect(r2.placement, r.placement);
      expect(r2.points, r.points);
      expect(r2.champion, r.champion);
    });
  });

  test('名次文本', () {
    expect(careerPlacementLabel(0), '退赛');
    expect(careerPlacementLabel(1), '冠军');
    expect(careerPlacementLabel(2), '亚军');
    expect(careerPlacementLabel(3), '四强');
    expect(careerPlacementLabel(5), '八强');
  });

  test('段位映射常量一致性', () {
    expect(RankSystem.kNumKyuRanks, 18);
  });
}
