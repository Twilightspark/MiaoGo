# Third-Party Notices · 第三方声明

> MiaoGo 喵棋 依赖多个第三方软件与数据资源。本文件汇总其来源与许可，并包含许可要求附带的版权声明。
> 本文件对应许可须随**发布包**一并分发。
>
> This file lists the third-party software and data bundled or used by MiaoGo and includes the
> copyright/permission notices required by their licenses. Notices required to ship with the
> distributed application are included below.

---

## 1. KataGo Engine（引擎）

- 来源 Source: <https://github.com/lightvector/KataGo>（本项目以 Android NDK 交叉编译出 `libkatago.so` 并随 APK 分发）
- 许可 License: MIT（`cpp/external/` 内嵌库及 `cpp/core/sha2.cpp` 另行遵循各自许可）

```
Copyright 2025 David J Wu ("lightvector") and/or other authors of the content in this repository.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

## 2. KataGo Neural Networks（神经网络模型）

- 来源 Source: <https://katagotraining.org/>（kata1 系列）
- 模型 Networks bundled:
  - `kata1-b6c96-s175395328-d26788732.txt.gz`（级位对弈 · kyu ranks）
  - `kata1-b18c384nbt-s9996604416-d4316597426.bin.gz`（段位对弈与分析 · dan ranks & analysis）
- 许可 License: [KataGo Neural Network License](https://katagotraining.org/network_license/)（MIT 式，允许商业使用）

```
KataGo Neural Network License

Copyright 2026 David J Wu ("lightvector").

Permission is hereby granted, free of charge, to any person obtaining a copy of the neural net files
or training weight files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

## 3. Flutter 与 Dart 依赖 · Flutter/Dart Dependencies

| 依赖 Dependency | 版本 Version | 许可 License |
|---|---|---|
| flutter_riverpod | ^2.6.1 | MIT |
| shared_preferences | ^2.3.5 | BSD-3-Clause (c) 2013 The Flutter Authors |
| path_provider | ^2.1.5 | BSD-3-Clause (c) 2013 The Flutter Authors |
| image_picker | ^1.2.2 | BSD-3-Clause (c) 2013 The Flutter Authors |
| crop_your_image | ^2.0.0 | MIT |
| cupertino_icons | ^1.0.8 | MIT |
| flutter_launcher_icons | ^0.14.4 | MIT |
| flutter_lints | ^6.0.0 | BSD-3-Clause (c) 2013 The Flutter Authors |

各依赖完整版权与许可文本以其包内 `LICENSE` 文件为准（`pubspec.lock` 锁定版本）。
For the full license texts of each package, refer to the `LICENSE` file inside the corresponding package.

## 4. 内嵌棋谱 / 功课数据 · Bundled Go Data

内嵌 `assets/famous`、`assets/problems`、`assets/lessons` 与代码内嵌课程数据来源及许可，
详见 [`docs/data-sources.md`](docs/data-sources.md)：

- **历史名谱（11 局）· Historical games**: `github.com/benjaminmantle/baduk-study-material`
  自由共享棋谱库（AI 时代 + 经典公开档案 CWI/Brouwer）。
- **死活题（422 题）· Life-and-death problems**: `baduk-study-material`
  `02-life-and-death/graded/gogameguru-weekly/`（gogameguru 每周一题）。
- **定式布局 · Joseki**: 自编 + `baduk-study-material` `05-joseki/1-dan-joseki-essentials.sgf`。
- **入门基础 · Lessons**: 自编图文。

`baduk-study-material` 在其 `LICENSE.md` 中声明内容免费、可自由使用；本项目未使用其标记 ⚠ 的社区共享素材。

---

*End of Third-Party Notices.*
