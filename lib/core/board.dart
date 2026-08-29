import 'package:miaogo/core/move.dart';

/// 围棋棋盘模型：落子、提子、禁自杀（除非提子）、打劫（含位置超劫）、合法点。
///
/// 可变对象；悔棋由控制器保存棋盘快照/按棋谱重放。坐标均为 0 起始的行列。
/// 默认启用[superko]（位置超劫，与 OGS/KGS 的中国规则一致）：一手不得重现
/// 任何更早的盘面着色。简单劫 `koPoint` 保留为快速路径；pass 不清历史。
class GoBoard {
  GoBoard({required this.size, this.superko = true})
      : _grid = _empty(size) {
    assert(size >= 5 && size <= 19, '棋盘尺寸须在 5~19 之间');
    if (superko) _positionHashes.add(_gridHash());
  }

  /// SGF 坐标字符序列：a..t，跳过 i（索引即列/行序号）。
  static const String letters = 'abcdefghjklmnopqrst';

  final int size;

  /// 是否启用位置超劫（默认开启）。
  final bool superko;

  /// 全部历史盘面着色哈希（含当前局面），用于位置超劫判定。
  final Set<int> _positionHashes = {};

  final List<List<PlayerColor?>> _grid;

  /// 简单打劫：最近一手提劫后被禁回提的点；null 表示无劫。
  (int, int)? koPoint;

  /// 黑方累计提掉的白子数。
  int capturesBlack = 0;

  /// 白方累计提掉的黑子数。
  int capturesWhite = 0;

  static List<List<PlayerColor?>> _empty(int size) =>
      List.generate(size, (_) => List<PlayerColor?>.filled(size, null));

  PlayerColor? at(int row, int col) => _grid[row][col];

  bool inBounds(int row, int col) =>
      row >= 0 && row < size && col >= 0 && col < size;

  bool get isEmpty {
    for (final row in _grid) {
      for (final cell in row) {
        if (cell != null) return false;
      }
    }
    return true;
  }

  /// 标准星位坐标（9 路 5 个、13/19 路 9 个），棋盘绘制与 AI 共用。
  static List<(int, int)> starPoints(int size) {
    final offsets = switch (size) {
      9 => const <int>[2, 6],
      13 => const <int>[3, 6, 9],
      _ => const <int>[3, 9, 15],
    };
    final pts = <(int, int)>[];
    for (final r in offsets) {
      for (final c in offsets) {
        pts.add((r, c));
      }
    }
    if (size == 9) pts.add((4, 4)); // 天元
    return pts;
  }

  /// 行列 → SGF 坐标（如 `(8,8)` → `jj`）。
  static String sgfCoord(int row, int col) {
    assert(row >= 0 && row < 19 && col >= 0 && col < 19, '坐标越界');
    return '${letters[col]}${letters[row]}';
  }

  /// SGF 坐标 → 行列（跳过 i）；非法坐标抛 [ArgumentError]。
  static (int, int) coordFromSgf(String s) {
    if (s.length != 2) throw ArgumentError('非法 SGF 坐标: "$s"');
    final c = letters.indexOf(s[0]);
    final r = letters.indexOf(s[1]);
    if (c < 0 || r < 0) throw ArgumentError('非法 SGF 坐标: "$s"');
    return (r, c);
  }

  /// 落子（含提子/打劫/超劫判定）；非法返回 false 且棋盘不变。
  bool play(PlayerColor color, int row, int col) {
    if (!_isLegalNoMutate(color, row, col)) return false;
    _grid[row][col] = color;
    final captured = <(int, int)>[];
    for (final (nr, nc) in _neighbors(row, col)) {
      final n = _grid[nr][nc];
      if (n == null || n == color) continue;
      if (!_hasLiberty(nr, nc)) captured.addAll(_removeGroup(nr, nc));
    }
    if (color == PlayerColor.black) {
      capturesBlack += captured.length;
    } else {
      capturesWhite += captured.length;
    }
    if (superko) _positionHashes.add(_gridHash());
    // 简单打劫：仅提一枚子且落子棋串只剩一口气（被提点）时，该点为劫
    if (captured.length == 1) {
      final (kr, kc) = captured.first;
      koPoint = groupLiberties(row, col) == 1 ? (kr, kc) : null;
    } else {
      koPoint = null;
    }
    return true;
  }

