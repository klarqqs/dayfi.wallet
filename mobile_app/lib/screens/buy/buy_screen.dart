// lib/screens/buy/buy_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../models/asset.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

class BuyScreen extends StatefulWidget {
  const BuyScreen({super.key});

  @override
  State<BuyScreen> createState() => _BuyScreenState();
}

class _BuyScreenState extends State<BuyScreen> {
  String _selectedAsset = 'USDC';
  final _amountController = TextEditingController();

  bool _loadingQuote = false;
  bool _loadingDeposit = false;
  Map<String, dynamic>? _quote;
  String? _quoteError;
  String? _stellarAddress;

  @override
  void initState() {
    super.initState();
    _loadAddress();
  }

  Future<void> _loadAddress() async {
    try {
      final data = await apiService.getAddress();
      setState(() => _stellarAddress = data['stellarAddress']);
    } catch (_) {}
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _getQuote(String amountStr) async {
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      setState(() {
        _quote = null;
        _quoteError = null;
      });
      return;
    }

    setState(() {
      _loadingQuote = true;
      _quoteError = null;
      _quote = null;
    });

    try {
      // Use Stellar DEX path payment quote — same as swap screen
      final result = await apiService.getSwapQuote(
        fromAsset: 'USDC', // user pays in USDC
        toAsset: _selectedAsset, // user receives selected asset
        amount: amount,
      );
      if (mounted) setState(() => _quote = result);
    } catch (e) {
      if (mounted) setState(() => _quoteError = apiService.parseError(e));
    } finally {
      if (mounted) setState(() => _loadingQuote = false);
    }
  }

  String _getUsdcIssuer() =>
      'GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5'; // testnet

  Future<void> _proceedToBuy() async {
    if (_stellarAddress == null) return;
    final amount = double.tryParse(_amountController.text.trim());

    setState(() => _loadingDeposit = true);
    try {
      final result = await apiService.initiateDeposit(
        assetCode: _selectedAsset,
        account: _stellarAddress!,
        amount: amount,
      );

      final url = result['url'] as String?;
      final txId = result['id'] as String?;

      if (url != null && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Sep24WebView(
              url: url,
              title: 'Buy $_selectedAsset',
              transactionId: txId,
              onComplete: (success) {
                if (success && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Deposit initiated! Funds will arrive shortly.',
                      ),
                      backgroundColor: DayFiColors.green,
                    ),
                  );
                  context.go('/home');
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(apiService.parseError(e)),
            backgroundColor: DayFiColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingDeposit = false);
    }
  }

  // Friendly description per asset — no longer from model
  String _assetDescription(String code) {
    switch (code) {
      case 'USDC':
        return 'US Dollar · Circle · Stellar';
      case 'EURC':
        return 'Euro · Circle · Stellar';
      case 'GOLD':
        return 'Gold-backed · 1 token = 1 troy oz';
      default:
        return code;
    }
  }

