// 定式匹配核心（纯 Dart，不依赖 Flutter，便于单测）。
//
// 与离线生成器 `joseki/generator/corner.py` 保持一致：
// - 坐标：19 路，row 0..18 自上而下，col 0..18 自左而右；
// - 角框：每个角为 `size~/2` 的方框（19 路 -> 4 个 9x9 角，中央十字线不属于任何角）；
// - 归一化：把 4 个角都镜像到右上角（TR），角内再对角镜像，取字典序最小者为规范序列；
//   这样任意角 / 任意朝向的同一棋形都会归一成同一个规范串（去重覆盖 8 个对称）。
library;

import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';

/// 一条定式：规范（右上角 TR）坐标序列 + 可回放 SGF + 元信息。
class JosekiEntry {
  const JosekiEntry({
    required this.id,
    required this.moves,
    required this.label,
    required this.sgf,
    this.frequency,
    this.direction = 'ruld',
  });

  final String id;

  /// 规范（右上角 TR 系）SGF 坐标串，如 `['pd','qc',...]`。
  final List<String> moves;
  final String label;

  /// 完整 SGF 文本，可被 `Sgf.parse` -> [SgfGame] 回放。
  final String sgf;
  final int? frequency;
  final String direction;

  factory JosekiEntry.fromJson(Map<String, dynamic> json) => JosekiEntry(
        id: json['id'] as String,
        moves: (json['moves'] as List).cast<String>(),
        label: json['label'] as String? ?? json['id'],
        sgf: json['sgf'] as String,
        frequency: json['frequency'] as int?,
        direction: json['direction'] as String? ?? 'ruld',
      );
}

/// 坐标 / 角部归一化工具（与生成器一致）。
class JosekiCoords {
  JosekiCoords._();

  /// 某点所属角；中央十字线返回 null。
  static String? cornerOf(int row, int col, int size) {
    final k = size ~/ 2;
    final top = row < k;
    final bottom = row >= size - k;
    final left = col < k;
    final right = col >= size - k;
    if (top && left) return 'TL';
    if (top && right) return 'TR';
    if (bottom && left) return 'BL';
    if (bottom && right) return 'BR';
    return null;
  }

  /// 角坐标 -> 右上角（TR）坐标。
  static (int, int) toTr((int, int) p, String corner, int size) {
    switch (corner) {
      case 'TR':
        return p;
      case 'TL':
        return (p.$1, size - 1 - p.$2);
      case 'BR':
        return (size - 1 - p.$1, p.$2);
      default: // BL
        return (size - 1 - p.$1, size - 1 - p.$2);
    }
  }

  /// TR 坐标 -> 反推回指定角坐标（inverse of [toTr]，供预览定位）。
  static (int, int) fromTr((int, int) p, String corner, int size) {
    switch (corner) {
      case 'TR':
        return p;
      case 'TL':
        return (p.$1, size - 1 - p.$2);
      case 'BR':
        return (size - 1 - p.$1, p.$2);
      default: // BL
        return (size - 1 - p.$1, size - 1 - p.$2);
    }
  }

  /// 右上角内的对角镜像（以 row+col=size-1 为轴）。
  static (int, int) anti((int, int) p, int size) =>
      (size - 1 - p.$2, size - 1 - p.$1);

  /// 把一段角部着法（角内坐标）归一化为规范 TR 坐标串。
  static List<String> canonical(List<(int, int)> points, int size) {
    if (points.isEmpty) return const [];
    final corner = cornerOf(points.first.$1, points.first.$2, size) ?? 'TR';
    final tr = [for (final p in points) toTr(p, corner, size)];
    final mir = [for (final p in tr) anti(p, size)];
    final chosen = _lt(tr, mir) ? tr : mir;
    return [for (final p in chosen) GoBoard.sgfCoord(p.$1, p.$2)];
  }

  /// 角框子棋盘（K=size~/2，角点恒在子图本地 (0,0) 左上）的本地坐标 -> 全盘坐标。
  static (int, int) localToBoard(
      String corner, int localRow, int localCol, int size) {
    switch (corner) {
      case 'TL':
        return (localRow, localCol);
      case 'TR':
        return (localRow, size - 1 - localCol);
      case 'BL':
        return (size - 1 - localRow, localCol);
      default: // BR
        return (size - 1 - localRow, size - 1 - localCol);
    }
  }

  /// 全盘坐标 -> 角框子棋盘本地坐标（inverse of [localToBoard]）。
  static (int, int) boardToLocal(
      String corner, int row, int col, int size) {
    switch (corner) {
      case 'TL':
        return (row, col);
      case 'TR':
        return (row, size - 1 - col);
      case 'BL':
        return (size - 1 - row, col);
      default: // BR
        return (size - 1 - row, size - 1 - col);
    }
  }

