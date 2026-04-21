// lib/screens/portfolio/portfolio_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/widgets/app_background.dart';
import 'package:mobile_app/widgets/app_bottomsheet.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/wallet_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

// ─── Provider ────────────────────────────────────────────────────────────────

final _txProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final result = await apiService.getTransactions(page: 1, limit: 100);
  return List<Map<String, dynamic>>.from(result['transactions'] ?? []);
});

// ─── Period config ────────────────────────────────────────────────────────────

const _periods = ['1D', '1W', '1M', 'ALL'];
const _periodLabels = ['today', 'this week', 'this month', 'all time'];

// ─── Asset detail model ───────────────────────────────────────────────────────

class _AssetDetail {
  final String code;
  final String name;
  final String imagePath;
  final double balance;
  final double usdValue;
  final double changePercent;
  final double available;
  final double reserved;
  final double price;
  final List<double> points;

  const _AssetDetail({
    required this.code,
    required this.name,
    required this.imagePath,
    required this.balance,
    required this.usdValue,
    required this.changePercent,
    required this.available,
    required this.reserved,
    required this.price,
    required this.points,
  });
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class PortfolioScreen extends ConsumerStatefulWidget {
  const PortfolioScreen({super.key});

  @override
  ConsumerState<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends ConsumerState<PortfolioScreen> {
  int _selectedPeriod = 1;

  DateTime get _periodStart {
    final now = DateTime.now();
    return switch (_selectedPeriod) {
      0 => now.subtract(const Duration(days: 1)),
      1 => now.subtract(const Duration(days: 7)),
      2 => now.subtract(const Duration(days: 30)),
      _ => DateTime(2000),
    };
  }

  List<double> _buildPoints(
    List<Map<String, dynamic>> txs,
    String asset,
    double currentBalance,
    double xlmPrice,
  ) {
    final cutoff = _periodStart;
    final filtered =
        txs.where((t) => t['asset'] == asset).where((t) {
          final dt = DateTime.tryParse(t['createdAt'] ?? '');
          return dt != null && dt.isAfter(cutoff);
        }).toList()..sort(
          (a, b) => DateTime.parse(
            a['createdAt'],
          ).compareTo(DateTime.parse(b['createdAt'])),
        );

    if (filtered.isEmpty) {
      final usd = asset == 'XLM' ? currentBalance * xlmPrice : currentBalance;
      return [usd, usd];
    }

    double running = currentBalance;
    final reversed = filtered.reversed.toList();
    final rawValues = <double>[];

    for (final tx in reversed) {
      final amt = (tx['amount'] as num).toDouble();
      final type = tx['type'] as String;
      final swapToAsset = (tx['swapToAsset'] as String?) ?? '';

      // Determine if this transaction affects current asset
      bool isOutgoing = false;

      if (type == 'send') {
        isOutgoing = true;
      } else if (type == 'swap') {
        // For swaps: check swapToAsset to determine direction
        // If swapToAsset matches current asset, it's incoming (receive)
        // Otherwise it's outgoing (send)
        isOutgoing = (swapToAsset != asset);
      }

      if (isOutgoing) {
        running += amt;
      } else {
        running -= amt;
      }
      rawValues.add(running.clamp(0, double.infinity));
    }

    final chronological = rawValues.reversed.toList()..add(currentBalance);
    return chronological.map((b) {
      return asset == 'XLM' ? b * xlmPrice : b;
    }).toList();
  }

  double _computeChange(List<double> points) {
    if (points.length < 2) return 0.0;
    final first = points.first;
    if (first <= 0) return 0.0;
    return ((points.last - first) / first) * 100;
  }

  List<double> _combinePoints(List<double> a, List<double> b) {
    final len = a.length > b.length ? a.length : b.length;
    if (len == 0) return [];
    List<double> interp(List<double> src) {
      if (src.length == len) return src;
      return List.generate(len, (i) {
        final t = i / (len - 1);
        final si = t * (src.length - 1);
        final lo = si.floor().clamp(0, src.length - 1);
        final hi = si.ceil().clamp(0, src.length - 1);
        return src[lo] + (src[hi] - src[lo]) * (si - lo);
      });
    }

    final ia = interp(a), ib = interp(b);
    return List.generate(len, (i) => ia[i] + ib[i]);
  }

  void _openAssetDetail(BuildContext context, _AssetDetail detail) {
    showDayFiBottomSheet(
      context: context,
      child: _AssetDetailSheet(detail: detail),
    );
  }

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(walletProvider);
    final txAsync = ref.watch(_txProvider);

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'Portfolio',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).textTheme.bodyLarge?.color?.withOpacity(.95),
              fontWeight: FontWeight.w500,
              fontSize: 16,
              letterSpacing: -0.1,
            ),
          ),
          leading: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.pop(),
            child: const Icon(Icons.arrow_back_ios, size: 20),
          ),
        ),
        body: SafeArea(
          child: txAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (txs) => RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(_txProvider);
                await ref.read(walletProvider.notifier).refresh();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: _buildBody(context, walletState, txs),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WalletState w,
    List<Map<String, dynamic>> txs,
  ) {
    const xlmReserve = 2.0;
    final xlmPrice = w.xlmPriceUSD;

    // Deduct reserve from XLM balance everywhere
    final xlmDisplayBalance = (w.xlmBalance - xlmReserve > 0)
        ? (w.xlmBalance - xlmReserve)
        : 0.0;
    final xlmUSD = xlmDisplayBalance * xlmPrice;
    final usdcUSD = w.usdcBalance;
    final totalUSD = xlmUSD + usdcUSD;

    final xlmPoints = _buildPoints(txs, 'XLM', xlmDisplayBalance, xlmPrice);
    final usdcPoints = _buildPoints(txs, 'USDC', w.usdcBalance, 1.0);
    final combined = _combinePoints(xlmPoints, usdcPoints);

    final changePct = _computeChange(combined);
    final changeAbs = combined.length >= 2
        ? combined.last - combined.first
        : 0.0;

    final xlmDetail = _AssetDetail(
      code: 'XLM',
      name: 'Stellar Lumens',
      imagePath: 'assets/images/stellar.png',
      balance: xlmDisplayBalance,
      usdValue: xlmUSD,
      changePercent: _computeChange(xlmPoints),
      available: xlmDisplayBalance,
      reserved: xlmReserve,
      price: xlmPrice,
      points: xlmPoints,
    );

    final usdcDetail = _AssetDetail(
      code: 'USDC',
      name: 'USD Coin',
      imagePath: 'assets/images/usdc.png',
      balance: w.usdcBalance,
      usdValue: usdcUSD,
      changePercent: _computeChange(usdcPoints),
      available: w.usdcBalance,
      reserved: 0,
      price: 1.0,
      points: usdcPoints,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          _buildTotalValue(totalUSD),
          const SizedBox(height: 12),
          _buildChangeRow(changePct, changeAbs),
          const SizedBox(height: 20),
          _buildReserveNotice(context),
          _buildAssetsSection(context, xlmDetail, usdcDetail, w),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  // ─── Total value ──────────────────────────────────────────

  Widget _buildTotalValue(double total) {
    final whole = total.toInt().toString();
    final decimal = (total - total.toInt()).toStringAsFixed(2).substring(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 32),
        Text(
          'Total balance',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            fontSize: 12,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '\$',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w400,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(.60),
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
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.85),
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
                  ).colorScheme.onSurface.withOpacity(.85),
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.05, end: 0),
      ],
    );
  }

  // ─── Change row ───────────────────────────────────────────

  Widget _buildChangeRow(double pct, double abs) {
    final pos = pct >= 0;
    final label = _periodLabels[_selectedPeriod];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _ChangeBadge(changePercent: pct),
        const SizedBox(width: 8),
        Text(
          '${pos ? '+' : ''}\$${abs.abs().toStringAsFixed(2)} $label',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
          ),
        ),
      ],
    ).animate().fadeIn(delay: 100.ms);
  }

  // ─── Reserve notice ───────────────────────────────────────

  void _openReserveInfo(BuildContext context) {
    showDayFiBottomSheet(context: context, child: _ReserveInfoSheet());
  }

  Widget _buildReserveNotice(BuildContext context) {
    return GestureDetector(
      onTap: () => _openReserveInfo(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/icons/svgs/alert2.svg',
              color: const Color.fromARGB(255, 232, 172, 9),
              height: 16,
            ),
            const SizedBox(width: 6),
            Text(
              'XLM reserve deducted from balance',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color.fromARGB(255, 232, 172, 9),
                fontSize: 13,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Period selector ──────────────────────────────────────

  Widget _buildPeriodSelector() {
    return Row(
      children: List.generate(_periods.length, (i) {
        final sel = i == _selectedPeriod;
        return InkWell(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          onTap: () => setState(() => _selectedPeriod = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: sel
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: sel
                    ? Colors.transparent
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.12),
              ),
            ),
            child: Text(
              _periods[i],
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: sel
                    ? Theme.of(context).scaffoldBackgroundColor
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w400,
                fontSize: 12,
              ),
            ),
          ),
        );
      }),
    );
  }

  // ─── Main chart ───────────────────────────────────────────

  Widget _buildChart(List<double> points) {
    final pos = _computeChange(points) >= 0;
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.06),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _SparklinePainter(
          points: points,
          color: pos ? DayFiColors.green : Colors.redAccent,
          fillColor: pos
              ? DayFiColors.green.withOpacity(0.06)
              : Colors.redAccent.withOpacity(0.06),
        ),
        child: const SizedBox.expand(),
      ),
    ).animate().fadeIn(delay: 200.ms);
  }

  // ─── Reserve card ─────────────────────────────────────────

  Widget _buildReserveCard(WalletState w) {
    const reserved = 2.0;
    final available = (w.xlmBalance - reserved).clamp(0, double.infinity);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reserve Information',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
              fontSize: 11,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Available to use',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.4),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${available.toStringAsFixed(4)} XLM',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: DayFiColors.green,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Reserved (minimum)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.4),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${reserved.toStringAsFixed(1)} XLM',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 250.ms);
  }

  // ─── Allocation section ───────────────────────────────────

  Widget _buildAllocationSection(double xlmUSD, double usdcUSD, double total) {
    final xlmPct = total > 0 ? xlmUSD / total : 0.5;
    final usdcPct = total > 0 ? usdcUSD / total : 0.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Allocation',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w500,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: CustomPaint(
                painter: _DonutPainter(
                  segments: [
                    _DonutSegment(
                      fraction: xlmPct,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.85),
                    ),
                    _DonutSegment(
                      fraction: usdcPct,
                      color: DayFiColors.green.withOpacity(0.7),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AllocationRow(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.85),
                    label: 'XLM',
                    pct: xlmPct,
                    value: xlmUSD,
                  ),
                  const SizedBox(height: 14),
                  _AllocationRow(
                    color: DayFiColors.green.withOpacity(0.7),
                    label: 'USDC',
                    pct: usdcPct,
                    value: usdcUSD,
                  ),
                  const SizedBox(height: 14),
                  // allocation bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Row(
                      children: [
                        Flexible(
                          flex: (xlmPct * 100).round(),
                          child: Container(
                            height: 4,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Flexible(
                          flex: (usdcPct * 100).round(),
                          child: Container(
                            height: 4,
                            color: DayFiColors.green.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(delay: 300.ms);
  }

  // ─── Assets section ───────────────────────────────────────

  Widget _buildAssetsSection(
    BuildContext context,
    _AssetDetail xlm,
    _AssetDetail usdc,
    WalletState w,
  ) {
    final assets = [xlm, usdc];
    final total = w.totalUSD - (2.0 * w.xlmPriceUSD);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w500,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 16),
        ...assets.asMap().entries.map((e) {
          final a = e.value;
          final alloc = total > 0 ? a.usdValue / total : 0.0;
          return _AssetCard(
                detail: a,
                allocPct: alloc,
                onTap: () => {_openAssetDetail(context, a)},
              )
              .animate()
              .fadeIn(delay: Duration(milliseconds: 350 + e.key * 80))
              .slideX(begin: 0.04, end: 0);
        }),
      ],
    );
  }
}

// ─── Asset card (tappable) ────────────────────────────────────────────────────

class _AssetCard extends StatelessWidget {
  final _AssetDetail detail;
  final double allocPct;
  final VoidCallback onTap;

  const _AssetCard({
    required this.detail,
    required this.allocPct,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pos = detail.changePercent >= 0;
    return InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      onTap: onTap,
      // onTap: () {},
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.1),
          borderRadius: BorderRadius.circular(18),
          // border: Border.all(
          //   color: Theme.of(context).colorScheme.onSurface.withOpacity(0.07),
          // ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                // icon
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Center(
                    child: Image.asset(detail.imagePath, width: 36, height: 36),
                  ),
                ),
                const SizedBox(width: 14),
                // name + balance
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.code,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.1,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.85),
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${detail.balance.toStringAsFixed(detail.code == 'USDC' ? 2 : 4)} ${detail.code}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.55),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // sparkline
                SizedBox(
                  width: 56,
                  height: 30,
                  child: CustomPaint(
                    painter: _SparklinePainter(
                      points: detail.points,
                      color: pos ? DayFiColors.green : Colors.redAccent,
                      fillColor: Colors.transparent,
                      strokeWidth: 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: 32),
                // value + change
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '\$${detail.usdValue.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.85),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),

                    Text(
                      '${pos ? '+' : ''}${detail.changePercent.toStringAsFixed(2)}%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: pos ? DayFiColors.green : Colors.redAccent,
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                // const SizedBox(width: 12),
                // Icon(
                //   Icons.chevron_right,
                //   size: 24,
                //   color: Theme.of(
                //     context,
                //   ).colorScheme.onSurface.withOpacity(0.25),
                // ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Asset detail bottom sheet ────────────────────────────────────────────────

class _AssetDetailSheet extends StatefulWidget {
  final _AssetDetail detail;
  const _AssetDetailSheet({required this.detail});

  @override
  State<_AssetDetailSheet> createState() => _AssetDetailSheetState();
}

class _AssetDetailSheetState extends State<_AssetDetailSheet> {
  int _period = 1;
  final _periodLabels = ['1D', '1W', '1M', 'ALL'];

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final pos = d.changePercent >= 0;
    final changeColor = pos ? DayFiColors.green : Colors.redAccent;
    final changeBg = pos
        ? DayFiColors.greenDim
        : Colors.redAccent.withOpacity(0.12);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Opacity(opacity: 0, child: Icon(Icons.close)),

              // const SizedBox(height: 4),
              Text(
                d.name,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.4),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close),
              ),
            ],
          ),

          // const SizedBox(height: 0),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(48),
                child: Image.asset(d.imagePath, width: 18, height: 18),
              ),
              const SizedBox(width: 8),
              Text(
                d.code,
                style: Theme.of(context).textTheme.titleLarge!.copyWith(
                  fontSize: 16,
                  letterSpacing: -.1,
                ),
              ),
            ],
          ),

          // const SizedBox(height: 32),

          // ─ Big amount
          // Text(
          //   '\$${d.usdValue.toStringAsFixed(2)}',
          //   style: Theme.of(context).textTheme.displayMedium?.copyWith(
          //     fontWeight: FontWeight.w400,
          //     letterSpacing: -2,
          //     height: 1,
          //   ),
          // ),
          // const SizedBox(height: 16),

          // _ChangeBadge(changePercent: d.changePercent),

          // const SizedBox(height: 16),

          // ─ Period selector
          // Row(
          //   children: List.generate(_periodLabels.length, (i) {
          //     final sel = i == _period;
          //     return InkWell(
          // splashColor: Colors.transparent,
          // highlightColor: Colors.transparent,
          // hoverColor: Colors.transparent,
          //       onTap: () => setState(() => _period = i),
          //       child: AnimatedContainer(
          //         duration: const Duration(milliseconds: 200),
          //         margin: const EdgeInsets.only(right: 8),
          //         padding: const EdgeInsets.symmetric(
          //           horizontal: 12,
          //           vertical: 5,
          //         ),
          //         decoration: BoxDecoration(
          //           color: sel
          //               ? Theme.of(context).colorScheme.onSurface
          //               : Colors.transparent,
          //           borderRadius: BorderRadius.circular(20),
          //           border: Border.all(
          //             color: sel
          //                 ? Colors.transparent
          //                 : Theme.of(
          //                     context,
          //                   ).colorScheme.onSurface.withOpacity(0.12),
          //           ),
          //         ),
          //         child: Text(
          //           _periodLabels[i],
          //           style: Theme.of(context).textTheme.bodySmall
          //               ?.copyWith(
          //                 color: sel
          //                     ? Theme.of(
          //                         context,
          //                       ).scaffoldBackgroundColor
          //                     : Theme.of(
          //                         context,
          //                       ).colorScheme.onSurface,
          //                 fontSize: 11,
          //               ),
          //         ),
          //       ),
          //     );
          //   }),
          // ),

          // const SizedBox(height: 14),

          // ─ Chart
          // Container(
          //   height: 110,
          //   decoration: BoxDecoration(
          //     color: Theme.of(context).colorScheme.surface,
          //     borderRadius: BorderRadius.circular(16),
          //     border: Border.all(
          //       color: Theme.of(
          //         context,
          //       ).colorScheme.onSurface.withOpacity(0.06),
          //     ),
          //   ),
          //   clipBehavior: Clip.antiAlias,
          //   child: CustomPaint(
          //     painter: _SparklinePainter(
          //       points: d.points,
          //       color: changeColor,
          //       fillColor: changeColor.withOpacity(0.07),
          //       showEndDot: true,
          //     ),
          //     child: const SizedBox.expand(),
          //   ),
          // ),
          const SizedBox(height: 20),

          // ─ Stats grid
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Balance',
                  value:
                      '${d.balance.toStringAsFixed(d.code == 'USDC' ? 2 : 4)} ${d.code}',
                  valueColor: Theme.of(
                    context,
                  ).textTheme.displayLarge?.color?.withOpacity(.85),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  label: '24h Change',
                  value:
                      '${pos ? '+' : ''}${d.changePercent.toStringAsFixed(2)}%',
                  valueColor: changeColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'USD Value',
                  value: '\$${d.usdValue.toStringAsFixed(2)}',
                  valueColor: Theme.of(
                    context,
                  ).textTheme.displayLarge?.color?.withOpacity(.85),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  label: 'Price',
                  value:
                      '\$${d.price.toStringAsFixed(d.code == 'USDC' ? 2 : 4)}',
                  valueColor: Theme.of(
                    context,
                  ).textTheme.displayLarge?.color?.withOpacity(.85),
                ),
              ),
            ],
          ),

          const SizedBox(height: 56),

          // ─ Action buttons
          Row(
            children: [
              _ActionButton(
                icon: "assets/icons/svgs/send.svg",
                label: 'Send',
                onPressed: () =>
                    context.push('/send', extra: {'asset': d.code}),
              ),
              const SizedBox(width: 10),
              _ActionButton(
                icon: "assets/icons/svgs/receive.svg",
                label: 'Receive',
                onPressed: () =>
                    context.push('/receive', extra: {'asset': d.code}),
              ),
              // const SizedBox(width: 10),
              // _ActionButton(
              //   icon: "assets/icons/svgs/swap.svg",
              //   label: 'Swap',
              //   onPressed: () => Navigator.pop(context),
              // ),
            ],
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ─── Stat card ────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StatCard({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return _CardContainer(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: valueColor,
              fontSize: 16,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── Info row ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;

  const _InfoRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.06),
                ),
              ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Allocation row ───────────────────────────────────────────────────────────

class _AllocationRow extends StatelessWidget {
  final Color color;
  final String label;
  final double pct, value;

  const _AllocationRow({
    required this.color,
    required this.label,
    required this.pct,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w400),
          ),
        ),
        Text(
          '${(pct * 100).toStringAsFixed(1)}%',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            fontSize: 11,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '\$${value.toStringAsFixed(2)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

// ─── Card container (reusable) ────────────────────────────────────────────────

class _CardContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const _CardContainer({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        // border: Border.all(
        //   color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
        // ),
      ),
      child: child,
    );
  }
}

// ─── Change badge (reusable) ──────────────────────────────────────────────────

class _ChangeBadge extends StatelessWidget {
  final double changePercent;

  const _ChangeBadge({required this.changePercent});

  @override
  Widget build(BuildContext context) {
    final pos = changePercent >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: pos ? DayFiColors.greenDim : Colors.red.withOpacity(0.12),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        '${pos ? '+' : ''}${changePercent.toStringAsFixed(2)}%',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: pos ? DayFiColors.green : Colors.redAccent,
          fontWeight: FontWeight.w500,
          fontSize: 11,
        ),
      ),
    );
  }
}

