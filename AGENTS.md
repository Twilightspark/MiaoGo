# MiaoGo（喵棋）— 项目说明 / Agent 工作手册

安卓围棋对弈应用。AI 对手由 **KataGo** 本地引擎驱动，通过控制思考时间与行棋选择参数，
构建从业余到职业多个级别的对手；支持中国 / 韩国 / 日本等规则，可随时展示领地分析与数子结果。

> 本文件面向 AI Agent 与开发者，说明项目目标、技术约束、功能设计、目录结构与验证命令。
> **每次修改代码前先阅读本文件；Agent 执行任务后必须运行"构建与验证"中的对应命令。**
> 工程进展：P0~P5 已完成（5-Tab 骨架 / 人机对弈闭环 / 引擎+双模型分析 / 生涯模式 /
> 棋谱模块 / 功课模块），P6（打磨与发布）见 §14 实施计划。

---

## 1. 技术栈与平台

| 项 | 选择 |
|---|---|
| 客户端框架 | **Flutter**（本机 3.38.0 stable / Dart 3.10，Android 构建在另一终端进行） |
| AI 引擎 | **KataGo 本地化**：Android NDK 交叉编译 KataGo C++ → `katago` 可执行 / `libkatago.so` |
| 交互协议 | GTP（KataGo GTP engine，stdin/stdout）；分析用 `kata-analyze` |
| 状态管理 | **flutter_riverpod**（Notifier/Provider，不用 codegen），禁止混用其他库 |
| 本地存储 | `shared_preferences`（用户/设置）+ `path_provider` 应用目录存 SGF 与 JSON 索引；**不引 sqflite** |
| 目标平台 | Android，minSdk 21+，优先 arm64-v8a（兼容 armeabi-v7a / x86_64） |
| 围棋规则 | 中国（数子）、韩国、日本（数目）等，对局中可切换 |

## 2. 功能总览（五大页面）

应用为 **5-Tab 底部导航**：首页 / 对弈 / 棋谱 / 功课 / 设置。

| 页面 | 内容 |
|---|---|
| 首页 | 顶部用户条（头像/名称/段位徽章/大赛积分）→ 四张功能入口卡片（对弈/棋谱/功课/设置）→ 底部 5-Tab |
| 对弈 | 两种模式：**生涯模式**（报名随机生成"对应个人段位"的大赛，按大赛积分升降级）与**人机模式**（自由选择对手段位/尺寸/规则对弈，不计积分）。共用对局页：棋盘绘制、悔棋/认输/PASS、实时形势判断（ownership 热力图）、AI 建议下一步、终局数子/数目、保存棋谱 |
| 棋谱 | 个人棋谱（优先）/ 历史名谱 / 研究棋谱 三类；个人棋谱支持复盘：逐步回放、任意手位查看双方势力范围、AI 智能分析下一手、终局数子；支持 SGF 导入/导出 |
| 功课 | 入门基础（规则/术语图文）/ 定式布局（常见定式 SGF 序列+讲解）/ 死活题（优先，答题判定+正解讲解+进度） |
| 设置 | 棋盘风格、棋子风格、棋盘大小（9/13/19，默认 9）、对弈规则（中/韩/日，贴目联动）、引擎高级参数（隐藏）、音效、关于与数据清除 |

### 视觉与颜色规范（Design Tokens）

设计令牌集中定义于 `lib/app_theme.dart`（`GoColors` + `buildGoTheme()`），Android 原生侧同步于
`android/app/src/main/res/values/colors.xml`（图标底色、启动页）。任何界面配色一律引用令牌，
**禁止散落硬编码颜色**。

| 令牌 | 色值 | 语义用途 |
|---|---|---|
| 主背景 · 宣纸白 | `#F7F2EA` | 页面背景 / AppBar（Scaffold 默认） |
| 卡片 · 暖米色 | `#EFE3D5` | 卡片、底部导航背景（经 `surfaceContainerHighest`） |
| 主色 · 松柏青 | `#4C8B70` | **当前选中状态**（底部导航/切分按钮/Tab）、**AI 提示**、**等级**（级位徽章）、**成就** |
| 深松柏青 | `#3B6B56` | 次级强调、功课/图标 |
| 浅松柏青 | `#D7E7DE` | 头像等浅色底（`primaryContainer`） |
| 强调色 · 棋盘木色 | `#A56A3A` | **积分**、**段位**（段位徽章）、**金牌**（大赛/奖杯） |
| 深木色 / 浅木色 | `#7A4B28` / `#F0E0CE` | 积分 chip 等木色系强调 |
| 一级文字 | `#2B2926` | 标题、正文（`onSurface`） |
| 二级文字 | `#77716B` | 次级说明（`onSurfaceVariant`） |
| 边框 / 分隔线 | `#C6BCAC` / `#DED4C5` | outline、Divider |