  /// 合法落子点列表（含禁自杀与劫禁）。
  List<(int, int)> legalPoints(PlayerColor color) {
    final result = <(int, int)>[];
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if (_isLegalNoMutate(color, r, c)) result.add((r, c));
      }
    }
    return result;
  }

  /// 判定落子是否合法（不修改棋盘；含占点/禁自杀/打劫禁）。
  bool isLegal(PlayerColor color, int row, int col) =>
      _isLegalNoMutate(color, row, col);

  /// 空白连通区分析：返回每个空区的（面积, 边界色集合）。
  /// 单色边界 → 一方领地；双色/无边界 → 未定地盘。供计分与地盘定型判断共用。
  List<({int area, Set<PlayerColor> borders})> emptyRegions() => [
        for (final r in emptyRegionsDetailed())
          (area: r.points.length, borders: r.borders),
      ];

  /// 空白连通区分析（含落点键，`row * 64 + col`）：
  /// 供终局计分做"双活眼剔除"等按点判定。
  List<({Set<int> points, Set<PlayerColor> borders})> emptyRegionsDetailed() {
    final visited = List.generate(
        size, (_) => List<bool>.filled(size, false));
    final regions = <({Set<int> points, Set<PlayerColor> borders})>[];
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if (_grid[r][c] != null || visited[r][c]) continue;
        final borders = <PlayerColor>{};
        final points = <int>{};
        final stack = <(int, int)>[(r, c)];
        visited[r][c] = true;
        while (stack.isNotEmpty) {
          final (cr, cc) = stack.removeLast();
          points.add(_key(cr, cc));
          for (final (nr, nc) in _neighbors(cr, cc)) {
            final cell = _grid[nr][nc];
            if (cell == null) {
              if (!visited[nr][nc]) {
                visited[nr][nc] = true;
                stack.add((nr, nc));
              }
            } else {
              borders.add(cell);
            }
          }
        }
        regions.add((points: points, borders: borders));
      }
    }
    return regions;
  }

  /// 棋串气数（不含己方占位的空点，去重）。
  int groupLiberties(int row, int col) {
    final color = _grid[row][col];
    if (color == null) return 0;
    final seen = <int>{_key(row, col)};
    final stack = <int>[_key(row, col)];
    final liberties = <int>{};
    while (stack.isNotEmpty) {
      final v = stack.removeLast();
      final r = v ~/ 64, c = v % 64;
      for (final (nr, nc) in _neighbors(r, c)) {
        final cell = _grid[nr][nc];
        if (cell == null) {
          liberties.add(_key(nr, nc));
        } else if (cell == color && seen.add(_key(nr, nc))) {
          stack.add(_key(nr, nc));
        }
      }
    }
    return liberties.length;
  }

  /// 克隆棋盘（悔棋快照 / 模拟分析）。
  ///
  /// [superko] 为空则沿用原棋盘设置；生命线分析等无对局历史的场景应传
  /// `superko: false` 关闭位置历史，避免模拟着法被超劫误拦。
  GoBoard clone({bool? superko}) {
    final enable = superko ?? this.superko;
    final b = GoBoard(size: size, superko: enable)
      ..koPoint = koPoint
      ..capturesBlack = capturesBlack
      ..capturesWhite = capturesWhite;
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        b._grid[r][c] = _grid[r][c];
      }
    }
    if (enable) {
      b._positionHashes.addAll(_positionHashes);
      if (!this.superko) b._positionHashes.add(b._gridHash());
    }
    return b;
  }

  /// 清空一个点（终局计分移除死子用；不影响劫/超劫历史）。
  void clearPoint(int row, int col) => _grid[row][col] = null;

  /// 直接设置某点棋子（测试布子 / 谱面装载用）。
  ///
  /// 跳过合法性、提子与劫/超劫历史更新，仅做网格赋值；不应在真实对局中使用。
  void setStone(int row, int col, PlayerColor color) => _grid[row][col] = color;

  /// 强制落子（正解演示/棋谱重放用）：绕过合法性、打劫与超劫检查，
  /// 仅处理提子并更新提子计数。用于 SGF 正解主线中的打劫回提等
  /// 按严格规则不可立即回提、但谱面明确要走的情形。
  void forcePlay(PlayerColor color, int row, int col) {
    assert(inBounds(row, col), '越界');
    _grid[row][col] = color;
    var captured = 0;
    for (final (nr, nc) in _neighbors(row, col)) {
      final n = _grid[nr][nc];
      if (n == null || n == color) continue;
      if (!_hasLiberty(nr, nc)) {
        captured += _removeGroup(nr, nc).length;
      }
    }
    if (color == PlayerColor.black) {
      capturesBlack += captured;
    } else {
      capturesWhite += captured;
    }
    koPoint = null;
  }

  /// FNV-1a 64 位哈希：整盘着色 → 确定性的盘面指纹（位置超劫用）。
  int _gridHash() {
    var h = 0xcbf29ce484222325;
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        final cell = _grid[r][c];
        final v = cell == null ? 0 : (cell == PlayerColor.black ? 1 : 2);
        h = (h ^ v) * 0x100000001b3;
      }
    }
    return h;
  }

  int _key(int r, int c) => r * 64 + c;

  List<(int, int)> _neighbors(int r, int c) {
    final out = <(int, int)>[];
    for (final (dr, dc) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final nr = r + dr, nc = c + dc;
      if (inBounds(nr, nc)) out.add((nr, nc));
    }
    return out;
  }

  bool _hasLiberty(int row, int col) {
    final color = _grid[row][col];
    if (color == null) return false;
    final seen = <int>{_key(row, col)};
    final stack = <int>[_key(row, col)];
    while (stack.isNotEmpty) {
      final v = stack.removeLast();
      final r = v ~/ 64, c = v % 64;
      for (final (nr, nc) in _neighbors(r, c)) {
        final cell = _grid[nr][nc];
        if (cell == null) return true;
        if (cell == color && seen.add(_key(nr, nc))) {
          stack.add(_key(nr, nc));
        }
      }
    }
    return false;
  }

  /// 提走 (row,col) 所在同色棋串，返回被提坐标。
  List<(int, int)> _removeGroup(int row, int col) {
    final color = _grid[row][col];
    if (color == null) return const [];
    final seen = <int>{_key(row, col)};
    final stack = <int>[_key(row, col)];
    final removed = <(int, int)>[];
    while (stack.isNotEmpty) {
      final v = stack.removeLast();
      final r = v ~/ 64, c = v % 64;
      removed.add((r, c));
      for (final (nr, nc) in _neighbors(r, c)) {
        if (_grid[nr][nc] == color && seen.add(_key(nr, nc))) {
          stack.add(_key(nr, nc));
        }
      }
    }
    for (final (r, c) in removed) {
      _grid[r][c] = null;
    }
    return removed;
  }

  /// 不修改棋盘地判定落子是否合法。
  bool _isLegalNoMutate(PlayerColor color, int row, int col) {
    if (!inBounds(row, col) || _grid[row][col] != null) return false;
    if (koPoint != null && row == koPoint!.$1 && col == koPoint!.$2) {
      return false;
    }
    _grid[row][col] = color;
    final captured = <(int, int)>[];
    for (final (nr, nc) in _neighbors(row, col)) {
      final n = _grid[nr][nc];
      if (n == null || n == color) continue;
      if (!_hasLiberty(nr, nc)) captured.addAll(_removeGroup(nr, nc));
    }
    final ok = _hasLiberty(row, col) &&
        (!superko || !_positionHashes.contains(_gridHash()));
    _grid[row][col] = null;
    for (final (r, c) in captured) {
      _grid[r][c] = color.opposite;
    }
    return ok;
  }
}
