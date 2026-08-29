import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/engine/engine_controller.dart';
import 'package:miaogo/engine/katago_engine.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/ui/analysis_overlay.dart';
import 'package:miaogo/ui/play/ai_setup_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 引擎状态固定的假控制器（loading/failed 测试用）。
class _FakeEngineController extends EngineController {
  _FakeEngineController(this.status);
  final EngineStatus status;

  @override
  EngineStatus build() => status;

  @override
  Future<void> start() async {} // 禁止真实启动（测试环境无插件）
}

Future<void> pumpSetup(
    WidgetTester tester, EngineController controller) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        engineStatusProvider.overrideWith(() => controller),
      ],
      child: const MaterialApp(home: AISetupPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('引擎加载中：设置页开始按钮禁用并显示加载', (tester) async {
    await pumpSetup(tester, _FakeEngineController(EngineStatus.loading));
    final button = tester
        .widget<FilledButton>(find.byKey(const ValueKey('ai_start_button')));
    expect(button.onPressed, isNull);
    expect(find.text('引擎加载中…'), findsOneWidget);
  });

  testWidgets('引擎失败：设置页显示错误与重试按钮', (tester) async {
    await pumpSetup(tester, _FakeEngineController(EngineStatus.failed));
    expect(find.textContaining('引擎不可用'), findsOneWidget);
    expect(find.text('重试加载引擎'), findsOneWidget);
  });

  testWidgets('引擎失败：显示不可用提示条', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          engineStatusProvider.overrideWith(
              () => _FakeEngineController(EngineStatus.failed)),
        ],
        child: const MaterialApp(home: Scaffold(body: EngineStatusBanner())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('KataGo 引擎不可用'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('引擎加载中：显示加载条', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          engineStatusProvider.overrideWith(
              () => _FakeEngineController(EngineStatus.loading)),
        ],
        child: const MaterialApp(home: Scaffold(body: EngineStatusBanner())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('引擎加载中'), findsOneWidget);
  });
}