规则约定：
- 首页四入口卡为**同构暖米卡片**，仅图标用语义色区分：对弈=松柏青、棋谱=木色、功课=深松柏青、设置=二级灰。
- 段位徽章：**级 = 松柏青，段 = 棋盘木色**（对应"等级/段位"语义）。
- 后续新增界面（对局/复盘/分析 overlay/成绩单）沿用上述语义：AI 建议与热力图用松柏青，积分/奖牌用木色。

## 3. 核心功能需求

1. **棋盘尺寸**：9 路（默认）、13 路、19 路可选；棋盘绘制与坐标正确（SGF 坐标 a1…t19，跳过 i）。
2. **AI 对手**：本地 KataGo，通过 GTP 交互；落子、提子、打劫、让子均由引擎规则保证。
3. **难度分级**：**27 段位**（18级~1级~1段~9段）映射引擎参数（思考量 + 选点方式），见 §8。
4. **规则支持**：中国 / 韩国 / 日本，Komi、贴目随规则变化；引擎侧用 `kgs-rules` 同步；对局中可切换。
5. **终局分析**：随时（不只终局后）调用 `kata-analyze` 获取 `ownership`（领地热力图，每点 -1~1）
   与 `territory`（领地划分），叠加在棋盘上；数子/数目结果面板展示。
6. **对局功能**：悔棋、新对局、认输、PASS、AI 建议下一步、棋谱（SGF）导入导出、设置界面。
7. **生涯模式**：随机生成匹配玩家段位的大赛（对手/赛程/积分表），按大赛积分进行段位升降级，见 §7。
8. **个人棋谱**：持久化所有个人对局（来源：生涯/人机/研究），可复盘、可看势力范围、可 AI 分析下一手。
9. **死活题**：内置按难度分组题库，答题判定（正确/失败/尝试次数）、正解分支与讲解、进度记录。

## 4. 架构与模块

```
miaogo/
├── android/                      # Flutter Android 宿主（另终端负责）
├── assets/
│   ├── katago/                   # 引擎资源：二进制 + 模型（外部准备，.gitignore 排除，体积红线）
│   ├── problems/                 # 死活题 SGF（内置，难度分级）
│   ├── famous/                   # 历史名谱 SGF（内置 10~20 局）
│   ├── lessons/                  # 入门基础/定式布局 内容（文本 + SGF）
│   └── icon/
├── lib/
│   ├── main.dart                 # 入口
│   ├── app.dart                  # 路由、5-Tab 导航壳
│   ├── app_theme.dart            # 设计令牌（GoColors 色板）与主题构建（buildGoTheme）
│   ├── core/                     # 纯 Dart 领域逻辑（不依赖 Flutter，便于单测）
│   │   ├── board.dart            # 棋盘模型、落子、提子、打劫、合法点（SGF 坐标）
│   │   ├── rules.dart            # 中国/韩国/日本规则、贴目、终局判定、禁着点
│   │   ├── scoring.dart          # 数子/数目计算、领地分析数据模型
│   │   ├── move.dart             # 棋步（含 pass / resign）
│   │   ├── rank.dart             # 段位体系：18级~9段 27 档 + 大赛积分→段位升降映射
│   │   └── sgf.dart              # SGF 解析/序列化（对局、名谱、死活题共用）
│   ├── engine/
│   │   ├── katago_engine.dart    # 引擎生命周期：解压资源、拉起进程、重建
│   │   ├── gtp_client.dart       # GTP 协议收发（子进程 stdin/stdout，超时处理）
│   │   ├── analysis.dart         # kata-analyze 请求与 ownership/territory/topMoves 解析
│   │   └── difficulty.dart       # 段位 → 引擎参数 + 选点容错（27 档映射，§8）
│   ├── game/
│   │   ├── game_controller.dart  # 对局状态机：人机/生涯共用、顺序、回合、悔棋
│   │   ├── match_engine.dart     # AI 决策调度（isolate 隔离，不阻塞 UI；失败降级 Dart 规则 AI）
│   │   ├── career_controller.dart# 生涯：大赛生成/报名/赛程/积分/升降级
│   │   └── review_controller.dart# 复盘：加载 SGF、跳转任意手位、重放建盘、随时点目
│   ├── study/
│   │   ├── problem_engine.dart   # 死活题：题库加载 + 判定（正解/错解/尝试次数/正解回放）
│   │   └── lesson_data.dart      # 入门基础图文 + 定式布局目录（自编）
│   ├── storage/
│   │   ├── user_store.dart       # 用户档案（名称/段位/积分）持久化
│   │   ├── settings_store.dart   # 设置持久化
│   │   ├── record_store.dart     # 个人棋谱（SGF 文件 + prefs 索引）
│   │   └── problem_store.dart    # 死活题进度（完成状态 + 尝试次数）持久化
│   └── ui/
│       ├── home/                 # 首页：用户条 + 四入口卡片
│       ├── play/                 # 对弈：模式选择/大赛列表/大赛详情/对局页
│       ├── record/               # 棋谱：个人/名谱/研究 + 复盘页 + 名谱目录
│       ├── study/                # 功课：课程/定式/题库/答题页
│       ├── settings/             # 设置页
│       ├── board_widget.dart     # 棋盘绘制（CustomPainter）、手势落子、提子动画
│       ├── analysis_overlay.dart # 领地热力图 + 终局数字覆盖层 + AI 建议标注
│       ├── score_sheet.dart      # 数子/数目结果面板
│       └── common/               # 段位徽章、列表项、对话框等复用组件
└── test/                         # core/engine/game/career/study 单测 + widget 测试
```

