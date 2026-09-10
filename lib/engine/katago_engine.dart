import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/engine/analysis.dart';
import 'package:miaogo/engine/difficulty.dart';
import 'package:miaogo/engine/gtp_client.dart';

/// 引擎生命周期状态。
enum EngineStatus {
  idle('未启动'),
  loading('引擎加载中'),
  ready('已就绪'),
  failed('引擎不可用');

  const EngineStatus(this.label);
  final String label;
}

/// 分析会话句柄：订阅更新并负责停止。
class AnalysisSession {
  AnalysisSession._(this._controller, this._stopTask);

  final StreamController<AnalysisUpdate> _controller;
  final Future<void> Function() _stopTask;

  Stream<AnalysisUpdate> get updates => _controller.stream;

  /// 停止分析（发送空行中断，并冲刷尾部行），保证后续命令协议状态干净。
  Future<void> stop() => _stopTask();
}

/// KataGo GTP 引擎：生命周期 + 盘面同步 + 搜索/分析。
///
/// 设计要点（AGENTS.md §4）：
/// - 通过 [GtpClient] 与子进程通信，进程/IO 均可注入以便单测。
/// - 引擎不维护棋步历史：每次搜索/分析用 `set_position` 重建盘面
///   （复盘"回放局面到引擎"同一入口）。
/// - 规则/贴目/难度参数做缓存，未变化不重复下发。
class KataGoEngine {
  /// 使用现成 client（测试注入 Mock）。
  KataGoEngine(this._client, {List<String> stderrTail = const []})
      : _stderrTail = stderrTail;

  /// 异步启动子进程并包装为引擎。
  ///
  /// [workingDirectory] 必须为可写目录：KataGo 默认把 `gtp_logs` 建在 CWD 下，
  /// Android 上应用进程 CWD 为 `/`（不可写），启动会抛
  /// "Error creating directory: Access is denied" 后退出，表现为 GTP 超时。
  /// [initialTimeout] 覆盖默认 GTP 超时：首个命令需等模型加载完成（真机冷启动较久）。
  /// 子进程 stderr 会被持续采集到 [stderrTail]（诊断用，引擎失败时可展示）。
  static Future<KataGoEngine> launch({
    required String binaryPath,
    required String modelPath,
    String? humanModelPath,
    required String configPath,
    String? workingDirectory,
    List<String> extraArgs = const [],
    Duration initialTimeout = const Duration(seconds: 120),
  }) async {
    final args = <String>['gtp', '-model', modelPath];
    if (humanModelPath != null) {
      args.addAll(['-human-model', humanModelPath]);
    }
    args.addAll(['-config', configPath, ...extraArgs]);
    final process = await Process.start(
      binaryPath,
      args,
      workingDirectory: workingDirectory,
    );
    final stderrTail = <String>[];
    process.stderr
        .transform(const Utf8Decoder())
        .transform(const LineSplitter())
        .listen((line) {
      stderrTail.add(line);
      if (stderrTail.length > 100) stderrTail.removeAt(0);
    });
    final engine = KataGoEngine(
      GtpClient(ProcessGtpIo(process), defaultTimeout: initialTimeout),
      stderrTail: stderrTail,
    );
    engine.exitCode = process.exitCode;
    return engine;
  }

  final GtpClient _client;
  final List<String> _stderrTail;

  /// 子进程退出码（测试注入 Mock 时为空；进程未退出则挂起等待）。
  Future<int>? exitCode;

  /// 最近 stderr 行（诊断用，引擎不可用时可展示）。
  List<String> get stderrTail => List.unmodifiable(_stderrTail);

  int? _boardSize;
  GoRule? _rule;
  double? _komi;

  /// 最近一次已应用的难度档（避免每手重复下发；分析态会清空）。
  int? _appliedRank;

  /// 当前已应用规则上下文（供诊断）。
  GoRule? get activeRule => _rule;

  Future<void> ensureConfigured({
    required int boardSize,
    required GoRule rule,
    required double komi,
  }) async {
    if (_boardSize != boardSize) {
      await _ok(await _client.send('boardsize $boardSize'),
          'boardsize $boardSize');
      _boardSize = boardSize;
    }
    if (_rule != rule) {
      await _ok(await _client.send('kata-set-rules ${rule.name}'),
          'kata-set-rules ${rule.name}');
      _rule = rule;
    }
    if (_komi != komi) {
      await _ok(await _client.send('komi ${_fmtNum(komi)}'), 'komi $komi');
      _komi = komi;
    }
  }

  /// 用 [board] 的全部棋子重建引擎盘面（`set_position`）。
  Future<void> setPosition(GoBoard board) async {
    final sb = StringBuffer('set_position');
    for (var r = 0; r < board.size; r++) {
      for (var c = 0; c < board.size; c++) {
        final stone = board.at(r, c);
        if (stone == null) continue;
        sb.write(' ${stone == PlayerColor.black ? 'b' : 'w'} '
            '${_coord(r, c)}');
      }
    }
    await _ok(await _client.send(sb.toString()), 'set_position');
  }