// ─── Action button (reusable) ─────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final String icon;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 50),
          side: BorderSide(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.85),
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SvgPicture.asset(
              icon,
              height: 20,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(.60),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withOpacity(0.85),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Reserve info bottom sheet ────────────────────────────────────────────────

class _ReserveInfoSheet extends StatelessWidget {
  const _ReserveInfoSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 24),
              Text(
                '',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 16,
                  letterSpacing: -0.1,
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, size: 24),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Warning icon
          SvgPicture.asset(
            'assets/icons/svgs/alert2.svg',
            color: const Color.fromARGB(255, 232, 172, 9),
            height: 56,
          ),
          const SizedBox(height: 24),

          // Description
          Text(
            'Stellar requires a 2 XLM minimum balance to maintain your account. This amount is locked and cannot be spent. Your available XLM balance excludes this 2 XLM reserve to ensure your account stays active.',

            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              height: 1.5,
            ),
          ),

          const SizedBox(height: 32),

          // Learn more button

          // Buttons
          Column(
            children: [
              // Create wallet
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(MediaQuery.of(context).size.width, 48),
                  side: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(.90),
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  final url = Uri.parse(
                    'https://stellar.org/learn/intro-to-stellar',
                  );
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                icon: Icon(
                  Icons.open_in_new,
                  size: 20,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(.90),
                ),
                label: Text(
                  'Learn More',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(.95),
                    fontSize: 15,
                  ),
                ),
              ).animate().fadeIn(delay: 500.ms),

              const SizedBox(height: 8),

              // Create wallet
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  side: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0),
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(context),

                label: Center(
                  child: Text(
                    'Cancel',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(.95),
                      fontSize: 15,
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 500.ms),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Sparkline painter ────────────────────────────────────────────────────────

class _SparklinePainter extends CustomPainter {
  final List<double> points;
  final Color color, fillColor;
  final double strokeWidth;
  final bool showEndDot;

  const _SparklinePainter({
    required this.points,
    required this.color,
    required this.fillColor,
    this.strokeWidth = 1.8,
    this.showEndDot = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final min = points.reduce((a, b) => a < b ? a : b);
    final max = points.reduce((a, b) => a > b ? a : b);
    final range = (max - min).clamp(0.001, double.infinity);
    final xStep = size.width / (points.length - 1);

    Offset pt(int i) => Offset(
      i * xStep,
      size.height -
          ((points[i] - min) / range) * size.height * 0.82 -
          size.height * 0.09,
    );

    // fill
    final fill = Path()..moveTo(0, size.height);
    for (int i = 0; i < points.length; i++) fill.lineTo(pt(i).dx, pt(i).dy);
    fill
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill,
    );

    // line
    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (int i = 1; i < points.length; i++) {
      final p = pt(i - 1), c = pt(i);
      final cx = (p.dx + c.dx) / 2;
      line.cubicTo(cx, p.dy, cx, c.dy, c.dx, c.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // end dot
    if (showEndDot && points.isNotEmpty) {
      final last = pt(points.length - 1);
      canvas.drawCircle(last, 4, Paint()..color = color);
      canvas.drawCircle(
        last,
        4,
        Paint()
          ..color = color.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter o) =>
      o.points != points || o.color != color;
}

// ─── Donut painter ────────────────────────────────────────────────────────────

class _DonutSegment {
  final double fraction;
  final Color color;
  const _DonutSegment({required this.fraction, required this.color});
}

class _DonutPainter extends CustomPainter {
  final List<_DonutSegment> segments;
  const _DonutPainter({required this.segments});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const sw = 11.0, gap = 0.04;
    final total = segments.fold<double>(0, (s, e) => s + e.fraction);
    double start = -3.14159 / 2;

    for (final seg in segments) {
      final sweep = (seg.fraction / total) * (2 * 3.14159) - gap;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - sw / 2),
        start,
        sweep,
        false,
        Paint()
          ..color = seg.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw
          ..strokeCap = StrokeCap.round,
      );
      start += sweep + gap;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter o) => o.segments != segments;
}