原则：
- `core/` 与 `engine/` 是纯 Dart / 可注入依赖，UI 不直接持有关键逻辑。
- 引擎与 UI 解耦：`GameController` 不依赖 KataGo 细节，引擎只提供"建议/落子/分析"。
- 复盘页与对局页共用 `GameController`：回放局面到引擎后请求分析，实现"随时看势力范围/AI 建议"。
- 中英文显示均可，包名建议 `com.miaogo.app`，应用名 `喵棋 MiaoGo`。

## 5. 数据模型

| 模型 | 关键字段 |
|---|---|
| `UserProfile` | name、rankIndex(0~26)、careerPoints、生涯胜/负、总对局数 |
| `GameRecord` | id、日期、对手名、对手段位、结果、用时、尺寸(9/13/19)、规则、贴目、SGF路径、来源(生涯/人机/研究) |
| `Tournament` | id、名称(随机生成)、组别(段位区间)、选手列表(玩家+AI persona)、赛程(3~5 局)、积分表 |
| `TournamentPlayer` | 名、段位、报名状态、胜负记录 |
| `Problem` | id、标题、难度(入门/初级/中级/高级)、尺寸、初始局面、目标色、SGF路径、是否已完成 |
| `AppSettings` | 棋盘风格、棋子风格、棋盘尺寸、规则、贴目、难度映射微调、音效等 |
| `Difficulty` | rankIndex → (maxVisits, maxTime, temperature, rootNoise, 选点 topK 容错) |

## 6. 段位体系与生涯模式（大赛制）

### 段位体系
- 共 **27 档**，索引 `i`：`i=0..17` = 18级…1级；`i=18..26` = 1段…9段。
- `core/rank.dart` 提供：段位文本（如 `12级`、`3段`）、积分→段位映射、升降级规则、阈值常量（集中可调）。

### 大赛机制
1. **大赛生成**：生涯页常备 **9/13/19 三场待报名大赛**（一场用完自动补新，始终三场可选）。
   赛事名随机（桃李杯/凌云杯/喵星人杯…）；**8 人单败淘汰**（8强→4强→决赛→冠军），
   7 名 AI 对手段位在玩家 ±2 档、国籍随机（中国/韩国/日本，中文名池生成）。
2. **报名**：同一时刻**至多参加一场**；报名后进入赛程页，逐局对弈（对手按段位映射真实棋力，§8）。
   玩家完成一轮后**同轮其余场次自动按段位差权重随机判胜**，晋级下一轮；玩家被淘汰则
   **自动模拟剩余赛程**并产生冠军。
