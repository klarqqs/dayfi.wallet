// lib/services/payments_service.dart
import 'api_service.dart';

class PaymentsService {
  // ─── Virtual Account ──────────────────────────────────────────────────────

  /// Returns { exists: bool, accountNumber?, bankName?, accountName? }
  Future<Map<String, dynamic>> getVirtualAccount() async {
    final res = await apiService.dio.get('/api/payments/virtual-account');
    return res.data as Map<String, dynamic>;
  }

  /// Creates a Flutterwave virtual account using the user's BVN.
  /// Returns { accountNumber, bankName, accountName }
  Future<Map<String, dynamic>> createVirtualAccount(String bvn) async {
    final res = await apiService.dio.post(
      '/api/payments/virtual-account',
      data: {'bvn': bvn},
    );
    return res.data as Map<String, dynamic>;
  }

  // ─── Banks ────────────────────────────────────────────────────────────────

  /// Returns list of { code, name } for all Nigerian banks.
  Future<List<Map<String, dynamic>>> getBanks() async {
    final res = await apiService.dio.get('/api/payments/flutterwave/banks');
    final List<dynamic> banks = res.data['banks'] ?? [];
    return banks.cast<Map<String, dynamic>>();
  }

  // ─── Resolve Account ──────────────────────────────────────────────────────

  /// Resolves an account number to an account name via Flutterwave.
  /// Returns { accountNumber, bankCode, accountName }
  Future<Map<String, dynamic>> resolveAccount({
    required String bankCode,
    required String accountNumber,
  }) async {
    final res = await apiService.dio.post(
      '/api/payments/flutterwave/resolve-account',
      data: {'bankCode': bankCode, 'accountNumber': accountNumber},
    );
    return res.data as Map<String, dynamic>;
  }

  // ─── Withdraw ─────────────────────────────────────────────────────────────

  /// Initiates an NGN bank withdrawal, debiting the user's NGNT balance.
  /// Returns { txRef, status, providerReference }
  Future<Map<String, dynamic>> withdraw({
    required double ngntAmount,
    required String bankCode,
    required String accountNumber,
    required String accountName,
    String? idempotencyKey,
  }) async {
    final res = await apiService.dio.post(
      '/api/payments/flutterwave/withdraw',
      data: {
        'ngntAmount':     ngntAmount,
        'bankCode':       bankCode,
        'accountNumber':  accountNumber,
        'accountName':    accountName,
        if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
      },
    );
    return res.data as Map<String, dynamic>;
  }

  // ─── Deposit (WebView flow — future) ──────────────────────────────────────

  /// Initiates a Flutterwave payment link for NGN deposit.
  /// Returns { txRef, paymentLink, status }
  Future<Map<String, dynamic>> initDeposit(double amount) async {
    final res = await apiService.dio.post(
      '/api/payments/flutterwave/init',
      data: {'amount': amount, 'currency': 'NGN'},
    );
    return res.data as Map<String, dynamic>;
  }

  /// Verifies a Flutterwave deposit by txRef.
  Future<Map<String, dynamic>> verifyDeposit(String txRef) async {
    final res = await apiService.dio.post(
      '/api/payments/flutterwave/verify',
      data: {'txRef': txRef},
    );
    return res.data as Map<String, dynamic>;
  }
}

final paymentsService = PaymentsService();