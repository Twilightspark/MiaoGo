import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';

/// SGF 属性：名称 + 一个或多个值（如 `AB[aa][bb]` 有两个值）。
class SgfProp {
  const SgfProp(this.name, this.values);

  final String name;
  final List<String> values;
}

/// SGF 节点：一组属性 + 子节点（变化）。
///
/// 主变化即[mainline]（始终取第一个子节点）；[children] 中其余为变化分支。
class SgfNode {
  SgfNode(this.props, this.children);

  /// 属性名（大写）→ 属性。
  final Map<String, SgfProp> props;

  /// 子节点：首个为延续主变化，其余为变化分支。
  final List<SgfNode> children;

  /// 取属性值列表；不存在返回 null。
  List<String>? values(String name) => props[name]?.values;

  /// 取单个属性值（多值时取第一个）；不存在返回 null。
  String? value(String name) => props[name]?.values.firstOrNull;

  /// 首个子节点（主变化下一步）。
  SgfNode? get firstChild => children.isEmpty ? null : children.first;

  /// 本节点是否表示一手棋（含 PASS）。
  Move? get move {
    final b = value('B');
    if (b != null) return _moveFromCoord(PlayerColor.black, b);
    final w = value('W');
    if (w != null) return _moveFromCoord(PlayerColor.white, w);
    return null;
  }

  static Move? _moveFromCoord(PlayerColor color, String coord) {
    if (coord.isEmpty) return Move.pass(color);
    final (r, c) = GoBoard.coordFromSgf(coord);
    return Move.point(color, r, c);
  }

  /// 主变化链（从本节点起沿首子一直到底）。
  List<SgfNode> get mainline {
    final out = <SgfNode>[this];
    var cur = this;
    while (cur.children.isNotEmpty) {
      cur = cur.children.first;
      out.add(cur);
    }
    return out;
  }

  /// `C[]` 注释；无则返回 null。
  String? get comment => value('C');
}

/// 一局 SGF：根节点 + 便捷元数据访问。
class SgfGame {
  SgfGame(this.root);

  final SgfNode root;

  int? get size {
    final v = root.value('SZ');
    return v == null ? null : int.tryParse(v);
  }

  String? get rulesProp => root.value('RU');

  double? get komi {
    final v = root.value('KM');
    return v == null ? null : double.tryParse(v);
  }

  String? get blackName => root.value('PB');
  String? get whiteName => root.value('PW');
  String? get blackRank => root.value('BR');
  String? get whiteRank => root.value('WR');
  String? get result => root.value('RE');
  String? get event => root.value('EV');
  String? get date => root.value('DT');
  String? get source => root.value('SO');

  int? get handicap {
    final v = root.value('HA');
    return v == null ? null : int.tryParse(v);
  }

  /// 执子方（`PL` 属性；无则取首步颜色，再缺省黑）。
  PlayerColor? get playerToMove {
    final pl = root.value('PL');
    if (pl != null) {
      if (pl == 'B' || pl == 'b') return PlayerColor.black;
      if (pl == 'W' || pl == 'w') return PlayerColor.white;
    }
    for (final n in root.mainline.skip(1)) {
      final m = n.move;
      if (m != null) return m.color;
    }
    return null;
  }

  /// 布子（`AB`，黑）——让子/死活题初始局面。
  List<(int, int)> get setupBlack => _points(root, 'AB');

  /// 布子（`AW`，白）。
  List<(int, int)> get setupWhite => _points(root, 'AW');

  /// 清除点（`AE`）。
  List<(int, int)> get setupEmpty => _points(root, 'AE');

  /// 主变化节点链（含根节点）。
  List<SgfNode> get mainline => root.mainline;

  /// 主变化中的棋步（跳过布子/属性节点，仅 B/W 落子与 PASS）。
  List<Move> get moves => [
        for (final n in mainline.skip(1))
          if (n.move != null) n.move!,
      ];

  static List<(int, int)> _points(SgfNode node, String name) => [
        for (final s in node.values(name) ?? const <String>[])
          GoBoard.coordFromSgf(s),
      ];
}

/// SGF 完整解析 / 生成 / 便捷访问。
///
/// P4 扩展：支持属性树、分支/变化、布子（AB/AW/AE）、注释（C）、转义、
/// 多值属性与空白容错；同时保留 P1 的 [build]/[parseMoves]/[prop] 兼容接口。
class Sgf {
  Sgf._();

