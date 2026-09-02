import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/storage/user_store.dart';

/// 单题进度。
class ProblemStatus {
  const ProblemStatus({required this.solved, required this.attempts});

  final bool solved;

  /// 累计尝试次数（答错计数）。
  final int attempts;

  Map<String, dynamic> toJson() => {'solved': solved, 'attempts': attempts};

  factory ProblemStatus.fromJson(Map<String, dynamic> json) => ProblemStatus(
        solved: json['solved'] as bool? ?? false,
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      );
}

/// 死活题进度：`problemId → 完成状态 + 尝试次数`，prefs 持久化。
class ProblemStore extends Notifier<Map<String, ProblemStatus>> {
  static const _key = 'problem_progress';

  @override
  Map<String, ProblemStatus> build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_key);
    if (raw == null) return const {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(
          k,
          ProblemStatus.fromJson(
              (v as Map).cast<String, dynamic>())));
    } catch (_) {
      return const {};
    }
  }

  /// 记录一次作答。
  void recordAttempt(String problemId, {required bool solved, int attempts = 1}) {
    final prev = state[problemId] ?? const ProblemStatus(solved: false, attempts: 0);
    final merged = ProblemStatus(
      solved: solved || prev.solved,
      attempts: prev.attempts + attempts,
    );
    state = {...state, problemId: merged};
    _persist();
  }

  /// 某题是否已完成。
  bool isSolved(String problemId) => state[problemId]?.solved ?? false;

  /// 清空全部做题进度（重生用）。
  void reset() {
    state = const {};
    _persist();
  }

  void _persist() {
    ref.read(sharedPreferencesProvider).setString(
          _key,
          jsonEncode(state.map((k, v) => MapEntry(k, v.toJson()))),
        );
  }
}

final problemStoreProvider =
    NotifierProvider<ProblemStore, Map<String, ProblemStatus>>(ProblemStore.new);
