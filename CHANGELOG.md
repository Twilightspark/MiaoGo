# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 与
[语义化版本](https://semver.org/lang/zh-CN/)。
All notable changes to **MiaoGo（喵棋）** are documented in this file.

版本节奏 Versioning：
- `1.0.x` — 功能展示效果完善与 Bug 修复（小版本间迭代）
- `2.0.0` — 新功能开发

## [Unreleased]

### Planned · 计划中

- **1.0.x**：棋盘/棋子风格完善、对局中切规则、引擎高级参数可视化、视觉动画打磨、
  真机校准 27 档难度参数表、各模块 Bug 修复。
- **2.0.0**：SGF 导入/导出、研究棋谱完善、在线对弈、AI 解说与胜率曲线、让子/让先、
  题库扩充、账号与云同步（候选）。

## [1.0.0] - 2026-08-29

首个正式版本，P0~P5 全部完成。

### Added

- **5-Tab 骨架**：首页 / 对弈 / 棋谱 / 功课 / 设置。
- **首页**：用户条（头像、名称、段位徽章、大赛积分）+ 四入口卡片（头像选择与裁剪）。
- **对弈·人机模式**：自由选择对手段位 / 尺寸 / 规则 / 先后手；悔棋、认输、PASS、AI 建议下一步、
  实时 ownership 热力图、终局数子/数目、棋谱保存。
- **对弈·生涯模式**：随机大赛（9/13/19）、8 人单败淘汰、积分升降级（18级~9段 27 档）、段位徽章。
- **引擎与分析（KataGo）**：双模型（b6c96 级位 / b18c384 段位+分析）、GTP 协议、27 档难度映射、
  `kata-analyze` 领地热力图与 top moves、Dart 规则 AI 降级兜底。
- **棋谱**：个人棋谱持久化与复盘（逐步回放、任意手位势力范围、AI 分析下一手、终局点目）；
  11 局历史名谱（AlphaGo 人机大战、吴清源/木谷实、秀策耳赤之妙手）。
- **功课**：入门基础图文、定式布局（SGF+讲解）、422 道死活题（答题判定、正解讲解、进度记录）。
- **设置**：棋盘/棋子风格、棋盘大小（9/13/19）、规则（中/韩/日，贴目联动）、音效、关于与数据清除。
- **工程**：`flutter_riverpod` 状态管理、`core/engine/game/study/storage` 分层、完整单元与 widget 测试。

### Fixed

- 首个正式版本，无既有回归项。

### Security

- KataGo 引擎与模型均为本地资源，应用不发起网络请求。

[1.0.0]: https://github.com/Twilightspark/MiaoGo/releases/tag/v1.0.0
