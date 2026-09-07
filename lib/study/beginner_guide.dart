// 基础规则新手指引：12 步引导式入门（纯 Dart，不依赖 Flutter，便于单测）。
//
// 由 BeginnerGuideEngine 驱动：每步维护独立棋盘（真实围棋规则，见 core/board），
// 支持上一步/重试/下一步、引导文案、棋盘标记与逐手反馈。

import 'dart:collection';

import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';

/// 步骤交互类型（决定“下一步”解锁与棋盘可点性）。
enum GuideInteraction {
  /// 纯阅读：进入即完成。
  info,

  /// 阅读 + 必须执行一次「停一手」动作。
  infoPass,

  /// 任意空点落一子即完成（第 1 步）。
  tapAny,

  /// 在棋盘选项点上选择气数答案。
  quizCount,

  /// 在指定目标点落子（含分相：先尝试禁着点 / 后补最后一手等）。
  place,
}

/// 棋盘标记种类。
enum GuideMarkKind { dot, badge, ring }

/// 标记配色标签（转 GoColors 用）。
enum GuideMarkColor { auto, pine, wood }

/// 一块棋盘标注（UI 转 BoardMark）。
class GuideMark {
  const GuideMark(
    this.row,
    this.col,
    this.kind, {
    this.text,
    this.color = GuideMarkColor.auto,
  });

  final int row;
  final int col;
  final GuideMarkKind kind;
  final String? text;
  final GuideMarkColor color;

  @override
  bool operator ==(Object other) =>
      other is GuideMark &&
      other.row == row &&
      other.col == col &&
      other.kind == kind &&
      other.text == text &&
      other.color == color;

  @override
  int get hashCode => Object.hash(row, col, kind, text, color);
}

/// 一次点击后的反馈。
class GuideFeedback {
  const GuideFeedback(this.message, {this.good = false});

  final String message;

  /// 是否正向（正确/教学成功的提示）。
  final bool good;
}

/// 单个步骤描述。
class GuideStep {
  const GuideStep({
    required this.title,
    required this.instruction,
    required this.interaction,
  });

  final String title;
  final String instruction;
  final GuideInteraction interaction;
}

