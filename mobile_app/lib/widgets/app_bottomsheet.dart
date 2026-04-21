// lib/widgets/dayfi_bottom_sheet.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

Future<T?> showDayFiBottomSheet<T>({
  required BuildContext context,
  required Widget child,
  bool isScrollControlled = true,
  bool isDismissible = true,
  double borderRadius = 24,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return Navigator.of(context).push<T>(
    _BlurSheetRoute<T>(
      isDark: isDark,
      isDismissible: isDismissible,
      borderRadius: borderRadius,
      child: child,
    ),
  );
}

// ─── Custom route ─────────────────────────────────────────────────────────────

class _BlurSheetRoute<T> extends PageRoute<T> {
  final bool isDark;
  final bool isDismissible;
  final double borderRadius;
  final Widget child;

  _BlurSheetRoute({
    required this.isDark,
    required this.isDismissible,
    required this.borderRadius,
    required this.child,
  }) : super(fullscreenDialog: false);

  @override
  bool get opaque => false;
  @override
  bool get barrierDismissible => isDismissible;
  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;
  @override
  bool get maintainState => true; // ← add this
  @override
  Duration get transitionDuration => const Duration(milliseconds: 320);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 240);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _BlurSheetScaffold(
      animation: animation,
      isDark: isDark,
      isDismissible: isDismissible,
      borderRadius: borderRadius,
      child: child,
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

// ─── Full-screen scaffold ─────────────────────────────────────────────────────

class _BlurSheetScaffold extends StatelessWidget {
  final Animation<double> animation;
  final bool isDark;
  final bool isDismissible;
  final double borderRadius;
  final Widget child;

  const _BlurSheetScaffold({
    required this.animation,
    required this.isDark,
    required this.isDismissible,
    required this.borderRadius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // ── Scrim: theme background color at low opacity ──────────────────────
    final scrimColor = isDark
        ? DayFiColors.background.withOpacity(0.55)
        : DayFiColors.lightBackground.withOpacity(0.45);

    // ── Sheet fill: surface color, semi-transparent for glass effect ──────
    final sheetFill = isDark
        ? DayFiColors.surface.withOpacity(0.85)
        : DayFiColors.lightSurface.withOpacity(0.82);

    // ── Border: theme border color ────────────────────────────────────────
    final borderColor = isDark
        ? DayFiColors.border.withOpacity(0.8)
        : DayFiColors.lightBorder.withOpacity(0.9);

    // ── Glow: green accent in dark, muted in light ────────────────────────
    final glowColor = isDark
        ? DayFiColors.green.withOpacity(0.06)
        : DayFiColors.lightBorder.withOpacity(0.6);

    // ── Handle: textSecondary color ───────────────────────────────────────
    final handleColor = isDark
        ? DayFiColors.textMuted
        : DayFiColors.lightTextSecondary.withOpacity(0.35);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isDismissible ? () => Navigator.of(context).pop() : null,
      child: AnimatedBuilder(
        animation: animation,
        builder: (ctx, _) {
          final t = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ).value;

          return Stack(
            children: [
              // ── Layer 1: backdrop blur + scrim ────────────────────────
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8 * t, sigmaY: 8 * t),
                  child: Container(
                    color: scrimColor.withOpacity(scrimColor.opacity * t),
                  ),
                ),
              ),

              // ── Layer 2: sheet sliding up ─────────────────────────────
              Align(
                alignment: Alignment.bottomCenter,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * 300),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(32),
                        ),
                        boxShadow: [
                          // Subtle glow using green accent
                          BoxShadow(
                            color: glowColor,
                            blurRadius: 40,
                            spreadRadius: 0,
                            offset: const Offset(0, -12),
                          ),
                          // Depth shadow
                          BoxShadow(
                            color: Colors.black.withOpacity(
                              isDark ? 0.40 : 0.08,
                            ),
                            blurRadius: 32,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(borderRadius),
                        ),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: Container(
                            decoration: BoxDecoration(
                              color: sheetFill,
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(borderRadius),
                              ),
                              border: Border(
                                top: BorderSide(color: borderColor, width: 0.5),
                                left: BorderSide(
                                  color: borderColor,
                                  width: 0.5,
                                ),
                                right: BorderSide(
                                  color: borderColor,
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 14),
                                // Drag handle using textMuted
                                Container(
                                  width: 36,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: handleColor,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                child,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
