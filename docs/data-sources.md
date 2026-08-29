# 棋谱 / 功课数据来源（P4/P5）

> 本文件记录 `assets/famous`、`assets/problems`、`assets/lessons` 内嵌数据的来源与许可。
> 引擎资源（KataGo 二进制/模型）不在本文件范围内，见 AGENTS.md §8/§9。

## 1. 历史名谱 `assets/famous/`（11 局）

**来源**：`github.com/benjaminmantle/baduk-study-material`（自由共享棋谱库）。

- **AI 时代（8 局）**：`10-whole-games/ai-era/`
  - AlphaGo vs 李世石 2016 五番棋（5 局，含第 4 局第 78 手名场面）；
  - AlphaGo vs 柯洁 2017 乌镇（第 1、3 局）；
  - AlphaGo vs 樊麾 2015（第 1 局，AI 首次战胜职业棋手）。
- **经典名局（3 局）**：`10-whole-games/classic/`（`*.tgz` 解压挑选）
  - 吴清源 vs 木谷实 1933（新布局名局）；木谷实 vs 吴清源 1933（和棋）；
  - 本因坊秀策 vs 幻庵因硕 1846（耳赤之妙手）。

**许可**：该库明确「棋谱为事实性内容，自由共享」；`classic/` 为公开领域档案（CWI/Brouwer）。
文件已处理：源库部分文件使用**非标全字母表（含 `i`）坐标**，解析器已自动归一化
（见 `lib/core/sgf.dart`）。

## 2. 死活题 `assets/problems/`（422 题）

**来源**：`github.com/benjaminmantle/baduk-study-material`
`02-life-and-death/graded/gogameguru-weekly/`（gogameguru 每周一题，422 个 SGF，含正解分支）。

- 难度映射（与 `ProblemDifficulty` 对应）：`easy`→入门、`intermediate`→初级、
  `hard`→中级、`other`→高级（后 2 题：长生/心形棋形）。
- `problems.json` 为文件索引（生成于入库时），运行期据此加载。
- 判定依赖 SGF 结构：根节点 `AW/AB` 布子 + `C[]` 题目说明 + 正解主线以 `C[Correct]` 标记。

## 3. 定式布局 `assets/lessons/`（5 项）

- `joseki-star-*.sgf`（4 项）：自编常见星位定式（坐标经专业资料核验，简明中文讲解）。
- `joseki-essentials.sgf`：源自 baduk-study-material `05-joseki/1-dan-joseki-essentials.sgf`，
  已将其非标坐标归一化为标准字母表；英文原版注释保留。

## 4. 入门基础（代码内嵌 `lib/study/lesson_data.dart`）

规则/术语图文为自编内容。

## 许可提示

- baduk-study-material：`LICENSE.md` 声明内容免费、可自由使用；个别社区共享素材
  在其 `docs/provenance.md` 中标记 ⚠（本项目未使用标记项）。
- 未采用 `gitee.com/zl_java/data_set`（GPL v2，119k 职业棋谱库）：copyleft 许可与
  应用打包分发策略冲突，仅作为备选数据源记录。