/// 十二步内容（顺序即索引）。
const List<GuideStep> kGuideSteps = [
  GuideStep(
    title: '认识棋盘与棋子',
    instruction: '棋盘由横竖交叉的线组成，交点就是落子处。对局双方轮流各下一子，'
        '黑方先手、白方后手。\n现在随便点一个空交叉点，先放下一颗黑棋试试。',
    interaction: GuideInteraction.tapAny,
  ),
  GuideStep(
    title: '气与提子',
    instruction: '与棋子直线相邻的空交叉点叫「气」，是棋子活着的依据。'
        '图中圆点标出了各棋串的气：中央黑子 4 气、角上黑子 2 气（贴边少一口气）。'
        '\n同色棋子连成一串，就共享整串的气；一方的气被全部堵死，就被提下棋盘——'
        '下一步亲手试试吃子。',
    interaction: GuideInteraction.info,
  ),
  GuideStep(
    title: '数气练习',
    instruction: '数一数中间这块黑棋有几口气？提示：只数紧贴黑棋的空点，'
        '被白棋占住的不算。\n下方 4 个带数字的选项点就是你的答案，'
        '点击它（在那落子）即可作答。',
    interaction: GuideInteraction.quizCount,
  ),
  GuideStep(
    title: '提子实操',
    instruction: '中间这颗白棋上下左都被黑棋围住，只剩一口气（圆圈处）。'
        '点击圆圈处，把最后一口气堵上，吃掉这颗白棋。',
    interaction: GuideInteraction.place,
  ),
  GuideStep(
    title: '禁入点与无气吃子',
    instruction: '规则一：落子后若自己的棋无气、又提不掉对方，该点为「禁入点」，'
        '不能下。先点一下中央带 ✗ 的点试试。\n'
        '规则二：若是落在对方的最后一口气上能吃掉对方，哪怕当时自己没有气也合法。'
        '随后去左下角，白棋只剩一口气，在那里落子提掉它们。',
    interaction: GuideInteraction.place,
  ),
  GuideStep(
    title: '连接延气',
    instruction: '中间这颗黑棋正被白棋围住，只剩一口气（圆圈处）。'
        '旁边有一颗己方黑棋——把这两颗连成一片，气就会变多，白棋就吃不掉了。\n'
        '点击圆圈处连接。',
    interaction: GuideInteraction.place,
  ),
  GuideStep(
    title: '分断吃子',
    instruction: '两颗白棋都只剩中间这一口气（圆圈处）——这里也是它们“快要连上”'
        '的断点。\n黑棋下在这里，既切断白棋的联系，又能把两颗白棋同时提掉。'
        '点击圆圈处。',
    interaction: GuideInteraction.place,
  ),
  GuideStep(
    title: '做眼：两眼活棋',
    instruction: '被围住的棋只要做出两个互不相连的「眼」，对方就永远吃不掉'
        '（两个眼不可能同时被填死）。\n左下这块黑棋在边上做成「直三」，'
        '在圆圈处补一手，即可得到两个眼位。点击圆圈处做眼。',
    interaction: GuideInteraction.place,
  ),
  GuideStep(
    title: '打劫',
    instruction: '第 1 步：中央白棋被三面包围，先在圆圈处提掉它。\n'
        '提子后这颗黑棋只剩一口气，正是刚才白棋的位置——白棋若立刻在原位提回，'
        '会还原成刚下完的局面。第 2 步：点击那个位置，试试用白棋立刻提回。',
    interaction: GuideInteraction.place,
  ),
  GuideStep(
    title: '胜负判定',
    instruction: '终局后比较双方围到的地盘与子：中国规则「数子」（子＋围住的空点），'
        '日韩规则「数目」（空＋提子）。黑棋先手占便宜，故黑方要「贴目」：'
        '中国规则贴 7.5 目（约 3¾ 子）。\n'
        '图中圆点即双方各围住的地盘空点；与电脑对弈到尾声点「点目」，会自动数子/'
        '数目判定胜负。',
    interaction: GuideInteraction.info,
  ),
  GuideStep(
    title: '停一手',
    instruction: '黑、白已沿中线各占半盘，各自靠两个独立的「眼位」（两口气）活棋，'
        '盘上再无可以争夺的空点。\n此时若黑方继续在自己眼位里落子，等于自己堵死一口气，'
        '陷入「自紧」，甚至可能被整串提掉；白方同理。\n正确做法是选择「停一手」：'
        '双方都停一手，对局结束并自动点目。点击下方按钮，让黑棋停一手。',
    interaction: GuideInteraction.infoPass,
  ),
  GuideStep(
    title: '毕业挑战',
    instruction: '恭喜你学到最后一课！盘面上 80 颗白棋占满了除天元外的所有交点，'
        '它们连成一片、只剩天元一口气。\n在天元（中心）落一颗黑棋，'
        '一口气提光整盘白棋！',
    interaction: GuideInteraction.place,
  ),
];

/// 引导引擎：管理步骤推进、各步棋盘与反馈。
class BeginnerGuideEngine {
  BeginnerGuideEngine({int initialStep = 0}) {
    _completed = List.filled(kGuideSteps.length, false);
    _boardCache = List<GoBoard?>.filled(kGuideSteps.length, null);
    _marksCache = List<List<GuideMark>?>.filled(kGuideSteps.length, null);
    _lastMoveCache = List<Move?>.filled(kGuideSteps.length, null);
    _step = initialStep.clamp(0, kGuideSteps.length - 1);
    _initStep();
  }

  static const int totalSteps = 12;

  int _step = 0;
  late List<bool> _completed;
  late List<GoBoard?> _boardCache;
  late List<List<GuideMark>?> _marksCache;
  late List<Move?> _lastMoveCache;

  // 当前步骤运行态。
  late GoBoard _board;
  List<GuideMark> _marks = const [];
  Move? _lastMove;
  bool _phaseA = false; // 第 5/9 步的分相标记
  GuideFeedback? _feedback;

  int get index => _step;
  GuideStep get step => kGuideSteps[_step];
  GoBoard get board => _board;
  List<GuideMark> get marks => _marks;
  Move? get lastMove => _lastMove;
  GuideFeedback? get feedback => _feedback;
  bool get completed => _completed[_step];

  /// 当前步是否可点（棋盘交互）。
  bool get canPlay {
    if (completed) return false;
    return step.interaction == GuideInteraction.tapAny ||
        step.interaction == GuideInteraction.quizCount ||
        step.interaction == GuideInteraction.place;
  }