  /// 应用 Human SL 对弈参数（按 [diff] 档位），切换到人类棋风选点。
  ///
  /// 同一档位重复调用直接返回；分析态（[applyAnalysisParams]）会清空缓存，
  /// 保证对弈前重新下发。
  Future<void> applyDifficulty(EngineDifficulty diff) async {
    if (_appliedRank == diff.rankIndex) return;
    await _setParams({
      'humanSLProfile': diff.humanSLProfile,
      'humanSLChosenMoveProp': 1.0,
      'humanSLChosenMoveIgnorePass': true,
      'humanSLChosenMovePiklLambda': diff.piklLambda,
      'humanSLRootExploreProbWeightless': diff.rootExploreProbWeightless,
      'humanSLCpuctPermanent': diff.cpuctPermanent,
      'chosenMoveTemperatureEarly': diff.chosenMoveTemperatureEarly,
      'chosenMoveTemperature': diff.chosenMoveTemperature,
      'chosenMoveTemperatureHalflife': diff.chosenMoveTemperatureHalflife,
      'chosenMoveTemperatureOnlyBelowProb':
          diff.chosenMoveTemperatureOnlyBelowProb,
      'maxVisits': diff.maxVisits,
      'maxTime': diff.maxTimeMs / 1000.0,
      // 人类棋风：关闭几项增强搜索强度的特性（官方 human 配置）。
      'useNoisePruning': false,
      'useUncertainty': false,
      'subtreeValueBiasFactor': 0.0,
      'useLcbForSelection': false,
    });
    _appliedRank = diff.rankIndex;
  }

  /// 恢复分析态参数：关闭 Human SL 搜索偏置，恢复默认强度特性与搜索上限。
  ///
  /// [maxVisits]/[maxTimeSec] 默认接近无限，供 `kata-analyze` 持续流式输出；
  /// 单局面一次性分析请传有限预算（见 [searchAnalysis]）。
  Future<void> applyAnalysisParams({
    int maxVisits = 100000000,
    double maxTimeSec = 100000000.0,
  }) async {
    await _setParams({
      'humanSLChosenMoveProp': 0.0,
      'humanSLRootExploreProbWeightless': 0.0,
      'humanSLRootExploreProbWeightful': 0.0,
      'humanSLPlaExploreProbWeightless': 0.0,
      'humanSLOppExploreProbWeightless': 0.0,
      'useNoisePruning': true,
      'useUncertainty': true,
      'subtreeValueBiasFactor': 0.45,
      'useLcbForSelection': true,
      'maxVisits': maxVisits,
      'maxTime': maxTimeSec,
    });
    _appliedRank = null;
  }

  /// 批量设置引擎参数（`kata-set-params` 单条 JSON，减少往返）。
  Future<void> _setParams(Map<String, Object> params) async {
    final json = jsonEncode(params);
    await _ok(await _client.send('kata-set-params $json'), 'kata-set-params');
  }

  /// 是否已加载 Human SL 模型（`kata-get-models` 自检，失败返回 false）。
  Future<bool> hasHumanModel() async {
    final r = await _client.send('kata-get-models');
    if (!r.ok) return false;
    try {
      final list = jsonDecode(r.body) as List<dynamic>;
      return list.any((m) => m is Map && m['usesHumanSLProfile'] == true);
    } catch (_) {
      return false;
    }
  }

  /// 对局中切换规则/贴目（不改棋盘尺寸）。
  Future<void> updateRules(GoRule rule, double komi) async {
    if (_rule != rule) {
      await _ok(await _client.send('kata-set-rules ${rule.name}'),
          'kata-set-rules ${rule.name}');
      _rule = rule;
    }
    if (_komi != komi) {
      await _ok(await _client.send('komi ${_fmtNum(komi)}'), 'komi $komi');
      _komi = komi;
    }
  }

  /// 对弈搜索：应用 [difficulty]（Human SL 参数）后单次搜索。
  ///
  /// 返回最近一次分析更新 + 引擎自选着法（`play <move>`，含 `pass`/`resign`）。
  Future<({AnalysisUpdate? update, String? chosen})> searchAndAnalyze({
    required GoBoard board,
    required PlayerColor toMove,
    required GoRule rule,
    required double komi,
    required EngineDifficulty difficulty,
    bool ownership = false,
    int intervalMs = 100,
  }) async {
    await applyDifficulty(difficulty);
    return _runSearch(
      board: board,
      toMove: toMove,
      rule: rule,
      komi: komi,
      ownership: ownership,
      intervalMs: intervalMs,
    );
  }

