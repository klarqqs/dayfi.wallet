import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

// ─── Auth State ───────────────────────────────────────────────────────────────

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final Map<String, dynamic>? user;
  final bool faceIdEnabled;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.faceIdEnabled = false,
    this.isLoading = false,
    this.error,
  });

  AuthState copyWith({
    AuthStatus? status,
    Map<String, dynamic>? user,
    bool? faceIdEnabled,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      faceIdEnabled: faceIdEnabled ?? this.faceIdEnabled,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// ─── Auth Notifier ────────────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AuthState> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  DateTime? _lastAuthTime;
  static const int _sessionTimeoutMinutes = 10;

  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  Future<void> _init() async {
    final token = await apiService.getToken();
    if (token == null) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final faceIdEnabled = prefs.getBool('face_id_enabled') ?? false;
      final user = await apiService.getMe();
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        faceIdEnabled: faceIdEnabled,
      );
    } catch (_) {
      await apiService.clearToken();
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> signIn(String token) async {
    await apiService.saveToken(token);
    try {
      final user = await apiService.getMe();
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> signOut() async {
    await apiService.clearToken();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<bool> enableFaceId() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) return false;

      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Enable Face ID for DayFi',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (authenticated) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('face_id_enabled', true);
        state = state.copyWith(faceIdEnabled: true);
      }

      return authenticated;
    } catch (_) {
      return false;
    }
  }

  Future<bool> disableFaceId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('face_id_enabled', false);
    state = state.copyWith(faceIdEnabled: false);
    return true;
  }

  Future<bool> authenticateWithFaceId() async {
    if (!state.faceIdEnabled) return true;
    
    // Check if session is still valid (within timeout)
    final now = DateTime.now();
    if (_lastAuthTime != null &&
        now.difference(_lastAuthTime!).inMinutes < _sessionTimeoutMinutes) {
      return true; // Session still valid, skip re-authentication
    }
    
    try {
      final result = await _localAuth.authenticate(
        localizedReason: 'Sign in to DayFi',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      
      if (result) {
        _lastAuthTime = now; // Record successful authentication time
      }
      
      return result;
    } catch (_) {
      return false;
    }
  }

  Future<void> refreshUser() async {
    try {
      final user = await apiService.getMe();
      state = state.copyWith(user: user);
    } catch (_) {}
  }
}

// ─── Providers ────────────────────────────────────────────────────────────────

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).status == AuthStatus.authenticated;
});

final currentUserProvider = Provider<Map<String, dynamic>?>((ref) {
  return ref.watch(authProvider).user;
});

final faceIdEnabledProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).faceIdEnabled;
});