  // Accent color per asset — no longer from model
  Color _assetColor(String code) {
    switch (code) {
      case 'USDC':
        return Colors.blue;
      case 'EURC':
        return Colors.indigo;
      case 'GOLD':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = kAssets[_selectedAsset]!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buy'),
        leading: InkWell(
  splashColor: Colors.transparent,
  highlightColor: Colors.transparent,
  hoverColor: Colors.transparent,
          onTap: () => context.pop(),
          child: const Icon(Icons.arrow_back_ios, size: 20),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),

              // ── Asset selector ──────────────────────────
              Text(
                'Select asset to buy',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),

              ...kAssetList.map((code) {
                final a = kAssets[code]!;
                final selected = _selectedAsset == code;
                final color = _assetColor(code);
                final desc = _assetDescription(code);

                return InkWell(
  splashColor: Colors.transparent,
  highlightColor: Colors.transparent,
  hoverColor: Colors.transparent,
                  onTap: () => setState(() {
                    _selectedAsset = code;
                    _quote = null;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: selected
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.05)
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.08),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              a.emoji,
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    a.code,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  if (a.regulated) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: DayFiColors.greenDim,
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Text(
                                        'KYC Required',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: DayFiColors.green,
                                              fontSize: 9,
                                            ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              Text(
                                desc,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (selected)
                          const Icon(
                            Icons.check_circle,
                            color: DayFiColors.green,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 24),

              // ── Amount ──────────────────────────────────
              Text(
                'Amount (USD)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (v) {
                  if (v.length > 1) _getQuote(v);
                },
                decoration: const InputDecoration(
                  hintText: '0.00',
                  prefixText: '\$ ',
                  suffixText: 'USD',
                ),
              ).animate().fadeIn(delay: 100.ms),

              const SizedBox(height: 16),

              // ── Quote card ──────────────────────────────
              if (_loadingQuote)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_quote != null)
                _QuoteCard(quote: _quote!, asset: asset).animate().fadeIn()
              else if (_quoteError != null)
                Text(
                  _quoteError!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: DayFiColors.red),
                ),

              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _loadingDeposit ? null : _proceedToBuy,
                child: _loadingDeposit
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : Text('Buy ${asset.code}'),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Powered by SEP-24 · Secured on Stellar',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sell Screen ──────────────────────────────────────────

class SellScreen extends StatefulWidget {
  const SellScreen({super.key});

  @override
  State<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends State<SellScreen> {
  String _selectedAsset = 'USDC';
  final _amountController = TextEditingController();
  bool _loadingWithdraw = false;
  String? _stellarAddress;

  @override
  void initState() {
    super.initState();
    _loadAddress();
  }

  Future<void> _loadAddress() async {
    try {
      final data = await apiService.getAddress();
      setState(() => _stellarAddress = data['stellarAddress']);
    } catch (_) {}
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _proceedToSell() async {
    if (_stellarAddress == null) return;
    final amount = double.tryParse(_amountController.text.trim());

    setState(() => _loadingWithdraw = true);
    try {
      final result = await apiService.initiateWithdraw(
        assetCode: _selectedAsset,
        account: _stellarAddress!,
        amount: amount,
      );
      final url = result['url'] as String?;
      if (url != null && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Sep24WebView(
              url: url,
              title: 'Sell $_selectedAsset',
              transactionId: result['id'],
              onComplete: (success) {
                if (success && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Withdrawal initiated!'),
                      backgroundColor: DayFiColors.green,
                    ),
                  );
                  context.go('/home');
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(apiService.parseError(e)),
            backgroundColor: DayFiColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingWithdraw = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sell'),
        leading: InkWell(
  splashColor: Colors.transparent,
  highlightColor: Colors.transparent,
  hoverColor: Colors.transparent,
          onTap: () => context.pop(),
          child: const Icon(Icons.arrow_back_ios, size: 20),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text(
                'Select asset to sell',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kAssetList.map((code) {
                  final a = kAssets[code]!;
                  final selected = _selectedAsset == code;
                  return InkWell(
  splashColor: Colors.transparent,
  highlightColor: Colors.transparent,
  hoverColor: Colors.transparent,
                    onTap: () => setState(() => _selectedAsset = code),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.15),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(a.emoji, style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Text(
                            code,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: selected
                                      ? Theme.of(context).colorScheme.background
                                      : null,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ).animate().fadeIn(),

              const SizedBox(height: 28),
              Text('Amount', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  hintText: '0.00',
                  suffixText: _selectedAsset,
                ),
              ).animate().fadeIn(delay: 100.ms),

              const Spacer(),

              ElevatedButton(
                onPressed: _loadingWithdraw ? null : _proceedToSell,
                style: ElevatedButton.styleFrom(
                  backgroundColor: DayFiColors.red,
                  foregroundColor: Colors.white,
                ),
                child: _loadingWithdraw
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text('Sell $_selectedAsset'),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Quote Card ───────────────────────────────────────────

class _QuoteCard extends StatelessWidget {
  final Map<String, dynamic> quote;
  final DayFiAsset asset;
  const _QuoteCard({required this.quote, required this.asset});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
        ),
      ),
      child: Column(
        children: [
          _QuoteRow(
            label: 'You receive',
            value: '${quote['buy_amount']} ${asset.code}',
          ),
          const SizedBox(height: 8),
          _QuoteRow(
            label: 'Rate',
            value: '1 USDC = ${quote['price']} ${asset.code}',
          ),
          const SizedBox(height: 8),
          _QuoteRow(label: 'Network', value: 'Stellar DEX'),
          const Divider(height: 20),
          _QuoteRow(
            label: 'You pay',
            value: '\$${quote['fromAmount']} USDC',
            bold: true,
          ),
          const SizedBox(height: 4),
          Text(
            'Est. ~5 seconds · Very low fees',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _QuoteRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _QuoteRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: bold ? FontWeight.w400 : FontWeight.w400,
            color: bold ? Theme.of(context).colorScheme.onSurface : null,
          ),
        ),
      ],
    );
  }
}

// ─── SEP-24 WebView ───────────────────────────────────────

class Sep24WebView extends StatefulWidget {
  final String url;
  final String title;
  final String? transactionId;
  final void Function(bool success) onComplete;

  const Sep24WebView({
    super.key,
    required this.url,
    required this.title,
    this.transactionId,
    required this.onComplete,
  });

  @override
  State<Sep24WebView> createState() => _Sep24WebViewState();
}

class _Sep24WebViewState extends State<Sep24WebView> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
          onNavigationRequest: (req) {
            if (req.url.contains('transaction_id') &&
                (req.url.contains('success') || req.url.contains('complete'))) {
              widget.onComplete(true);
              Navigator.pop(context);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: InkWell(
  splashColor: Colors.transparent,
  highlightColor: Colors.transparent,
  hoverColor: Colors.transparent,
          onTap: () {
            widget.onComplete(false);
            Navigator.pop(context);
          },
          child: const Icon(Icons.close),
        ),
        actions: [
          if (widget.transactionId != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  'ID: ${widget.transactionId!.substring(0, 8)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
