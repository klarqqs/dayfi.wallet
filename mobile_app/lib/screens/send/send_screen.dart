// lib/screens/send/send_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:mobile_app/widgets/app_bottomsheet.dart';
import '../../models/asset.dart';
import '../../providers/wallet_provider.dart';
import '../../services/api_service.dart';
import '../../services/payments_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_background.dart';

class SendScreen extends ConsumerStatefulWidget {
  final String? initialAsset;
  const SendScreen({super.key, this.initialAsset});

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  // ─── Crypto send state ────────────────────────────────────
  final _toController = TextEditingController();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();

  String _selectedAsset = 'USDC';
  bool _loading = false;
  bool _resolving = false;
  bool _invalidAmount = false;
  String? _amountError;
  Map<String, dynamic>? _resolvedRecipient;
  String? _recipientError;

  // ─── Sub-tab (NGNT only) ──────────────────────────────────
  int _sendTab = 0; // 0 = crypto, 1 = bank withdrawal

  // ─── Bank withdrawal state ────────────────────────────────
  final _accountNumberCtrl = TextEditingController();
  final _bankAmountCtrl = TextEditingController();
  List<Map<String, dynamic>> _banks = [];
  Map<String, dynamic>? _selectedBank;
  String? _resolvedAccountName;
  bool _resolvingAccount = false;
  String? _accountResolveError;
  bool _banksLoaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialAsset != null) _selectedAsset = widget.initialAsset!;
    _amountController.addListener(_validateAmount);
    _toController.addListener(() => setState(() {}));
    _bankAmountCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _toController.dispose();
    _amountController.dispose();
    _memoController.dispose();
    _accountNumberCtrl.dispose();
    _bankAmountCtrl.dispose();
    super.dispose();
  }

  // ─── Validation ───────────────────────────────────────────

  void _validateAmount() {
    final amount = double.tryParse(_amountController.text.trim());
    final available = _availableBalance(_selectedAsset);
    setState(() {
      if (amount == null) {
        _invalidAmount = false;
        _amountError = null;
      } else if (amount <= 0) {
        _invalidAmount = true;
        _amountError = 'Amount must be greater than 0';
      } else if (amount > available) {
        _invalidAmount = true;
        _amountError =
            'Insufficient balance. Available: '
            '${available.toStringAsFixed(_selectedAsset == 'XLM' ? 4 : 2)} $_selectedAsset';
      } else {
        _invalidAmount = false;
        _amountError = null;
      }
    });
  }

  double _availableBalance(String asset) {
    final wallet = ref.read(walletProvider);
    if (asset == 'XLM') {
      return (wallet.xlmBalance - 2.0).clamp(0, double.infinity);
    }
    if (asset == 'NGNT') return wallet.ngntBalance;
    return wallet.usdcBalance;
  }

  // ─── Crypto recipient resolution ──────────────────────────

  Future<void> _resolveRecipient(String value) async {
    if (value.length < 3) {
      setState(() {
        _resolvedRecipient = null;
        _recipientError = null;
      });
      return;
    }
    setState(() {
      _resolving = true;
      _recipientError = null;
      _resolvedRecipient = null;
    });
    try {
      final result = await ref
          .read(walletProvider.notifier)
          .resolveRecipient(value);
      if (mounted) {
        if (result != null) {
          setState(() => _resolvedRecipient = result);
        } else {
          setState(() => _recipientError = 'Username or address not found');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _recipientError = 'Username or address not found');
      }
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  // ─── Bank helpers ─────────────────────────────────────────

Future<void> _loadBanks() async {
  if (_banksLoaded) return;
  try {
    final banks = await paymentsService.getBanks();
    if (mounted) setState(() { _banks = banks; _banksLoaded = true; });
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load banks. Try again.')),
      );
    }
  }
}

  Future<void> _resolveAccountName() async {
    if (_selectedBank == null || _accountNumberCtrl.text.length != 10) return;
    setState(() {
      _resolvingAccount = true;
      _resolvedAccountName = null;
      _accountResolveError = null;
    });
    try {
      final result = await paymentsService.resolveAccount(
        bankCode: _selectedBank!['code'],
        accountNumber: _accountNumberCtrl.text.trim(),
      );
      if (mounted) {
        setState(() => _resolvedAccountName = result['accountName'] as String?);
      }
    } catch (_) {
      if (mounted) setState(() => _accountResolveError = 'Account not found');
    } finally {
      if (mounted) setState(() => _resolvingAccount = false);
    }
  }

  // ─── Crypto send ──────────────────────────────────────────

  Future<void> _send() async {
    final to = _toController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());

    if (to.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid recipient and amount')),
      );
      return;
    }
    if (_invalidAmount) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_amountError ?? 'Invalid amount')));
      return;
    }

    setState(() => _loading = true);

    showDayFiBottomSheet(
      context: context,
      isDismissible: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 24),
            const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            Text(
              'Sending...',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Processing your payment',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 17,
                letterSpacing: -.5,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );

    try {
      final result = await apiService.sendFunds(
        to: to,
        amount: amount,
        asset: _selectedAsset,
        memo: _memoController.text.trim().isEmpty
            ? null
            : _memoController.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context);
        _showSendSuccess(result);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        showDayFiBottomSheet(
          context: context,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'This transaction could not be completed. ${apiService.parseError(e)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 17,
                      letterSpacing: -.5,
                      height: 1.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 32),
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
                  onPressed: () {
                    Navigator.pop(context);
                    _send();
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: Text(
                    'Retry',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(.95),
                      fontSize: 15,
                    ),
                  ),
                ).animate().fadeIn(delay: 500.ms),
                const SizedBox(height: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size(MediaQuery.of(context).size.width, 48),
                    side: const BorderSide(
                      color: Colors.transparent,
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Dismiss',
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
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSendSuccess(Map<String, dynamic> result) {
    showDayFiBottomSheet(
      context: context,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Lottie.asset(
              'assets/animations/success.json',
              width: 120,
              height: 120,
              repeat: false,
            ),
            const SizedBox(height: 4),
            Text(
              'Sent!',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${_amountController.text} $_selectedAsset sent successfully.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 17,
                letterSpacing: -.5,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
            ),
            if (result['transaction']?['hash'] != null) ...[
              const SizedBox(height: 8),
              Text(
                'Tx: ${(result['transaction']['hash'] as String).substring(0, 12)}...',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(letterSpacing: 0.2),
              ),
            ],
            const SizedBox(height: 32),
            OutlinedButton(
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

  // ─── Bank withdraw ────────────────────────────────────────

  Future<void> _withdraw() async {
    final amount = double.tryParse(_bankAmountCtrl.text.trim());
    if (amount == null ||
        amount <= 0 ||
        _selectedBank == null ||
        _accountNumberCtrl.text.length != 10 ||
        _resolvedAccountName == null) {
      return;
    }

    setState(() => _loading = true);

    showDayFiBottomSheet(
      context: context,
      isDismissible: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 24),
            const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            Text(
              'Withdrawing...',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Sending ₦${amount.toStringAsFixed(2)} to $_resolvedAccountName',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 17,
                letterSpacing: -.5,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );

    try {
      await paymentsService.withdraw(
        ngntAmount: amount,
        bankCode: _selectedBank!['code'],
        accountNumber: _accountNumberCtrl.text.trim(),
        accountName: _resolvedAccountName!,
        idempotencyKey:
            '${_accountNumberCtrl.text}-${DateTime.now().millisecondsSinceEpoch}',
      );
      if (mounted) {
        Navigator.pop(context);
        await ref.read(walletProvider.notifier).refresh();
        _showWithdrawSuccess(amount);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiService.parseError(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showWithdrawSuccess(double amount) {
    showDayFiBottomSheet(
      context: context,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Lottie.asset(
              'assets/animations/success.json',
              width: 120,
              height: 120,
              repeat: false,
            ),
            const SizedBox(height: 4),
            Text(
              'Withdrawal Initiated!',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '₦${amount.toStringAsFixed(2)} is on its way to $_resolvedAccountName.\n'
              'Typically arrives within minutes.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 16,
                letterSpacing: -.5,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            OutlinedButton(
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

  // ─── Asset picker ─────────────────────────────────────────

  double _getEmojiHeight(String? emoji) =>
      emoji == 'assets/images/stellar.png' ? 38 : 40;

  void _showAssetPicker() {
    showDayFiBottomSheet(
      context: context,
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
                  'Choose Asset to Send',
                  style: Theme.of(context).textTheme.titleLarge!.copyWith(
                    fontSize: 16,
                    letterSpacing: -.1,
                  ),
                ),
                InkWell(
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 32),
            ...kAssetList.map((assetCode) {
              final asset = kAssets[assetCode]!;
              return InkWell(
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
                onTap: () {
                  setState(() {
                    _selectedAsset = assetCode;
                    _sendTab = 0;
                    _amountController.clear();
                    _amountError = null;
                    _invalidAmount = false;
                  });
                  Navigator.pop(context);
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
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(54),
                        child: Image.asset(
                          asset.emoji,
                          height: _getEmojiHeight(asset.emoji),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        assetCode,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
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

  // ─── Bank picker ──────────────────────────────────────────
  void _showBankPicker() {
    // If not loaded yet, load then open
    if (!_banksLoaded) {
      _loadBanks().then((_) {
        if (mounted) _showBankPicker();
      });
      return;
    }

    showDayFiBottomSheet(
      context: context,
      child: _BankPickerContent(
        banks: _banks,
        onSelected: (bank) {
          setState(() {
            _selectedBank = bank;
            _resolvedAccountName = null;
            _accountResolveError = null;
          });
          if (_accountNumberCtrl.text.length == 10) _resolveAccountName();
        },
      ),
    );
  }

  // ─── Balance info ─────────────────────────────────────────

  Widget _buildSendBalanceInfo(String assetCode) {
    final available = _availableBalance(assetCode);
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'Available: ${available.toStringAsFixed(assetCode == 'XLM' ? 4 : 2)} $assetCode',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  // ─── Bank withdraw form ───────────────────────────────────

  Widget _buildBankWithdrawForm() {
    final amount = double.tryParse(_bankAmountCtrl.text.trim());
    final canSend =
        _resolvedAccountName != null &&
        _bankAmountCtrl.text.isNotEmpty &&
        amount != null &&
        amount > 0 &&
        !_loading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),

        // Bank selector
        InkWell(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          onTap: _showBankPicker,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).textTheme.bodySmall?.color?.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedBank?['name'] ?? 'Select bank',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _selectedBank != null
                          ? Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(.85)
                          : Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(.35),
                      fontSize: 15,
                      letterSpacing: -.1,
                    ),
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 20,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.4),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Account number
        TextField(
          controller: _accountNumberCtrl,
          keyboardType: TextInputType.number,
          maxLength: 10,
          onChanged: (v) {
            if (v.length == 10) {
              _resolveAccountName();
            } else {
              setState(() {
                _resolvedAccountName = null;
                _accountResolveError = null;
              });
            }
          },
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(.85),
            fontSize: 15,
            letterSpacing: -.1,
          ),
          decoration: InputDecoration(
            hintText: 'Account number (10 digits)',
            hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(.35),
              fontSize: 15,
              letterSpacing: -.1,
            ),
            fillColor: Theme.of(
              context,
            ).textTheme.bodySmall?.color?.withOpacity(0.1),
            counterText: '',
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
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 14,
            ),
            suffixIcon: _resolvingAccount
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _resolvedAccountName != null
                ? const Icon(
                    Icons.check_circle,
                    color: Color(0xFF22C55E),
                    size: 20,
                  )
                : null,
          ),
        ),

        if (_resolvedAccountName != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              _resolvedAccountName!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF22C55E),
                fontSize: 12,
              ),
            ),
          ),
        if (_accountResolveError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              _accountResolveError!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),

        const SizedBox(height: 12),

        // Amount
        TextField(
          controller: _bankAmountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(.85),
            fontSize: 15,
            letterSpacing: -.1,
          ),
          decoration: InputDecoration(
            hintText: 'Amount (₦)',
            hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(.35),
              fontSize: 15,
              letterSpacing: -.1,
            ),
            fillColor: Theme.of(
              context,
            ).textTheme.bodySmall?.color?.withOpacity(0.1),
            prefixText: '₦ ',
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
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 14,
            ),
          ),
        ),

        const SizedBox(height: 4),
        Center(
          child: Text(
            'Available: ${ref.read(walletProvider).ngntBalance.toStringAsFixed(2)} NGNT',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
        ),

        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              side: BorderSide(
                color: canSend
                    ? Theme.of(context).colorScheme.onSurface.withOpacity(.90)
                    : Theme.of(context).colorScheme.onSurface.withOpacity(.35),
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: canSend ? _withdraw : null,
            child: Text(
              'Withdraw to Bank',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 15,
                color: canSend
                    ? Theme.of(context).colorScheme.onSurface.withOpacity(.90)
                    : Theme.of(context).colorScheme.onSurface.withOpacity(.35),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isNgnt = _selectedAsset == 'NGNT';
    final showBankForm = isNgnt && _sendTab == 1;
    final canCryptoSend =
        !_loading && !_invalidAmount && _amountController.text.isNotEmpty;

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
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),

                Center(
                  child: Text(
                    showBankForm
                        ? 'Withdraw to Bank'
                        : 'Send ${_selectedAsset}',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    showBankForm
                        ? 'Enter your bank details below.\nWe\'ll verify the account before sending.'
                        : 'Enter a username or wallet address.\nWe\'ll automatically handle the transfer.',
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      fontSize: 14,
                      letterSpacing: -.1,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 15.ms),
                ),
                const SizedBox(height: 24),

                // Asset picker
                Center(
                  child: SizedBox(
                    width: (MediaQuery.of(context).size.width * .5) - 8,
                    child: InkWell(
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      onTap: _showAssetPicker,
                      child: _DropdownBox(
                        emoji: kAssets[_selectedAsset]!.emoji,
                        label: _selectedAsset,
                      ),
                    ),
                  ).animate().fadeIn(delay: 25.ms),
                ),

                // ── NGNT sub-tabs ──────────────────────────────
                if (isNgnt) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).textTheme.bodySmall?.color?.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _SubTab(
                            label: 'Crypto',
                            selected: _sendTab == 0,
                            onTap: () => setState(() => _sendTab = 0),
                          ),
                          _SubTab(
                            label: 'Withdraw to Bank',
                            selected: _sendTab == 1,
                            onTap: () {
                              setState(() => _sendTab = 1);
                              _loadBanks();
                            },
                          ),
                        ],
                      ),
                    ),
                  ).animate().fadeIn(delay: 30.ms),
                ],

                const SizedBox(height: 20),

                // ── Bank withdrawal form ───────────────────────
                if (showBankForm)
                  _buildBankWithdrawForm().animate().fadeIn(delay: 40.ms),

                // ── Crypto send form ───────────────────────────
                if (!showBankForm) ...[
                  TextField(
                    controller: _toController,
                    autocorrect: false,
                    onChanged: (v) {
                      if (v.length > 2) _resolveRecipient(v);
                    },
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(.85),
                      fontSize: 15,
                      letterSpacing: -.1,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Type recipient\'s username or wallet address',
                      hintStyle: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(.35),
                            fontSize: 15,
                            letterSpacing: -.1,
                          ),
                      fillColor: Theme.of(
                        context,
                      ).textTheme.bodySmall?.color?.withOpacity(0.1),
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
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 10,
                      ),
                      suffixIcon: _resolving
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : _resolvedRecipient != null
                          ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: SvgPicture.asset(
                                'assets/icons/svgs/circle_check.svg',
                                color: DayFiColors.green,
                                height: 16,
                              ),
                            )
                          : null,
                    ),
                  ).animate().fadeIn(delay: 50.ms),

                  if (_recipientError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Text(
                        _recipientError!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else if (_resolvedRecipient != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Text(
                        _resolvedRecipient!['username'] ??
                            _resolvedRecipient!['address'] ??
                            'Recipient found on-chain',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: DayFiColors.green,
                          fontSize: 12,
                        ),
                      ),
                    ),

                  const SizedBox(height: 20),

                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(.85),
                      fontSize: 15,
                      letterSpacing: -.1,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Enter amount (0.00)',
                      hintStyle: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(.35),
                            fontSize: 15,
                            letterSpacing: -.1,
                          ),
                      fillColor: Theme.of(
                        context,
                      ).textTheme.bodySmall?.color?.withOpacity(0.1),
                      prefixText: _selectedAsset == 'USDC' ? '\$ ' : '',
                      suffixText: _selectedAsset,
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
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 10,
                      ),
                    ),
                  ).animate().fadeIn(delay: 100.ms),

                  const SizedBox(height: 4),
                  InkWell(
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    onTap: () {
                      final max = _availableBalance(_selectedAsset);
                      _amountController.text = max.toStringAsFixed(
                        _selectedAsset == 'XLM' ? 4 : 2,
                      );
                    },
                    child: _buildSendBalanceInfo(kAssets[_selectedAsset]!.code),
                  ),

                  const SizedBox(height: 20),

                  TextField(
                    controller: _memoController,
                    maxLength: 28,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(.85),
                      fontSize: 15,
                      letterSpacing: -.1,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Add memo (optional)',
                      hintStyle: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(.35),
                            fontSize: 15,
                            letterSpacing: -.1,
                          ),
                      fillColor: Theme.of(
                        context,
                      ).textTheme.bodySmall?.color?.withOpacity(0.1),
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
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 10,
                      ),
                      counterText: '',
                    ),
                  ).animate().fadeIn(delay: 100.ms),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        side: BorderSide(
                          color: canCryptoSend
                              ? Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(.90)
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(.45),
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: canCryptoSend ? _send : null,
                      child: Text(
                        'Send',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: canCryptoSend
                              ? Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(.90)
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(.45),
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _DropdownBox extends StatelessWidget {
  final String? emoji;
  final String label;
  const _DropdownBox({this.emoji, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: emoji != null ? 8 : 16,
        vertical: emoji != null ? 7.5 : 10,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.050),
        ),
      ),
      child: Row(
        children: [
          if (emoji != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(54),
              child: Image.asset(emoji!, height: 24),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.90),
                fontSize: 13.5,
                letterSpacing: -.1,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(
            Icons.keyboard_arrow_down,
            size: 20,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
          ),
        ],
      ),
    );
  }
}

