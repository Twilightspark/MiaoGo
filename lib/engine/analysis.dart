import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';

/// 单步棋的分析结果（来自 `kata-analyze` 的 `info move ...` 块）。
class MoveAnalysis {
  const MoveAnalysis({
    required this.move,
    required this.visits,
    required this.winrate,
    required this.utility,
    required this.scoreLead,
    required this.prior,
    required this.lcb,
    required this.order,
    required this.pv,
    this.isSymmetryOf,
  });

  /// GTP 坐标（如 `E4`）或 `pass`。
  final String move;
  final int visits;
  final double winrate;
  final double utility;
  final double scoreLead;
  final double prior;
  final double lcb;

  /// KataGo 对候选的排序，0 = 最佳。
  final int order;
  final List<String> pv;

  /// 若由对称剪枝复制而来，指向被复制的候选（其数值即本候选数值）。
  final String? isSymmetryOf;
}

/// 根信息（`rootInfo` 块）：整局面统计。
class RootInfo {
  const RootInfo({
    required this.visits,
    required this.winrate,
    required this.scoreLead,
  });

  final int visits;
  final double winrate;
  final double scoreLead;
}

/// 一次 `kata-analyze` 更新（单行）的解析结果。
class AnalysisUpdate {
  const AnalysisUpdate({
    required this.moves,
    this.ownership,
    this.rootInfo,
  });

  final List<MoveAnalysis> moves;

  /// ownership 预测（[-1,1]，行主序、自左上 A19 起），
  /// 正值 = 轮到行棋一方领地。null 表示未请求/解析失败。
  final List<double>? ownership;
  final RootInfo? rootInfo;

  /// 按 [order] 排序后的 top 候选（isSymmetryOf 并入其原型）。
  List<MoveAnalysis> get orderedMoves {
    final list = [...moves];
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }
}

/// `kata-analyze` 输出解析器。
///
/// 单行格式：`info move E4 <kv> pv E4 ... info move D5 ... rootInfo ... ownership <N floats>`
/// 逐 token 顺序解析；`info`/`rootInfo`/`ownership` 为顶层字段，
/// `pv` 之后连续取坐标直至下一个顶层字段，`isSymmetryOf` 后取一个坐标。
/// 对字段顺序/新增字段保持健壮：未知 key 跳过其值。
class KataAnalyzeParser {
  KataAnalyzeParser({required this.boardSize});

  final int boardSize;

  /// 顶层字段关键字（其后按各自语义解析）。
  static const Set<String> _topLevel = {
    'info',
    'rootInfo',
    'ownership',
    'ownershipStdev',
    'territory',
  };

  /// 单个浮点值的已知字段（不按通用规则吞掉未知字段）。
  static const Set<String> _floatKeys = {
    'visits',
    'edgeVisits',
    'utility',
    'winrate',
    'scoreMean',
    'scoreStdev',
    'scoreLead',
    'scoreSelfplay',
    'prior',
    'lcb',
    'utilityLcb',
    'weight',
    'order',
    'edgeWeight',
    'playSelectionValue',
  };

  /// 解析单行分析更新；格式异常时抛 [FormatException]。
  AnalysisUpdate parse(String line) {
    final tokens =
        line.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    var i = 0;
    final moves = <MoveAnalysis>[];
    List<double>? ownership;
    RootInfo? rootInfo;

    while (i < tokens.length) {
      final key = tokens[i];
      if (key == 'info') {
        final parsed = _parseMoveBlock(tokens, i + 1);
        moves.add(parsed.$1);
        i = parsed.$2;
      } else if (key == 'rootInfo') {
        final parsed = _parseRootInfo(tokens, i + 1);
        rootInfo = parsed.$1;
        i = parsed.$2;
      } else if (key == 'ownership') {
        ownership = _parseFloatRun(tokens, i + 1, boardSize * boardSize);
        i += 1 + boardSize * boardSize;
      } else if (key == 'ownershipStdev' || key == 'territory') {
        // 当前不需要：跳过 boardSize^2 个浮点。
        i += 1 + boardSize * boardSize;
      } else {
        // 未知顶层字段：跳过其后的一个值，保持健壮。
        i += 2;
      }
    }

    return AnalysisUpdate(moves: moves, ownership: ownership, rootInfo: rootInfo);
  }