3. **积分结算**：**赛事完结统一结算**——每局胜 +20 / 负 +5，大赛冠军额外 +30
   （常量为可调参数，用于校准节奏）。**提前退赛无任何积分/胜负/参赛统计**，历史记「退赛·0 分」。
4. **升降级**：`careerPoints` 达下一档阈值 → 晋升（携带余分）；跌破当前档底线 → 降级。
   保护：不低于 18级、不高于 9段。晋升/降级有动画与提示。
5. **人机模式**：自由选择对手段位/尺寸/规则/先后手对弈，不计积分、不影响段位。

## 7. 难度分级设计（27 段位 → 引擎参数 + 选点容错）

KataGo 在低 visit 下仍远超人类，故弱化需"引擎参数 + 选点容错"双轴：

- **引擎参数**（`kata-set-param <name> <value>` 运行时改参）：对 `i=0..26` 做分段线性插值：

| 索引 i（段位） | 参考 maxVisits | 参考 maxTime | temperature | rootNoise | 选点 topK 容错 |
|---|---|---|---|---|---|
| 0（18级） | 1~5 | 0.1s | 1.5 | 高 | 很大（常抽次优/再次优） |
| 8（10级） | 20 | 0.4s | 0.8 | 高 | 大 |
| 17（1级） | 60 | 0.6s | 0.5 | 中 | 中 |
| 18（1段） | 150 | 1.2s | 0.3 | 低 | 低 |
| 22（5段） | 500 | 2.5s | 0.15 | 很低 | 很低 |
| 26（9段） | 2000+ | 6s+ | <0.05 | 无 | 无（取最优） |

- **选点容错（Dart 侧，强于纯引擎弱化）**：`kata-analyze` 取 top-N 候选，按温度加权采样"次优/再次优"落子；
  段位越低 N 越大、随机性越强，用于制造低段位的明显漏招，突破纯引擎的棋力地板。
- **真机校准**：开发模式菜单内置"校准工具"，可边对弈边调 visits/temperature/topK 并即时生效，
  产出每个段位的实测参数表并写回默认配置（必须真机校准，访问次数与硬件线程强相关，以耗时预算为硬约束）。
- 其他可调参数：`forcedPlayouts`/`forcedTime`（强制最少思考）、`rootPessimism`（弱化）、
  `policyInitAreaTemperature`（早期多样度）、`cpuct`。让子/让先可由 `boardsize`+规则或减 visit 近似，勿破坏引擎状态。

## 8. KataGo Android 集成要点

- 源码：`https://github.com/lightvector/KataGo`（C++ 部分在 `cpp/`）。
- **双模型（P3）**：App 同时加载两个引擎实例（同一二进制，不同模型）：
  - 小模型 **b6c96**（`engineStatusProvider`/`kataGoEngineProvider`）——**18级~1级**（rankIndex 0..17）人机对弈；
  - 大模型 **b18c384**（`danEngineStatusProvider`/`kataGoDanEngineProvider`）——**1段~9段**（rankIndex 18..26）人机对弈
    及**全部落点分析**（实时热力图/`kata-analyze`、AI 建议下一步）。
  - 选型：`KataGoMoveProvider.engineFor(rankIndex)` 按段位自动切换（`match_engine.dart`）；
    级位门槛看小模型、段位/分析门槛看大模型（`ai_setup_page.dart`、`game_page.dart`）。
  - 模型文件：`assets/katago/kata1-b6c96-*.txt.gz`（约 5MB gz）、
    `assets/katago/kata1-b18c384nbt-*.bin.gz`（约 98MB gz），均已在 pubspec 声明随 APK 打包。
