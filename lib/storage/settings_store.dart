import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/storage/user_store.dart';

/// 棋盘尺寸。
enum BoardSize {
  nine(9),
  thirteen(13),
  nineteen(19);

  const BoardSize(this.size);
  final int size;
}

/// 落子方式：双击落子（双击棋盘同一点落子） / 确认落子（选点后点落子按钮）。
enum MoveStyle {
  doubleTap('双击落子'),
  confirm('确认落子');

  const MoveStyle(this.label);
  final String label;
}

/// 应用设置：棋盘/棋子风格、棋盘大小、对弈规则、贴目、音效、落子方式。
class AppSettings {
  const AppSettings({
    required this.boardStyle,
    required this.stoneStyle,
    required this.boardSize,
    required this.rule,
    required this.komi,
    required this.soundEnabled,
    required this.moveStyle,
  });

  factory AppSettings.defaults() => AppSettings(
        boardStyle: 'wood',
        stoneStyle: 'goe',
        boardSize: BoardSize.nine,
        rule: GoRule.chinese,
        komi: GoRule.chinese.defaultKomi,
        soundEnabled: true,
        moveStyle: MoveStyle.confirm,
      );

  final String boardStyle;
  final String stoneStyle;
  final BoardSize boardSize;
  final GoRule rule;
  final double komi;
  final bool soundEnabled;
  final MoveStyle moveStyle;

  AppSettings copyWith({
    String? boardStyle,
    String? stoneStyle,
    BoardSize? boardSize,
    GoRule? rule,
    double? komi,
    bool? soundEnabled,
    MoveStyle? moveStyle,
  }) {
    return AppSettings(
      boardStyle: boardStyle ?? this.boardStyle,
      stoneStyle: stoneStyle ?? this.stoneStyle,
      boardSize: boardSize ?? this.boardSize,
      rule: rule ?? this.rule,
      komi: komi ?? this.komi,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      moveStyle: moveStyle ?? this.moveStyle,
    );
  }

  Map<String, dynamic> toJson() => {
        'boardStyle': boardStyle,
        'stoneStyle': stoneStyle,
        'boardSize': boardSize.name,
        'rule': rule.name,
        'komi': komi,
        'soundEnabled': soundEnabled,
        'moveStyle': moveStyle.name,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      boardStyle: json['boardStyle'] as String? ?? 'wood',
      stoneStyle: json['stoneStyle'] as String? ?? 'goe',
      boardSize: BoardSize.values
          .firstWhere((e) => e.name == json['boardSize'],
              orElse: () => BoardSize.nine),
      rule: GoRule.values.firstWhere((e) => e.name == json['rule'],
          orElse: () => GoRule.chinese),
      komi: (json['komi'] as num?)?.toDouble() ??
          GoRule.chinese.defaultKomi,
      soundEnabled: json['soundEnabled'] as bool? ?? true,
      moveStyle: MoveStyle.values.firstWhere((e) => e.name == json['moveStyle'],
          orElse: () => MoveStyle.confirm),
    );
  }
}

class SettingsStore extends Notifier<AppSettings> {
  static const _key = 'app_settings';

  @override
  AppSettings build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_key);
    if (raw == null) return AppSettings.defaults();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AppSettings.defaults();
    }
  }

  void _persist(AppSettings settings) {
    state = settings;
    ref
        .read(sharedPreferencesProvider)
        .setString(_key, jsonEncode(settings.toJson()));
  }

  void setBoardSize(BoardSize size) => _persist(state.copyWith(boardSize: size));

  /// 切换规则并联动默认贴目。
  void setRule(GoRule rule) =>
      _persist(state.copyWith(rule: rule, komi: rule.defaultKomi));

  void setKomi(double komi) => _persist(state.copyWith(komi: komi));

  void setBoardStyle(String style) =>
      _persist(state.copyWith(boardStyle: style));

  void setStoneStyle(String style) =>
      _persist(state.copyWith(stoneStyle: style));

  void setSoundEnabled(bool enabled) =>
      _persist(state.copyWith(soundEnabled: enabled));

  /// 切换落子方式（双击 / 确认）。
  void setMoveStyle(MoveStyle style) =>
      _persist(state.copyWith(moveStyle: style));

  void reset() => _persist(AppSettings.defaults());
}

final settingsProvider =
    NotifierProvider<SettingsStore, AppSettings>(SettingsStore.new);
