# 棋谱 / 功课数据来源（P4/P5）

> 本文件记录 `assets/famous`、`assets/problems`、`assets/lessons` 内嵌数据的来源与许可。
> 引擎资源（KataGo 二进制/模型）不在本文件范围内，见 AGENTS.md §8/§9。
> 死活题离线生成管道：`D:\AI\go\tsumego\`（Python，纯标准库），来源固定、可重放
> （baduk-study-material 固定 commit；tsumego-pdf 本网络无法解析提交 SHA，暂按 `main`
> 分支记录，见 `tsumego/datasets.py`）；产物为 `assets/problems/`（单题 SGF +
> `problems.json` 索引 + `sources.json` 来源/许可清单）。
> `sources.json` 的 `tier` 沿用来源仓库 provenance 分级：`clean`（公版/CC）、
> `grey-pd-positions`（题目位置公版，SGF 转制为社区流传，按“被要求即下架”处理）。

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

## 2. 死活题 `assets/problems/`（2678 题，三档模型）

难度分级（2026-09 起整体为**三档**，与 `ProblemDifficulty` 对应）：
`入门(beginner) / 中级(intermediate) / 高级(advanced)`。

### 2a. gogameguru 每周一题（422 题）

**来源**：`github.com/benjaminmantle/baduk-study-material`
`02-life-and-death/graded/gogameguru-weekly/`（gogameguru 每周一题，422 个 SGF，含正解分支）。

- 三档映射：`easy`+`intermediate`(文件夹)→**入门**、`hard`→**中级**、
  `other`→**高级**（后 2 题：长生/心形棋形）。
- `problems.json` 为文件索引（由管道按三档重建），运行期据此加载。
- 判定依赖 SGF 结构：根节点 `AW/AB` 布子 + `C[]` 题目说明 + 正解主线以 `C[Correct]` 标记。

### 2b. Gokyo Shumyo（《碁経》古典死活，509 题，2026-09 扩容）

**来源**：同仓库 `02-life-and-death/collections/gokyo-shumyo/gokyo shumyo.zip`
（每题一个 SGF；MultiGo FF3 全字母表坐标，根布子 + 提示 C[] + 正解首分支）。

- 古典死活位置属公版；SGF 转制为社区流传（`grey-pd-positions`，逐一标注来源）。
- 管道处理：坐标全字母表→标准字母表 → 每题规范化为单文件（`gokyo/gokyo-NNN.sgf`，
  保留源编号）→ 首分支链为正解主线并打 `C[Correct]` → 三档模型下归入**中级**档。
- 合规备注：`PL` 与首分支异色（#12/#160/#226）与整盘大怪题（#513–520，主线 >60 手）
  不适配移动端逐手判题，导入时跳过并记录于管道输出。
- 许可风险按仓库承诺“被要求即下架”；如需移除，删 `assets/problems/gokyo/` 目录并重跑
  `python build.py`（`D:\AI\go\tsumego`）即可重生 `problems.json`/`sources.json`。

### 2c. Cho Chikun 死活辞典 Elementary（887 题）与 Intermediate（860 题），2026-09 扩容

**来源**：`github.com/travisgk/tsumego-pdf`（MIT；题册正文与 `go-problems.json` 一致）。
题目源自 `tsumego.tasuki.org`（Chih-Chun 收集），**正解为 online-go.com 社区逐题回放**；
数据中每题的编号棋子/空点标记（`X`=第 1 手、`2..9`=空点标记、`❶..⓴`/`①..⑳`=黑/白子上
手数标记）即**完整交替正解主线**（黑先、奇数黑偶数白）。管道按 19 路规则逐题回放
（含提子、禁自杀）校验：Elementary 900 → 887 入库（13 题回放不合法跳过）；
Intermediate 861 → 860 入库（1 题跳过）。题册全部黑先、按题号顺序由易到难。

- 三档映射：**Elementary 全册 → 入门**；**Intermediate 前 2/3 → 中级**、
  **末 1/3 → 高级**（填高级档空档）。
- 每题规范化为单文件 `cho-elementary/cho-elem-NNN.sgf` 与
  `cho-intermediate/cho-int-NNN.sgf`（保留源编号；`PL[B]` + 主线 + `C[Correct]` 末节点）。
- 许可状态不明（题目来源网站、正解来自 OGS 社区），按 `grey-pd-positions` 登记：
  **被要求即下架**；如需移除，删对应目录并重跑管道即可。
- 2026-09 前曾整体评估「四档」模型；Cho 扩容同步完成**三档迁移**
  （`problems.json`/`ProblemDifficulty` 仅剩 入门/中级/高级 三档）。

### 2d. 评估后未收录：Xuanxuan Qijing / Igo Hatsuyōron

- **Xuanxuan Qijing（《玄玄棋經》/ Gengen Gokyo，1349）**：`collections/gengen-gokyo-xuanxuan-qijing/gengen gokyo.zip`
  有 347 道带正解直链主线的社区转制 SGF（位置公版），曾短暂入库 343 道（剔除整盘大怪题 #343–346）
  并归入**高级**档；后因**源文件无讲解/目标语**，本地 KataGo 试点（b18c384，单题 genmove≈20s）
  无法可靠生成并缓存可用的答案文本（仅推荐点/胜率，多数首手与源主线不一致），**已于 2026-09 下线**。
  数据集配方保留在 `D:\AI\go\tsumego/tsumego/datasets.py`（`enabled: false` 与下线原因）；
  待「KataGo 正解生成/结局判定补目标语」路线可用再重启。
- **Igo Hatsuyōron（《碁經精妙》，1713）**：仅 `importable-sgf/igo-hatsuyoron.sgf`（183 题、题目
  无正解线，位置公版）；仓库内无配套正解 SGF/PDF，同样暂缓（同上线路线就绪后再入「高级」档）。
- **Cho Chikun Advanced（792 题）**：tsumego-pdf 无正解标记（README「Cho Advanced」不标注
  Solutions Available）；与 Xuanxuan/Hatsuyōron 同类问题暂缓，待 OGS 导出/其他正解路线。

### 2e. 来源清单

`assets/problems/sources.json`（v2）记录：tier（`cc-by-nc-sa-4.0` / `grey-pd-positions`）、
各来源题数、说明与来源仓库，供 UI「数据来源与许可」页与审计使用。

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
