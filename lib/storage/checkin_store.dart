import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/storage/user_store.dart';

/// 打卡状态：记录「完成每日一题」的日期集合（`YYYY-MM-DD`）。
///
/// 打卡天数 = [completedDays] 的集合大小。每日 5 题全部解出即记一次打卡。
class CheckinState {
  const CheckinState({required this.completedDays});

  const CheckinState.empty() : completedDays = const <String>{};

  final Set<String> completedDays;

  /// 累计打卡天数。
  int get count => completedDays.length;

  Map<String, dynamic> toJson() => {
        'completedDays': completedDays.toList(),
      };

  factory CheckinState.fromJson(Map<String, dynamic> json) => CheckinState(
        completedDays: (json['completedDays'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toSet(),
      );
}

/// 打卡（每日一题完成）持久化。
class CheckinStore extends Notifier<CheckinState> {
  static const _key = 'checkin_days';

  @override
  CheckinState build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_key);
    if (raw == null) return const CheckinState.empty();
    try {
      return CheckinState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const CheckinState.empty();
    }
  }

  /// 当日已完成每日一题：把今天标记为打卡（幂等，不重复计）。
  void markToday({DateTime? now}) {
    final key = _dateKey(now ?? DateTime.now());
    if (state.completedDays.contains(key)) return;
    state = CheckinState(completedDays: {...state.completedDays, key});
    _persist();
  }

  /// 同步当日进度：仅当 [solved] >= [total] 时记打卡（幂等）。
  void syncDaily({required int solved, required int total, DateTime? now}) {
    if (total > 0 && solved >= total) markToday(now: now);
  }

  /// 清空打卡记录（重生用）。
  void reset() {
    state = const CheckinState.empty();
    _persist();
  }

  void _persist() {
    ref.read(sharedPreferencesProvider).setString(
          _key,
          jsonEncode(state.toJson()),
        );
  }
}

final checkinStoreProvider =
    NotifierProvider<CheckinStore, CheckinState>(CheckinStore.new);

/// 日期键：`YYYY-MM-DD`（本地日期）。
String _dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
