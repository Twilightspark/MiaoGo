# assets/katago — KataGo 引擎资源

P2 已接线：引擎（`lib/engine/`）在启动时把模型/配置从本目录解压到应用目录，
二进制则作为原生库从 `nativeLibraryDir` 直接执行（GTP 子进程）。资源按体积红线分发（AGENTS.md §9），不入仓库。

- `gtp.cfg` — 完整 GTP 配置（默认配置 + 低资源覆盖：`maxThreads=2`、
  `nnMaxBatchSize=2`、`nnCacheSizePowerOfTwo=16`、关日志）。**随 APK 打包**。
- `kata1-b6c96-s175395328-d26788732.txt.gz` — b6c96 模型（生涯/人机主力，
  约 5MB gz）。**随 APK 打包**（pubspec 已声明）。`.gitignore` 排除。
- `kata1-b18c384nbt-s9996604416-d4316597426.bin.gz` — b18c384 模型
  （高段/深度分析，约 98MB gz）。未在 pubspec 声明，接入深度分析后再开。

引擎二进制（原生库）不在本目录：
`android/app/src/main/jniLibs/arm64-v8a/libkatago.so`（约 7.2MB 已 strip，
`tools/fetch_katago.ps1` NDK 交叉编译产出，随 APK 打进 `nativeLibraryDir`）。
应用私有 `files/` 目录被 SELinux/noexec 禁止执行二进制，故必须走原生库目录
（见 AGENTS.md §8）。`.gitignore` 排除，干净环境需重新编译后随 APK 打包。

说明：
- 开发机验证用 Windows eigen 版：`tools/fetch_katago.ps1 -Mode WindowsDev`
  （解压到 `tools/katago-dev/`，被 .gitignore 排除）。
- 引擎不可用时对局被引擎门槛拦截（无 Dart 规则 AI 降级），见 `lib/ui/play/game_page.dart`。
