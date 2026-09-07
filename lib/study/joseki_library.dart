import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/core/joseki.dart';
import 'package:miaogo/core/sgf.dart';

/// 定式库：从打包资产 `assets/joseki/joseki.json` 加载。
class JosekiLibrary {
  JosekiLibrary(this.entries, this.matcher);

  final List<JosekiEntry> entries;
  final JosekiMatcher matcher;

  static Future<JosekiLibrary> load() async {
    final data = await rootBundle.loadString('assets/joseki/joseki.json');
    final map = jsonDecode(data) as Map<String, dynamic>;
    final list = (map['joseki_list'] as List).cast<Map<String, dynamic>>();
    final entries = <JosekiEntry>[];
    for (final m in list) {
      entries.add(JosekiEntry.fromJson(m));
    }
    // 校验：跳过无法解析 SGF 的条目。
    entries.removeWhere((e) {
      try {
        Sgf.parse(e.sgf);
        return false;
      } on FormatException {
        return true;
      }
    });
    return JosekiLibrary(entries, JosekiMatcher(entries));
  }
}

final josekiLibraryProvider =
    FutureProvider<JosekiLibrary>((ref) => JosekiLibrary.load());