  /// 扁平比较两个坐标序列（r 优先、其次 c），返回 a<b。
  static bool _lt(List<(int, int)> a, List<(int, int)> b) {
    for (var i = 0; i < a.length; i++) {
      final pa = a[i], pb = b[i];
      if (pa.$1 != pb.$1) return pa.$1 < pb.$1;
      if (pa.$2 != pb.$2) return pa.$2 < pb.$2;
    }
    return false;
  }
}

/// 定式匹配器：对用户当前角部着法（先 [JosekiCoords.canonical]）做前缀识别。
class JosekiMatcher {
  JosekiMatcher(List<JosekiEntry> entries) : _entries = entries;

  final List<JosekiEntry> _entries;

  /// 最少匹配手数（前 1 手就命中时仍会返回，便于引导）。
  static const int minMatch = 1;

  /// 返回按（匹配手数降序, 频率降序）排序的命中项。
  List<JosekiMatch> match(List<String> userMoves, {int limit = 50}) {
    final out = <JosekiMatch>[];
    for (final e in _entries) {
      final lcp = longestCommonPrefix(userMoves, e.moves);
      if (lcp < minMatch) continue;
      out.add(JosekiMatch(e, lcp));
    }
    out.sort((a, b) {
      if (a.matchLen != b.matchLen) return b.matchLen.compareTo(a.matchLen);
      final fa = a.entry.frequency ?? 0, fb = b.entry.frequency ?? 0;
      if (fa != fb) return fb.compareTo(fa);
      return a.entry.id.compareTo(b.entry.id);
    });
    return out.length > limit ? out.take(limit).toList() : out;
  }

  static int longestCommonPrefix(List<String> a, List<String> b) {
    final n = a.length < b.length ? a.length : b.length;
    var i = 0;
    while (i < n && a[i] == b[i]) {
      i++;
    }
    return i;
  }
}

/// 匹配结果：命中的定式 + 已匹配手数。
class JosekiMatch {
  const JosekiMatch(this.entry, this.matchLen);
  final JosekiEntry entry;
  final int matchLen;

  String get summary => '匹配 $matchLen/${entry.moves.length} 手';
}

/// 推荐下一手：规范 TR 坐标 + 归一化概率（0..1）。
class JosekiMoveHint {
  const JosekiMoveHint(this.coord, this.probability);

  /// 规范（右上角 TR 系）SGF 坐标。
  final String coord;

  /// 由命中定式频次加权的归一化概率。
  final double probability;
}

/// 依据当前用户着法（规范串）推荐最高概率的后续点位（默认最多 4 个）。
///
/// - 棋盘为空：按全部定式的首手分布加权；
/// - 已有着法：按命中定式（前缀匹配）的下一手分布加权；
/// - 权重 = 定式频次（缺失按 1）；概率 = 权重 / 总权重。
List<JosekiMoveHint> recommendNext(
  List<JosekiEntry> entries,
  List<String> userMoves, {
  int limit = 4,
}) {
  final weights = <String, double>{};
  var total = 0.0;

  void add(String coord, int? freq) {
    final w = (freq ?? 1).toDouble();
    weights[coord] = (weights[coord] ?? 0) + w;
    total += w;
  }

  if (userMoves.isEmpty) {
    for (final e in entries) {
      if (e.moves.isEmpty) continue;
      add(e.moves.first, e.frequency);
    }
  } else {
    final matched = JosekiMatcher(entries).match(userMoves);
    for (final m in matched) {
      final seq = m.entry.moves;
      if (m.matchLen >= seq.length) continue; // 已完全命中，无下一手
      add(seq[m.matchLen], m.entry.frequency);
    }
  }

  if (total <= 0) return const [];
  final list = weights.entries.toList()
    ..sort((a, b) {
      if (a.value != b.value) return b.value.compareTo(a.value);
      return a.key.compareTo(b.key);
    });
  return [
    for (final e in list.take(limit))
      JosekiMoveHint(e.key, e.value / total),
  ];
}

/// 把规范 TR 坐标序列在指定角内展开成一串棋步（预览用），黑白交替、黑先行。
List<Move> movesInCorner(
    List<String> canonicalMoves, String corner, int size) {
  final moves = <Move>[];
  for (var i = 0; i < canonicalMoves.length; i++) {
    final color = i.isEven ? PlayerColor.black : PlayerColor.white;
    final (r, c) = GoBoard.coordFromSgf(canonicalMoves[i]);
    final (br, bc) = JosekiCoords.fromTr((r, c), corner, size);
    moves.add(Move.point(color, br, bc));
  }
  return moves;
}
