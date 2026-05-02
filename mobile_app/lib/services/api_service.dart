// lib/services/api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  static const String baseUrl = 'https://dayfiwallet-production.up.railway.app';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  late final Dio dio;

  ApiService() {
    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: 'auth_token');
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            await _storage.delete(key: 'auth_token');
          }
          handler.next(error);
        },
      ),
    );
  }

  // ─── Auth ────────────────────────────────────────────────
  Future<Map<String, dynamic>> sendOtp(String email) async =>
      (await dio.post('/api/auth/send-otp', data: {'email': email})).data;

  Future<Map<String, dynamic>> verifyOtp(String email, String otp) async =>
      (await dio.post(
        '/api/auth/verify-otp',
        data: {'email': email, 'otp': otp},
      )).data;

  Future<Map<String, dynamic>> checkUsername(String username) async =>
      (await dio.get('/api/auth/check-username/$username')).data;

  Future<Map<String, dynamic>> setupUsername(
    String username,
    String setupToken,
  ) async {
    final res = await dio.post(
      '/api/auth/setup-username',
      data: {'username': username, 'setupToken': setupToken},
    );
    if (res.data['token'] != null) await saveToken(res.data['token']);
    return res.data;
  }

  // ─── User ─────────────────────────────────────────────────
  Future<Map<String, dynamic>> getMe() async =>
      (await dio.get('/api/user/me')).data;

  Future<void> registerDeviceToken(String token, String platform) async =>
      dio.post(
        '/api/user/device-token',
        data: {'token': token, 'platform': platform},
      );

  // ─── Wallet ───────────────────────────────────────────────
  Future<Map<String, dynamic>> getBalance() async =>
      (await dio.get('/api/wallet/balance')).data;

  Future<Map<String, dynamic>> getAddress() async =>
      (await dio.get('/api/wallet/address')).data;

  Future<Map<String, dynamic>> getNetworkConfig() async =>
      (await dio.get('/api/wallet/networks')).data;

  Future<Map<String, dynamic>> sendFunds({
    required String to,
    required double amount,
    required String asset,
    String? memo,
  }) async => (await dio.post(
    '/api/wallet/send',
    data: {
      'to': to,
      'amount': amount,
      'asset': asset,
      if (memo != null) 'memo': memo,
    },
  )).data;

  Future<Map<String, dynamic>> resolveRecipient(String identifier) async =>
      (await dio.get('/api/wallet/resolve/$identifier')).data;

  // ─── Transactions ─────────────────────────────────────────
  Future<Map<String, dynamic>> getTransactions({
    int page = 1,
    int limit = 20,
    String? type,
    String? asset,
  }) async => (await dio.get(
    '/api/transactions',
    queryParameters: {
      'page': page,
      'limit': limit,
      if (type != null) 'type': type,
      if (asset != null) 'asset': asset,
    },
  )).data;

  // ─── SEP-38: Quotes ───────────────────────────────────────
  Future<Map<String, dynamic>> getQuote({
    required String sellAsset,
    required String buyAsset,
    double? sellAmount,
    double? buyAmount,
  }) async => (await dio.get(
    '/sep38/price',
    queryParameters: {
      'sell_asset': sellAsset,
      'buy_asset': buyAsset,
      if (sellAmount != null) 'sell_amount': sellAmount.toString(),
      if (buyAmount != null) 'buy_amount': buyAmount.toString(),
    },
  )).data;

  Future<Map<String, dynamic>> getPrices({
    required String sellAsset,
    required double sellAmount,
  }) async => (await dio.get(
    '/sep38/prices',
    queryParameters: {
      'sell_asset': sellAsset,
      'sell_amount': sellAmount.toString(),
    },
  )).data;

  // ─── SEP-24: Deposit / Withdraw ───────────────────────────
  Future<Map<String, dynamic>> initiateDeposit({
    required String assetCode,
    required String account,
    double? amount,
  }) async => (await dio.post(
    '/sep24/transactions/deposit/interactive',
    data: {
      'asset_code': assetCode,
      'account': account,
      if (amount != null) 'amount': amount.toString(),
    },
  )).data;

  Future<Map<String, dynamic>> initiateWithdraw({
    required String assetCode,
    required String account,
    double? amount,
  }) async => (await dio.post(
    '/sep24/transactions/withdraw/interactive',
    data: {
      'asset_code': assetCode,
      'account': account,
      if (amount != null) 'amount': amount.toString(),
    },
  )).data;

  Future<Map<String, dynamic>> getDepositStatus(String txId) async =>
      (await dio.get('/sep24/transaction', queryParameters: {'id': txId})).data;

  // ─── Swap ─────────────────────────────────────────────────
  Future<Map<String, dynamic>> getSwapQuote({
    required String fromAsset,
    required String toAsset,
    required double amount,
  }) async => (await dio.get(
    '/api/wallet/swap-quote',
    queryParameters: {
      'from': fromAsset,
      'to': toAsset,
      'amount': amount.toString(),
    },
  )).data;

  Future<Map<String, dynamic>> executeSwap({
    required String fromAsset,
    required String toAsset,
    required double amount,
  }) async => (await dio.post(
    '/api/wallet/swap',
    data: {'fromAsset': fromAsset, 'toAsset': toAsset, 'amount': amount},
  )).data;
  // // ─── User ────────────────────────────────────────────────
  // Future<Map<String, dynamic>> getMe() async =>
  //     (await _dio.get('/api/user/me')).data;

  Future<void> markBackedUp() async =>
      await dio.post('/api/auth/mark-backed-up');

  // ─── Wallet (add below getAddress) ───────────────────────────────────────────
  Future<List<String>> getMnemonic() async {
    final res = await dio.get('/api/auth/mnemonic');
    final List<dynamic> words = res.data['words'] ?? [];
    return words.cast<String>();
  }

  Future<Map<String, dynamic>> syncTransactionsFromBlockchain() async =>
      (await dio.post('/api/wallet/sync-transactions')).data;

  Future<Map<String, dynamic>> testFundWallet() async =>
      (await dio.post('/api/wallet/test-funding')).data;

  // ─── Token ────────────────────────────────────────────────
  Future<void> saveToken(String t) async =>
      _storage.write(key: 'auth_token', value: t);
  Future<String?> getToken() async => _storage.read(key: 'auth_token');
  Future<void> clearToken() async => _storage.delete(key: 'auth_token');

  String parseError(dynamic error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['error'] != null) return data['error'];
      if (data is Map && data['errors'] != null) {
        return (data['errors'] as List).map((e) => e['msg']).join(', ');
      }
      // Better error message for network errors
      if (error.type == DioExceptionType.badResponse) {
        return 'Server error: ${error.response?.statusCode ?? 'Unknown'}';
      }
      return error.message ?? 'Network error';
    }
    // Extract meaningful text from generic exceptions
    final errStr = error.toString();
    if (errStr.contains('not a function')) {
      return 'Server processing error - please try again';
    }
    if (errStr.contains('Insufficient')) {
      return errStr.split('\n')[0]; // First line only
    }
    return errStr.length > 100 ? '${errStr.substring(0, 97)}...' : errStr;
  }
}

final apiService = ApiService();