  bool get canPrev => _step > 0;

  /// 讲解/停一手步无“重试”概念。
  bool get canRetry =>
      step.interaction == GuideInteraction.tapAny ||
      step.interaction == GuideInteraction.quizCount ||
      step.interaction == GuideInteraction.place;

  bool get showPass => step.interaction == GuideInteraction.infoPass;

  bool get canNext => completed;

  bool get isLastStep => _step == kGuideSteps.length - 1;

  /// 进入新步骤：恢复完成态棋盘或重建初始局面。
  void _initStep() {
    _feedback = null;
    final cached = _boardCache[_step];
    if (cached != null) {
      _board = cached;
      _marks = _marksCache[_step] ?? const [];
      _lastMove = _lastMoveCache[_step];
    } else {
      _buildInitial();
      _phaseA = false;
    }
    if (step.interaction == GuideInteraction.info) {
      _completed[_step] = true;
    }
  }

  /// 重建当前步骤初始局面（重试 / 首次进入）。
  void _buildInitial() {
    _lastMove = null;
    switch (_step) {
      case 0:
        _board = _emptyBoard();
        _marks = const [];
        break;
      case 1:
        _board = _emptyBoard();
        _setup(_board, [
          black(4, 4),
          black(0, 0),
          white(6, 6),
        ]);
        _marks = [
          liberty(3, 4),
          liberty(5, 4),
          liberty(4, 3),
          liberty(4, 5),
          liberty(0, 1),
          liberty(1, 0),
          liberty(5, 6),
          liberty(7, 6),
          liberty(6, 5),
          liberty(6, 7),
        ];
        break;
      case 2:
        _board = _emptyBoard();
        _setup(_board, [
          black(4, 4),
          black(4, 5),
          black(5, 4),
          black(5, 5),
          white(3, 4),
          white(3, 5),
          white(6, 4),
          white(6, 5),
        ]);
        _marks = _quizOptionMarks();
        break;
      case 3:
        _board = _emptyBoard();
        _setup(_board, [
          white(4, 4),
          black(3, 4),
          black(4, 3),
          black(4, 5),
        ]);
        _marks = [ring(5, 4)];
        break;
      case 4:
        _board = _emptyBoard();
        _setup(_board, [
          // 白环（中央禁入点演示）。
          white(3, 3),
          white(3, 4),
          white(3, 5),
          white(4, 3),
          white(4, 5),
          white(5, 3),
          white(5, 4),
          white(5, 5),
          // 左下角白 L：仅剩一口“无气吃子”的气。
          white(6, 0),
          white(7, 0),
          white(8, 0),
          white(8, 1),
          white(8, 2),
          // 黑方围堵（含包住目标气 (6,1) 的黑子）。
          black(5, 0),
          black(5, 1),
          black(6, 2),
          black(7, 1),
          black(7, 2),
          black(8, 3),
        ]);
        _marks = [badge(4, 4, '✗')];
        break;
      case 5:
        _board = _emptyBoard();
        _setup(_board, [
          black(4, 4),
          black(4, 6),
          white(3, 4),
          white(4, 3),
          white(5, 4),
        ]);
        _marks = [ring(4, 5)];
        break;
      case 6:
        _board = _emptyBoard();
        _setup(_board, [
          white(4, 4),
          white(4, 6),
          black(3, 4),
          black(4, 3),
          black(5, 4),
          black(3, 6),
          black(4, 7),
          black(5, 6),
        ]);
        _marks = [ring(4, 5)];
        break;
      case 7:
        _board = _emptyBoard();
        _setup(_board, [
          // 黑“直三”活形（含待补点 (8,5)）。
          black(7, 3),
          black(7, 4),
          black(7, 5),
          black(7, 6),
          black(7, 7),
          black(8, 3),
          black(8, 7),
          // 白墙。
          white(6, 2),
          white(6, 3),
          white(6, 4),
          white(6, 5),
          white(6, 6),
          white(6, 7),
          white(6, 8),
          white(7, 2),
          white(8, 2),
          white(7, 8),
          white(8, 8),
        ]);
        _marks = [ring(8, 5)];
        break;
      case 8:
        _board = _emptyBoard();
        _setup(_board, [
          // 白：中心子将被提，形成单劫。
          white(4, 4),
          white(3, 5),
          white(5, 5),
          white(4, 6),
          // 黑：三面包围。
          black(3, 4),
          black(4, 3),
          black(5, 4),
        ]);
        _marks = [ring(4, 5)];
        break;
      case 9:
        _board = _emptyBoard();
        _setup(_board, _endgameStones());
        _marks = [
          liberty(7, 0, color: GuideMarkColor.pine),
          liberty(7, 1, color: GuideMarkColor.pine),
          liberty(8, 0, color: GuideMarkColor.pine),
          liberty(8, 1, color: GuideMarkColor.pine),
          liberty(2, 6, color: GuideMarkColor.wood),
          liberty(2, 7, color: GuideMarkColor.wood),
          liberty(3, 6, color: GuideMarkColor.wood),
          liberty(3, 7, color: GuideMarkColor.wood),
        ];
        break;
      case 10:
        // 停一手：黑、白各占半盘，各剩两个眼位（两口气）；再下只会自紧。
        _board = _emptyBoard();
        for (var r = 0; r < 4; r++) {
          for (var c = 0; c < 9; c++) {
            if ((r == 1 && c == 2) || (r == 1 && c == 6)) continue;
            _board.setStone(r, c, PlayerColor.white);
          }
        }
        for (var r = 4; r < 9; r++) {
          for (var c = 0; c < 9; c++) {
            if ((r == 7 && c == 2) || (r == 7 && c == 6)) continue;
            _board.setStone(r, c, PlayerColor.black);
          }
        }
        _marks = [
          liberty(7, 2, color: GuideMarkColor.pine),
          liberty(7, 6, color: GuideMarkColor.pine),
          liberty(1, 2, color: GuideMarkColor.wood),
          liberty(1, 6, color: GuideMarkColor.wood),
        ];
        break;
      default:
        _board = _emptyBoard();
        for (var r = 0; r < 9; r++) {
          for (var c = 0; c < 9; c++) {
            if (r == 4 && c == 4) continue;
            _board.setStone(r, c, PlayerColor.white);
          }
        }
        _marks = [ring(4, 4)];
    }
  }

