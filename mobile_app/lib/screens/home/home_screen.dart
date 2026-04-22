// lib/screens/home/home_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_app/widgets/app_background.dart';
import '../../models/asset.dart';
import '../../providers/wallet_provider.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';

final userProvider = FutureProvider<Map<String, dynamic>>(
  (ref) => apiService.getMe(),
);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _balanceHidden = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      ref.read(walletProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // ─── Open menu as full-screen route ─────────────────────

  void _openMenu() {
    final userAsync = ref.read(userProvider);
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        pageBuilder: (ctx, animation, _) => _MenuOverlay(
          animation: animation,
          onNavigate: (route) {
            Navigator.of(ctx).pop(); // close menu first
            if (route != null) context.push(route);
          },
          onTestFund: () async {
            Navigator.of(ctx).pop();
            try {
              await apiService.testFundWallet();
              await ref.read(walletProvider.notifier).refresh();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Wallet funded with 1.0 XLM'),
                    backgroundColor: Color(0xFF4CAF50),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('❌ Fund failed: $e'),
                    backgroundColor: const Color(0xFFE53935),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            }
          },
        ),
        transitionsBuilder: (ctx, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 180),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(walletProvider);

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          centerTitle: true,
          automaticallyImplyLeading: false,
          title: _buildTopBar(context),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: InkWell(
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
                onTap: _openMenu,
                child: SvgPicture.asset(
                  "assets/icons/svgs/menu.svg",
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.55),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              await ref.read(walletProvider.notifier).refresh();
              ref.invalidate(userProvider);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height:
                      MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom,
                  child: Column(
                    children: [
                      const Spacer(flex: 4),
                      _buildBalanceLabel(),
                      const SizedBox(height: 16),
                      _buildTotalBalance(walletState),
                      const SizedBox(height: 16),
                      _buildPortfolioChip(walletState),
                      const SizedBox(height: 32),
                      _buildTransactionsLink(),
                      const Spacer(flex: 4),
                      _buildActionRow(),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Top bar ─────────────────────────────────────────────

  // ─── Balance label ───────────────────────────────────────

  Widget _buildBalanceLabel() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Total Wallet Balance',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(.60),
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 6),
        InkWell(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          onTap: () => setState(() => _balanceHidden = !_balanceHidden),
          child: SvgPicture.asset(
            _balanceHidden
                ? "assets/icons/svgs/eye_closed.svg"
                : "assets/icons/svgs/eye_open.svg",
            height: 21,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(.60),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 500.ms);
  }

  Widget _buildTotalBalance(WalletState walletState) {
    final xlmPriceUSD = walletState.xlmPriceUSD ?? 0.0;
    const xlmReserve = 2.0;
    final reservedUSD = xlmReserve * xlmPriceUSD;

    // ── Determine what value to actually display ──────────────
    // Priority: live total → last known → dash (never show 0.00 falsely)
    final rawTotal = walletState.totalUSD - reservedUSD;
    final liveTotal = rawTotal < 0
        ? 0.0
        : double.parse(rawTotal.toStringAsFixed(2));

    // Use last known if current fetch errored/offline and live is 0
    final displayTotal =
        (walletState.hasError || walletState.isOffline) && liveTotal == 0
        ? walletState.lastKnownTotal
        : liveTotal;

    final hasMeaningfulValue = displayTotal != null && displayTotal > 0;

    // ── Loading spinner (first load only, no lastKnown yet) ───
    if (walletState.isLoading && walletState.lastKnownTotal == null) {
      return Text(
        '\$—',
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w400,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(.40),
          letterSpacing: 0.4,
          fontSize: 28,
        ),
      );
    }

    // ── Hidden balance ────────────────────────────────────────
    if (_balanceHidden) {
      return _buildBalanceRow(context, '***', '.**', isHidden: true);
    }

    // ── Offline / error with no cached value → show dash + badge ─
    if (!hasMeaningfulValue &&
        (walletState.hasError || walletState.isOffline)) {
      return Column(
        children: [
          Text(
            '\$—',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontSize: 64,
              fontWeight: FontWeight.w400,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(.40),
              letterSpacing: 0.4,
              height: .88,
            ),
          ),
          const SizedBox(height: 10),
          _buildStatusBadge(walletState),
        ],
      ).animate().fadeIn(duration: 400.ms);
    }

    // ── Normal display (with optional stale badge) ────────────
    final total = displayTotal ?? 0.0;
    final wholePart = total.toInt().toString();
    final decimalPart = total.toStringAsFixed(2).split('.')[1];

    return Column(
      children: [
        _buildBalanceRow(context, wholePart, '.$decimalPart'),

        // Subtle "last known" badge when showing cached data
        if ((walletState.hasError || walletState.isOffline) &&
            hasMeaningfulValue) ...[
          const SizedBox(height: 10),
          _buildStatusBadge(walletState),
        ],
      ],
    ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.05, end: 0);
  }

  // ─── Shared balance row renderer ────────────────────────────────────────────

  Widget _buildBalanceRow(
    BuildContext context,
    String whole,
    String decimal, {
    bool isHidden = false,
  }) {
    final opacity = isHidden ? .40 : .85;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            '\$',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w400,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(.60),
              letterSpacing: 0.4,
              fontSize: 28,
            ),
          ),
        ),
        Text(
          whole,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontSize: 64,
            fontWeight: FontWeight.w400,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(opacity),
            letterSpacing: 0.4,
            height: .88,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            decimal,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w400,
              fontSize: 28,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withOpacity(opacity),
              letterSpacing: 0.4,
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.05, end: 0);
  }

  // ─── Status badge (offline / error) ─────────────────────────────────────────

  Widget _buildStatusBadge(WalletState walletState) {
    final isOffline = walletState.isOffline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (isOffline ? Colors.orange : DayFiColors.red).withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (isOffline ? Colors.orange : DayFiColors.red).withOpacity(
            0.25,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOffline ? Icons.wifi_off_rounded : Icons.sync_problem_rounded,
            size: 12,
            color: (isOffline ? Colors.orange : DayFiColors.red).withOpacity(
              0.8,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            isOffline
                ? (walletState.lastKnownTotal != null
                      ? 'Offline · last known balance'
                      : 'No connection')
                : 'Couldn\'t refresh · pull to retry',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: (isOffline ? Colors.orange : DayFiColors.red).withOpacity(
                0.8,
              ),
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms);
  }

  // ─── Portfolio chip ──────────────────────────────────────

  Widget _buildPortfolioChip(WalletState walletState) {
    final heldAssets = <String>[];
    if (walletState.xlmBalance > 0) {
      heldAssets.add('assets/images/stellar.png');
    }
    if (walletState.usdcBalance > 0) {
      heldAssets.add('assets/images/usdc.png');
    }
    if (heldAssets.isEmpty) {
      heldAssets.add('assets/images/stellar.png');
      heldAssets.add('assets/images/usdc.png');
    }

    final assets = ['assets/images/stellar.png', 'assets/images/usdc.png'];

    return InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      onTap: () => context.push('/portfolio'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).textTheme.bodySmall!.color!.withOpacity(0.1),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16.0 + (assets.length * 16.0),
              height: 26,
              child: Stack(
                children: List.generate(assets.length, (i) {
                  return Positioned(
                    left: i * 16.0,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset(
                            assets[i],
                            fit: BoxFit.contain,
                            height: assets[i] == "assets/images/stellar.png"
                                ? 20
                                : 24,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(width: 2),
            Text(
              'Portfolio',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w400,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.60),
                letterSpacing: 0.4,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 8),
            RotatedBox(
              quarterTurns: -1,
              child: SvgPicture.asset(
                "assets/icons/svgs/dropdown.svg",
                height: 18,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
            const SizedBox(width: 2),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 200.ms);
  }

  // ─── Transactions link ───────────────────────────────────

  Widget _buildTransactionsLink() {
    return InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      onTap: () => context.push('/transactions'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            "assets/icons/svgs/transactions.svg",
            height: 18,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(.60),
          ),
          const SizedBox(width: 8),
          Text(
            'Transactions',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(.60),
              letterSpacing: 0.4,
              fontSize: 12,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms);
  }

  // ─── Action row ──────────────────────────────────────────

  Widget _buildActionRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 72),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).textTheme.bodySmall!.color!.withOpacity(0.1),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
          ),
        ),
        child: Row(
          children: [
            _ActionButton(
              icon: "assets/icons/svgs/receive.svg",
              label: 'Receive',
              onTap: () => context.push('/receive'),
            ),
            _ActionButton(
              icon: "assets/icons/svgs/swap.svg",
              label: 'Swap',
              onTap: () => context.push('/swap'),
            ),
            _ActionButton(
              icon: "assets/icons/svgs/send.svg",
              label: 'Send',
              onTap: () => context.push('/send'),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.4, end: 0);
  }
}

Widget _buildTopBar(context) {
  return Opacity(
    opacity: .45,
    child: Image.asset("assets/images/word_logo.png", width: 88),
  );
}

// ─── Menu Overlay (separate route, no flash) ─────────────────────────────────

class _MenuOverlay extends StatelessWidget {
  final Animation<double> animation;
  final void Function(String? route) onNavigate;
  final VoidCallback onTestFund;

  const _MenuOverlay({
    required this.animation,
    required this.onNavigate,
    required this.onTestFund,
  });

  static const _items = [
    ('transactions', '/transactions'),
    ('security', '/security'),
    ('settings', '/settings'),
    ('support', null),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        onTap: () => Navigator.of(context).pop(),
        child: AppBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              centerTitle: true,
              automaticallyImplyLeading: false,
              title: _buildTopBar(context),
              backgroundColor: Colors.transparent,
              elevation: 0,
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: InkWell(
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    onTap: () => Navigator.of(context).pop(),
                    child: SvgPicture.asset(
                      "assets/icons/svgs/menu.svg",
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.55),
                    ),
                  ),
                ),
              ],
            ),
            body: SizedBox.expand(
              child: Column(
                children: [
                  const Expanded(child: SizedBox()),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: List.generate(_items.length, (i) {
                      final item = _items[i];
                      return AnimatedBuilder(
                        animation: animation,
                        builder: (ctx, child) {
                          // Stagger: each item starts slightly later
                          final staggered = CurvedAnimation(
                            parent: animation,
                            curve: Interval(
                              i * 0.08,
                              (i * 0.08 + 0.6).clamp(0.0, 1.0),
                              curve: Curves.easeOutCubic,
                            ),
                          );
                          return Transform.translate(
                            offset: Offset(60 * (1 - staggered.value), 0),
                            child: Opacity(
                              opacity: staggered.value.clamp(0.0, 1.0),
                              child: child,
                            ),
                          );
                        },
                        child: InkWell(
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          hoverColor: Colors.transparent,
                          // behavior: HitTestBehavior.opaque,
                          onTap: () {
                            onNavigate(item.$2);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              item.$1,
                              style: Theme.of(context).textTheme.displayLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w400,
                                    fontSize: 38,
                                    letterSpacing: -0.8,
                                  ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const Expanded(child: SizedBox()),
                  const Text("DayFi v1.0.1 (Build 34)"),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Action Button ────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                icon,
                height: 22,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.60),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(.60),
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
