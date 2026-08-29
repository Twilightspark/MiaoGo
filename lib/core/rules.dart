/// 对弈规则：中国（数子）、韩国/日本（数目），含默认贴目与计分方式。
///
/// 此前位于 `storage/settings_store.dart`，为便于 core 与存储层共享迁至此处。
enum GoRule {
  chinese('中国', 7.5, ScoringMethod.area),
  korean('韩国', 6.5, ScoringMethod.territory),
  japanese('日本', 6.5, ScoringMethod.territory);

  const GoRule(this.label, this.defaultKomi, this.scoring);
  final String label;
  final double defaultKomi;
  final ScoringMethod scoring;
}

/// 终局计分方式：数子（中国） / 数目（日韩）。
enum ScoringMethod { area, territory }
