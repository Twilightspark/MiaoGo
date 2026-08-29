import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/engine/katago_engine.dart';
import 'package:miaogo/game/match_engine.dart';
import 'package:miaogo/storage/settings_store.dart';
import 'package:path_provider/path_provider.dart';

/// 引擎资源常量。
/// 二进制随 APK 作为原生库打进 nativeLibraryDir（android/app/src/main/jniLibs/arm64-v8a/libkatago.so），
/// 模型/配置仍为 Flutter assets（数据文件，解压到应用目录即可读取）。
const String kEngineBinaryLib = 'libkatago.so';
const String kB6c96ModelAsset =
    'assets/katago/kata1-b6c96-s175395328-d26788732.txt.gz';
const String kB18c384ModelAsset =
    'assets/katago/kata1-b18c384nbt-s9996604416-d4316597426.bin.gz';
const String kEngineConfigAsset = 'assets/katago/gtp.cfg';

/// 模型规格：一个引擎实例绑定一个模型（P3 双模型）。
///
/// - [kEngineModelKyu]（b6c96 小模型）：18级~1级（rankIndex 0..17）人机对弈。
/// - [kEngineModelDan]（b18c384 大模型）：1段~9段（rankIndex 18..26）人机对弈，
///   以及落点推荐/实时分析等全部分析功能。
class EngineModel {
  const EngineModel({
    required this.name,
    required this.modelAsset,
    required this.modelFile,
  });

  final String name;
  final String modelAsset;

  /// 解压到应用目录后的文件名（与 asset 同名，保证幂等跳过）。
  final String modelFile;

  @override
  bool operator ==(Object other) =>
      other is EngineModel && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// 小模型（级位对弈）：18级~1级。
const EngineModel kEngineModelKyu = EngineModel(
  name: 'b6c96',
  modelAsset: kB6c96ModelAsset,
  modelFile: 'kata1-b6c96-s175395328-d26788732.txt.gz',
);

/// 大模型（段位对弈 + 全部落点分析）：1段~9段。
const EngineModel kEngineModelDan = EngineModel(
  name: 'b18c384',
  modelAsset: kB18c384ModelAsset,
  modelFile: 'kata1-b18c384nbt-s9996604416-d4316597426.bin.gz',
);

/// 原生侧桥（MainActivity 注册）。
const MethodChannel _nativeChannel = MethodChannel('miaogo/native');

/// 获取可执行的原生库目录（Android nativeLibraryDir）。
///
/// 应用私有 files/ 目录被 SELinux/noexec 禁止 exec，原生库目录才可执行
/// （引擎二进制须走这里，见 AGENTS.md §8）。
Future<String> nativeLibraryDir() async {
  final path = await _nativeChannel.invokeMethod<String>('nativeLibraryDir');
  if (path == null || path.isEmpty) {
    throw const EngineResourceException(
        '未能获取 nativeLibraryDir（MethodChannel miaogo/native 未实现？）');
  }
  return path;
}

/// 单个引擎实例（一个模型）的加载状态控制器。
///
/// 同一 [EngineController] 类承载两个实例：
/// - [engineStatusProvider] = 小模型（b6c96，核心，级位对弈）；
/// - [danEngineStatusProvider] = 大模型（b18c384，段位对弈与分析）。
/// 各自独立生命周期，加载/失败互不影响。
class EngineController extends Notifier<EngineStatus> {
  /// 默认构造绑定小模型（保持公开无参，测试子类 super() 不受影响）。
  EngineController({this.model = kEngineModelKyu});

  final EngineModel model;

  KataGoEngine? _engine;

  /// 已就绪的引擎实例（ready 状态才有值）。
  KataGoEngine? get engine => _engine;

  /// 引擎初始化失败原因（failed 状态时有值）。
  String? lastError;

  @override
  EngineStatus build() {
    ref.onDispose(() {
      _engine?.close();
      _engine = null;
    });
    return EngineStatus.idle;
  }

