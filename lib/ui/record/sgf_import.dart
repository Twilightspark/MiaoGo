import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/storage/record_store.dart';

/// 选择并读取一个本地 SGF 文件内容；用户取消返回 null。
typedef SgfPicker = Future<String?> Function();

/// 默认本地文件选择器：走系统文件选择（Android SAF），仅过滤 `.sgf`。
Future<String?> _pickSgfFromDevice() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['sgf'],
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  final bytes = file.bytes;
  if (bytes != null && bytes.isNotEmpty) return _decode(bytes);
  final path = file.path;
  if (path == null) return null;
  try {
    return await File(path).readAsString();
  } catch (_) {
    return null;
  }
}

String _decode(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// 导入选文件服务（widget 测试可 override 返回固定内容）。
final sgfPickerProvider = Provider<SgfPicker>((_) => _pickSgfFromDevice);

/// 生成导入棋谱记录 id（与观赛记录同规则，保证唯一且可落盘为文件名）。
String newImportedRecordId() =>
    '${DateTime.now().microsecondsSinceEpoch}';

/// 由已解析的 SGF 构造「导入」棋谱记录（元数据取自文件头）。
///
/// 命名/结果按棋盘视角约定：黑先在前、`GameResult.win/loss` 表示黑/白胜，
/// 供棋谱页展示（个人对局的"玩家视角"语义仅用于首页历史，互不干扰）。
GameRecord importedRecord({
  required String id,
  required SgfGame game,
  DateTime? fallbackDate,
}) {
  final boardSize = _boardSize(game.size);
  final rule = ruleFromSgfProp(game.rulesProp);
  final komi = game.komi ?? rule.defaultKomi;
  final date = _parseSgfDate(game.date) ?? fallbackDate ?? DateTime.now();
  final black = _cleanName(game.blackName);
  final white = _cleanName(game.whiteName);
  final event = _cleanName(game.event);
  final result = _resultFromRe(game.result);

  String opponentName;
  if (black.isNotEmpty || white.isNotEmpty) {
    opponentName = [if (black.isNotEmpty) black, if (white.isNotEmpty) white]
        .join(' 对 ');
  } else if (event.isNotEmpty) {
    opponentName = event;
  } else {
    opponentName = '导入棋谱';
  }

  return GameRecord(
    id: id,
    date: date,
    opponentName: opponentName,
    opponentRank: 0,
    result: result,
    boardSize: boardSize,
    rule: rule,
    komi: komi,
    sgfPath: '',
    source: GameSource.imported,
    moveCount: game.moves.length,
    blackName: black.isEmpty ? null : black,
    whiteName: white.isEmpty ? null : white,
    sgfContent: null,
  );
}

/// 外部导入内容时统一走本入口（先校验能否解析，再落库）。
/// 返回记录；解析失败抛 [FormatException]。
GameRecord importedRecordFromContent({
  required String id,
  required String content,
  DateTime? fallbackDate,
}) {
  final game = Sgf.parse(content);
  return importedRecord(id: id, game: game, fallbackDate: fallbackDate);
}

String _cleanName(String? raw) => (raw ?? '').trim();

/// SGF `SZ` → 合法棋盘尺寸（异常缺省 19）。
int _boardSize(int? raw) {
  if (raw == null || raw < 2 || raw > 25) return 19;
  return raw;
}

/// SGF `RU` → 规则（容错大小写/后缀，如 `Chinese rules`）；未知缺省中国规则。
GoRule ruleFromSgfProp(String? raw) {
  if (raw == null) return GoRule.chinese;
  final v = raw.toLowerCase();
  if (v.contains('korea')) return GoRule.korean;
  if (v.contains('japan')) return GoRule.japanese;
  return GoRule.chinese;
}

/// SGF `DT`（如 `2016-03-09` / `2005-12-01a`）→ 日期；无法识别返回 null。
DateTime? _parseSgfDate(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(raw);
  if (m == null) return null;
  final year = int.tryParse(m.group(1)!);
  final month = int.tryParse(m.group(2)!);
  final day = int.tryParse(m.group(3)!);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month.clamp(1, 12).toInt(), day.clamp(1, 31).toInt());
}

/// SGF `RE` → 棋盘视角结果：`B…`黑胜 / `W…`白胜 / Draw·Jigo·0 和 / 其它未下完。
GameResult _resultFromRe(String? re) {
  if (re == null) return GameResult.abandoned;
  final v = re.toUpperCase();
  if (v.startsWith('B')) return GameResult.win;
  if (v.startsWith('W')) return GameResult.loss;
  if (v.startsWith('0') || v.contains('DRAW') || v.contains('JIGO')) {
    return GameResult.draw;
  }
  return GameResult.abandoned;
}
