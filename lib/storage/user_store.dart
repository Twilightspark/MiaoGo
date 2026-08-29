import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/core/rank.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 在 `main()` 中注入的 SharedPreferences 实例。
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider 必须在 main() 中 override');
});

/// 用户档案：名称、头像、段位、大赛积分、生涯统计。
class UserProfile {
  const UserProfile({
    required this.name,
    required this.avatarPath,
    required this.rankIndex,
    required this.careerPoints,
    required this.wins,
    required this.losses,
    required this.totalGames,
    required this.participations,
    required this.championships,
  });

  factory UserProfile.defaults() => UserProfile(
        name: '棋手',
        avatarPath: '',
        rankIndex: RankSystem.kDefaultRankIndex,
        careerPoints: RankSystem.pointsForRank(RankSystem.kDefaultRankIndex),
        wins: 0,
        losses: 0,
        totalGames: 0,
        participations: 0,
        championships: 0,
      );

  final String name;

  /// 头像本地文件路径；空串表示未设置（显示姓名首字）。
  final String avatarPath;
  final int rankIndex;
  final int careerPoints;
  final int wins;
  final int losses;
  final int totalGames;

  /// 参赛次数。
  final int participations;

  /// 冠军次数。
  final int championships;

  /// 胜率（0~1，无对局时为 0）。
  double get winRate => totalGames == 0 ? 0 : wins / totalGames;

  UserProfile copyWith({
    String? name,
    String? avatarPath,
    int? rankIndex,
    int? careerPoints,
    int? wins,
    int? losses,
    int? totalGames,
    int? participations,
    int? championships,
  }) {
    return UserProfile(
      name: name ?? this.name,
      avatarPath: avatarPath ?? this.avatarPath,
      rankIndex: rankIndex ?? this.rankIndex,
      careerPoints: careerPoints ?? this.careerPoints,
      wins: wins ?? this.wins,
      losses: losses ?? this.losses,
      totalGames: totalGames ?? this.totalGames,
      participations: participations ?? this.participations,
      championships: championships ?? this.championships,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'avatarPath': avatarPath,
        'rankIndex': rankIndex,
        'careerPoints': careerPoints,
        'wins': wins,
        'losses': losses,
        'totalGames': totalGames,
        'participations': participations,
        'championships': championships,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: json['name'] as String? ?? '棋手',
      avatarPath: json['avatarPath'] as String? ?? '',
      rankIndex: (json['rankIndex'] as num?)?.toInt() ??
          RankSystem.kDefaultRankIndex,
      careerPoints: (json['careerPoints'] as num?)?.toInt() ?? 0,
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      losses: (json['losses'] as num?)?.toInt() ?? 0,
      totalGames: (json['totalGames'] as num?)?.toInt() ?? 0,
      participations: (json['participations'] as num?)?.toInt() ?? 0,
      championships: (json['championships'] as num?)?.toInt() ?? 0,
    );
  }
}

class UserStore extends Notifier<UserProfile> {
  static const _key = 'user_profile';

  @override
  UserProfile build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_key);
    if (raw == null) return UserProfile.defaults();
    try {
      return UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return UserProfile.defaults();
    }
  }

  void _persist(UserProfile profile) {
    state = profile;
    ref
        .read(sharedPreferencesProvider)
        .setString(_key, jsonEncode(profile.toJson()));
  }

  void updateName(String name) {
    if (name.trim().isEmpty) return;
    _persist(state.copyWith(name: name.trim()));
  }

  /// 更新头像本地路径（空串清除头像）。
  void updateAvatar(String path) =>
      _persist(state.copyWith(avatarPath: path));

  /// 记录一次大赛参赛结果（供 P3 生涯模式调用）。
  void recordParticipation({required bool champion}) {
    _persist(state.copyWith(
      participations: state.participations + 1,
      championships: state.championships + (champion ? 1 : 0),
    ));
  }

  /// 赛事完结统一结算（P3）：积分 + 胜负局数 + 参赛/冠军统计 + 段位联动。
  ///
  /// 大赛按「胜 +20 / 负 +5、冠军 +30」在赛事完结时一次性结算
  /// （退赛不调用本方法 = 无任何积分奖励）。
  void settleTournament({
    required int wins,
    required int losses,
    required int points,
    required bool champion,
  }) {
    final reconciled =
        RankSystem.reconcile(state.careerPoints + points, state.rankIndex);
    _persist(state.copyWith(
      rankIndex: reconciled.rank,
      careerPoints: reconciled.points,
      wins: state.wins + wins,
      losses: state.losses + losses,
      totalGames: state.totalGames + wins + losses,
      participations: state.participations + 1,
      championships: state.championships + (champion ? 1 : 0),
    ));
  }

  void reset() => _persist(UserProfile.defaults());

  /// 记录一局生涯对局结果，按大赛积分结算并联动段位升降。
  void recordCareerResult({required bool won, required int pointsDelta}) {
    final reconciled = RankSystem.reconcile(
      state.careerPoints + pointsDelta,
      state.rankIndex,
    );
    _persist(state.copyWith(
      rankIndex: reconciled.rank,
      careerPoints: reconciled.points,
      wins: state.wins + (won ? 1 : 0),
      losses: state.losses + (won ? 0 : 1),
      totalGames: state.totalGames + 1,
    ));
  }
}

final userProfileProvider =
    NotifierProvider<UserStore, UserProfile>(UserStore.new);
