/// 棋子颜色。
enum PlayerColor {
  black('黑'),
  white('白');

  const PlayerColor(this.label);
  final String label;

  PlayerColor get opposite =>
      this == PlayerColor.black ? PlayerColor.white : PlayerColor.black;
}

/// 一步棋：普通落子（row/col 非空）或 PASS / 认输。
class Move {
  const Move.point(this.color, this.row, this.col)
      : isPass = false,
        isResign = false;

  const Move.pass(this.color)
      : row = null,
        col = null,
        isPass = true,
        isResign = false;

  const Move.resign(this.color)
      : row = null,
        col = null,
        isPass = false,
        isResign = true;

  final PlayerColor color;
  final int? row;
  final int? col;
  final bool isPass;
  final bool isResign;

  @override
  bool operator ==(Object other) =>
      other is Move &&
      other.color == color &&
      other.row == row &&
      other.col == col &&
      other.isPass == isPass &&
      other.isResign == isResign;

  @override
  int get hashCode => Object.hash(color, row, col, isPass, isResign);

  @override
  String toString() {
    if (isPass) return '${color.name} PASS';
    if (isResign) return '${color.name} 认输';
    return '${color.name}($row,$col)';
  }
}
