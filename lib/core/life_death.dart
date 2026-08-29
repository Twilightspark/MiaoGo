import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';

/// 棋串死活状态。
enum GroupStatus {
  /// 活棋：无条件活（两眼/大眼）或尚有外气（未定型，保守按活处理）。
  alive,

  /// 死子：被围且无法做出两眼，终局时移除并计为对方俘虏。
  dead,

  /// 双活（seki）：与对方互不捕获，保留在盘上；其"眼"在数目法中不计分。
  seki,
}

/// 单个棋串（同色连通块）及其气。
class GoGroup {
  GoGroup({
    required this.color,
    required this.stones,
    required this.liberties,
  });

  final PlayerColor color;

  /// 棋串落子点（以 `row * 64 + col` 编码）。
  final Set<int> stones;

  /// 棋串气（空点，以 `row * 64 + col` 编码，去重）。
  final Set<int> liberties;

  int get size => stones.length;
}

/// 空白连通区。
class _EmptyRegion {
  _EmptyRegion(this.points);

  final Set<int> points;

  /// 边界棋串的编码键（取该串首子编码）。
  final Set<int> borderingChains = {};

  /// 边界颜色：仅单色时非空（此时该区域是此色的候选"眼"）。
  PlayerColor? color;
}

/// 死活分析结果。
class LifeDeathResult {
  LifeDeathResult({
    required this.groupStatus,
    required this.deadPoints,
    required this.sekiPoints,
    required this.sekiEyes,
  });

  /// 每个棋串首子编码 → 状态。
  final Map<int, GroupStatus> groupStatus;

  /// 死子落点（终局移除，计对方俘虏）。
  final Set<int> deadPoints;

  /// 双活棋串落点（保留在盘上）。
  final Set<int> sekiPoints;

  /// 双活棋串的"眼"（空区，数目法不计分）。
  final List<Set<int>> sekiEyes;

  /// 查询 (row,col) 处棋串的死活状态；空点返回 null。
  GroupStatus? statusOf(GoBoard board, int row, int col) {
    if (board.at(row, col) == null) return null;
    final k = _key(row, col);
    if (deadPoints.contains(k)) return GroupStatus.dead;
    if (sekiPoints.contains(k)) return GroupStatus.seki;
    return GroupStatus.alive;
  }
}

int _key(int r, int c) => r * 64 + c;
(int, int) _rc(int k) => (k ~/ 64, k % 64);

/// 判定 (row,col) 是否邻接某色棋子。
bool _adjacentTo(GoBoard board, int row, int col, PlayerColor color) {
  for (final (dr, dc) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
    final nr = row + dr, nc = col + dc;
    if (board.inBounds(nr, nc) && board.at(nr, nc) == color) return true;
  }
  return false;
}

/// 收集全部棋串。
List<GoGroup> _collectGroups(GoBoard board) {
  final groups = <GoGroup>[];
  final visited = <int>{};
  for (var r = 0; r < board.size; r++) {
    for (var c = 0; c < board.size; c++) {
      final color = board.at(r, c);
      if (color == null || visited.contains(_key(r, c))) continue;
      final stones = <int>{};
      final liberties = <int>{};
      final stack = <int>[_key(r, c)];
      visited.add(_key(r, c));
      while (stack.isNotEmpty) {
        final k = stack.removeLast();
        stones.add(k);
        final (cr, cc) = _rc(k);
        for (final (dr, dc) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nr = cr + dr, nc = cc + dc;
          if (!board.inBounds(nr, nc)) continue;
          final cell = board.at(nr, nc);
          if (cell == null) {
            liberties.add(_key(nr, nc));
          } else if (cell == color && visited.add(_key(nr, nc))) {
            stack.add(_key(nr, nc));
          }
        }
      }
      groups.add(GoGroup(color: color, stones: stones, liberties: liberties));
    }
  }
  return groups;
}

/// 收集空白连通区（含边界颜色与边界棋串）。
List<_EmptyRegion> _collectEmptyRegions(GoBoard board,
    Map<int, GoGroup> chainByPoint) {
  final regions = <_EmptyRegion>[];
  final visited = <int>{};
  for (var r = 0; r < board.size; r++) {
    for (var c = 0; c < board.size; c++) {
      if (board.at(r, c) != null || visited.contains(_key(r, c))) continue;
      final region = _EmptyRegion(<int>{});
      final borders = <PlayerColor>{};
      final stack = <int>[_key(r, c)];
      visited.add(_key(r, c));
      while (stack.isNotEmpty) {
        final k = stack.removeLast();
        region.points.add(k);
        final (cr, cc) = _rc(k);
        for (final (dr, dc) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nr = cr + dr, nc = cc + dc;
          if (!board.inBounds(nr, nc)) continue;
          final nk = _key(nr, nc);
          final cell = board.at(nr, nc);
          if (cell == null) {
            if (visited.add(nk)) stack.add(nk);
          } else {
            borders.add(cell);
            final chain = chainByPoint[nk];
            if (chain != null) region.borderingChains.add(chain.stones.first);
          }
        }
      }
            regions.add(region);
      // 颜色信息附加到区域（供调用方判断单色边界）。
      region.color = borders.length == 1 ? borders.first : null;    }
  }
  return regions;
}