  /// 解析 SGF 文本为完整树；空/畸形输入抛 [FormatException]。
  ///
  /// 自动识别两种坐标字母表：
  /// - 标准 SGF：`a..t` 跳过 `i`；
  /// - 非标全字母表（部分老工具/棋谱库使用）：`a..t` 含 `i`。
  /// 检测到含 `i` 的坐标时，把树内坐标归一化为标准字母表，便于后续棋盘建模。
  static SgfGame parse(String text) {
    final parser = _SgfParser(text);
    final root = parser.parseGame().root;
    // 检测到任何坐标含 `i` 即视为非标全字母表，统一归一化为标准字母表。
    if (_hasICoord(root)) _normalizeTree(root);
    return SgfGame(root);
  }

  /// 树中是否存在含 `i` 的坐标值（布子/棋步/标记）。
  static bool _hasICoord(SgfNode node) {
    for (final name in _coordProps) {
      final p = node.props[name];
      if (p == null) continue;
      for (final v in p.values) {
        if (v.contains('i')) return true;
      }
    }
    for (final child in node.children) {
      if (_hasICoord(child)) return true;
    }
    return false;
  }

  /// 全字母表（含 i）：a..t → 0..19。
  static const _fullAlphabet = 'abcdefghijklmnopqrst';

  /// 标准字母表（跳过 i）。
  static const _stdAlphabet = 'abcdefghjklmnopqrst';

  /// 单个字母从全字母表映射到标准字母表（同下标）。
  static String _mapLetter(String c) {
    final i = _fullAlphabet.indexOf(c);
    if (i < 0 || i >= _stdAlphabet.length) return c;
    return _stdAlphabet.substring(i, i + 1);
  }

  /// 映射坐标值：仅映射前两个字母（坐标对），其余（标签等）保留。
  static String _mapCoordValue(String s) {
    if (s.length < 2) return s;
    return _mapLetter(s.substring(0, 1)) + _mapLetter(s.substring(1, 2)) +
        s.substring(2);
  }

  /// 涉及棋盘坐标的属性（映射 B/W/布子/标记）。
  static const _coordProps = {
    'B',
    'W',
    'AB',
    'AW',
    'AE',
    'LB',
    'TR',
    'SQ',
    'CR',
    'MA',
    'DD',
    'SL',
    'MN',
    'AR',
  };

  static void _normalizeTree(SgfNode node) {
    final props = node.props;
    for (final name in _coordProps) {
      final p = props[name];
      if (p == null) continue;
      props[name] =
          SgfProp(name, [for (final v in p.values) _mapCoordValue(v)]);
    }
    for (final child in node.children) {
      _normalizeTree(child);
    }
  }

  /// 序列化一棵子树（以 `(...)` 形式）。
  ///
  /// 每个子节点序列化为独立 gametree，语义与源树一致，可反复往返解析。
  static String encode(SgfGame game) => '(${_encodeTree(game.root)})';

  static String _encodeTree(SgfNode node) {
    final sb = StringBuffer(';');
    for (final prop in node.props.values) {
      sb.write(prop.name);
      for (final v in prop.values) {
        sb.write('[');
        sb.write(_escape(v));
        sb.write(']');
      }
    }
    for (final child in node.children) {
      sb.write('(${_encodeTree(child)})');
    }
    return sb.toString();
  }

  /// 转义属性值：`\` 与 `]` 反斜杠转义，换行折叠为空格。
  static String _escape(String v) => v
      .replaceAll('\\', '\\\\')
      .replaceAll(']', '\\]')
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ');

  /// 生成 SGF 文本（P1 对局保存用）；[result] 例如 `B+1.5`、`W+R`。
  static String build({
    required int size,
    required String rules,
    required double komi,
    String blackName = '',
    String whiteName = '',
    String result = '',
    List<Move> moves = const [],
  }) {
    final sb = StringBuffer();
    sb.write('(;GM[1]FF[4]CA[UTF-8]SZ[$size]RU[$rules]KM[$komi]');
    if (blackName.isNotEmpty) sb.write('PB[$blackName]');
    if (whiteName.isNotEmpty) sb.write('PW[$whiteName]');
    if (result.isNotEmpty) sb.write('RE[$result]');
    for (final m in moves) {
      if (m.isResign) continue; // 认输不入谱，以 RE 记录
      final tag = m.color == PlayerColor.black ? 'B' : 'W';
      final coord = m.isPass ? '' : GoBoard.sgfCoord(m.row!, m.col!);
      sb.write(';$tag[$coord]');
    }
    sb.write(')');
    return sb.toString();
  }

