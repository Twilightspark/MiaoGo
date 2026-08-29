# 贡献指南 · Contributing

感谢你考虑为 **MiaoGo（喵棋）** 贡献代码。请先阅读 [`AGENTS.md`](AGENTS.md)（架构、目录、构建与验证规则）。

## 流程 · Workflow

1. Fork 仓库并创建特性分支 `feat/xxx` 或 `fix/xxx`。
2. 开发前阅读 `AGENTS.md` §1 技术栈与 §2 设计令牌（**禁止硬编码颜色**）。
3. 修改 `core/`、`engine/`、`game/`、`study/` 逻辑后**必须**补充/更新对应 `test/` 单测。
4. 提交前运行以下命令并确保全部通过：
   ```powershell
   flutter analyze
   flutter test
   ```
5. 提交信息建议使用 `feat:` / `fix:` / `refactor:` / `docs:` 前缀，说明简洁。
6. 提交 PR 到 `main`，附上变更说明；CI 通过后等待 Review。

## 开发环境 · Development Environment

- Flutter 3.38+ / Dart ^3.10，JDK 17（AGP 8）。
- 引擎资源（模型 / 二进制）不入 git，见 [`tools/fetch_models.ps1`](tools/fetch_models.ps1) 与
  [`tools/fetch_katago.ps1`](tools/fetch_katago.ps1)。
- 数据来源与许可见 [`docs/data-sources.md`](docs/data-sources.md)。

## 行为准则 · Code of Conduct

保持友善、尊重；讨论集中于技术与改进。Issue 报告请包含：现象、复现步骤、期望行为、设备/版本信息。
