# assets/katago — KataGo 引擎资源

P2 已接线：引擎（`lib/engine/`）在启动时把模型/配置从本目录解压到应用目录，
二进制则作为原生库从 `nativeLibraryDir` 直接执行（GTP 子进程）。资源按体积红线分发（AGENTS.md §9），不入仓库。

单引擎架构（P6）：一个 KataGo 进程同时加载 b18c384 主模型（落点分析）与
Human SL 模型（`-human-model`，18级~9段拟人对手），避免重复加载大模型。

- `gtp.cfg` — 完整 GTP 配置（默认配置 + 低资源覆盖：`numSearchThreads=2`、
  `nnMaxBatchSize=2`、`nnCacheSizePowerOfTwo=16`、关日志；末尾附 Human SL 基线）。
  **随 APK 打包**。
- `kata1-b18c384nbt-s9996604416-d4316597426.bin.gz` — b18c384 主模型
  （落点分析、搜索评估，约 98MB gz）。**随 APK 打包**。`.gitignore` 排除。
- `b18c384nbt-humanv0.bin.gz` — Human SL 模型（KataGo v1.15.0 发布，约 95MB gz）：
  按 `humanSLProfile`（`rank_18k`~`rank_9d`）模仿各段位人类棋风。
  **随 APK 打包**。`.gitignore` 排除。

> 旧 b6c96 小模型（18级~1级）已随 Human SL 方案下线，不再随 APK 打包；
> 若目录中仍有残留可删除。

引擎二进制（原生库）不在本目录：
`android/app/src/main/jniLibs/arm64-v8a/libkatago.so`（约 7.2MB 已 strip，Eigen(CPU) 后端，
`tools/fetch_katago.ps1` NDK 交叉编译产出，随 APK 打进 `nativeLibraryDir`）。
应用私有 `files/` 目录被 SELinux/noexec 禁止执行二进制，故必须走原生库目录
（见 AGENTS.md §8）。`.gitignore` 排除，干净环境需重新编译后随 APK 打包。

> **GPU 后端（未启用）**：`tools/fetch_katago.ps1 -Backend OpenCL` 可构建 OpenCL 版二进制
> （含厂商 OpenCL 转发 shim `libOpenCL.so`），但 **Android 以子进程运行引擎时处于 linker
> `(default)` namespace，无法访问 `/vendor` 的 OpenCL 驱动**，引擎启动即失败（`exit=-6`）。
> 故 Android 默认仍用 Eigen；要启用 GPU 需改为 in-process（JNI）加载引擎，尚未实现。

说明：
- 开发机验证用 Windows eigen 版：`tools/fetch_katago.ps1 -Mode WindowsDev`
  （解压到 `tools/katago-dev/`，被 .gitignore 排除）。
- 引擎不可用时对局被引擎门槛拦截（无 Dart 规则 AI 降级），见 `lib/ui/play/game_page.dart`。
- 模型获取：`tools/fetch_models.ps1`（b18c384 + humanv0，含 sha256 校验）。