/// 死活分析（启发式）。
///
/// 参考 KataGo 规则文档与 Sayuri 的 Benson 实现：
/// - **眼** = 仅被己方颜色包围（bordered only by own color）且面积 ≤ [maxEyeSize]
///   的空白连通区（单子/大眼/假眼的判定基础）。
/// - **活**：≥2 个眼区，或单个"活眼形"（面积 ≥5，或面积 4 且非方四/丁四）。
/// - **双活（seki）**：双方均非活、各有 ≥1 个眼、且所有非眼气均与组件内其他
///   棋串共享（共享气组件）。
/// - **死**：无外气可逃、非双活、眼形不足。
/// - **未定型**：尚有非共享外气，保守视为活（不误杀逃逸棋）。
///
/// 已知局限（P2 接入 KataGo 后替换）：盘角曲四、双劫、千年劫等极端死活形状
/// 以及"死同色子挡眼"型假眼可能误判，一律按保守方向处理。
LifeDeathResult analyzeLifeDeath(GoBoard board, {int maxEyeSize = 12}) {
  final groups = _collectGroups(board);
  final chainByPoint = <int, GoGroup>{};
  for (final g in groups) {
    for (final p in g.stones) {
      chainByPoint[p] = g;
    }
  }

  final regions = _collectEmptyRegions(board, chainByPoint);
  final chainKey = {for (final g in groups) g.stones.first: g};
  final regByChainKey = <int, List<_EmptyRegion>>{
    for (final g in groups) g.stones.first: <_EmptyRegion>[],
  };
  for (final r in regions) {
    if (r.color == null || r.points.length > maxEyeSize) continue;
    for (final ck in r.borderingChains) {
      regByChainKey[ck]?.add(r);
    }
  }

  final status = <int, GroupStatus>{};
  final notAliveKeys = <int>[];

  for (final g in groups) {
    final eyes = regByChainKey[g.stones.first]!;
    final key = g.stones.first;
    if (eyes.length >= 2 || (eyes.length == 1 && _liveEyeShape(eyes.first))) {
      status[key] = GroupStatus.alive;
    } else {
      notAliveKeys.add(key);
    }
  }

  // 双活组件检测。
  final sekiKeys = _detectSeki(
    board,
    notAliveKeys,
    chainKey,
    chainByPoint,
    regByChainKey,
  );
  for (final k in sekiKeys) {
    status[k] = GroupStatus.seki;
  }

  // 其余未活棋串：死 or 未定型。
  final deadPoints = <int>{};
  final sekiPoints = <int>{};
  final sekiEyes = <Set<int>>[];

  for (final k in notAliveKeys) {
    if (status[k] == GroupStatus.seki) {
      sekiPoints.addAll(chainKey[k]!.stones);
      continue;
    }
    final g = chainKey[k]!;
    final eyes = regByChainKey[k]!;
    final eyeLibs = <int>{};
    for (final e in eyes) {
      eyeLibs.addAll(e.points);
    }
    // 非眼气中，未被对方棋子邻接的算"可逃"气。
    var canRun = false;
    for (final lib in g.liberties) {
      if (eyeLibs.contains(lib)) continue;
      final (lr, lc) = _rc(lib);
      if (!_adjacentTo(board, lr, lc, g.color.opposite)) {
        canRun = true;
        break;
      }
    }
    if (canRun) {
      status[k] = GroupStatus.alive;
    } else {
      status[k] = GroupStatus.dead;
      deadPoints.addAll(g.stones);
    }
  }

  // 双活棋串的眼：仅当该空区所有边界棋串均为双活时，才从数目领地中剔除。
  for (final r in regions) {
    if (r.color == null || r.points.length > maxEyeSize) continue;
    if (r.borderingChains.isEmpty) continue;
    var allSeki = true;
    for (final ck in r.borderingChains) {
      if (status[ck] != GroupStatus.seki) {
        allSeki = false;
        break;
      }
    }
    if (allSeki) sekiEyes.add(r.points);
  }

  return LifeDeathResult(
    groupStatus: status,
    deadPoints: deadPoints,
    sekiPoints: sekiPoints,
    sekiEyes: sekiEyes,
  );
}