class _SubTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SubTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withOpacity(.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: selected
                ? Theme.of(context).textTheme.bodyLarge?.color?.withOpacity(.85)
                : null,
            fontWeight: FontWeight.w500,
            fontSize: 13,
            letterSpacing: -.1,
          ),
        ),
      ),
    );
  }
}

class _BankPickerContent extends StatefulWidget {
  final List<Map<String, dynamic>> banks;
  final ValueChanged<Map<String, dynamic>> onSelected;
  const _BankPickerContent({required this.banks, required this.onSelected});

  @override
  State<_BankPickerContent> createState() => _BankPickerContentState();
}

class _BankPickerContentState extends State<_BankPickerContent> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.banks
        : widget.banks
              .where(
                (b) => (b['name'] as String).toLowerCase().contains(
                  _query.toLowerCase(),
                ),
              )
              .toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Opacity(opacity: 0, child: Icon(Icons.close)),
              Text(
                'Select Bank',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 16,
                  letterSpacing: -.1,
                ),
              ),
              InkWell(
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Search field
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search banks...',
              hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.35),
                fontSize: 14,
              ),
              prefixIcon: Icon(
                Icons.search,
                size: 18,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.4),
              ),
              fillColor: Theme.of(
                context,
              ).textTheme.bodySmall?.color?.withOpacity(.08),
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
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 11,
              ),
            ),
          ),

          const SizedBox(height: 12),

          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * .45,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final bank = filtered[i];
                return InkWell(
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  onTap: () {
                    widget.onSelected(bank);
                    Navigator.pop(context);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      bank['name'] as String,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 14.5,
                        letterSpacing: -.1,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