  static GoBoard _emptyBoard() => GoBoard(size: 9, superko: true);

  static void _setup(GoBoard b, List<(PlayerColor, int, int)> stones) {
    for (final (color, r, c) in stones) {
      b.setStone(r, c, color);
    }
  }

  static (PlayerColor, int, int) black(int r, int c) =>
      (PlayerColor.black, r, c);
  static (PlayerColor, int, int) white(int r, int c) =>
      (PlayerColor.white, r, c);

  static GuideMark liberty(int r, int c,
          {GuideMarkColor color = GuideMarkColor.auto}) =>
      GuideMark(r, c, GuideMarkKind.dot, color: color);
  static GuideMark badge(int r, int c, String text) =>
      GuideMark(r, c, GuideMarkKind.badge, text: text);
  static GuideMark ring(int r, int c) =>
      GuideMark(r, c, GuideMarkKind.ring);

  /// 第 3 步选项：数值徽章放在底部 4 个交点。
  static List<GuideMark> _quizOptionMarks() => const [
        GuideMark(8, 1, GuideMarkKind.badge, text: '3'),
        GuideMark(8, 3, GuideMarkKind.badge, text: '4'),
        GuideMark(8, 5, GuideMarkKind.badge, text: '8'),
        GuideMark(8, 7, GuideMarkKind.badge, text: '6'),
      ];

  /// 收官示例盘（第 10/11 步共用）：黑右下围 4 点、白左上围 4 点。
  static List<(PlayerColor, int, int)> _endgameStones() => [
        black(6, 0),
        black(6, 1),
        black(6, 2),
        black(7, 2),
        black(8, 2),
        white(1, 6),
        white(1, 7),
        white(4, 6),
        white(4, 7),
        white(2, 5),
        white(3, 5),
        white(2, 8),
        white(3, 8),
      ];

  void retry() {
    _boardCache[_step] = null;
    _marksCache[_step] = null;
    _lastMoveCache[_step] = null;
    _completed[_step] = false;
    _feedback = null;
    _buildInitial();
  }

  void gotoPrev() {
    if (_step == 0) return;
    _step--;
    _initStep();
  }