- NDK 交叉编译（示例，参考已在 Android 上成功跑通的社区工程如
  `kinfkong/katago-android`、`lzjyzq2a/KataGo-Android`）：
  ```powershell
  cmake -B build -DCMAKE_TOOLCHAIN_FILE=$env:ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake `
    -DCMAKE_SYSTEM_NAME=Android -DCMAKE_ANDROID_ARCH_ABI=arm64-v8a -DCMAKE_BUILD_TYPE=Release ..
  cmake --build build -j
  ```
- 运行方式：**二进制作为原生库**打进 `android/app/src/main/jniLibs/<abi>/libkatago.so`
  （`.so` 后缀才被 Gradle 打包），运行时从 `nativeLibraryDir`（MethodChannel
  `miaogo/native` 获取）以子进程方式执行并走 GTP；**应用私有 `files/` 目录被
  SELinux/noexec 禁止 exec，不得从那里启动二进制**。模型/配置为 assets 数据，
  解压到应用目录读取即可。低资源参数是 gtp.cfg 配置键（**不是命令行参数**，
  传 `--maxThreads` 等会被拒启动）：`numSearchThreads=2`、`nnMaxBatchSize=2`、
  `nnCacheSizePowerOfTwo=16`，已设在 `assets/katago/gtp.cfg` 文末；工作目录须
  可写（`logDir=gtp_logs` 相对 CWD），否则 KataGo 启动即退出（表现为 GTP 超时）。
- App 启动预加载引擎（解压+拉起进程），UI 显示加载状态；大模型首次加载慢、占内存。
- GTP 关键命令：`boardsize N`、`kgs-rules chinese|korean|japanese`、`komi`、
  `clear_board`、`play b D4`、`genmove b`、`final_score`、`kata-analyze b <interval>`、
  `kata-set-param name value`、`time_settings`。
- 领地分析：`kata-analyze` 的 `ownership`（逐点 -1~1）用于热力图，`territory` 用于终局标色，
  top moves（胜率/访问数）用于 AI 建议与选点容错采样。

## 9. 需提前准备的资源（数据清单）

| 资源 | 内容 | 来源/方式 | 是否入仓库 |
|---|---|---|---|
| KataGo 二进制 | arm64-v8a，NDK 编译 | 社区包/自编译（另终端） | 否（.gitignore，体积红线） |
| KataGo 模型 | **b6c96**（级位）+ **b18c384**（段位/分析），均随 APK | katagotraining.org | 否（.gitignore；pubspec 已声明，构建前须存在） |
| 死活题数据 | 422 题 SGF（gogameguru，含正解分支/`C[Correct]` 讲解/难度） | baduk-study-material 自由共享库整理（**已核对许可**，见 docs/data-sources.md） | 是（`assets/problems/`） |
| 历史名谱 | 11 局知名对局 SGF（AlphaGo 人机大战、吴清源/木谷实、秀策耳赤） | baduk-study-material（ai-era + classic 公开档案） | 是（`assets/famous/`） |
| 入门基础内容 | 围棋规则/术语图文 | 自编 | 是（`lib/study/lesson_data.dart`） |
| 定式布局 | 常见定式 SGF + 讲解（自编 4 项 + 专业精讲 1 项） | 自编/公开资料整理 | 是（`assets/lessons/`） |

> 引擎二进制与模型走脚本/下载链接分发（按体积红线）；死活题/名谱等小资源直接入库。
> 引擎二进制位于 `android/app/src/main/jniLibs/arm64-v8a/libkatago.so`（已更新本规则）。

## 10. 依赖清单（待加入 pubspec）

`flutter_riverpod`、`shared_preferences`、`path_provider`。
（SGF 解析自研，不引第三方；死活题判定基于自研规则逻辑，不依赖引擎。）

## 11. 构建与验证（必须执行）

```powershell
flutter pub get          # 安装依赖
flutter analyze          # 静态检查（无 error 才提交）
flutter test             # 运行单元测试（core/engine/game/study 逻辑）
flutter build apk --debug    # 快速验证可编译 APK
flutter build apk --release # 发布包（含资源）
```

### 打包规则（发布包，务必遵守）

目标平台只出 **arm64-v8a**（minSdk 21+，优先 arm64；兼容包才考虑 armeabi-v7a/x86_64）。

```powershell
flutter build apk --release --target-platform android-arm64   # 单 ABI 发布包
flutter build apk --release --split-per-abi                   # 需要分 ABI 渠道时
flutter build apk --release --no-tree-shake-icons             # 仅当图标字库被误裁时
```

- 默认 debug fat APK（4 ABI）约 138MB，仅用于快速验证，**禁止作为发布包**。
- release 单 arm64 实测约 14MB；接入 KataGo 二进制/模型后会增大，届时以模型体积为主。
- 体积红线：KataGo 模型（b18 约 98MB gz / b6c96 约 5MB gz）**不进仓库**，按 `.gitignore` 排除
  （`assets/katago/*.gz`），但已在 pubspec 声明随 APK 打包——构建前须先放置模型文件
  （脚本/下载链接分发）；引擎二进制进 `jniLibs` 或 `assets` 时同步更新本规则。
- 修改 `core/`、`engine/`、`game/`、`study/` 逻辑后必须补对应 `test/` 单测。
- 任何提交不得包含引擎密钥/私有模型。

## 12. 测试计划

- `core`：board（提子/打劫/合法点）、rules（三规则贴目/终局）、scoring、rank（积分/升降边界）、sgf（解析往返）。
- `engine`：gtp_client 收发、analysis 解析（mock stdout）、difficulty 27 档映射单调性。
- `game`：game_controller 状态机（悔棋/认输/先后手/切换规则）、career 积分结算与升降级边界。
- `study`：problem_engine 判定（正解/错解/尝试次数耗尽）。
- widget：首页五 Tab 与四入口卡片导航冒烟。

## 13. Flutter SDK 安装（其他终端）

详见 `docs/flutter-setup.md`（尚未创建时按此执行）：
1. 下载 Flutter SDK：`https://docs.flutter.dev/get-started/install/<平台>`。
2. 解压并把 `flutter/bin` 加入 PATH（Windows 建议 `C:\src\flutter\bin`）。
3. 安装 Android Studio（含 Android SDK），并装 JDK 17（Temurin）——Android Gradle Plugin 8 需 JDK 17，Java 8 不可用。
4. `flutter doctor` 检查环境；`flutter doctor --android-licenses` 接受许可。
5. 配置 Android SDK 路径：`flutter config --android-sdk <path>`。
6. 验证：`flutter doctor -v` 无红叉后 `flutter build apk --debug`。

## 14. 实施计划（建议顺序）

> 每阶段完成即运行 `flutter analyze` + `flutter test`；含核心逻辑的节点（P1/P3）加跑 `flutter build apk --debug` 冒烟。
> P2/P3 依赖 §9 引擎资源，未就绪时先用 Dart 规则 AI 兜底开发，不阻塞进度。

| 阶段 | 目标 | 产出/验证 |
|---|---|---|
| **P0 骨架** ✅ | pubspec 依赖；`app.dart` 5-Tab 壳+主题；`core/rank.dart`；user/settings store；首页用户条+四卡；设置页 | `flutter analyze` 通过；首页可导航五 Tab |
| **P1 对弈闭环（人机优先）** ✅ | `core/board/rules/scoring/move`+单测；`board_widget`；`game_controller`；Dart 规则 AI 跑通人机对弈+悔棋+认输+数子+保存棋谱与个人棋谱列表 | `flutter test` 通过；`flutter build apk --debug` 冒烟 |
| **P2 引擎与分析** ✅ | `gtp_client`、`katago_engine`、`analysis`、`difficulty` 27 档映射；实时 ownership 热力图、AI 建议下一步、对局中切换规则 | mock stdout 单测通过；真机可对弈与分析 |
| **P3 生涯模式** ✅ | `career_controller`（大赛生成/报名/赛程/积分/升降级）；生涯统计；段位徽章 | career 结算单测通过 |
| **P4 棋谱模块** ✅ | `core/sgf.dart` 完整解析/序列化（树/布子/分支/注释/双字母表容错）；复盘页（回放+势力范围+AI 建议+点目）；历史名谱浏览；个人棋谱接通复盘 | sgf 往返 + review_controller 单测；复盘页可用（研究棋谱/SGF 导入导出未做） |
| **P5 功课模块** ✅ | `problem_engine`（422 题判定）+ `problem_store` 进度 + 答题页/正解回放/讲解；入门基础与定式布局页面 | problem_engine/problem_store 单测 + 资产校验（422 题可解析可走通） |
| **P6 打磨与发布** | 棋盘/棋子风格、棋盘大小、对局中切规则、引擎高级参数；**真机校准难度表**；release 单 arm64 打包；补充文档 | release 包可安装；难度表已校准 |

## 15. 风险与待确认

- **低段位棋力地板**：纯引擎难以造出"18级"，必须依赖选点容错采样（§7），需真机校准。
- **19 路高段位耗时**：生涯默认建议 9/13 路，19 路留给人机/分析；以耗时预算为硬约束。
- **死活题/名谱版权**：入库前核对许可证（§9）。
- **引擎资源依赖**：P2/P3 依赖外部准备完成，未就绪时用 Dart 规则 AI 顶替开发。
- **Design.png 视觉规范**：Agent 模型无法读取该图片；颜色体系以 §2「视觉与颜色规范」的文字定义为准，
  如需严格对齐图片布局，请补充文字描述后调整。
