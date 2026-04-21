// lib/screens/receive/receive_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/widgets/app_background.dart';
import 'package:mobile_app/widgets/app_bottomsheet.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/api_service.dart';

// ─── Emoji mapping for emojis that come from backend ────────────────────────────

final Map<String, String> _assetEmojis = {
  'USDC': 'assets/images/usdc.png',
  'XLM': 'assets/images/stellar.png',
};

final Map<String, String> _networkEmojis = {
  'stellar': 'assets/images/stellar.png',
};

// ─── Screen ───────────────────────────────────────────────────────────────────

class ReceiveScreen extends StatefulWidget {
  final String? initialAsset;
  const ReceiveScreen({super.key, this.initialAsset});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  int _selectedTab = 0; // 0 = Blockchains, 1 = Username

  Map<String, dynamic>? _addressData;
  Map<String, dynamic>? _rawAssets;
  Map<String, dynamic>? _rawNetworks;
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
      // Fetch both address and network config in parallel
      final results = await Future.wait([
        apiService.getAddress(),
        apiService.getNetworkConfig(),
      ]);

      final addressData = results[0];
      final configData = results[1];

      if (mounted) {
        setState(() {
          _addressData = addressData;
          // Parse assets map: { "USDC": ["stellar"], "XLM": ["stellar"] }
          _rawAssets =
              configData['assets'] as Map<String, dynamic>? ??
              {
                'USDC': ['stellar'],
                'XLM': ['stellar'],
              };
          // Parse networks map: { "stellar": { "name": "Stellar", ... } }
          _rawNetworks =
              configData['networks'] as Map<String, dynamic>? ??
              {
                'stellar': {
                  'name': 'Stellar Network',
                  'emoji': 'assets/images/stellar.png',
                  'description': 'Fast, low-cost payments on Stellar',
                },
              };
          _loading = false;
        });
      }
    } catch (e) {
      print('Error loading wallet config: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          // Set defaults on error
          _rawAssets = {
            'USDC': ['stellar'],
            'XLM': ['stellar'],
          };
          _rawNetworks = {
            'stellar': {
              'name': 'Stellar Network',
              'emoji': 'assets/images/stellar.png',
              'description': 'Fast, low-cost payments on Stellar',
            },
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

  /// Map network key to the corresponding address field
  String _getAddressForNetwork() {
    if (_selectedNetworkKey == null) return '';

    switch (_selectedNetworkKey) {
      case 'stellar':
        return _addressData?['stellarAddress'] ?? '';
      case 'bitcoin':
        return _addressData?['bitcoinAddress'] ?? '';
      case 'solana':
        return _addressData?['solanaAddress'] ?? '';
      default:
        // Ethereum, Arbitrum, Polygon, Avalanche all use EVM address
        return _addressData?['evmAddress'] ?? '';
    }
  }

  // ─── Currency bottom sheet ───────────────────────────────

  void _showCurrencyPicker() {
    if (_rawAssets == null) return;

    final currencies = _rawAssets!.keys.toList();

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
              final emoji =
                  _assetEmojis[assetCode] ?? 'assets/images/default.png';
              final isSelected = _selectedAssetCode == assetCode;

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
                      // if (isSelected)
                      //   Icon(
                      //     Icons.check_circle,
                      //     color: Theme.of(ctx).colorScheme.primary,
                      //     size: 20,
                      //   ),
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

  // ─── Network bottom sheet ────────────────────────────────
  // COMMENTED OUT: Network is always Stellar
  /* void _showNetworkPicker() {
    if (_selectedAssetCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a currency first')),
      );
      return;
    }

    final supportedNetworks =
        _rawAssets?[_selectedAssetCode] as List<dynamic>? ?? [];

    showDayFiBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
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
                  'Choose Network',
                  style: Theme.of(ctx).textTheme.titleLarge!.copyWith(
                    fontSize: 16,
                    letterSpacing: -.1,
                  ),
                ),
                InkWell(
  splashColor: Colors.transparent,
  highlightColor: Colors.transparent,
  hoverColor: Colors.transparent,
                  onTap: () => Navigator.pop(ctx),
                  child: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 32),
            ...supportedNetworks.map((networkKey) {
              final networkInfo =
                  _rawNetworks?[networkKey] as Map<String, dynamic>? ?? {};
              final networkName = networkInfo['name'] ?? networkKey;
              final networkEmoji = _networkEmojis[networkKey] ?? '🔗';
              final currencyEmoji =
                  _assetEmojis[_selectedAssetCode] ??
                  'assets/images/default.png';
              final isSelected = _selectedNetworkKey == networkKey;

              return InkWell(
  splashColor: Colors.transparent,
  highlightColor: Colors.transparent,
  hoverColor: Colors.transparent,
                onTap: () {
                  setState(() => _selectedNetworkKey = networkKey);
                  Navigator.pop(ctx);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(54),
                            child: Image.asset(
                              currencyEmoji,
                              height: _getEmojiHeight(currencyEmoji),
                            ),
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(54),
                            child: Image.asset(
                              networkEmoji,
                              height: _getEmojiHeight(networkEmoji) / 2.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      Text(
                        networkName,
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      // if (isSelected)
                      //   Icon(
                      //     Icons.check_circle,
                      //     color: Theme.of(ctx).colorScheme.primary,
                      //     size: 20,
                      //   ),
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
  } */

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
                      // Tab switcher
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
                              label: 'dayfi.me Username',
                              selected: _selectedTab == 1,
                              onTap: () => setState(() => _selectedTab = 1),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(),

                      const SizedBox(height: 18),

                      if (_selectedTab == 0) _buildBlockchainTab(),
                      if (_selectedTab == 1) _buildUsernameTab(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  // ─── Blockchain tab ───────────────────────────────────────

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

        // Currency picker only
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

        // QR + address — show when both selected
        if (!ready) ...[
          Center(
            child: Column(
              children: [
                const SizedBox(height: 24),
                SvgPicture.asset(
                  "assets/images/qrcode.svg",
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
                  'Once you select a currency and network,\nyour QR code and wallet address will\nappear right here.',
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

  // ─── Username tab ─────────────────────────────────────────

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
        ).animate().fadeIn(delay: 0.ms),
        const SizedBox(height: 32),
        _ActionButtons(
          onShare: () => _share('Send me USDC at $username'),
          onCopy: () => _copy(username),
        ).animate().fadeIn(delay: 0.ms),
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
            fontSize: 14,
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
