import 'dart:async';

import 'package:miaogo/engine/gtp_client.dart';

/// 脚本化 GTP 传输：`write(command)` 时按 [script] 把该命令的响应行排入队列。
///
/// - 队列为空时 [readLine] 挂起直到有数据或超时（返回 null）。
/// - [scriptPrefixes] 用于按命令前缀匹配（如每次不同的 `set_position` / `kata-set-param`）。
/// - [writeError] 非空时 `write` 抛异常，用于测试引擎异常。
class MockGtpIo implements GtpIo {
  MockGtpIo([Map<String, List<String>>? script]) : script = script ?? {};

  /// command → 该命令依次返回的行（含 `=`/`?` 终止行）。
  Map<String, List<String>> script;

  /// 前缀脚本：命令不精确命中 [script] 时按前缀匹配。
  List<({String prefix, List<String> lines})> scriptPrefixes = [];

  /// 设置后 write 抛此异常（模拟引擎进程异常）。
  Object? writeError;

  /// 全部已发送命令。
  final List<String> sent = [];

  final List<String> _queue = [];
  final List<Completer<String?>> _waiters = [];

  @override
  Future<void> write(String line) async {
    if (writeError != null) throw writeError!;
    sent.add(line);
    final lines = script[line];
    if (lines != null) {
      _queue.addAll(lines);
      _pump();
      return;
    }
    for (final p in scriptPrefixes) {
      if (line.startsWith(p.prefix)) {
        _queue.addAll(p.lines);
        _pump();
        return;
      }
    }
  }

  @override
  Future<String?> readLine({Duration? timeout}) async {
    if (_queue.isNotEmpty) return _queue.removeAt(0);
    final completer = Completer<String?>();
    _waiters.add(completer);
    return completer.future.timeout(timeout ?? const Duration(milliseconds: 200),
        onTimeout: () => null);
  }

  void _pump() {
    while (_queue.isNotEmpty && _waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(_queue.removeAt(0));
    }
  }

  @override
  Future<void> close() async {}
}
