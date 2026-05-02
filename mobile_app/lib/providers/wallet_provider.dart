// lib/providers/wallet_provider.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/payments_service.dart';

// ─── Wallet State ─────────────────────────────────────────────────────────────

class WalletState {
  final double usdcBalance;
  final double xlmBalance;
  final double ngntBalance;
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

  // Virtual account
  final bool virtualAccountExists;
  final String? virtualAccountNumber;
  final String? virtualAccountBank;
  final String? virtualAccountName;

  const WalletState({
    this.usdcBalance = 0.0,
    this.xlmBalance = 0.0,
    this.ngntBalance = 0.0,
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
    this.virtualAccountExists = false,
    this.virtualAccountNumber,
    this.virtualAccountBank,
    this.virtualAccountName,
  });

  double get totalUSD =>
      usdcBalance + (xlmBalance * xlmPriceUSD);

  double get availableXLM =>
      xlmBalance > 1.0 ? xlmBalance - 1.0 : 0.0;

  double get availableXLMUSD => availableXLM * xlmPriceUSD;

  WalletState copyWith({
    double? usdcBalance,
    double? xlmBalance,
    double? ngntBalance,
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
    bool? virtualAccountExists,
    String? virtualAccountNumber,
    String? virtualAccountBank,
    String? virtualAccountName,
  }) {
    return WalletState(
      usdcBalance:          usdcBalance    ?? this.usdcBalance,
      xlmBalance:           xlmBalance     ?? this.xlmBalance,
      ngntBalance:          ngntBalance    ?? this.ngntBalance,
      xlmPriceUSD:          xlmPriceUSD   ?? this.xlmPriceUSD,
      stellarAddress:       stellarAddress ?? this.stellarAddress,
      dayfiUsername:        dayfiUsername  ?? this.dayfiUsername,
      isLoading:            isLoading      ?? this.isLoading,
      isRefreshing:         isRefreshing   ?? this.isRefreshing,
      error:                error,
      lastUpdated:          lastUpdated    ?? this.lastUpdated,
      hasError:             hasError       ?? this.hasError,
      isOffline:            isOffline      ?? this.isOffline,
      lastKnownTotal:       lastKnownTotal ?? this.lastKnownTotal,
      virtualAccountExists: virtualAccountExists ?? this.virtualAccountExists,
      virtualAccountNumber: virtualAccountNumber ?? this.virtualAccountNumber,
      virtualAccountBank:   virtualAccountBank   ?? this.virtualAccountBank,
      virtualAccountName:   virtualAccountName   ?? this.virtualAccountName,
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
          .get(Uri.parse(
            'https://api.coingecko.com/api/v3/simple/price?ids=stellar&vs_currencies=usd',
          ))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['stellar']['usd'] as num).toDouble();
      }
    } catch (_) {}
    return state.xlmPriceUSD;
  }

  double? _computeLastKnown({
    required double usdcBalance,
    required double xlmBalance,
    required double xlmPrice,
  }) {
    final live = usdcBalance + (xlmBalance * xlmPrice);
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

  // ─── Initial load ─────────────────────────────────────────

  Future<void> load() async {
    state = state.copyWith(
      isLoading: true,
      hasError:  false,
      isOffline: false,
      error:     null,
    );

    try {
      final results = await Future.wait([
        apiService.getBalance(),
        apiService.getAddress(),
        _fetchXlmPrice(),
      ]);

      final balanceData = results[0] as Map<String, dynamic>;
      final addressData = results[1] as Map<String, dynamic>;
      final xlmPrice    = results[2] as double;
      final balances    = balanceData['balances'] as Map<String, dynamic>? ?? {};

      final usdc = (balances['USDC'] as num?)?.toDouble() ?? 0.0;
      final xlm  = (balances['XLM']  as num?)?.toDouble() ?? 0.0;
      final ngnt = (balances['NGNT'] as num?)?.toDouble() ?? 0.0;

      state = state.copyWith(
        usdcBalance:    usdc,
        xlmBalance:     xlm,
        ngntBalance:    ngnt,
        xlmPriceUSD:    xlmPrice,
        stellarAddress: addressData['stellarAddress'] as String?,
        dayfiUsername:  addressData['dayfiUsername']  as String?,
        isLoading:      false,
        hasError:       false,
        isOffline:      false,
        lastKnownTotal: _computeLastKnown(
          usdcBalance: usdc,
          xlmBalance:  xlm,
          xlmPrice:    xlmPrice,
        ),
        lastUpdated: DateTime.now(),
      );

      // Load virtual account in background — don't block main load
      loadVirtualAccount();
    } catch (e) {
      final offline = _isNetworkError(e);
      state = state.copyWith(
        isLoading: false,
        hasError:  !offline,
        isOffline: offline,
        error:     e.toString(),
      );
    }
  }

  // ─── Periodic / pull-to-refresh ───────────────────────────

  Future<void> refresh() async {
    if (state.isRefreshing) return;

    final previousTotal = state.totalUSD > 0
        ? state.totalUSD
        : state.lastKnownTotal;

    state = state.copyWith(
      isRefreshing: true,
      hasError:     false,
      isOffline:    false,
      error:        null,
    );

    try {
      final results = await Future.wait([
        apiService.getBalance(),
        _fetchXlmPrice(),
      ]);

      final balanceData = results[0] as Map<String, dynamic>;
      final xlmPrice    = results[1] as double;
      final balances    = balanceData['balances'] as Map<String, dynamic>? ?? {};

      final usdc = (balances['USDC'] as num?)?.toDouble() ?? 0.0;
      final xlm  = (balances['XLM']  as num?)?.toDouble() ?? 0.0;
      final ngnt = (balances['NGNT'] as num?)?.toDouble() ?? 0.0;

      state = state.copyWith(
        usdcBalance:    usdc,
        xlmBalance:     xlm,
        ngntBalance:    ngnt,
        xlmPriceUSD:    xlmPrice,
        isRefreshing:   false,
        hasError:       false,
        isOffline:      false,
        lastKnownTotal: _computeLastKnown(
          usdcBalance: usdc,
          xlmBalance:  xlm,
          xlmPrice:    xlmPrice,
        ),
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      final offline = _isNetworkError(e);
      state = state.copyWith(
        isRefreshing:  false,
        hasError:      !offline,
        isOffline:     offline,
        error:         e.toString(),
        usdcBalance:   state.usdcBalance,
        xlmBalance:    state.xlmBalance,
        ngntBalance:   state.ngntBalance,
        lastKnownTotal: previousTotal,
      );
    }
  }

  // ─── Virtual account ──────────────────────────────────────

  Future<void> loadVirtualAccount() async {
    try {
      final data   = await paymentsService.getVirtualAccount();
      final exists = data['exists'] == true;
      state = state.copyWith(
        virtualAccountExists: exists,
        virtualAccountNumber: exists ? data['accountNumber'] as String? : null,
        virtualAccountBank:   exists ? data['bankName']      as String? : null,
        virtualAccountName:   exists ? data['accountName']   as String? : null,
      );
    } catch (_) {
      // Non-fatal — virtual account section shows setup card instead
    }
  }

  // ─── Send ─────────────────────────────────────────────────

  Future<Map<String, dynamic>> send({
    required String to,
    required double amount,
    required String asset,
    String? memo,
  }) async {
    final result = await apiService.sendFunds(
      to:     to,
      amount: amount,
      asset:  asset,
      memo:   memo,
    );
    await refresh();
    return result;
  }

  // ─── Withdraw ─────────────────────────────────────────────

Future<Map<String, dynamic>> withdraw({
  required double ngntAmount,
  required String bankCode,
  required String accountNumber,
  required String accountName,
}) async {
  final result = await paymentsService.withdraw(
    ngntAmount:     ngntAmount,
    bankCode:       bankCode,
    accountNumber:  accountNumber,
    accountName:    accountName,
    idempotencyKey: 'wd-${DateTime.now().millisecondsSinceEpoch}',
  );
  await refresh();
  return result;
}

  // ─── Resolve recipient ────────────────────────────────────

  Future<Map<String, dynamic>?> resolveRecipient(String identifier) async {
    if (identifier.length < 3) return null;

    if (_isStellarAddress(identifier)) {
      return {
        'stellarAddress': identifier,
        'dayfiUsername':  null,
        'displayName':    identifier,
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
        RegExp(r'^[A-Z2-7]+$').hasMatch(input);
  }
}

// ─── Providers ────────────────────────────────────────────────────────────────

final walletProvider = StateNotifierProvider<WalletNotifier, WalletState>(
  (ref) => WalletNotifier(),
);

final usdcBalanceProvider = Provider<double>(
  (ref) => ref.watch(walletProvider).usdcBalance,
);
final xlmBalanceProvider = Provider<double>(
  (ref) => ref.watch(walletProvider).xlmBalance,
);
final ngntBalanceProvider = Provider<double>(
  (ref) => ref.watch(walletProvider).ngntBalance,
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
final virtualAccountProvider = Provider<Map<String, dynamic>?>((ref) {
  final w = ref.watch(walletProvider);
  if (!w.virtualAccountExists) return null;
  return {
    'accountNumber': w.virtualAccountNumber,
    'bankName':      w.virtualAccountBank,
    'accountName':   w.virtualAccountName,
  };
});
final banksProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return paymentsService.getBanks();
});