  (MoveAnalysis, int) _parseMoveBlock(List<String> tokens, int start) {
    var i = start;
    // 期望 `move <坐标>`
    if (i >= tokens.length || tokens[i] != 'move') {
      throw FormatException('info 块缺 move: ${tokens.join(' ')}');
    }
    i++;
    final move = tokens[i++];

    String? symmetryOf;
    List<String> pv = const [];
    final stats = <String, double>{};

    while (i < tokens.length && !_topLevel.contains(tokens[i])) {
      final key = tokens[i++];
      if (key == 'pv') {
        pv = [];
        while (i < tokens.length && !_topLevel.contains(tokens[i])) {
          pv.add(tokens[i++]);
        }
      } else if (key == 'isSymmetryOf') {
        if (i < tokens.length) symmetryOf = tokens[i++];
      } else if (key == 'movesOwnership' || key == 'movesOwnershipStdev') {
        i += boardSize * boardSize;
      } else if (_floatKeys.contains(key)) {
        if (i >= tokens.length) break;
        final v = double.parse(tokens[i++]);
        stats[key] = v;
      } else {
        // 未知字段：跳过其值。
        if (i < tokens.length) i++;
      }
    }

    return (
      MoveAnalysis(
        move: move,
        visits: (stats['visits'] ?? 0).round(),
        winrate: stats['winrate'] ?? 0,
        utility: stats['utility'] ?? 0,
        scoreLead: stats['scoreLead'] ?? 0,
        prior: stats['prior'] ?? 0,
        lcb: stats['lcb'] ?? 0,
        order: (stats['order'] ?? 0).round(),
        pv: pv,
        isSymmetryOf: symmetryOf,
      ),
      i,
    );
  }

  (RootInfo, int) _parseRootInfo(List<String> tokens, int start) {
    var i = start;
    int visits = 0;
    double winrate = 0, scoreLead = 0;
    while (i < tokens.length && !_topLevel.contains(tokens[i])) {
      final key = tokens[i++];
      if (i >= tokens.length) break;
      final v = double.parse(tokens[i++]);
      if (key == 'visits') {
        visits = v.round();
      } else if (key == 'winrate') {
        winrate = v;
      } else if (key == 'scoreLead') {
        scoreLead = v;
      }
    }
    return (RootInfo(visits: visits, winrate: winrate, scoreLead: scoreLead), i);
  }

  List<double> _parseFloatRun(List<String> tokens, int start, int count) {
    final out = <double>[];
    for (var j = 0; j < count; j++) {
      if (start + j >= tokens.length) break;
      out.add(double.parse(tokens[start + j]));
    }
    return out;
  }
}

/// 将 KataGo ownership（行主序、正值 = [toMove] 一方）转为
/// 棋盘热力图约定：正值 = 黑方势力，负值 = 白方势力。
List<List<double>> ownershipToInfluence(
    List<double> ownership, int boardSize, PlayerColor toMove) {
  final n = boardSize;
  final flip = toMove == PlayerColor.white;
  final map = List.generate(n, (r) {
    return List<double>.generate(n, (c) {
      final v = ownership[r * n + c];
      return flip ? -v : v;
    });
  });
  return map;
}

/// GTP 坐标 → 行列（`pass` 返回 null）。
///
/// GTP 顶点格式为「列字母 + 行数字」（如 `E4`：第 4 列、自底向上第 4 行），
/// 行从 1 起；转为 0 起始的行列。非法抛 [ArgumentError]。
(int, int)? coordFromGtp(String vertex) {
  if (vertex == 'pass') return null;
  if (vertex.length < 2) {
    throw ArgumentError('非法 GTP 坐标: "$vertex"');
  }
  final col = GoBoard.letters.indexOf(vertex[0].toLowerCase());
  final rowNum = int.tryParse(vertex.substring(1));
  if (col < 0 || rowNum == null || rowNum < 1) {
    throw ArgumentError('非法 GTP 坐标: "$vertex"');
  }
  return (rowNum - 1, col);
}