  void gotoNext() {
    if (!canNext) return;
    if (_step >= kGuideSteps.length - 1) return;
    _step++;
    _initStep();
  }

  /// 停一手（第 11 步）。
  void pass() {
    if (!showPass || completed) return;
    _completed[_step] = true;
    _feedback = const GuideFeedback('黑棋停一手。双方都停一手后，对局结束、自动点目判定胜负。',
        good: true);
  }

  /// 处理一次棋盘点击，返回反馈（同时记录为当前反馈）。
  GuideFeedback onTap(int row, int col) {
    final GuideFeedback result;
    switch (_step) {
      case 0:
        result = _handleTapAny(row, col);
      case 1:
        result = const GuideFeedback('这里是阅读步骤，点“下一步”继续。');
      case 2:
        result = _handleQuiz(row, col);
      case 3:
        result = _handleSimpleCapture(
          row,
          col,
          target: (5, 4),
          effect: (b) => b.at(4, 4) == null,
          success: '提子成功！白棋的最后一口气被堵上，整颗白子被提下棋盘（提 1 子）。',
          wrong: '要提的是中央白棋：它的最后一口气在圆圈处，在那里落子。',
        );
      case 4:
        result = _handleSuicideThenCapture(row, col);
      case 5:
        result = _handleConnect(row, col);
      case 6:
        result = _handleCut(row, col);
      case 7:
        result = _handleEye(row, col);
      case 8:
        result = _handleKo(row, col);
      case 9:
        result = const GuideFeedback('这里是阅读步骤，点“下一步”继续。');
      case 10:
        result = const GuideFeedback('请点击下方「停一手」按钮。');
      default:
        result = _handleFinale(row, col);
    }
    // 处理程序内部未写入反馈的返回（错误/占点等）才补记；成功路径自带更完整文案。
    _feedback ??= result;
    return result;
  }

  /// 尝试落子：克隆验证，命中效果则提交并（默认）完成步骤；否则仅提示。
  ///
  /// [complete] 为 false 时（如打劫第 1 相）只提交棋盘、不改完成态。
  GuideFeedback _tryTarget(
    int row,
    int col,
    List<(int, int)> candidates,
    bool Function(GoBoard after) effect, {
    required String success,
    required String wrong,
    bool complete = true,
    List<GuideMark> Function()? marksBuilder,
  }) {
    if (_board.at(row, col) != null) {
      return const GuideFeedback('这里已经有棋子了。');
    }
    if (!candidates.any((p) => p.$1 == row && p.$2 == col)) {
      return GuideFeedback(wrong);
    }
    final trial = _board.clone(superko: true);
    if (!trial.play(PlayerColor.black, row, col)) {
      return GuideFeedback(wrong);
    }
    if (!effect(trial)) {
      return GuideFeedback(wrong);
    }
    _board = trial;
    _lastMove = Move.point(PlayerColor.black, row, col);
    _feedback = GuideFeedback(success, good: true);
    if (complete) {
      _complete(success, marksBuilder: marksBuilder);
    }
    return GuideFeedback(success, good: true);
  }

  /// 通用提交：完成当前步骤并缓存状态。
  void _complete(String msg, {List<GuideMark> Function()? marksBuilder}) {
    _completed[_step] = true;
    if (marksBuilder != null) _marks = marksBuilder();
    _boardCache[_step] = _board;
    _marksCache[_step] = List.of(_marks);
    _lastMoveCache[_step] = _lastMove;
    _feedback = GuideFeedback(msg, good: true);
  }

  GuideFeedback _handleTapAny(int row, int col) {
    if (_board.at(row, col) != null) {
      return const GuideFeedback('这里已经有棋子了，换个空点。');
    }
    _board = _board.clone();
    _board.play(PlayerColor.black, row, col);
    _lastMove = Move.point(PlayerColor.black, row, col);
    _complete('落子成功！这就是一手棋：黑先手落子，接下来换白方。点“下一步”学习“气”。');
    return GuideFeedback('落子成功！', good: true);
  }

