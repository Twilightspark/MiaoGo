import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:path_provider/path_provider.dart';

/// 棋谱来源。
enum GameSource {
  career('生涯'),
  ai('人机'),
  research('研究');

  const GameSource(this.label);
  final String label;
}

/// 对局结果（玩家视角）。
enum GameResult {
  win('胜'),
  loss('负'),
  draw('和');

  const GameResult(this.label);
  final String label;
}

/// 一局个人棋谱记录。
class GameRecord {
  const GameRecord({
    required this.id,
    required this.date,
    required this.opponentName,
    required this.opponentRank,
    required this.result,
    required this.boardSize,
    required this.rule,
    required this.komi,
    required this.sgfPath,
    required this.source,
    required this.moveCount,
    this.tournamentId,
    this.sgfContent,
  });

  final String id;
  final DateTime date;
  final String opponentName;
  final int opponentRank;
  final GameResult result;
  final int boardSize;
  final GoRule rule;
  final double komi;
  final String sgfPath;
  final GameSource source;
  final int moveCount;

  /// 生涯大赛 id（无则为空；用于赛事复盘定位本赛事对局）。
  final String? tournamentId;

  /// SGF 内容（写入文件后不入索引持久化）。
  final String? sgfContent;

  GameRecord copyWith({String? sgfPath, String? sgfContent}) => GameRecord(
        id: id,
        date: date,
        opponentName: opponentName,
        opponentRank: opponentRank,
        result: result,
        boardSize: boardSize,
        rule: rule,
        komi: komi,
        sgfPath: sgfPath ?? this.sgfPath,
        source: source,
        moveCount: moveCount,
        tournamentId: tournamentId,
        sgfContent: sgfContent ?? this.sgfContent,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.millisecondsSinceEpoch,
        'opponentName': opponentName,
        'opponentRank': opponentRank,
        'result': result.name,
        'boardSize': boardSize,
        'rule': rule.name,
        'komi': komi,
        'sgfPath': sgfPath,
        'source': source.name,
        'moveCount': moveCount,
        'tournamentId': tournamentId,
      };

  factory GameRecord.fromJson(Map<String, dynamic> json) => GameRecord(
        id: json['id'] as String? ?? '',
        date: DateTime.fromMillisecondsSinceEpoch(
            (json['date'] as num?)?.toInt() ?? 0),
        opponentName: json['opponentName'] as String? ?? '',
        opponentRank: (json['opponentRank'] as num?)?.toInt() ?? 0,
        result: GameResult.values.firstWhere((e) => e.name == json['result'],
            orElse: () => GameResult.draw),
        boardSize: (json['boardSize'] as num?)?.toInt() ?? 9,
        rule: GoRule.values.firstWhere((e) => e.name == json['rule'],
            orElse: () => GoRule.chinese),
        komi: (json['komi'] as num?)?.toDouble() ?? 7.5,
        sgfPath: json['sgfPath'] as String? ?? '',
        source: GameSource.values.firstWhere((e) => e.name == json['source'],
            orElse: () => GameSource.ai),
        moveCount: (json['moveCount'] as num?)?.toInt() ?? 0,
        tournamentId: json['tournamentId'] as String?,
      );
}

/// 个人棋谱：SGF 落盘到应用文档目录 `records/`，索引经 prefs 同步读写。
///
/// （P1 为便于测试采用 prefs 索引；P4 完整 SGF 导入导出时迁移到文档目录 JSON。）
class RecordStore extends Notifier<List<GameRecord>> {
  static const _key = 'game_records';

  @override
  List<GameRecord> build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(GameRecord.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 新增一局（含 SGF 落盘）；新记录在最前。
  Future<void> add(GameRecord record) async {
    final withFile = await _writeSgfIfNeeded(record);
    state = [withFile, ...state];
    _persist();
  }

  void delete(String id) {
    state = state.where((r) => r.id != id).toList();
    _persist();
  }

  /// 读取一局棋谱的 SGF 文本：优先暂存内容，否则读落盘文件。
  Future<String?> sgfContentOf(GameRecord record) async {
    final cached = record.sgfContent;
    if (cached != null && cached.isNotEmpty) return cached;
    if (record.sgfPath.isEmpty) return null;
    try {
      final file = File(record.sgfPath);
      if (await file.exists()) return await file.readAsString();
    } catch (_) {
      // 读盘失败按缺失处理。
    }
    return null;
  }

  void clear() {
    state = const [];
    _persist();
  }

  Future<GameRecord> _writeSgfIfNeeded(GameRecord record) async {
    final content = record.sgfContent;
    if (content == null || content.isEmpty) return record;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder =
          Directory('${dir.path}${Platform.pathSeparator}records');
      await folder.create(recursive: true);
      final file =
          File('${folder.path}${Platform.pathSeparator}${record.id}.sgf');
      await file.writeAsString(content, flush: true);
      return record.copyWith(sgfPath: file.path);
    } catch (_) {
      // 无平台目录（如测试环境）时仅记录索引，SGF 路径留空。
      return record;
    }
  }

  void _persist() {
    ref.read(sharedPreferencesProvider).setString(
          _key,
          jsonEncode(state.map((r) => r.toJson()).toList()),
        );
  }
}

final recordStoreProvider =
    NotifierProvider<RecordStore, List<GameRecord>>(RecordStore.new);
