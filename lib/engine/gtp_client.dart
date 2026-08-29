import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// GTP 传输层抽象：命令写入 + 带超时的逐行读取。
///
/// 供 [GtpClient] 使用；真机走 [ProcessGtpIo]（子进程 stdin/stdout），
/// 测试用 [MockGtpIo] 注入脚本化响应。
abstract class GtpIo {
  /// 写入一行命令（自带换行）。
  Future<void> write(String line);

  /// 读取一行；[timeout] 内无数据返回 null。
  Future<String?> readLine({Duration? timeout});

  Future<void> close();
}

/// 进程式传输：包装 [Process] 的 stdin/stdout。
class ProcessGtpIo implements GtpIo {
  ProcessGtpIo(this._process);

  final Process _process;

  StreamQueue<String>? _queue;

  @override
  Future<void> write(String line) async {
    _process.stdin.write('$line\n');
    await _process.stdin.flush();
  }

  @override
  Future<String?> readLine({Duration? timeout}) {
    _queue ??= StreamQueue<String>(
      _process.stdout
          .transform(const Utf8Decoder())
          .transform(const LineSplitter()),
    );
    return _queue!.next(timeout: timeout ?? const Duration(seconds: 30));
  }

  @override
  Future<void> close() async {
    try {
      _process.stdin.close();
      await _process.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {
      _process.kill();
    }
  }
}

/// GTP 响应：`= body`（ok=true）或 `? body`（ok=false）。
class GtpResponse {
  const GtpResponse({required this.ok, required this.body, this.command});

  final bool ok;
  final String body;

  /// 引发该响应的原始命令（诊断用）。
  final String? command;

  bool get isError => !ok;
  @override
  String toString() =>
      'GtpResponse(${ok ? '=' : '?'} "$body"${command == null ? '' : ' <= $command'})';
}

/// GTP 超时异常。
class GtpTimeoutException implements Exception {
  const GtpTimeoutException(this.command);
  final String command;

  @override
  String toString() => 'GTP 命令超时: "$command"';
}

/// GTP 客户端：请求/响应 + 流式分析。
///
/// 命令均为行协议；响应以 `= `（成功）或 `? `（失败）开头。
/// [sendStream] 支持回调处理流式行（如 `info` / `play`），直到响应终止行。
class GtpClient {
  GtpClient(this._io, {this.defaultTimeout = const Duration(seconds: 30)});

  final GtpIo _io;
  final Duration defaultTimeout;

  /// 底层传输（流式命令直接读写用）。
  GtpIo get io => _io;

  /// 简单请求/响应；忽略响应前的流式行。
  Future<GtpResponse> send(String command, {Duration? timeout}) =>
      sendStream(command, (_) {}, timeout: timeout);

  /// 流式命令（kata-search_analyze / kata-analyze）读取。
  ///
  /// 协议：命令发出后立即回 `=` 作为回执，随后持续输出 `info`/`play` 等行，
  /// 直至 [until] 谓词满足或再次出现 `=`/`?`。首个 `=` 自动跳过。
  Future<void> streamLines(
    String command,
    bool Function(String line) until, {
    void Function(String line)? onLine,
    Duration? timeout,
  }) async {
    final t = timeout ?? defaultTimeout;
    await _io.write(command);
    final deadline = DateTime.now().add(t);
    var acked = false;
    while (true) {
      final remain = deadline.difference(DateTime.now());
      if (remain <= Duration.zero) {
        throw GtpTimeoutException(command);
      }
      final line = await _io.readLine(timeout: remain);
      if (line == null) {
        throw GtpTimeoutException(command);
      }
      if (line.startsWith('=')) {
        if (!acked) {
          acked = true; // 命令回执
          continue;
        }
        return; // 再次 `=` 视为完成
      }
      if (line.startsWith('?')) {
        throw GtpTimeoutException('$command 返回错误: $line');
      }
      if (until(line)) return;
      onLine?.call(line);
    }
  }

  /// 逐行读取直到出现响应终止行（`=`/`?`）。
  ///
  /// [onLine] 收到每条非响应行（含空行）。返回的 [GtpResponse] 为终止行结果。
  Future<GtpResponse> sendStream(
    String command,
    void Function(String line) onLine, {
    Duration? timeout,
  }) async {
    final t = timeout ?? defaultTimeout;
    await _io.write(command);
    final deadline = DateTime.now().add(t);
    while (true) {
      final remain = deadline.difference(DateTime.now());
      if (remain <= Duration.zero) {
        throw GtpTimeoutException(command);
      }
      final line = await _io.readLine(timeout: remain);
      if (line == null) {
        throw GtpTimeoutException(command);
      }
      if (line.startsWith('=')) {
        return GtpResponse(
          ok: true,
          body: line.length > 1 ? line.substring(1).trim() : '',
          command: command,
        );
      }
      if (line.startsWith('?')) {
        return GtpResponse(
          ok: false,
          body: line.length > 1 ? line.substring(1).trim() : '',
          command: command,
        );
      }
      onLine(line);
    }
  }

  /// 关闭传输。
  Future<void> close() => _io.close();
}

/// 简易流队列：依次取出流中的元素，支持超时。
///
/// 关键：同一时刻至多一个 [next] 等待者；新等待会放弃旧的未完成等待，
/// 但数据始终留在 [queue] 中（不会因废弃的等待回调而丢失）。
class StreamQueue<T> {
  StreamQueue(Stream<T> stream) {
    _subscription = stream.listen(
      (v) {
        _queue.add(v);
        _pump();
      },
      onDone: () {
        _done = true;
        _pumpDone();
      },
      onError: (Object e, StackTrace st) {
        _error = e;
        _pumpDone();
      },
      cancelOnError: true,
    );
  }

  final List<T> _queue = [];
  StreamSubscription<T>? _subscription;
  Completer<T?>? _pending;
  bool _done = false;
  Object? _error;

  /// 取下一个元素；流结束返回 null，错误重抛。
  /// [timeout] 内无数据返回 null，且该次等待被废弃（数据留待下次读取）。
  Future<T?> next({Duration? timeout}) {
    if (_queue.isNotEmpty) return Future.value(_queue.removeAt(0));
    if (_error != null) return Future.error(_error!);
    if (_done) return Future.value(null);
    _pending = Completer<T?>();
    final completer = _pending!;
    if (timeout == null) return completer.future;
    return completer.future.timeout(timeout, onTimeout: () {
      if (identical(_pending, completer)) _pending = null;
      return null;
    });
  }

  void _pump() {
    final c = _pending;
    if (c == null || c.isCompleted || _queue.isEmpty) return;
    _pending = null;
    c.complete(_queue.removeAt(0));
  }

  void _pumpDone() {
    final c = _pending;
    if (c == null || c.isCompleted) return;
    _pending = null;
    c.complete(null);
  }

  void cancel() => _subscription?.cancel();
}