  GuideFeedback _handleQuiz(int row, int col) {
    final liberties = _board.groupLiberties(4, 4);
    // 只允许点击选项徽章点。
    final optionAt = <(int, int), String>{
      (8, 1): '3',
      (8, 3): '4',
      (8, 5): '8',
      (8, 7): '6',
    };
    final text = optionAt[(row, col)];
    if (text == null) {
      return const GuideFeedback('请在下方四个选项点作答。');
    }
    if (_board.at(row, col) != null) {
      return const GuideFeedback('这个选项点已经有子了。');
    }
    if ('$liberties' != text) {
      return GuideFeedback(
          '答错了。再数一次：只把紧贴黑棋的空点算作气，被白棋占住的不算。');
    }
    final b = _board.clone();
    b.play(PlayerColor.black, row, col);
    _board = b;
    _lastMove = Move.point(PlayerColor.black, row, col);
    final revealed = <GuideMark>[];
    for (final (r, c) in const [(4, 3), (4, 6), (5, 3), (5, 6)]) {
      revealed.add(liberty(r, c));
    }
    _complete('答对了！这块 2×2 黑棋共有 $liberties 口气，图中小点即为它的气。',
        marksBuilder: () => revealed);
    return GuideFeedback('正确！', good: true);
  }

  GuideFeedback _handleSimpleCapture(
    int row,
    int col, {
    required (int, int) target,
    required bool Function(GoBoard b) effect,
    required String success,
    required String wrong,
  }) {
    return _tryTarget(row, col, [target], effect,
        success: success, wrong: wrong);
  }

  GuideFeedback _handleSuicideThenCapture(int row, int col) {
    if (!_phaseA) {
      // 阶段 A：尝试中心禁入点（无气且不能吃子 → 规则禁止）。
      if (row == 4 && col == 4) {
        if (_board.at(4, 4) != null) {
          return const GuideFeedback('这里被白棋包围着，不要真下；用旁边棋盘试试。');
        }
        final legal = _board.isLegal(PlayerColor.black, 4, 4);
        if (legal) {
          return const GuideFeedback('咦，这一手居然是合法的？请重新试一次。');
        }
        _phaseA = true;
        _marks = [
          badge(4, 4, '✗'),
          ...const [GuideMark(6, 1, GuideMarkKind.ring)],
        ];
        return const GuideFeedback(
          '对！这是禁入点：黑子落下去没有气，也吃不到白棋（自杀禁着），所以点不动。'
          '现在去左下角：白棋只剩一口气，堵上那口气就能把它提掉。',
          good: true,
        );
      }
      return const GuideFeedback(
          '先试试中央带 ✗ 的点：它四周都是白棋，黑子落下去无气又不能吃子，属于禁入点。');
    }
    // 阶段 B：无气吃子点 (6,1)。
    return _tryTarget(
      row,
      col,
      const [(6, 1)],
      (b) => b.at(6, 0) == null &&
          b.at(7, 0) == null &&
          b.at(8, 0) == null &&
          b.at(8, 1) == null &&
          b.at(8, 2) == null,
      success: '提子成功！(6,1) 这颗黑子本身也没有气，但因为它正好堵住白棋的最后一口气、'
          '能提掉 5 颗白棋，所以是合法的一手。',
      wrong: '要去左下角提白棋：它们只剩一口气，在那口气（圆圈处）落子即可。',
    );
  }

  GuideFeedback _handleConnect(int row, int col) {
    return _tryTarget(
      row,
      col,
      const [(4, 5)],
      (b) => _sameGroup(b, 4, 4, 4, 6),
      success: '连接成功！两颗黑棋连成一片，共 5 口气，白棋再也吃不掉这块棋了。',
      wrong: '这颗黑棋只剩一口气（圆圈处），在那里落子与右边的黑棋相连才能延气。',
    );
  }

  GuideFeedback _handleCut(int row, int col) {
    return _tryTarget(
      row,
      col,
      const [(4, 5)],
      (b) => b.at(4, 4) == null && b.at(4, 6) == null,
      success: '分断成功！黑棋切断了两颗白棋（它们本来可以连上），并把它们同时提走 2 子。',
      wrong: '要在中间断点（圆圈处）落子：它能切断白棋并同时提掉两子。',
    );
  }

