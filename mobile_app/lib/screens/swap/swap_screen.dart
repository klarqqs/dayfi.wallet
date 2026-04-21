// lib/screens/swap/swap_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:mobile_app/widgets/app_bottomsheet.dart';
import '../../models/asset.dart';
import '../../providers/wallet_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_background.dart';
import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SwapScreen extends ConsumerStatefulWidget {
  const SwapScreen({super.key});

  @override
  ConsumerState<SwapScreen> createState() => _SwapScreenState();
}

class _SwapScreenState extends ConsumerState<SwapScreen> {
  String _fromAsset = 'XLM';
  String _toAsset = 'USDC';

  final _fromAmountController = TextEditingController();
  final _toAmountController = TextEditingController();

  Map<String, dynamic>? _quote;
  bool _loadingQuote = false;
  bool _executing = false;
  String? _quoteError;
  Timer? _debounce;
  String _lastModifiedField = 'from';

  @override
  void dispose() {
    _fromAmountController.dispose();
    _toAmountController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ─── Balance helpers ──────────────────────────────────────

  double _balanceFor(String asset) {
    final w = ref.read(walletProvider);
    switch (asset) {
      case 'USDC':
        return w.usdcBalance;
      case 'XLM':
        return w.xlmBalance;
      default:
        return 0;
    }
  }

  // XLM: reserve 2.0 for multi-hop swaps (0.5 base + 0.5 USDC trustline + 0.5-1.0 for path intermediates)
  // USDC: no reserve needed
  // Fee: negligible (~0.00001 XLM per operation)
  double _availableFor(String asset) {
    final balance = _balanceFor(asset);
    if (asset == 'XLM') {
      // Reserve 2.0 XLM minimum to handle multi-hop swap paths with intermediate assets
      return (balance - 2.0).clamp(0, double.infinity);
    }
    // USDC: can use full balance (fee is paid in XLM)
    return balance;
  }

  // Estimate swap fee in XLM (Stellar base fee is ~1 stroop = 0.00001 XLM)
  double _estimatedFeeXLM() => 0.00001;

  bool get _hasInsufficientBalance {
    final amount = double.tryParse(_fromAmountController.text.trim()) ?? 0;
    return amount > 0 && amount > _availableFor(_fromAsset);
  }

  // ─── Quote ────────────────────────────────────────────────

  void _onAmountChanged(String val, {String field = 'from'}) {
    _debounce?.cancel();
    setState(() {
      _lastModifiedField = field;
      _quote = null;
      _quoteError = null;
    });
    if (val.isEmpty || double.tryParse(val) == null) return;
    _debounce = Timer(const Duration(milliseconds: 800), _fetchQuote);
  }

  Future<void> _fetchQuote() async {
    final fromAmount = double.tryParse(_fromAmountController.text.trim());
    final toAmount = double.tryParse(_toAmountController.text.trim());

    if (_fromAsset == _toAsset) {
      setState(() => _quoteError = 'Choose two different assets');
      return;
    }

    // FORWARD: User entered in "You Pay" field
    if (_lastModifiedField == 'from') {
      final amount = fromAmount;
      if (amount == null || amount <= 0) return;

      // Balance check before hitting API
      if (amount > _availableFor(_fromAsset)) {
        setState(
          () => _quoteError =
              'Insufficient balance. Available: ${_availableFor(_fromAsset).toStringAsFixed(6)} $_fromAsset',
        );
        return;
      }

      setState(() {
        _loadingQuote = true;
        _quoteError = null;
      });
      try {
        final result = await apiService.getSwapQuote(
          fromAsset: _fromAsset,
          toAsset: _toAsset,
          amount: amount,
        );
        if (mounted) {
          setState(() => _quote = result);
          // Update the "to" amount based on quote
          if (_quote != null) {
            final calculatedToAmount =
                _quote!['buy_amount'] ?? _quote!['toAmount'];
            if (calculatedToAmount != null) {
              _toAmountController.text = calculatedToAmount.toString();
            }
          }
        }
      } catch (e, stack) {
        final errorMsg = apiService.parseError(e);
        developer.log(
          'Quote fetch failed',
          error: e,
          stackTrace: stack,
          name: 'SwapScreen.fetchQuote',
        );
        if (mounted)
          setState(
            () => _quoteError = errorMsg.isEmpty
                ? 'Failed to fetch quote'
                : errorMsg,
          );
      } finally {
        if (mounted) setState(() => _loadingQuote = false);
      }
      return;
    }

    // REVERSE: User entered in "You Receive" field
    if (_lastModifiedField == 'to') {
      final amount = toAmount;
      if (amount == null || amount <= 0) return;

      setState(() {
        _loadingQuote = true;
        _quoteError = null;
      });
      try {
        // Get quote for a small test amount to calculate the rate, then reverse it
        // Or call API with the toAmount to get the required fromAmount
        final result = await apiService.getSwapQuote(
          fromAsset: _fromAsset,
          toAsset: _toAsset,
          amount: amount,
        );

        if (mounted) {
          // Extract rate from quote to calculate required from amount
          final rate =
              double.tryParse(
                result['price']?.toString() ??
                    result['rate']?.toString() ??
                    '0',
              ) ??
              1.0;

          if (rate > 0) {
            // Reverse calculate: toAmount / rate = required fromAmount
            final requiredFromAmount = amount / rate;

            // Check if user has sufficient balance in "You Pay" currency
            final available = _availableFor(_fromAsset);
            if (requiredFromAmount > available) {
              setState(() {
                _quoteError =
                    'Insufficient balance. Need ${requiredFromAmount.toStringAsFixed(6)} $_fromAsset, '
                    'but only have ${available.toStringAsFixed(6)} available';
                _quote = null;
              });
            } else {
              // Update "You Pay" field with calculated amount
              _fromAmountController.text = requiredFromAmount.toStringAsFixed(
                _fromAsset == 'XLM' ? 4 : 2,
              );
              setState(() {
                _quote = result;
                _quoteError = null;
              });
            }
          } else {
            setState(() => _quoteError = 'Could not calculate swap rate');
          }
        }
      } catch (e, stack) {
        final errorMsg = apiService.parseError(e);
        developer.log(
          'Quote fetch failed',
          error: e,
          stackTrace: stack,
          name: 'SwapScreen.fetchQuote',
        );
        if (mounted)
          setState(
            () => _quoteError = errorMsg.isEmpty
                ? 'Failed to fetch quote'
                : errorMsg,
          );
      } finally {
        if (mounted) setState(() => _loadingQuote = false);
      }
    }
  }

  Future<void> _executeSwap() async {
    final amount = double.tryParse(_fromAmountController.text.trim());
    if (amount == null || _quote == null) return;

    // Final balance guard
    if (amount > _availableFor(_fromAsset)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Insufficient $_fromAsset balance. '
            'Available: ${_availableFor(_fromAsset).toStringAsFixed(6)}',
          ),
          backgroundColor: DayFiColors.red,
        ),
      );
      return;
    }

    setState(() => _executing = true);

    // Show loading dialog that persists
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  height: 40,
                  width: 40,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(height: 16),
                Text(
                  'Processing swap...',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'This may take a few seconds',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final result = await apiService.executeSwap(
        fromAsset: _fromAsset,
        toAsset: _toAsset,
        amount: amount,
      );

      // Wait for Stellar to fully settle (3 retries, 1 sec each)
      bool confirmed = false;
      for (int i = 0; i < 3; i++) {
        await Future.delayed(const Duration(seconds: 1));
        try {
          await ref.read(walletProvider.notifier).refresh();
          confirmed = true;
          break;
        } catch (_) {
          // Keep retrying
        }
      }

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        _showSwapSuccess(result, confirmed);
      }
    } catch (e, stack) {
      final errorMsg = apiService.parseError(e);
      developer.log(
        'Swap execution failed',
        error: e,
        stackTrace: stack,
        name: 'SwapScreen.executeSwap',
      );

      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        // Determine user-friendly message
        String displayMsg = errorMsg;
        if (displayMsg.isEmpty || displayMsg.contains('DioException')) {
          displayMsg = 'Swap failed - please check your balance and try again';
        } else if (displayMsg.contains('Insufficient')) {
          displayMsg = 'Not enough XLM available. Need 2.0 XLM reserved.';
        } else if (displayMsg.contains('Server processing')) {
          displayMsg = 'Server processing error - please try again in a moment';
        }

        // Show error with snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(displayMsg),
            backgroundColor: DayFiColors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _executeSwap,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _executing = false);
    }
  }

  void _flip() {
    setState(() {
      final tmp = _fromAsset;
      _fromAsset = _toAsset;
      _toAsset = tmp;
      _quote = null;
      _quoteError = null;
      // Swap the amounts
      final tmpAmount = _fromAmountController.text;
      _fromAmountController.text = _toAmountController.text;
      _toAmountController.text = tmpAmount;
    });
    if (_fromAmountController.text.isNotEmpty) _fetchQuote();
  }

  void _showSwapSuccess(Map<String, dynamic> result, bool confirmed) {
    showDayFiBottomSheet(
      context: context,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),

            // ── Lottie success ──────────────────────────────
            Lottie.asset(
              'assets/animations/success.json',
              width: 120,
              height: 120,
              repeat: false,
            ),

            const SizedBox(height: 4),

            Text(
              'Swap Complete!',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 10),

            Text(
              '${_fromAmountController.text} $_fromAsset → $_toAsset',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 17,
                letterSpacing: -.5,
                height: 1.3,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),

            // Confirmed / Processing badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (confirmed
                    ? DayFiColors.greenDim
                    : DayFiColors.textMuted.withOpacity(0.15)),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: confirmed
                      ? DayFiColors.green.withOpacity(0.25)
                      : DayFiColors.textMuted.withOpacity(0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    confirmed
                        ? Icons.check_circle_outline_rounded
                        : Icons.access_time_rounded,
                    size: 12,
                    color: confirmed
                        ? DayFiColors.green
                        : DayFiColors.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Stellar DEX · ${confirmed ? 'Confirmed' : 'Processing'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: confirmed
                          ? DayFiColors.green
                          : DayFiColors.textSecondary,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),

            if (result['transaction']?['hash'] != null) ...[
              const SizedBox(height: 10),
              Text(
                'Tx: ${(result['transaction']['hash'] as String).substring(0, 12)}...',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(letterSpacing: 0.2),
              ),
            ],

            const SizedBox(height: 32),

            // ── Done button ─────────────────────────────────
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: Size(MediaQuery.of(context).size.width, 50),
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
              onPressed: () {
                Navigator.pop(context);
                context.go('/home');
              },
              child: Text(
                'Done',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(.95),
                  fontSize: 15,
                ),
              ),
            ).animate().fadeIn(delay: 500.ms),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(walletProvider);
    final fromAsset = kAssets[_fromAsset]!;
    final toAsset = kAssets[_toAsset]!;
    final available = _availableFor(_fromAsset);
    final totalUSD = walletState.totalUSD;

    // Disable if wallet hasn't loaded or total is 0
    final walletEmpty = !walletState.isLoading && totalUSD <= 0;

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(
            '',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).textTheme.bodyLarge?.color!.withOpacity(.95),
              fontWeight: FontWeight.w500,
              fontSize: 16,
              letterSpacing: -0.1,
            ),
          ),
          leading: GestureDetector(
            onTap: () => context.pop(),
            child: const Icon(Icons.arrow_back_ios, size: 20),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    'Swap Assets',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Instant swaps via Stellar DEX.\nSettled in seconds.',
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      fontSize: 14,
                      letterSpacing: -.1,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 100.ms),
                ),
                const SizedBox(height: 24),

                // Empty wallet warning
                if (walletEmpty)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        "assets/icons/svgs/alert2.svg",
                        color: const Color.fromARGB(255, 232, 172, 9),
                        height: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Your wallet has no funds to swap.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color.fromARGB(255, 232, 172, 9),
                          fontSize: 14,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ).animate().fadeIn(),
                // FROM label
                Text('You Pay', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),

                // FROM card
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 0,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).textTheme.bodySmall?.color?.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    // border: Border.all(
                    //   color: Theme.of(
                    //     context,
                    //   ).colorScheme.onSurface.withOpacity(0.2),
                    // ),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _showAssetPicker(isFrom: true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(.05),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(77),
                                child: Image.asset(fromAsset.emoji, height: 24),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _fromAsset,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontSize: 14,
                                      letterSpacing: -.1,
                                    ),
                              ),
                              Icon(
                                Icons.keyboard_arrow_down,
                                size: 18,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.4),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _fromAmountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (val) =>
                              _onAmountChanged(val, field: 'from'),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(.85),
                                fontSize: 18,
                                letterSpacing: -.1,
                                fontWeight: FontWeight.w500,
                              ),
                          decoration: InputDecoration(
                            hintText: '0.00',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 24,
                              horizontal: 6,
                            ),
                            fillColor: Colors.transparent,

                            hintStyle: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(.35),
                                  fontSize: 18,
                                  letterSpacing: -.1,
                                ),
                          ),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 150.ms),

                // Available balance hint
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: GestureDetector(
                    onTap: _executing
                        ? null
                        : () {
                            final toUse = available - _estimatedFeeXLM();
                            _fromAmountController.text = toUse.toStringAsFixed(
                              _fromAsset == 'XLM' ? 4 : 2,
                            );
                            _onAmountChanged(
                              _fromAmountController.text,
                              field: 'from',
                            );
                          },
                    child: Text(
                      'Available: ${available.toStringAsFixed(_fromAsset == 'XLM' ? 4 : 2)} $_fromAsset',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _executing
                            ? DayFiColors.red
                            : _hasInsufficientBalance
                            ? DayFiColors.red
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.4),
                        fontWeight: _executing
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Flip button
                Center(
                  child: GestureDetector(
                    onTap: _flip,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.1),
                        ),
                      ),
                      child: Icon(
                        Icons.swap_vert,
                        size: 18,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // TO label
                Text(
                  'You Receive',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),

                // TO card
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 0,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).textTheme.bodySmall?.color?.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    // border: Border.all(
                    //   color: Theme.of(
                    //     context,
                    //   ).colorScheme.onSurface.withOpacity(0.2),
                    // ),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _showAssetPicker(isFrom: false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(.05),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(77),
                                child: Image.asset(toAsset.emoji, height: 24),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _toAsset,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontSize: 14,
                                      letterSpacing: -.1,
                                    ),
                              ),
                              Icon(
                                Icons.keyboard_arrow_down,
                                size: 18,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.4),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _toAmountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (val) =>
                              _onAmountChanged(val, field: 'to'),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(.85),
                                fontSize: 18,
                                letterSpacing: -.1,
                                fontWeight: FontWeight.w500,
                              ),
                          decoration: InputDecoration(
                            hintText: _loadingQuote ? '...' : '0.00',

                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 24,
                              horizontal: 6,
                            ),
                            fillColor: Colors.transparent,
                            hintStyle: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(.35),
                                  fontSize: 18,
                                  letterSpacing: -.1,
                                ),

                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 200.ms),

                const SizedBox(height: 20),

                //   // Error messages
                //  if (_quoteError != null)
                //     Container(
                //       width: double.infinity,
                //       padding: const EdgeInsets.all(12),
                //       margin: const EdgeInsets.only(bottom: 16),
                //       decoration: BoxDecoration(
                //         color: DayFiColors.redDim,
                //         borderRadius: BorderRadius.circular(12),
                //       ),
                //       child: Text(
                //         _quoteError!,
                //         style: Theme.of(
                //           context,
                //         ).textTheme.bodySmall?.copyWith(color: DayFiColors.red),
                //       ),
                //     ).animate().fadeIn(),

                //   // Quote details
                //   if (_quote != null && !_hasInsufficientBalance) ...[
                //     const SizedBox(height: 8),
                //     _QuoteDetails(
                //       quote: _quote!,
                //       fromAsset: _fromAsset,
                //       toAsset: _toAsset,
                //     ).animate().fadeIn(),
                //     const SizedBox(height: 20),
                //   ],

                // Swap button
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    side: BorderSide(
                      color:
                          (_quote == null ||
                              _executing ||
                              _hasInsufficientBalance ||
                              walletEmpty)
                          ? Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(.45)
                          : Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(.90),
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed:
                      (_quote == null ||
                          _executing ||
                          _hasInsufficientBalance ||
                          walletEmpty)
                      ? null
                      : _executeSwap,

                  label: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        _quote != null
                            ? 'Swap $_fromAsset → $_toAsset'
                            : 'Enter amount to get quote',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              (_quote == null ||
                                  _executing ||
                                  _hasInsufficientBalance ||
                                  walletEmpty)
                              ? Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(.45)
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(.90),
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _getEmojiHeight(String? emoji) {
    return emoji == 'assets/images/stellar.png' ? 38 : 40;
  }

  void _showAssetPicker({required bool isFrom}) {
    final excluded = isFrom ? _toAsset : _fromAsset;
    showDayFiBottomSheet(
      context: context,
      // backgroundColor: Theme.of(context).colorScheme.surface,
      // shape: const RoundedRectangleBorder(
      //   borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      // ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Opacity(opacity: 0, child: Icon(Icons.close)),

                Text(
                  'Select Asset',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 32),
            ...kAssetList.map((code) {
              final a = kAssets[code]!;
              final isDisabled = code == excluded;
              final isSelected = code == (isFrom ? _fromAsset : _toAsset);
              final bal = _availableFor(code);
              return GestureDetector(
                onTap: isDisabled
                    ? null
                    : () {
                        Navigator.pop(context);
                        setState(() {
                          if (isFrom)
                            _fromAsset = code;
                          else
                            _toAsset = code;
                          _quote = null;
                        });
                        if (_fromAmountController.text.isNotEmpty)
                          _fetchQuote();
                      },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    // border: Border.all(
                    //   color: isSelected
                    //       ? Theme.of(ctx).colorScheme.primary.withOpacity(0.3)
                    //       : Theme.of(
                    //           ctx,
                    //         ).colorScheme.onSurface.withOpacity(0.1),
                    // ),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(54),
                        child: Image.asset(
                          a.emoji,
                          height: _getEmojiHeight(a.emoji),
                        ),
                      ),
                      const SizedBox(width: 14),

                      Text(
                        a.code,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: isDisabled
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.3)
                                  : null,
                            ),
                      ),

                      const Spacer(),

                      if (isDisabled && !isSelected)
                        Text(
                          'In use ',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.3),
                              ),
                        ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─── Quote Details ────────────────────────────────────────

class _QuoteDetails extends StatelessWidget {
  final Map<String, dynamic> quote;
  final String fromAsset;
  final String toAsset;

  const _QuoteDetails({
    required this.quote,
    required this.fromAsset,
    required this.toAsset,
  });

  @override
  Widget build(BuildContext context) {
    final price =
        quote['price']?.toString() ?? quote['rate']?.toString() ?? '—';

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
        children: [
          _Row(label: 'Network', value: 'Stellar DEX'),
          _Row(label: 'Rate', value: '1 $fromAsset = $price $toAsset'),
          _Row(label: 'Est. Time', value: '~5 seconds'),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
