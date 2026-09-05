import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/game/career.dart';

void main() {
  test('CareerNames.aiPlayerName 生成非空竞赛风格姓名', () {
    final rng = Random(7);
    for (var i = 0; i < 20; i++) {
      final name = CareerNames.aiPlayerName(rng);
      expect(name, isNotEmpty);
      expect(name.length >= 2, isTrue,
          reason: '名字至少 2 字符（$name）');
    }
  });
}