  /// 解析主变化棋步序列（含 PASS）；认输步不体现在 SGF 中。
  ///
  /// 通过完整解析取主变化，避免正则误吞注释/变化分支。
  static List<Move> parseMoves(String sgf) {
    try {
      return parse(sgf).moves;
    } on FormatException {
      return const [];
    }
  }

  /// 读取根节点单值属性（如 SZ/KM/RE/RU/PB/PW）；不存在返回 null。
  static String? prop(String sgf, String name) {
    try {
      return parse(sgf).root.value(name);
    } on FormatException {
      return null;
    }
  }

}

/// 递归下降 SGF 解析器（容错：跳过空白、容忍非规范属性名、处理转义）。
class _SgfParser {
  _SgfParser(this._s);

  final String _s;
  int _pos = 0;

  SgfGame parseGame() {
    final root = _parseGameTree();
    return SgfGame(root);
  }

  /// `( sequence gametree* )` → 返回序列首个节点。
  SgfNode _parseGameTree() {
    _skipWs();
    if (_pos >= _s.length || _s[_pos] != '(') {
      throw FormatException('SGF 应为 `(...)` 开头');
    }
    _pos++;
    _skipWs();
    final first = _parseNode();
    var current = first;
    // 同一 gametree 内的后续序列节点：串成主变化链（仅一个子节点）。
    _skipWs();
    while (_pos < _s.length && _s[_pos] == ';') {
      final next = _parseNode();
      current.children.add(next);
      current = next;
      _skipWs();
    }
    // 子 gametree（变化分支）。
    while (_pos < _s.length && _s[_pos] == '(') {
      current.children.add(_parseGameTree());
      _skipWs();
    }
    if (_pos >= _s.length || _s[_pos] != ')') {
      throw FormatException('SGF 缺少 `)`');
    }
    _pos++;
    return first;
  }

  /// `;prop...` → 节点。
  SgfNode _parseNode() {
    if (_pos >= _s.length || _s[_pos] != ';') {
      throw FormatException('SGF 节点应以 `;` 开头');
    }
    _pos++;
    _skipWs();
    final props = <String, SgfProp>{};
    while (_pos < _s.length && _s[_pos] != ';' && _s[_pos] != '(' &&
        _s[_pos] != ')') {
      final name = _readPropIdent();
      if (name.isEmpty) break;
      final values = <String>[];
      while (_pos < _s.length && _s[_pos] == '[') {
        values.add(_readPropValue());
      }
      props[name] = SgfProp(name, values);
      _skipWs();
    }
    return SgfNode(props, []);
  }

  String _readPropIdent() {
    final start = _pos;
    while (_pos < _s.length) {
      final u = _s.codeUnitAt(_pos);
      final isLetter = (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A);
      if (!isLetter) break;
      _pos++;
    }
    return _s.substring(start, _pos);
  }

  /// 读取一个属性值 `[ ... ]`，处理 `\]` / `\\` 转义。
  String _readPropValue() {
    _pos++; // '['
    final sb = StringBuffer();
    while (_pos < _s.length && _s[_pos] != ']') {
      final c = _s[_pos];
      if (c == r'\') {
        if (_pos + 1 < _s.length) {
          sb.write(_s[_pos + 1]);
          _pos += 2;
        } else {
          _pos++;
        }
      } else {
        sb.write(c);
        _pos++;
      }
    }
    if (_pos >= _s.length) throw FormatException('SGF 属性值缺少 `]`');
    _pos++; // ']'
    return sb.toString();
  }

  void _skipWs() {
    while (_pos < _s.length &&
        (_s[_pos] == ' ' ||
            _s[_pos] == '\t' ||
            _s[_pos] == '\r' ||
            _s[_pos] == '\n')) {
      _pos++;
    }
  }
}