/// 活眼形判定：面积 ≥5 必活；面积 4 仅方四（2×2）与丁四（T 形）为死眼形。
bool _liveEyeShape(_EmptyRegion region) {
  final n = region.points.length;
  if (n >= 5) return true;
  if (n != 4) return false;
  return !_isSquareFour(region) && !_isTFour(region);
}

bool _isSquareFour(_EmptyRegion region) {
  if (region.points.length != 4) return false;
  var minR = 99, maxR = -1, minC = 99, maxC = -1;
  for (final k in region.points) {
    final (r, c) = _rc(k);
    if (r < minR) minR = r;
    if (r > maxR) maxR = r;
    if (c < minC) minC = c;
    if (c > maxC) maxC = c;
  }
  return maxR - minR == 1 && maxC - minC == 1;
}

bool _isTFour(_EmptyRegion region) {
  if (region.points.length != 4) return false;
  for (final k in region.points) {
    final (r, c) = _rc(k);
    var nbrs = 0;
    for (final (dr, dc) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      if (region.points.contains(_key(r + dr, c + dc))) nbrs++;
    }
    if (nbrs == 3) return true;
  }
  return false;
}

/// 双活检测：在未活棋串上按"共享气"建图，逐连通分量判定。
Set<int> _detectSeki(
  GoBoard board,
  List<int> notAliveKeys,
  Map<int, GoGroup> chainKey,
  Map<int, GoGroup> chainByPoint,
  Map<int, List<_EmptyRegion>> regByChainKey,
) {
  final result = <int>{};
  if (notAliveKeys.length < 2) return result;

  final notAliveSet = notAliveKeys.toSet();

  // 棋串 → 其共享气的邻接棋串（仅限未活棋串）。
  final adj = <int, Set<int>>{};
  for (final k in notAliveKeys) {
    final g = chainKey[k]!;
    for (final lib in g.liberties) {
      final (lr, lc) = _rc(lib);
      for (final (dr, dc) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nr = lr + dr, nc = lc + dc;
        if (!board.inBounds(nr, nc)) continue;
        final cell = board.at(nr, nc);
        if (cell == null || cell == g.color) continue;
        final nk = chainByPoint[_key(nr, nc)]?.stones.first;
        if (nk != null && notAliveSet.contains(nk)) {
          adj.putIfAbsent(k, () => {}).add(nk);
        }
      }
    }
  }

  final visited = <int>{};
  for (final start in notAliveKeys) {
    if (visited.contains(start)) continue;
    final comp = <int>[];
    final stack = <int>[start];
    visited.add(start);
    while (stack.isNotEmpty) {
      final k = stack.removeLast();
      comp.add(k);
      for (final nk in adj[k] ?? const <int>{}) {
        if (visited.add(nk)) stack.add(nk);
      }
    }
    if (comp.length < 2) continue;
    if (_isSekiComponent(comp, chainKey, regByChainKey, adj)) {
      result.addAll(comp);
    }
  }
  return result;
}

/// 组件是否构成双活：每串 ≥1 眼；每串所有非眼气均与本组件内其他棋串共享。
bool _isSekiComponent(
  List<int> comp,
  Map<int, GoGroup> chainKey,
  Map<int, List<_EmptyRegion>> regByChainKey,
  Map<int, Set<int>> adj,
) {
  // 每串须 ≥1 个眼。
  for (final k in comp) {
    if ((regByChainKey[k] ?? const <_EmptyRegion>[]).isEmpty) return false;
  }
  // 组件邻接集合。
  final compSet = comp.toSet();
  for (final k in comp) {
    final g = chainKey[k]!;
    final eyes = regByChainKey[k]!;
    final eyeLibs = <int>{};
    for (final e in eyes) {
      eyeLibs.addAll(e.points);
    }
    for (final lib in g.liberties) {
      if (eyeLibs.contains(lib)) continue;
      // 非眼气必须与本组件内其他棋串共享（通过 adj 中的某个伙伴）。
      var shared = false;
      for (final nk in adj[k] ?? const <int>{}) {
        if (!compSet.contains(nk)) continue;
        final partner = chainKey[nk]!;
        if (partner.liberties.contains(lib)) {
          shared = true;
          break;
        }
      }
      if (!shared) return false;
    }
  }
  return true;
}