  GuideFeedback _handleEye(int row, int col) {
    return _tryTarget(
      row,
      col,
      const [(8, 5)],
      (b) =>
          b.at(8, 5) == PlayerColor.black &&
          b.at(8, 4) == null &&
          b.at(8, 6) == null &&
          b.groupLiberties(7, 3) == 2,
      success: '做眼成功！这块黑棋有了两个独立的眼（图中标出）。白棋无论先填哪个眼都会'
          '因无气自杀而不能下，黑棋已无法被吃掉——这就是活棋。',
      marksBuilder: () => const [
            GuideMark(8, 4, GuideMarkKind.badge, text: '眼'),
            GuideMark(8, 6, GuideMarkKind.badge, text: '眼'),
          ],
      wrong: '要在“直三”的中间点（圆圈处）落子，把两个眼位分开。',
    );
  }

  GuideFeedback _handleKo(int row, int col) {
    if (!_phaseA) {
      // 第 1 相：黑先在 (4,5) 提掉白子（不完成步骤，进入打劫讲解相）。
      final r = _tryTarget(
        row,
        col,
        const [(4, 5)],
        (b) =>
            b.at(4, 4) == null &&
            b.koPoint != null &&
            b.koPoint!.$1 == 4 &&
            b.koPoint!.$2 == 4,
        success: '你提掉了这颗白棋——但注意：这颗黑子也只剩一口气，正是刚才白棋所在的位置，'
            '局面形成了「劫」。现在试着用白棋立刻提回这颗黑子：点击 (4,4)。',
        wrong: '先提掉中央白棋：它的最后一口气在圆圈处，点击那里。',
        complete: false,
      );
      if (_board.at(4, 5) == PlayerColor.black) {
        _phaseA = true;
        _marks = const [GuideMark(4, 4, GuideMarkKind.ring)];
      }
      return r;
    }
    // 第 2 步：以白方干跑尝试立刻回提。
    if (_board.at(row, col) != null) {
      return const GuideFeedback('这里已有棋子；请点空的 (4,4) 试回提。');
    }
    final legal = _board.isLegal(PlayerColor.white, row, col);
    if (row == 4 && col == 4) {
      if (legal) {
        return const GuideFeedback('咦，(4,4) 居然能提回？请用「重试」再看一次。');
      }
      _complete('这就是打劫规则：刚被提一子的地方不能立刻原样提回。必须先到别处下一手'
          '（找劫材），等对方应了以后才能回来提劫。',
          marksBuilder: () => const [GuideMark(4, 4, GuideMarkKind.ring)]);
      return GuideFeedback('不能立刻提回！', good: true);
    }
    if (!legal) {
      return const GuideFeedback('这里也无气不能落子。请回到 (4,4)，直接试试“立刻提回”。');
    }
    return const GuideFeedback('这一手相当于到别处「找劫材」（是合法的）。不过为了体验规则，'
        '请回到 (4,4) 直接试一次“立刻提回”。');
  }

  GuideFeedback _handleFinale(int row, int col) {
    return _tryTarget(
      row,
      col,
      const [(4, 4)],
      (b) => _countStones(b, PlayerColor.white) == 0,
      success: '一锤定音！80 颗白棋只剩天元一口气，被这一手全部提光。你已掌握入门基础规则！',
      wrong: '要在天元（中心圆环处）落子：整片白棋唯一的气就是那里。',
    );
  }

  /// (r1,c1) 与 (r2,c2) 是否同色同串。
  bool _sameGroup(GoBoard b, int r1, int c1, int r2, int c2) {
    final color = b.at(r1, c1);
    if (color == null || color != b.at(r2, c2)) return false;
    final seen = <int>{};
    final queue = Queue<int>();
    queue.add(r1 * 9 + c1);
    seen.add(r1 * 9 + c1);
    while (queue.isNotEmpty) {
      final v = queue.removeFirst();
      if (v == r2 * 9 + c2) return true;
      final r = v ~/ 9, c = v % 9;
      for (final (dr, dc) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nr = r + dr, nc = c + dc;
        if (!b.inBounds(nr, nc)) continue;
        if (b.at(nr, nc) == color && seen.add(nr * 9 + nc)) {
          queue.add(nr * 9 + nc);
        }
      }
    }
    return false;
  }

  int _countStones(GoBoard b, PlayerColor color) {
    var n = 0;
    for (var r = 0; r < b.size; r++) {
      for (var c = 0; c < b.size; c++) {
        if (b.at(r, c) == color) n++;
      }
    }
    return n;
  }
}
