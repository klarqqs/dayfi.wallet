// lib/providers/wallet_provider.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

// ─── Wallet State ─────────────────────────────────────────────────────────────

class WalletState {
  final double usdcBalance;
  final double xlmBalance;
  final double xlmPriceUSD;
  final String? stellarAddress;
  final String? dayfiUsername;
  final bool isLoading;
  final bool isRefreshing;
  final String? error;
  final DateTime? lastUpdated;
  final bool hasError;
  final bool isOffline;
  final double? lastKnownTotal;

  const WalletState({
    this.usdcBalance = 0.0,
    this.xlmBalance = 0.0,
    this.xlmPriceUSD = 0.169,
    this.stellarAddress,
    this.dayfiUsername,
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.lastUpdated,
    this.hasError = false,
    this.isOffline = false,
    this.lastKnownTotal,
  });

  double get totalUSD => usdcBalance + (xlmBalance * xlmPriceUSD);
  double get availableXLM => xlmBalance > 1.0 ? xlmBalance - 1.0 : 0.0;
  double get availableXLMUSD => availableXLM * xlmPriceUSD;

  WalletState copyWith({
    double? usdcBalance,
    double? xlmBalance,
    double? xlmPriceUSD,
    String? stellarAddress,
    String? dayfiUsername,
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    DateTime? lastUpdated,
    bool? hasError,
    bool? isOffline,
    double? lastKnownTotal,
  }) {
    return WalletState(
      usdcBalance: usdcBalance ?? this.usdcBalance,
      xlmBalance: xlmBalance ?? this.xlmBalance,
      xlmPriceUSD: xlmPriceUSD ?? this.xlmPriceUSD,
      stellarAddress: stellarAddress ?? this.stellarAddress,
      dayfiUsername: dayfiUsername ?? this.dayfiUsername,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      error: error,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      hasError: hasError ?? this.hasError,
      isOffline: isOffline ?? this.isOffline,
      lastKnownTotal: lastKnownTotal ?? this.lastKnownTotal,
    );
  }
}

// ─── Wallet Notifier ──────────────────────────────────────────────────────────

class WalletNotifier extends StateNotifier<WalletState> {
  WalletNotifier() : super(const WalletState(isLoading: true)) {
    load();
  }