  /// 预加载引擎：解压资源 → 启动子进程 → 就绪。
  ///
  /// 幂等：loading/ready 期间重复调用直接返回。
  Future<void> start() async {
    if (state == EngineStatus.loading || state == EngineStatus.ready) return;
    state = EngineStatus.loading;
    try {
      final paths = await _prepareAssets();
      final settings = ref.read(settingsProvider);
      _engine = await KataGoEngine.launch(
        binaryPath: paths.binary,
        modelPath: paths.model,
        configPath: paths.config,
        // 可写 CWD：KataGo 会把 gtp_logs 建在 CWD 下（Android 进程 CWD=/ 不可写，
        // 会导致启动即退出，见 katago_engine.dart）。
        workingDirectory: paths.engineDir,
        // 日志目录指向工作目录（可写）；低资源参数（maxThreads/nnMaxBatchSize/
        // nnCacheSizePowerOfTwo）是 gtp.cfg 的配置键，不是命令行参数，
        // 已在 assets/katago/gtp.cfg 底部设置。
        extraArgs: const [
          '-override-config',
          'logDir=gtp_logs',
        ],
      );
      // 首局默认配置（对局开始/切换规则时按需更新）。
      await _engine!.ensureConfigured(
        boardSize: settings.boardSize.size,
        rule: settings.rule,
        komi: settings.komi,
      );
      state = EngineStatus.ready;
    } catch (e) {
      var msg = e.toString();
      final eng = _engine;
      if (eng != null) {
        // 进程是否已退出：已退出附带 exit code；仍在跑视为超时挂起。
        final exitCode = eng.exitCode;
        int? exit;
        if (exitCode != null) {
          try {
            exit = await exitCode.timeout(const Duration(seconds: 1));
          } catch (_) {
            // 未退出（超时挂起/加载中）。
          }
        }
        if (exit != null) msg += '\n(引擎进程已退出，exit=$exit)';
        final tail = eng.stderrTail;
        if (tail.isNotEmpty) {
          msg += '\n--- 引擎 stderr 末 ${tail.length} 行 ---\n${tail.join('\n')}';
        }
      }
      lastError = msg;
      state = EngineStatus.failed;
      if (eng != null) {
        _engine = null;
        await eng.close();
      }
    }
  }

  /// 停止引擎（应用退出/设置页数据清除）。
  Future<void> stop() async {
    await _engine?.close();
    _engine = null;
    state = EngineStatus.idle;
  }

  /// 重启引擎（引擎进程异常后由对局页调用）：先停再启，回到 ready/failed。
  Future<void> restart() async {
    await stop();
    await start();
  }

  /// 从 assets 解压模型/配置到应用目录（幂等，跳过已存在）；二进制走原生库目录。
  Future<({String binary, String model, String config, String engineDir})>
      _prepareAssets() async {
    final dir = await getApplicationSupportDirectory();
    final engineDir = Directory('${dir.path}/katago');
    await engineDir.create(recursive: true);

    final modelFile =
        await _extractIfMissing(engineDir, model.modelFile, model.modelAsset);
    final config =
        await _extractIfMissing(engineDir, 'gtp.cfg', kEngineConfigAsset);

    final binary = File('${await nativeLibraryDir()}/$kEngineBinaryLib');
    if (!await binary.exists()) {
      throw EngineResourceException(
          '缺少 KataGo 原生库（$kEngineBinaryLib）。'
          '请运行 tools/fetch_katago.ps1 编译后放入 '
          'android/app/src/main/jniLibs/arm64-v8a/。');
    }
    return (binary: binary.path, model: modelFile.path, config: config.path,
        engineDir: engineDir.path);
  }

  Future<File> _extractIfMissing(
      Directory dir, String fileName, String assetPath) async {
    final file = File('${dir.path}/$fileName');
    if (!await file.exists()) {
      final data = await rootBundle.load(assetPath);
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    return file;
  }
}

/// 引擎资源缺失/提取失败。
class EngineResourceException implements Exception {
  const EngineResourceException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 引擎加载状态。
final engineStatusProvider = NotifierProvider<EngineController, EngineStatus>(
    () => EngineController());

/// 大模型（b18c384）加载状态：段位对弈与落点分析的门槛。
final danEngineStatusProvider =
    NotifierProvider<EngineController, EngineStatus>(
        () => EngineController(model: kEngineModelDan));

/// 已就绪的小模型引擎（未就绪返回 null）。
final kataGoEngineProvider = Provider<KataGoEngine?>((ref) {
  final status = ref.watch(engineStatusProvider);
  if (status != EngineStatus.ready) return null;
  return ref.read(engineStatusProvider.notifier).engine;
});

/// 已就绪的大模型引擎（未就绪返回 null）。
final kataGoDanEngineProvider = Provider<KataGoEngine?>((ref) {
  final status = ref.watch(danEngineStatusProvider);
  if (status != EngineStatus.ready) return null;
  return ref.read(danEngineStatusProvider.notifier).engine;
});

/// 引擎版选点器（双模型，P3）：按对手段位自动选型。
///
/// - rankIndex < 18（18级~1级）→ 小模型 b6c96；
/// - rankIndex >= 18（1段~9段）→ 大模型 b18c384。
/// 小模型就绪即返回非空（核心门槛）；大模型未就绪时由 UI 按难度拦截，
/// 不走到这里（[KataGoMoveProvider.chooseMove] 对缺失引擎抛错兜底）。
final kataGoMoveProvider = Provider<KataGoMoveProvider?>((ref) {
  final kyu = ref.watch(kataGoEngineProvider);
  if (kyu == null) return null;
  final dan = ref.watch(kataGoDanEngineProvider);
  return KataGoMoveProvider(
    kyuEngine: kyu,
    danEngine: dan,
    rule: ref.read(settingsProvider).rule,
    komi: ref.read(settingsProvider).komi,
  );
});
