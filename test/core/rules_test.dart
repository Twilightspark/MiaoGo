import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/rules.dart';

void main() {
  test('三规则默认贴目', () {
    expect(GoRule.chinese.label, '中国');
    expect(GoRule.chinese.defaultKomi, 7.5);
    expect(GoRule.korean.defaultKomi, 6.5);
    expect(GoRule.japanese.defaultKomi, 6.5);
  });

  test('计分方式：中国数子，韩日数目', () {
    expect(GoRule.chinese.scoring, ScoringMethod.area);
    expect(GoRule.korean.scoring, ScoringMethod.territory);
    expect(GoRule.japanese.scoring, ScoringMethod.territory);
  });
}
