// lib/router.dart
import 'package:go_router/go_router.dart';
import 'package:mobile_app/screens/buy/buy_screen.dart';
import 'package:mobile_app/screens/portfolio/portfolio_screen.dart';
import 'package:mobile_app/screens/swap/swap_screen.dart';
import 'package:mobile_app/screens/auth/backup_screen.dart';
import 'package:mobile_app/screens/security/security_screen.dart';
import 'package:mobile_app/screens/security/recovery_phrase_screen.dart';
import 'package:mobile_app/screens/transactions/transactions_screen.dart';
import 'screens/auth/email_screen.dart';
import 'screens/auth/otp_screen.dart';
import 'screens/auth/username_screen.dart';
import 'screens/auth/biometric_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/receive/receive_screen.dart';
import 'screens/send/send_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'services/api_service.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  redirect: (context, state) async {
    final token = await apiService.getToken();
    final isAuth = token != null;
    final loc = state.matchedLocation;

    // These are allowed even when authenticated (post-signup flow)
    final isPostSignup = loc == '/auth/biometric' || loc == '/auth/backup';
    final isAuthRoute = loc.startsWith('/auth') && !isPostSignup;
    final isOnboarding = loc == '/onboarding';

    if (isAuth && (isAuthRoute || isOnboarding)) return '/home';
    if (!isAuth && !isAuthRoute && !isOnboarding && !isPostSignup)
      return '/onboarding';
    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      redirect: (_, __) async {
        final token = await apiService.getToken();
        return token != null ? '/home' : '/onboarding';
      },
    ),

    // Onboarding
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),

    // Auth
    GoRoute(
      path: '/auth/email',
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return EmailScreen(isNewUser: extra?['isNewUser'] ?? true);
      },
    ),
    GoRoute(
      path: '/auth/otp',
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>;
        return OtpScreen(
          email: extra['email'],
          isNewUser: extra['isNewUser'] ?? false,
        );
      },
    ),
    GoRoute(
      path: '/auth/username',
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>;
        return UsernameScreen(setupToken: extra['setupToken']);
      },
    ),
    GoRoute(
      path: '/auth/biometric',
      builder: (_, __) => const BiometricScreen(),
    ),
    GoRoute(path: '/auth/backup', builder: (_, __) => const BackupScreen()),

    // Main app
    GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
    GoRoute(
      path: '/receive',
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return ReceiveScreen(initialAsset: extra?['asset'] as String?);
      },
    ),
    GoRoute(
      path: '/send',
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return SendScreen(initialAsset: extra?['asset'] as String?);
      },
    ),

    GoRoute(path: '/buy', builder: (_, __) => const BuyScreen()),
    GoRoute(path: '/sell', builder: (_, __) => const SellScreen()),
    GoRoute(path: '/swap', builder: (_, __) => const SwapScreen()),
    GoRoute(
      path: '/transactions',
      builder: (_, __) => const TransactionsScreen(),
    ),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),

    // Security
    GoRoute(path: '/security', builder: (_, __) => const SecurityScreen()),
    GoRoute(
      path: '/security/phrase',
      builder: (_, __) => const RecoveryPhraseScreen(),
    ),

    GoRoute(path: '/portfolio', builder: (_, __) => const PortfolioScreen()),
  ],
);
