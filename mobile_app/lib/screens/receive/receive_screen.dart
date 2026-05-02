// lib/screens/receive/receive_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/widgets/app_background.dart';
import 'package:mobile_app/widgets/app_bottomsheet.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/wallet_provider.dart';
import '../../services/api_service.dart';
import '../../services/payments_service.dart';

final Map<String, String> _assetEmojis = {
  'USDC': 'assets/images/usdc.png',
  'XLM': 'assets/images/stellar.png',
  'NGNT': 'assets/images/ng.png',
};

// ─── Screen ───────────────────────────────────────────────────────────────────

class ReceiveScreen extends ConsumerStatefulWidget {
  final String? initialAsset;
  const ReceiveScreen({super.key, this.initialAsset});

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen> {
  int _selectedTab = 0; // 0 = Blockchains, 1 = Username, 2 = Virtual Account

  Map<String, dynamic>? _addressData;
  Map<String, dynamic>? _rawAssets;
  bool _loading = true;

  String? _selectedAssetCode;
  String? _selectedNetworkKey;

  @override
  void initState() {
    super.initState();
    _selectedNetworkKey = 'stellar';
    if (widget.initialAsset != null) {
      _selectedAssetCode = widget.initialAsset;
    }
    _loadInitialData();
  }

  double _getEmojiHeight(String? emoji) {
    return emoji == 'assets/images/stellar.png' ? 38 : 40;
  }

  Future<void> _loadInitialData() async {
    try {
      final results = await Future.wait([
        apiService.getAddress(),
        apiService.getNetworkConfig(),
      ]);

      final addressData = results[0];
      final configData = results[1];

      if (mounted) {
        setState(() {
          _addressData = addressData;
          _rawAssets =
              configData['assets'] as Map<String, dynamic>? ??
              {
                'USDC': ['stellar'],
                'XLM': ['stellar'],
                'NGNT': ['stellar'],
              };
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _rawAssets = {
            'USDC': ['stellar'],
            'XLM': ['stellar'],
            'NGNT': ['stellar'],
          };
        });
      }
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  void _share(String text) => Share.share(text);

  String _getAddressForNetwork() {
    switch (_selectedNetworkKey) {
      case 'stellar':
        return _addressData?['stellarAddress'] ?? '';
      case 'bitcoin':
        return _addressData?['bitcoinAddress'] ?? '';
      case 'solana':
        return _addressData?['solanaAddress'] ?? '';
      default:
        return _addressData?['evmAddress'] ?? '';
    }
  }

  void _showCurrencyPicker() {
    if (_rawAssets == null) return;
    final currencies = _rawAssets!.keys.toList();

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
                  'Choose Currency to Receive',
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
            ...currencies.map((assetCode) {
              final emoji = _assetEmojis[assetCode] ?? 'assets/images/usdc.png';
              return InkWell(
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
                onTap: () {
                  setState(() {
                    _selectedAssetCode = assetCode;
                    _selectedNetworkKey = 'stellar';
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
                          emoji,
                          height: _getEmojiHeight(emoji),
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

  // ─── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(
            'Receive Funds',
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
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),

                      // ── Tab switcher (3 tabs) ─────────────────────────
                      Container(
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
                            _Tab(
                              label: 'Blockchains',
                              selected: _selectedTab == 0,
                              onTap: () => setState(() => _selectedTab = 0),
                            ),
                            _Tab(
                              label: 'dayfi.me',
                              selected: _selectedTab == 1,
                              onTap: () => setState(() => _selectedTab = 1),
                            ),
                            _Tab(
                              label: 'Bank',
                              selected: _selectedTab == 2,
                              onTap: () => setState(() => _selectedTab = 2),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(),

                      const SizedBox(height: 18),

                      if (_selectedTab == 0) _buildBlockchainTab(),
                      if (_selectedTab == 1) _buildUsernameTab(),
                      if (_selectedTab == 2) _buildVirtualAccountTab(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  // ─── Tab 0: Blockchain ────────────────────────────────────

  Widget _buildBlockchainTab() {
    final address = _getAddressForNetwork();
    final ready = _selectedAssetCode != null && address.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Receive on Stellar',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ).animate().fadeIn(),
        const SizedBox(height: 8),
        Text(
          'Choose the currency below to get\nyour unique receiving address and QR code.',
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
            fontSize: 14,
            letterSpacing: -.1,
            height: 1.2,
          ),
          textAlign: TextAlign.center,
        ).animate().fadeIn(delay: 100.ms),
        const SizedBox(height: 24),

        Center(
          child: SizedBox(
            width: (MediaQuery.of(context).size.width * .5) - 8,
            child: InkWell(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
              onTap: _showCurrencyPicker,
              child: _DropdownBox(
                emoji: _selectedAssetCode != null
                    ? _assetEmojis[_selectedAssetCode]
                    : null,
                label: _selectedAssetCode ?? 'Choose Currency',
              ),
            ),
          ),
        ).animate().fadeIn(delay: 150.ms),

        const SizedBox(height: 18),

        if (!ready) ...[
          Center(
            child: Column(
              children: [
                const SizedBox(height: 24),
                SvgPicture.asset(
                  'assets/images/qrcode.svg',
                  height: 80,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.15),
                ),
                const SizedBox(height: 16),
                Text(
                  'Waiting for selection...',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.3),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Once you select a currency,\nyour QR code and wallet address will\nappear right here.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ] else ...[
          Center(
            child: _QRCard(data: address).animate().fadeIn(delay: 100.ms),
          ),
          const SizedBox(height: 20),
          Text(
            'Stellar network',
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
              fontSize: 13.5,
              letterSpacing: -.1,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          _AddressBox(
            text: address.length > 16
                ? '${address.substring(0, 10)}...${address.substring(address.length - 10)}'
                : address,
            onCopy: () => _copy(address),
          ).animate().fadeIn(),
          const SizedBox(height: 32),
          _ActionButtons(
            onShare: () => _share(address),
            onCopy: () => _copy(address),
          ).animate().fadeIn(),
        ],

        const SizedBox(height: 32),
      ],
    );
  }

  // ─── Tab 1: Username ──────────────────────────────────────

  Widget _buildUsernameTab() {
    final username = _addressData?['dayfiUsername'] ?? '';
    final qrData = 'https://dayfi.me/pay/$username';

    return Column(
      children: [
        Text(
          'Receive via dayfi.me',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ).animate().fadeIn(),
        const SizedBox(height: 8),
        Text(
          'Share this QR or your dayfi.me username.\nAnyone can send you USDC instantly.',
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
            fontSize: 14,
            letterSpacing: -.1,
            height: 1.2,
          ),
          textAlign: TextAlign.center,
        ).animate().fadeIn(delay: 100.ms),
        const SizedBox(height: 40),
        _QRCard(data: qrData).animate().fadeIn(delay: 100.ms),
        const SizedBox(height: 20),
        Text(
          'Stellar Network',
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
            fontSize: 13.5,
            letterSpacing: -.1,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        _AddressBox(
          text: username,
          onCopy: () => _copy(username),
        ).animate().fadeIn(),
        const SizedBox(height: 32),
        _ActionButtons(
          onShare: () => _share('Send me USDC at $username'),
          onCopy: () => _copy(username),
        ).animate().fadeIn(),
        const SizedBox(height: 32),
      ],
    );
  }

  // ─── Tab 2: Virtual Account (NGN bank transfer) ───────────

  Widget _buildVirtualAccountTab() {
    final wallet = ref.watch(walletProvider);

    return Column(
      children: [
        Text(
          'Receive via Bank Transfer',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ).animate().fadeIn(),
        const SizedBox(height: 8),
        Text(
          'Send NGN from any Nigerian bank to this account.',
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
            fontSize: 14,
            letterSpacing: -.1,
            height: 1.2,
          ),
          textAlign: TextAlign.center,
        ).animate().fadeIn(delay: 100.ms),
        const SizedBox(height: 28),

        if (wallet.isLoading)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: CircularProgressIndicator(),
          )
        else if (!wallet.virtualAccountExists)
          _BvnSetupCard(
            onCreated: () =>
                ref.read(walletProvider.notifier).loadVirtualAccount(),
          ).animate().fadeIn(delay: 100.ms)
        else ...[
          _AccountDetailRow(
            label: 'Bank',
            value: wallet.virtualAccountBank ?? '',
          ).animate().fadeIn(delay: 100.ms),
          const SizedBox(height: 10),
          _AccountDetailRow(
            label: 'Account Number',
            value: wallet.virtualAccountNumber ?? '',
          ).animate().fadeIn(delay: 130.ms),
          const SizedBox(height: 10),
          _AccountDetailRow(
            label: 'Account Name',
            value: wallet.virtualAccountName ?? '',
          ).animate().fadeIn(delay: 160.ms),
          const SizedBox(height: 32),
          _ActionButtons(
            onShare: () => _share(
              'Pay me NGN:\n'
              'Bank: ${wallet.virtualAccountBank}\n'
              'Account: ${wallet.virtualAccountNumber}\n'
              'Name: ${wallet.virtualAccountName}',
            ),
            onCopy: () => _copy(wallet.virtualAccountNumber ?? ''),
          ).animate().fadeIn(delay: 180.ms),
        ],

        const SizedBox(height: 32),
      ],
    );
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _Tab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Tab({
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
                ? Theme.of(context).textTheme.bodyLarge?.color!.withOpacity(.85)
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

class _QRCard extends StatelessWidget {
  final String data;
  const _QRCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 225,
      child: PrettyQrView.data(
        data: data.isEmpty ? 'dayfi' : data,
        decoration: PrettyQrDecoration(
          shape: PrettyQrSmoothSymbol(
            color: Theme.of(
              context,
            ).textTheme.bodyLarge!.color!.withOpacity(0.85),
          ),
        ),
      ),
    );
  }
}

class _AddressBox extends StatelessWidget {
  final String text;
  final VoidCallback onCopy;
  const _AddressBox({required this.text, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      onTap: onCopy,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.02),
          ),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(.90),
            fontSize: 13.5,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final VoidCallback onShare;
  final VoidCallback onCopy;
  const _ActionButtons({required this.onShare, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              side: BorderSide(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.90),
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: onShare,
            icon: Icon(
              Icons.ios_share,
              size: 18,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(.90),
            ),
            label: Text(
              'Share',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.90),
                fontSize: 15,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              side: BorderSide(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.90),
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: onCopy,
            icon: Icon(
              Icons.copy,
              size: 18,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(.90),
            ),
            label: Text(
              'Copy',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.90),
                fontSize: 15,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Account Detail Row ───────────────────────────────────────────────────────

class _AccountDetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _AccountDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: -.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── BVN Setup Card ───────────────────────────────────────────────────────────

class _BvnSetupCard extends StatefulWidget {
  final VoidCallback onCreated;
  const _BvnSetupCard({required this.onCreated});

  @override
  State<_BvnSetupCard> createState() => _BvnSetupCardState();
}

class _BvnSetupCardState extends State<_BvnSetupCard> {
  final _bvnCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _bvnCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final bvn = _bvnCtrl.text.trim();
    if (bvn.length != 11 || !RegExp(r'^\d{11}$').hasMatch(bvn)) {
      setState(() => _error = 'BVN must be exactly 11 digits');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await paymentsService.createVirtualAccount(bvn);
      widget.onCreated();
    } catch (e) {
      setState(() => _error = apiService.parseError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 18.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SvgPicture.asset(
                "assets/icons/svgs/alert2.svg", // swap for your info icon
                color: const Color(0xFF60A5FA), // blue tint
                height: 24,
              ),
              const SizedBox(height: 6),
              Text(
                'Your BVN is used to create a dedicated virtual account for NGN deposits. It is never stored or shared.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF60A5FA),
                  fontSize: 13,
                  letterSpacing: -0.2,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ).animate().fadeIn(),
        ),

        TextField(
          controller: _bvnCtrl,
          keyboardType: TextInputType.number,
          maxLength: 11,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(.85),
            fontSize: 15,
            letterSpacing: -.1,
          ),
          decoration: InputDecoration(
            hintText: 'Enter your BVN (11 digits)',
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
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
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
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.9),
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Create Bank Account',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 15,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(.9),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
