import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app.dart';
import 'package:miaogo/engine/engine_controller.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const _MiaoGoRoot(),
    ),
  );
}

/// 应用根：启动后预加载 KataGo 引擎（后台解压 + 拉起进程）。
class _MiaoGoRoot extends ConsumerStatefulWidget {
  const _MiaoGoRoot();

  @override
  ConsumerState<_MiaoGoRoot> createState() => _MiaoGoRootState();
}

class _MiaoGoRootState extends ConsumerState<_MiaoGoRoot> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 单引擎（P6）：b18c384 主模型 + Human SL 模型，对弈与分析共用。
      ref.read(engineStatusProvider.notifier).start();
    });
  }

  @override
  Widget build(BuildContext context) => const MiaoGoApp();
}
