import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/storage/problem_store.dart';
import 'package:miaogo/study/problem_engine.dart';
import 'package:miaogo/ui/study/problem_solve_view.dart';

/// 题库作答页：在给定题目列表内逐题作答（上一题 / 下一题切换）。
///
/// 复用 [ProblemSolveView]；自身不涉及每日轮次，仅更新 [problemStoreProvider]。
class ProblemSolvePage extends ConsumerStatefulWidget {
  const ProblemSolvePage({
    super.key,
    required this.problems,
    this.initialIndex = 0,
  });

  final List<Problem> problems;
  final int initialIndex;

  @override
  ConsumerState<ProblemSolvePage> createState() => _ProblemSolvePageState();
}

class _ProblemSolvePageState extends ConsumerState<ProblemSolvePage> {
  late int _index =
      widget.initialIndex.clamp(0, widget.problems.length - 1);

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(problemStoreProvider);
    final problem = widget.problems[_index];
    return Scaffold(
      appBar: AppBar(title: Text(problem.title)),
      body: SafeArea(
        child: ProblemSolveView(
          problems: widget.problems,
          index: _index,
          onIndexChanged: (i) => setState(() => _index = i),
          restoreProgress: (p) => (0, progress[p.id]?.attempts ?? 0),
        ),
      ),
    );
  }
}