  /// 单局面一次性分析搜索：中性参数 + 有限预算（[maxVisits]/[maxTimeMs]）。
  ///
  /// 用于胜率曲线采样 / 观赛领地评估等，避免套用对手段位的 Human SL 参数。
  Future<({AnalysisUpdate? update, String? chosen})> searchAnalysis({
    required GoBoard board,
    required PlayerColor toMove,
    required GoRule rule,
    required double komi,
    required int maxVisits,
    required int maxTimeMs,
    bool ownership = false,
    int intervalMs = 100,
  }) async {
    await applyAnalysisParams(
        maxVisits: maxVisits, maxTimeSec: maxTimeMs / 1000.0);
    return _runSearch(
      board: board,
      toMove: toMove,
      rule: rule,
      komi: komi,
      ownership: ownership,
      intervalMs: intervalMs,
    );
  }

  /// 搜索执行：`set_position` → `kata-search_analyze <color> <interval>[ ownership true]`
  /// → 跳过 ack（`= `）后逐行收集 `info`，直至 `play <move>` 行。
  Future<({AnalysisUpdate? update, String? chosen})> _runSearch({
    required GoBoard board,
    required PlayerColor toMove,
    required GoRule rule,
    required double komi,
    bool ownership = false,
    int intervalMs = 100,
  }) async {
    await ensureConfigured(boardSize: board.size, rule: rule, komi: komi);
    await setPosition(board);

    final parser = KataAnalyzeParser(boardSize: board.size);
    final color = toMove == PlayerColor.black ? 'b' : 'w';
    final cmd = StringBuffer('kata-search_analyze $color $intervalMs');
    if (ownership) cmd.write(' ownership true');

    AnalysisUpdate? last;
    String? chosen;
    await _client.streamLines(
      cmd.toString(),
      (line) {
        if (line.startsWith('play ')) {
          chosen = line.substring(5).trim();
          return true; // 搜索完成
        }
        return false;
      },
      onLine: (line) {
        if (line.startsWith('info ')) {
          last = parser.parse(line);
        }
      },
    );
    return (update: last, chosen: chosen);
  }

  /// 持续分析（实时热力图/AI 建议）：返回会话，可多次 [AnalysisSession.updates]
  /// 订阅直至 [AnalysisSession.stop]。
  ///
  /// 进入前先 [applyAnalysisParams]（中性参数 + 近无限上限）——实时覆盖层面向
  /// 人类复盘，应持续输出稳定评估，且不得残留对手段位的 Human SL 搜索偏置。
  AnalysisSession startAnalysis({
    required GoBoard board,
    required PlayerColor toMove,
    required GoRule rule,
    required double komi,
    int intervalMs = 200,
  }) {
    final controller = StreamController<AnalysisUpdate>();
    final io = _client.io;
    final parser = KataAnalyzeParser(boardSize: board.size);
    final color = toMove == PlayerColor.black ? 'b' : 'w';
    final cmd = 'kata-analyze $color $intervalMs ownership true rootInfo true';

    var cancelled = false;
    var acked = false;
    Future<void> readLoop() async {
      await applyAnalysisParams();
      await ensureConfigured(boardSize: board.size, rule: rule, komi: komi);
      await setPosition(board);
      await io.write(cmd);
      while (!cancelled) {
        final line =
            await io.readLine(timeout: const Duration(milliseconds: 200));
        if (line == null) continue;
        if (line.startsWith('=')) {
          if (!acked) {
            acked = true; // 命令回执
            continue;
          }
          break; // 引擎侧终止
        }
        if (line.startsWith('info ')) {
          final parsed = parser.parse(line);
          if (!controller.isClosed) controller.add(parsed);
        }
      }
      if (!controller.isClosed) await controller.close();
    }

    final task = readLoop();
    return AnalysisSession._(controller, () async {
      cancelled = true;
      await io.write(''); // 空行中断分析
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await task; // 等待读取循环退出
      // 冲刷尾部行（含空行命令的 `?`/`=` 与最后一批 info），保证后续命令干净。
      final drainDeadline =
          DateTime.now().add(const Duration(milliseconds: 250));
      while (DateTime.now().isBefore(drainDeadline)) {
        final line =
            await io.readLine(timeout: const Duration(milliseconds: 60));
        if (line == null) break;
        if (line.startsWith('info ')) {
          final parsed = parser.parse(line);
          if (!controller.isClosed) controller.add(parsed);
        }
      }
    });
  }

  /// 终局比分（GTP `final_score`）。
  Future<String> finalScore() async {
    final r = await _client.send('final_score');
    return r.ok ? r.body : '错误: ${r.body}';
  }

  Future<void> close() => _client.close();

  Future<void> _ok(GtpResponse r, String what) async {
    if (!r.ok) throw GtpEngineException('$what 失败: ${r.body}');
  }

  /// 行列 → GTP 顶点（大写列字母 + 自底向上行数字，如 `(3,4)` → `E4`）。
  static String _coord(int row, int col) =>
      '${GoBoard.letters[col].toUpperCase()}${row + 1}';

  static String _fmtNum(num v) => v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(1);
}

/// 引擎命令执行失败。
class GtpEngineException implements Exception {
  const GtpEngineException(this.message);
  final String message;

  @override
  String toString() => 'GtpEngineException: $message';
}