  Future<double> _fetchXlmPrice() async {
    try {
      final res = await http
          .get(
            Uri.parse(
              'https://api.coingecko.com/api/v3/simple/price?ids=stellar&vs_currencies=usd',
            ),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['stellar']['usd'] as num).toDouble();
      }
    } catch (_) {}
    return state
        .xlmPriceUSD; // reuse last known price rather than hardcoded fallback
  }

  // ─── Helpers ────────────────────────────────────────────

  /// Returns the best "last known total" to preserve across failures.
  /// Only updates when we have a confirmed successful fetch with a live price.
  double? _computeLastKnown({
    required double usdcBalance,
    required double xlmBalance,
    required double xlmPrice,
  }) {
    final live = usdcBalance + (xlmBalance * xlmPrice);
    // Only save as lastKnown if it's a meaningful non-zero value
    return live > 0 ? live : state.lastKnownTotal;
  }

  bool _isNetworkError(Object e) {
    return e is SocketException ||
        e is TimeoutException ||
        e.toString().contains('SocketException') ||
        e.toString().contains('TimeoutException') ||
        e.toString().contains('Failed host lookup') ||
        e.toString().contains('Network is unreachable') ||
        e.toString().contains('Connection refused');
  }

  // ─── Initial load ────────────────────────────────────────

  Future<void> load() async {
    state = state.copyWith(
      isLoading: true,
      hasError: false,
      isOffline: false,
      error: null,
    );

    try {
      final results = await Future.wait([
        apiService.getBalance(),
        apiService.getAddress(),
        _fetchXlmPrice(),
      ]);

      final balanceData = results[0] as Map<String, dynamic>;
      final addressData = results[1] as Map<String, dynamic>;
      final xlmPrice = results[2] as double;
      final balances = balanceData['balances'] as Map<String, dynamic>? ?? {};

      final usdc = (balances['USDC'] as num?)?.toDouble() ?? 0.0;
      final xlm = (balances['XLM'] as num?)?.toDouble() ?? 0.0;

      state = state.copyWith(
        usdcBalance: usdc,
        xlmBalance: xlm,
        xlmPriceUSD: xlmPrice,
        stellarAddress: addressData['stellarAddress'] as String?,
        dayfiUsername: addressData['dayfiUsername'] as String?,
        isLoading: false,
        hasError: false,
        isOffline: false,
        lastKnownTotal: _computeLastKnown(
          usdcBalance: usdc,
          xlmBalance: xlm,
          xlmPrice: xlmPrice,
        ),
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      final offline = _isNetworkError(e);
      state = state.copyWith(
        isLoading: false,
        hasError: !offline,
        isOffline: offline,
        error: e.toString(),
        // balances stay at 0 on first load failure — lastKnownTotal is null
        // so the UI will show $— instead of $0.00
      );
    }
  }

  // ─── Periodic / pull-to-refresh ──────────────────────────

  Future<void> refresh() async {
    if (state.isRefreshing) return;

    // Snapshot the best "previous total" before touching state
    final previousTotal = state.totalUSD > 0
        ? state.totalUSD
        : state.lastKnownTotal;

    state = state.copyWith(
      isRefreshing: true,
      hasError: false,
      isOffline: false,
      error: null,
    );

    try {
      final results = await Future.wait([
        apiService.getBalance(),
        _fetchXlmPrice(),
      ]);

      final balanceData = results[0] as Map<String, dynamic>;
      final xlmPrice = results[1] as double;
      final balances = balanceData['balances'] as Map<String, dynamic>? ?? {};

      final usdc = (balances['USDC'] as num?)?.toDouble() ?? 0.0;
      final xlm = (balances['XLM'] as num?)?.toDouble() ?? 0.0;

      state = state.copyWith(
        usdcBalance: usdc,
        xlmBalance: xlm,
        xlmPriceUSD: xlmPrice,
        isRefreshing: false,
        hasError: false,
        isOffline: false,
        lastKnownTotal: _computeLastKnown(
          usdcBalance: usdc,
          xlmBalance: xlm,
          xlmPrice: xlmPrice,
        ),
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      final offline = _isNetworkError(e);
      state = state.copyWith(
        isRefreshing: false,
        hasError: !offline,
        isOffline: offline,
        error: e.toString(),
        // Restore balances from last known so UI doesn't flash 0.00
        usdcBalance: state.usdcBalance,
        xlmBalance: state.xlmBalance,
        lastKnownTotal: previousTotal,
      );
    }
  }

  // ─── Send ────────────────────────────────────────────────

  Future<Map<String, dynamic>> send({
    required String to,
    required double amount,
    required String asset,
    String? memo,
  }) async {
    final result = await apiService.sendFunds(
      to: to,
      amount: amount,
      asset: asset,
      memo: memo,
    );
    await refresh();
    return result;
  }

  // ─── Resolve recipient ───────────────────────────────────

  Future<Map<String, dynamic>?> resolveRecipient(String identifier) async {
    if (identifier.length < 3) return null;

    // ── If it's a valid Stellar address, resolve directly — no API lookup needed
    if (_isStellarAddress(identifier)) {
      return {
        'stellarAddress': identifier,
        'dayfiUsername': null,
        'displayName': identifier,
      };
    }

    try {
      return await apiService.resolveRecipient(identifier);
    } catch (_) {
      return null;
    }
  }

  bool _isStellarAddress(String input) {
    return input.length == 56 &&
        input.startsWith('G') &&
        RegExp(r'^[A-Z2-7]+$').hasMatch(input); // Stellar uses base32
  }
}

// ─── Providers ────────────────────────────────────────────────────────────────

final walletProvider = StateNotifierProvider<WalletNotifier, WalletState>((
  ref,
) {
  return WalletNotifier();
});

final usdcBalanceProvider = Provider<double>(
  (ref) => ref.watch(walletProvider).usdcBalance,
);
final xlmBalanceProvider = Provider<double>(
  (ref) => ref.watch(walletProvider).xlmBalance,
);
final xlmPriceProvider = Provider<double>(
  (ref) => ref.watch(walletProvider).xlmPriceUSD,
);
final walletAddressProvider = Provider<String?>(
  (ref) => ref.watch(walletProvider).stellarAddress,
);
final dayfiUsernameProvider = Provider<String?>(
  (ref) => ref.watch(walletProvider).dayfiUsername,
);
