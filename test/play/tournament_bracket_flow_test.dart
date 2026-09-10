import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/game/career_controller.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/ui/play/tournament_bracket_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 赛程页覆盖：报名后渲染四列赛程；引擎未就绪时点「进行对局」给出提示。
void main() {
  testWidgets('赛程页：报名后渲染四列赛程，引擎未就绪给出提示', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    // 报名 9 路大赛（触发待报名大赛生成）。
    final id = container
        .read(careerControllerProvider)
        .upcoming
        .firstWhere((t) => t.boardSize == 9)
        .id;
    expect(container.read(careerControllerProvider.notifier).signUp(id), isTrue);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TournamentBracketPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 四列赛程 + 冠军。
    expect(find.text('1/4 决赛'), findsOneWidget);
    expect(find.text('半决赛'), findsOneWidget);
    expect(find.text('决赛'), findsOneWidget);
    expect(find.text('冠军'), findsOneWidget);
    expect(find.byKey(const ValueKey('bracket_play')), findsOneWidget);

    // 引擎未就绪：点击开始对局给出提示，不进入对局。
    await tester.tap(find.byKey(const ValueKey('bracket_play')));
    await tester.pumpAndSettle();
    expect(find.textContaining('未就绪'), findsOneWidget);
  });
}
