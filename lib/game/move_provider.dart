import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';

/// 选点器抽象：对局逻辑依赖该接口取 AI 棋步。
///
/// 生产环境唯一实现为 KataGo 引擎（[KataGoMoveProvider]）；测试注入
/// 脚本化/固定行为的假实现（GameController 构造参数）。
abstract class MoveProvider {
  Future<Move> chooseMove(GoBoard board, PlayerColor toMove,
      {required int rankIndex});
}
