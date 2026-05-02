// lib/screens/transactions/transactions_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/widgets/app_background.dart';
import 'package:mobile_app/widgets/app_bottomsheet.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _searchDebounce;

  List<dynamic> _transactions = [];
  bool _loading = true;
  int _page = 1;
  bool _hasMore = true;
  String _searchQuery = '';

  final _selectedAssets = <String>{};
  final _selectedTypes = <String>{};
  final int _sortOption = 0;
  String? _assetFilter;
  String? _typeFilter;

  List<dynamic> _cachedFiltered = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(
          () => _searchQuery = _searchController.text.trim().toLowerCase(),
        );
      }
    });
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _page = 1;
        _hasMore = true;
        _transactions = [];
      });
    }

    try {
      final result = await apiService.getTransactions(page: _page, limit: 20);

      final txs = result['transactions'] as List;
      final pagination = result['pagination'];

      if (mounted) {
        setState(() {
          _transactions = refresh ? txs : [..._transactions, ...txs];
          _hasMore = _page < (pagination['pages'] ?? 1);
          _loading = false;
        });
        _refreshCache();
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _refreshCache() {
    // Filter transactions
    _cachedFiltered = _transactions.where((tx) {
      final asset = (tx['asset'] as String?) ?? '';
      final type = (tx['type'] as String?) ?? '';
      final swapToAsset = (tx['swapToAsset'] as String?) ?? '';
      final swapFromAsset = (tx['swapFromAsset'] as String?) ?? '';

      // Hide the incoming swap leg (the duplicate)
      if (type == 'swap' && asset == swapToAsset && asset != swapFromAsset) {
        return false;
      }

      // Asset filter
      if (_selectedAssets.isNotEmpty && !_selectedAssets.contains(asset)) {
        return false;
      }

      // Type filter
      if (_selectedTypes.isNotEmpty && !_selectedTypes.contains(type)) {
        return false;
      }

      // Search query
      if (_searchQuery.isNotEmpty) {
        final toUsername = (tx['toUsername'] as String?) ?? '';
        if (!toUsername.toLowerCase().contains(_searchQuery) &&
            !asset.toLowerCase().contains(_searchQuery)) {
          return false;
        }
      }

      return true;
    }).toList();

    // Sort
    _cachedFiltered.sort((a, b) {
      final dateA = DateTime.tryParse(a['createdAt'] ?? '') ?? DateTime.now();
      final dateB = DateTime.tryParse(b['createdAt'] ?? '') ?? DateTime.now();
      final amountA = (a['amount'] as num).toDouble();
      final amountB = (b['amount'] as num).toDouble();

      switch (_sortOption) {
        case 0: // Date newest first
          return dateB.compareTo(dateA);
        case 1: // Amount high to low
          return amountB.compareTo(amountA);
        case 2: // Amount low to high
          return amountA.compareTo(amountB);
        default:
          return dateB.compareTo(dateA);
      }
    });
  }

  void _applyFilter(String? type, String? asset) {
    setState(() {
      _typeFilter = type;
      _assetFilter = asset;
      if (type != null) {
        _selectedTypes.add(type);
      } else {
        _selectedTypes.clear();
      }
      if (asset != null) {
        _selectedAssets.add(asset);
      } else {
        _selectedAssets.clear();
      }
    });
    _refreshCache();
  }

  Map<String, List<Map<String, dynamic>>> _groupTransactionsByDate(
    List<dynamic> txs,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));

    for (final tx in txs) {
      final createdAt =
          DateTime.tryParse(tx['createdAt'] ?? '') ?? DateTime.now();
      final createdDate = DateTime(
        createdAt.year,
        createdAt.month,
        createdAt.day,
      );
      final todayDate = DateTime(today.year, today.month, today.day);
      final yesterdayDate = DateTime(
        yesterday.year,
        yesterday.month,
        yesterday.day,
      );

      String dateLabel;
      if (createdDate == todayDate) {
        dateLabel = 'Today';
      } else if (createdDate == yesterdayDate) {
        dateLabel = 'Yesterday';
      } else {
        dateLabel = DateFormat('MMM d').format(createdAt);
      }

      grouped.putIfAbsent(dateLabel, () => []);
      grouped[dateLabel]!.add(tx as Map<String, dynamic>);
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(
            'Transactions',
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
            behavior: HitTestBehavior.opaque,
            onTap: () => context.pop(),
            child: const Icon(Icons.arrow_back_ios, size: 20),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Filter chips
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    _FilterChip(label: 'Date', selected: false, onTap: () {}),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Currency',
                      selected: _assetFilter != null,
                      onTap: () => _showAssetFilter(),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Type',
                      selected: _typeFilter != null,
                      onTap: () => _showTypeFilter(),
                    ),
                  ],
                ),
              ).animate().fadeIn(),

              // List
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _transactions.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: () => _load(refresh: true),
                        child: _buildGroupedTransactionsList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(
            "assets/icons/svgs/transfer.svg",
            height: 48,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.050),
          ),
          const SizedBox(height: 16),
          Text(
            'No transactions yet',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms);
  }

  Widget _buildLoadMore() {
    return Center(
      child: TextButton(
        onPressed: () {
          setState(() => _page++);
          _load();
        },
        child: const Text('Load more'),
      ),
    );
  }

  Widget _buildGroupedTransactionsList() {
    final grouped = _groupTransactionsByDate(_cachedFiltered);
    final dateLabels = grouped.keys.toList();

    dateLabels.sort((a, b) {
      if (a == 'Today') return -1;
      if (b == 'Today') return 1;
      if (a == 'Yesterday') return -1;
      if (b == 'Yesterday') return 1;
      return 0;
    });

    final items = <Map<String, dynamic>>[];
    int tileIndex = 0;

    for (final dateLabel in dateLabels) {
      items.add({'type': 'header', 'label': dateLabel});
      for (final tx in grouped[dateLabel]!) {
        items.add({'type': 'tile', 'tx': tx, 'index': tileIndex++});
      }
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (scroll) {
        if (scroll.metrics.pixels >= scroll.metrics.maxScrollExtent - 200 &&
            _hasMore &&
            !_loading) {
          setState(() => _page++);
          _load();
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length + (_hasMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i == items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }

          final item = items[i];

          if (item['type'] == 'header') {
            return Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 8),
              child: Text(
                item['label'] as String,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.5),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            );
          } else {
            return _TxTile(
              tx: item['tx'] as Map<String, dynamic>,
              index: item['index'] as int,
            );
          }
        },
      ),
    );
  }

  void _showTypeFilter() {
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
            Center(
              child: Text(
                'Filter by Type',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              splashColor: Colors.transparent,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              title: const Text('All'),
              onTap: () {
                Navigator.pop(context);
                _applyFilter(null, _assetFilter);
              },
            ),
            ListTile(
              splashColor: Colors.transparent,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              title: const Text('Sent'),
              onTap: () {
                Navigator.pop(context);
                _applyFilter('send', _assetFilter);
              },
            ),
            ListTile(
              splashColor: Colors.transparent,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              title: const Text('Received'),
              onTap: () {
                Navigator.pop(context);
                _applyFilter('receive', _assetFilter);
              },
            ),
            ListTile(
              splashColor: Colors.transparent,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              title: const Text('Swapped'),
              onTap: () {
                Navigator.pop(context);
                _applyFilter('swap', _assetFilter);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAssetFilter() {
    showDayFiBottomSheet(
      context: context,

      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                'Filter by Currency',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              splashColor: Colors.transparent,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              title: const Text('All'),
              onTap: () {
                Navigator.pop(context);
                _applyFilter(_typeFilter, null);
              },
            ),
            ListTile(
              splashColor: Colors.transparent,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              title: const Text('USDC'),
              onTap: () {
                Navigator.pop(context);
                _applyFilter(_typeFilter, 'USDC');
              },
            ),
            ListTile(
              splashColor: Colors.transparent,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              title: const Text('XLM'),
              onTap: () {
                Navigator.pop(context);
                _applyFilter(_typeFilter, 'XLM');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withOpacity(.75)
              : Theme.of(context).colorScheme.surface.withOpacity(.4),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: selected ? Theme.of(context).colorScheme.background : null,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

void _showTxDetails(BuildContext context, Map<String, dynamic> tx) {
  final isSend = tx['type'] == 'send';
  final isSwap = tx['type'] == 'swap';
  final amount = (tx['amount'] as num).toDouble();
  final asset = tx['asset'] as String;
  final swapToAsset = (tx['swapToAsset'] as String?) ?? '';
  final swapToAmount = (tx['receivedAmount'] ?? tx['swapToAmount']) != null
      ? ((tx['receivedAmount'] ?? tx['swapToAmount']) as num).toDouble()
      : null;
  final createdAt = DateTime.tryParse(tx['createdAt'] ?? '') ?? DateTime.now();
  final txHash = tx['stellarTxHash'] as String?;
  final memo = tx['memo'] as String?;
  final fee = tx['fee'] as String?;

  showDayFiBottomSheet(
    context: context,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Opacity(opacity: 0, child: Icon(Icons.close)),
              Text(
                'Details',
                style: Theme.of(context).textTheme.titleLarge!.copyWith(
                  fontSize: 16,
                  letterSpacing: -.1,
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 32),

          SvgPicture.asset(
            isSwap
                ? 'assets/icons/svgs/swap.svg'
                : (isSend
                      ? 'assets/icons/svgs/arrow_out.svg'
                      : 'assets/icons/svgs/arrow_in.svg'),
            color: Theme.of(context).colorScheme.onSurface.withOpacity(.55),
            width: 24,
            height: 24,
          ),

          const SizedBox(height: 12),

          // Info
          Text(
            isSwap
                ? '$amount $asset → ${swapToAmount != null ? '${swapToAmount.toStringAsFixed(2)} ' : ''}$swapToAsset'
                : '${isSend ? '-' : '+'}${amount.toStringAsFixed(2)} $asset',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: isSwap
                  ? Theme.of(context).colorScheme.primary
                  : (isSend ? DayFiColors.red : DayFiColors.green),
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 24),

          // Details rows
          _DetailRow(
            label: 'Type',
            value: isSwap ? 'Swapped' : (isSend ? 'Sent' : 'Received'),
          ),
          if (tx['toUsername'] != null)
            _DetailRow(
              label: isSend ? 'To' : 'From',
              value: '@${tx['toUsername']}',
            ),
          _DetailRow(
            label: 'Date',
            value: DateFormat(
              'MMM d, yyyy · h:mm a',
            ).format(createdAt.toLocal()),
          ),
          if (memo != null && memo.isNotEmpty)
            _DetailRow(label: 'Memo', value: memo),
          if (fee != null) _DetailRow(label: 'Network fee', value: fee),
          if (txHash != null)
            _DetailRow(
              label: 'Tx Hash',
              value:
                  '${txHash.substring(0, 8)}...${txHash.substring(txHash.length - 8)}',
              mono: true,
            ),

          const SizedBox(height: 20),

          // View on Stellar Expert button
          if (txHash != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
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
                  launchUrl(
                    Uri.parse(
                      'https://stellar.expert/explorer/public/tx/$txHash',
                    ),
                  );
                },
                icon: Icon(
                  Icons.open_in_new,
                  size: 18,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(.90),
                ),
                label: Text(
                  'View on Stellar Expert',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(.90),
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 20),
        ],
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;

  const _DetailRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontFamily: mono ? 'monospace' : null,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _TxTile extends StatelessWidget {
  final Map<String, dynamic> tx;
  final int index;

  const _TxTile({required this.tx, required this.index});

  @override
  Widget build(BuildContext context) {
    final isSend = tx['type'] == 'send';
    final isSwap = tx['type'] == 'swap';
    final amount = (tx['amount'] as num).toDouble();
    final asset = tx['asset'] as String;
    final swapToAsset = (tx['swapToAsset'] as String?) ?? '';
    final swapToAmount = (tx['receivedAmount'] ?? tx['swapToAmount']) != null
        ? ((tx['receivedAmount'] ?? tx['swapToAmount']) as num).toDouble()
        : null;
    final createdAt =
        DateTime.tryParse(tx['createdAt'] ?? '') ?? DateTime.now();
    final toUsername = tx['toUsername'] as String?;
    final memo = tx['memo'] as String?;

    return GestureDetector(
      onTap: () => _showTxDetails(context, tx),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            // Icon
            SvgPicture.asset(
              isSwap
                  ? 'assets/icons/svgs/swap.svg'
                  : (isSend
                        ? 'assets/icons/svgs/arrow_out.svg'
                        : 'assets/icons/svgs/arrow_in.svg'),
              color: Theme.of(context).colorScheme.onSurface.withOpacity(.55),
              width: 18,
              height: 18,
            ),

            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Text(
                isSwap
                    ? '$amount $asset → ${swapToAmount != null ? '${swapToAmount.toStringAsFixed(2)} ' : ''}$swapToAsset'
                    : '${isSend ? '-' : '+'}${amount.toStringAsFixed(2)} $asset',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: isSwap
                      ? Theme.of(context).colorScheme.primary
                      : (isSend ? DayFiColors.red : DayFiColors.green),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            // Amount
            Text(
              "${DateFormat('h:mm a').format(createdAt.toLocal())} ",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ).animate().fadeIn(delay: Duration(milliseconds: index * 50)),
    );
  }
}
