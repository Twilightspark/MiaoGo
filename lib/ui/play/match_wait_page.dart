import 'dart:math';

import 'package:flutter/material.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/ui/play/opponent_pool.dart';

/// 老虎机弹窗时间参数（毫秒），便于整体微调节奏。
///
/// 落点约定：目标 `t`=「旗鼓相当的对手」，首个落点 `t+3`（目标下方第 3 个
/// 随机项）；回冲时扫过 `t` 并略微超过至 `t - overshootRows`，再落定回 `t`。
class MatchSpinTiming {
  MatchSpinTiming._();

  /// 回冲时超过目标的格数（上方回弹 1 格即可，衔接更连贯）。
  static const int overshootRows = 1;

  /// A：高速起步 → 逐渐减速，刹停在“目标下方第 3 个随机项”。
  static const int fastToStop = 3000;

  /// A 落点后的悬停。
  static const int restPause = 180;

  /// B：回滚（短暂加速后减速，扫过目标并略超）；速度已减半。
  static const int flickBack = 1240;

  /// 略超位置处的悬停。
  static const int settlePause = 180;

  /// C：回落到「旗鼓相当的对手」。
  static const int settleLand = 380;

  /// D：定格亮灯展示。
  static const int lockedHold = 3000;
}

/// 匹配定格结果：永远为“旗鼓相当的对手”。
const String kMatchedOpponentName = '旗鼓相当的对手';

