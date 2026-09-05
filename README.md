# 喵棋 MiaoGo

> 安卓围棋对弈应用 · An Android Go (Weiqi/Baduk) app powered by a local **KataGo** AI engine.

![Version](https://img.shields.io/badge/version-1.2.0-4C8B70)
![Platform](https://img.shields.io/badge/platform-Android-3DDC84)
![Flutter](https://img.shields.io/badge/Flutter-3.38-02569B)
![License](https://img.shields.io/badge/license-Apache--2.0-blue)
[![CI](https://github.com/Twilightspark/MiaoGo/actions/workflows/ci.yml/badge.svg)](https://github.com/Twilightspark/MiaoGo/actions/workflows/ci.yml)

---

## 简介 · Introduction

**喵棋（MiaoGo）** 是一款基于 **Flutter** 开发的安卓围棋对弈应用。AI 对手由 **KataGo** 本地引擎驱动，
通过控制思考时间与行棋选择参数，构建从 **18 级到 9 段** 共 27 档难度的人机对手；支持中国 / 韩国 / 日本规则，
可随时查看领地分析与数子结果，并内置生涯对战、历史名谱、死活题与定式等学习内容。

**MiaoGo** is an Android Go (Weiqi/Baduk) game built with **Flutter**. Its AI opponents are driven by a
**local KataGo** engine. By tuning the engine's search budget and move-selection parameters, it provides
**27 ranks from 18 kyu to 9 dan**. It supports Chinese / Korean / Japanese rules, on-demand territory
analysis and scoring, plus a career tournament mode, historical famous games, life-and-death problems and
joseki study content.

## 功能特性 · Features

应用为 **5-Tab 底部导航**（首页 / 对弈 / 棋谱 / 功课 / 设置）：

The app uses a **5-tab bottom navigation** (Home / Play / Records / Study / Settings):

| 页面 Page | 内容 Highlights |
|---|---|
| **首页 · Home** | 顶部用户区（头像 / 名称 / 设置）+ 统计卡（打卡天数 / 对局数量 / 棋手积分 / 当前棋力）+ 统一功能卡（每日一题 · 快速对弈 · 赛事生涯）+ 无边框快捷入口 + 懒加载历史记录。Sticky user header (avatar / name / settings) + stats card + unified feature cards (daily problem / quick play / career tournament) + quick entries + lazy-loaded game & tournament history. |
| **对弈 · Play** | **生涯模式**（随机大赛、积分升降级）与**人机模式**（自由选段位 / 尺寸 / 规则 / 落子方式）。共用对局页：顶部选手卡片、两步/双击落子、悔棋、停手、实时 ownership 热力图、胜率走势曲线、保存续弈与弃局、终局数子、保存棋谱。Career tournament mode & Free-play mode. Shared game page: player cards, two-step/double-tap placement, undo, pass, real-time ownership heatmap, black-winrate curve, save/resume & abandon, scoring, SGF save. |
| **棋谱 · Records** | 个人棋谱 / 历史名谱 / 研究棋谱；复盘：逐步回放、任意手位看势力范围、AI 分析下一手、终局数子。Personal games, 11 historical famous games, and review with per-move territory + AI analysis. |
| **功课 · Study** | 入门基础（规则 / 术语图文）、定式布局（SGF 序列 + 讲解）、**422 道死活题**（答题判定 + 正解讲解 + 进度）。Lessons, joseki patterns, and 422 graded life-and-death problems with solutions & progress. |
| **设置 · Settings** | 棋盘 / 棋子风格、棋盘大小（9 / 13 / 19）、对弈规则（中 / 韩 / 日，贴目联动）、音效、关于与数据清除。Board & stone styles, board size, ruleset, sound, about & data reset. |

其他核心能力 Core capabilities:

- 🤖 **本地 AI · Local AI**：KataGo 双模型——b6c96 小模型负责 **18级~1级**，b18c384 大模型负责 **1段~9段** 及全部落点分析。Dual-model KataGo: b6c96 (kyu ranks) and b18c384 (dan ranks + all move analysis).
- 🎯 **27 段位难度 · 27 ranks**：引擎思考量 + 选点容错双轴弱化，低段位也能"像人一样"漏招。Search budget + move-selection tolerance produce human-like mistakes at low ranks.
- 🌏 **多规则 · Multi-rules**：中国（数子）/ 韩国 / 日本（数目），对局中可切换。Chinese/Korean/Japanese rules, switchable mid-game.
- 📊 **实时形势判断 · Live territory**：`kata-analyze` ownership 热力图 + AI 建议，任意时刻可用。Ownership heatmap & AI hints at any time.
- 🎮 **生涯大赛 · Career tournaments**：随机赛事、8 人单败淘汰、积分升降级、AI 对手段位动态匹配。Random tournaments, 8-player single elimination, rank progression.
- 📚 **内置功课 · Built-in study**：422 死活题 + 名谱 + 定式，全部离线可用。All offline.

## 截图 · Screenshots

<!-- 截图占位：请将实际运行截图放入 docs/screenshots/ 后替换下列图片链接 -->
<!-- Placeholder: put real screenshots under docs/screenshots/ and update the links below -->
<!--
| 首页 Home | 对弈 Play | 功课 Study |
|---|---|---|
| ![Home](docs/screenshots/home.png) | ![Play](docs/screenshots/play.png) | ![Study](docs/screenshots/study.png) |
-->

## 技术栈 · Tech Stack

| 项 Item | 选择 Choice |
|---|---|
| 客户端框架 · Client | **Flutter** (Dart SDK ^3.10) |
| AI 引擎 · Engine | **KataGo** (GTP, Android NDK 交叉编译，原生库 `libkatago.so` 子进程方式运行) |
| 状态管理 · State | **flutter_riverpod**（Notifier/Provider，无 codegen） |
| 本地存储 · Storage | `shared_preferences` + `path_provider`（SGF 与 JSON 索引） |
| 目标平台 · Platform | Android，minSdk 21+，**arm64-v8a** |
| 围棋规则 · Rules | 中国 / 韩国 / 日本，Komi 随规则联动 |

## 项目结构 · Project Structure

```
miaogo/
├── android/                  # Flutter Android 宿主（KataGo jniLibs 原生库）
├── assets/
│   ├── katago/               # KataGo 引擎资源（模型/配置，.gitignore 排除，构建前须 fetch）
│   ├── problems/             # 422 道死活题 SGF
│   ├── famous/               # 11 局历史名谱 SGF
│   ├── lessons/              # 定式布局 SGF + 讲解
│   ├── icons/                # 首页 SVG 语义色图标（做题/对弈/竞赛/入门/定式/题库/棋谱/历史/比赛）
│   └── icon/                 # 应用图标
├── lib/
│   ├── core/                 # 纯 Dart 领域逻辑：棋盘/规则/数子/段位/SGF（可单测）
│   ├── engine/               # KataGo 引擎：GTP 客户端、kata-analyze 分析、27 档难度映射
│   ├── game/                 # 对局状态机、人机决策调度、生涯模式、复盘控制器
│   ├── study/                # 死活题引擎、入门基础与定式数据
│   ├── storage/              # 用户/设置/棋谱/题目进度 持久化
│   └── ui/                   # 首页/对弈/棋谱/功课/设置 + 棋盘绘制、热力图、成绩单
├── tools/
│   ├── fetch_katago.ps1      # KataGo 二进制：Windows 开发版 / Android NDK 编译
│   └── fetch_models.ps1      # KataGo 模型下载（校验 sha256）
├── test/                     # core/engine/game/career/study 单测 + widget 测试
├── docs/data-sources.md      # 内嵌棋谱/功课数据来源与许可
└── pubspec.yaml
```

架构原则 Architecture principles：`core/`、`engine/` 为纯 Dart / 可注入依赖，UI 不直接持有关键逻辑；
`GameController` 不依赖 KataGo 细节，引擎仅提供"建议 / 落子 / 分析"。

## 快速开始 · Quick Start

### 环境要求 Prerequisites

- Flutter SDK 3.38+（Dart ^3.10），Android Studio + JDK 17（AGP 8）
- Android NDK（仅发布包需要，用于编译 KataGo 原生库）
- PowerShell（模型/引擎资源脚本）

### 获取引擎资源 · Fetch engine resources

> KataGo 二进制与模型**不入 git 仓库**（体积红线，见 `AGENTS.md`）。干净克隆后必须先执行：

```powershell
# 1) 下载双模型到 assets/katago/（含 sha256 校验，幂等）
./tools/fetch_models.ps1

# 2) 开发机验证用 Windows 版二进制（可选）
./tools/fetch_katago.ps1 -Mode WindowsDev

# 3) 发布包用 Android 原生库 libkatago.so（NDK 交叉编译，另终端执行）
./tools/fetch_katago.ps1 -NdkPath <你的NDK路径>
```

### 构建与验证 · Build & test

```powershell
flutter pub get
flutter analyze          # 静态检查，无 error
flutter test             # 单元 + widget 测试
flutter build apk --release --target-platform android-arm64   # 单 ABI 发布包
```

## 路线图 · Roadmap

### 1.2.0（当前 · Current）

对局体验打磨：两步/双击落子、保存续弈与弃局、胜率走势曲线、实时分析整合。详细变更见 [`CHANGELOG.md`](CHANGELOG.md)。

### 1.1.0

首页重构与视觉统一 + 玩家进度体系。详细变更见 [`CHANGELOG.md`](CHANGELOG.md)：

- 顶部用户区固定（头像 / 名称 / 设置同一水平线居中），去掉段位徽章与名称弹窗
- 统计卡（打卡天数 / 对局数量 / 棋手积分 / 当前棋力）+ 每日一题（日期种子 5 题，完成即打卡）
- 三张统一功能卡（每日一题 / 快速对弈 / 赛事生涯）+ 无边框快捷入口 + 懒加载历史记录（空态居中）
- SVG 图标体系：`assets/icons` 9 枚语义色图标 + `AppIconTile` 统一圆底图标瓦片
- 设置页：等级 tag 改头像（点击弹头像修改框）、底部红色「重生棋手」一键重置全部进度
- 赛事对局 ↔ 棋谱（`tournamentId`）贯通，竞赛历史可复盘单局

### 1.0.0

功能基本完成：5-Tab 全模块、人机对弈闭环、KataGo 双模型分析、生涯模式、棋谱与功课模块。

### 后续打磨 · Polish

- 完善功能展示效果：棋盘/棋子风格、对局中切规则、引擎高级参数的可视化与交互打磨
- 视觉与动画打磨（落子/提子/升降级/热力图过渡效果）
- **真机校准 27 档难度参数表**（校准工具产出的实测值写回默认配置）
- 修复各模块已发现的功能 Bug，补充边界用例

### 2.0.0（新功能 · New Features）

- SGF 导入 / 导出（本地文件与分享）
- 研究棋谱模块完善（自定义研棋、变化图分支）
- 在线对弈 / 远程观战（联网多人）
- AI 解说与胜率走势曲线
- 让子棋 / 让先支持
- 更多定式与死活题库扩充
- 账号体系与棋谱云同步（可选）

> 具体清单与排期以项目 Issue / 里程碑为准。See milestone/issues for details.

## 第三方依赖与致谢 · Third-Party Dependencies & Credits

| 依赖 Dependency | 用途 Purpose | 许可 License |
|---|---|---|
| [KataGo](https://github.com/lightvector/KataGo) (engine) | 围棋 AI 引擎（GTP） | MIT |
| KataGo 神经网络 b6c96 / b18c384 | 对弈与分析模型 | [KataGo Neural Network License](https://katagotraining.org/network_license/)（MIT 式） |
| [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) | 状态管理 | MIT |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | 本地存储 | BSD-3-Clause |
| [path_provider](https://pub.dev/packages/path_provider) | 应用目录路径 | BSD-3-Clause |
| [image_picker](https://pub.dev/packages/image_picker) | 头像选择 | BSD-3-Clause |
| [crop_your_image](https://pub.dev/packages/crop_your_image) | 头像裁剪 | MIT |
| [flutter_svg](https://pub.dev/packages/flutter_svg) | SVG 图标渲染 | MIT |
| [cupertino_icons](https://pub.dev/packages/cupertino_icons) | 图标 | MIT |
| [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons) | 应用图标生成 | MIT |
| [flutter_lints](https://pub.dev/packages/flutter_lints) | 静态检查 | BSD-3-Clause |

完整声明（含版权与许可原文要求）见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

### 数据来源 · Data Sources

内嵌棋谱 / 功课数据来源与许可记录于 [`docs/data-sources.md`](docs/data-sources.md)：

- **历史名谱（11 局）**：`baduk-study-material` 自由共享棋谱库（AI 时代 + 经典公开档案）
- **死活题（422 题）**：`gogameguru` 每周一题（经 `baduk-study-material` 整理）
- **定式布局**：自编 + 公开资料整理
- **入门基础**：自编图文

## 贡献指南 · Contributing

欢迎 Issue、PR 与建议。请阅读 [`CONTRIBUTING.md`](CONTRIBUTING.md) 与 `AGENTS.md`（构建/验证规则）。
Feel free to open issues and pull requests. See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## 开源协议 · License

本项目源码采用 **Apache License 2.0** 开源（见 [`LICENSE`](LICENSE)）。
内嵌的 KataGo 引擎、模型与第三方数据分别遵循其各自许可，见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

This project is licensed under the **Apache License 2.0** — see [`LICENSE`](LICENSE).
KataGo engine, networks and bundled data are covered by their own licenses, see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## 联系 · Contact

- GitHub: [Twilightspark/MiaoGo](https://github.com/Twilightspark/MiaoGo)
- 问题反馈：在仓库 [Issues](https://github.com/Twilightspark/MiaoGo/issues) 提出