/// 以居中木质老虎机弹窗执行匹配；匹配完成后自动关闭并返回结果名，
/// 用户无法中途取消（`matched == null` 理论不可达，仅作兜底）。
Future<String?> showMatchDialog(
  BuildContext context, {
  Random? random,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '匹配对手中',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, _) => PopScope(
      canPop: false,
      child: _MatchDialog(random: random),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved =
          CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _MatchDialog extends StatefulWidget {
  const _MatchDialog({this.random});

  /// 随机源（测试注入用）。
  final Random? random;

  @override
  State<_MatchDialog> createState() => _MatchDialogState();
}

class _MatchDialogState extends State<_MatchDialog>
    with TickerProviderStateMixin {
  /// 名字重复轮数，保证高速段有足够滚动距离。
  static const int _copies = 3;

  /// 定格项下方保留的一整轮随机名字，用于“下方第 3 个随机项”过冲与收尾。
  late final List<String> _items;
  late final int _targetIndex;
  late final int _overshootIndex;
  late final int _overshootPastIndex;
  late final FixedExtentScrollController _wheel;
  late final AnimationController _bulbs;

  bool _locked = false;

  @override
  void initState() {
    super.initState();
    final random = widget.random ?? Random();
    final seg = List<String>.of(kOpponentPool)..shuffle(random);
    // seg×N + 目标 + seg：目标后仍有大量随机名，过冲不露轴底。
    _items = [
      for (var c = 0; c < _copies; c++) ...seg,
      kMatchedOpponentName,
      ...seg,
    ];
    _targetIndex = _copies * kOpponentPool.length;
    _overshootIndex = _targetIndex + 3;
    _overshootPastIndex = _targetIndex - MatchSpinTiming.overshootRows;
    final startIndex = random.nextInt(kOpponentPool.length);
    _wheel = FixedExtentScrollController(initialItem: startIndex);
    _bulbs = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _run();
    });
  }

  @override
  void dispose() {
    _bulbs.dispose();
    _wheel.dispose();
    super.dispose();
  }

  /// 以短动画控制器制造“停顿”，保证整段流程持续出帧（pumpAndSettle 稳定）。
  Future<void> _delay(Duration duration) async {
    final controller =
        AnimationController(vsync: this, duration: duration);
    await controller.forward();
    controller.dispose();
  }

  Future<void> _run() async {
    _bulbs.repeat();

    // A) 高速起步 → 逐渐减速，刹停在“目标下方第 3 个随机项”。
    await _wheel.animateToItem(
      _overshootIndex,
      duration: const Duration(milliseconds: MatchSpinTiming.fastToStop),
      curve: Curves.easeOutQuart,
    );
    if (!mounted) return;

    // B) 短暂悬停后回冲：加速扫过目标并略微超过（上方 overshootRows 格）。
    await _delay(const Duration(milliseconds: MatchSpinTiming.restPause));
    if (!mounted) return;
    await _wheel.animateToItem(
      _overshootPastIndex,
      duration: const Duration(milliseconds: MatchSpinTiming.flickBack),
      curve: Curves.easeInOutCubic,
    );
    if (!mounted) return;

    // C) 短暂悬停后落定「旗鼓相当的对手」。
    await _delay(const Duration(milliseconds: MatchSpinTiming.settlePause));
    if (!mounted) return;
    await _wheel.animateToItem(
      _targetIndex,
      duration: const Duration(milliseconds: MatchSpinTiming.settleLand),
      curve: Curves.easeOutQuad,
    );
    if (!mounted) return;

    // D) 定格亮灯展示，随后自动关闭弹窗。
    _bulbs.stop();
    setState(() => _locked = true);
    await _delay(const Duration(milliseconds: MatchSpinTiming.lockedHold));
    if (!mounted) return;
    Navigator.of(context).pop(kMatchedOpponentName);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('match_dialog'),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: _buildCabinet(Theme.of(context)),
          ),
        ),
      ),
    );
  }

  /// 木质机身。
  Widget _buildCabinet(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [GoColors.woodHighlight, GoColors.wood, GoColors.woodDeep],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: GoColors.woodHighlight, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildMarquee(theme),
          const SizedBox(height: 16),
          _buildWindow(theme),
          const SizedBox(height: 16),
          _buildFooter(theme),
        ],
      ),
    );
  }

  /// 顶部铭牌与灯珠。
  Widget _buildMarquee(ThemeData theme) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _Rivet(),
            const SizedBox(width: 12),
            Text(
              'MATCH · 快速匹配',
              style: theme.textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(width: 12),
            const _Rivet(),
          ],
        ),
        const SizedBox(height: 10),
        _buildBulbs(),
      ],
    );
  }

  /// 6 颗灯珠：滚动中随机闪烁，定格后常亮松柏青。
  Widget _buildBulbs() {
    return AnimatedBuilder(
      animation: _bulbs,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 6; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              _Bulb(
                on: _locked,
                flicker: (sin(_bulbs.value * 2 * pi - i * 1.7) + 1) / 2,
              ),
            ],
          ],
        );
      },
    );
  }

  /// 老虎机玻璃窗。
  Widget _buildWindow(ThemeData theme) {
    const windowHeight = 248.0;
    return Container(
      height: windowHeight,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GoColors.woodDark, width: 1.5),
      ),
      child: Stack(
        children: [
          IgnorePointer(
            child: ListWheelScrollView(
              controller: _wheel,
              itemExtent: 52,
              diameterRatio: 1.9,
              useMagnifier: true,
              magnification: 1.28,
              squeeze: 1.0,
              children: [
                for (final name in _items)
                  Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        name,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: GoColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 中心取景行高亮。
          Positioned(
            left: 0,
            right: 0,
            top: (windowHeight - 52) / 2,
            height: 52,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: GoColors.pineContainer.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
          // 上下玻璃渐隐。
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 40,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      theme.colorScheme.surfaceContainerLowest,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 40,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      theme.colorScheme.surfaceContainerLowest,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 两侧木质滚轴立柱。
          const Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: _Rail(),
          ),
          const Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: _Rail(),
          ),
          // 顶部漫反射光泽。
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: windowHeight / 2,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.08),
                      Colors.white.withValues(alpha: 0.02),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.4, 1],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return SizedBox(
      height: 44,
      child: Center(
        child: _locked
            ? const SizedBox.shrink()
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: GoColors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '匹配中，请稍候…',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// 机身四角/铭牌两侧的铆钉装饰。
class _Rivet extends StatelessWidget {
  const _Rivet();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFF8A5A2E)],
        ),
        border: Border.all(color: GoColors.woodDeep),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 3),
        ],
      ),
      child: Center(
        child: Container(
          width: 4,
          height: 4,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: GoColors.woodDeep,
          ),
        ),
      ),
    );
  }
}

/// 顶排灯珠（滚动中闪烁 / 定格常亮）。
class _Bulb extends StatelessWidget {
  const _Bulb({required this.on, required this.flicker});

  final bool on;

  /// 0~1 亮度（滚动中随机闪烁用）。
  final double flicker;

  @override
  Widget build(BuildContext context) {
    final glow = on || flicker > 0.5;
    final color = on ? GoColors.pine : GoColors.woodHighlight;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: glow ? color : GoColors.woodDeep,
        border: Border.all(color: GoColors.woodDark, width: 1),
        boxShadow: [
          if (glow)
            BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 6),
        ],
      ),
    );
  }
}

/// 玻璃窗两侧的木质滚轴立柱。
class _Rail extends StatelessWidget {
  const _Rail();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [GoColors.woodDeep, GoColors.wood, GoColors.woodDeep],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < 4; i++)
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: GoColors.woodContainer,
              ),
            ),
        ],
      ),
    );
  }
}
