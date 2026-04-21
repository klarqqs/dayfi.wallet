// lib/screens/auth/biometric_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/auth_button.dart';
import '../../widgets/app_background.dart';

class BiometricScreen extends StatefulWidget {
  const BiometricScreen({super.key});

  @override
  State<BiometricScreen> createState() => _BiometricScreenState();
}

class _BiometricScreenState extends State<BiometricScreen> {
  final _auth = LocalAuthentication();
  bool _loading = false;
  bool _available = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final can = await _auth.canCheckBiometrics;
      final sup = await _auth.isDeviceSupported();
      setState(() => _available = can && sup);
    } catch (_) {}
  }

  Future<void> _enable() async {
    setState(() => _loading = true);
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Enable Face ID to secure your wallet',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (ok && mounted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('faceIdEnabled', true);
        // Go to backup sheet
        context.go('/auth/backup');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Face ID setup failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _skip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('faceIdEnabled', false);
    if (mounted) context.go('/auth/backup');
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              // Back button (only if can pop)
              if (context.canPop())
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => context.pop(),
                    child: const Icon(Icons.arrow_back_ios, size: 20),
                  ),
                ),

              const Spacer(flex: 1),

              // Icon
              SvgPicture.asset(
                'assets/icons/svgs/faceid.svg',
                height: 80,
              ).animate().scale(delay: 100.ms),

              const SizedBox(height: 28),

              // Title
              Text(
                'Enable Face ID',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  height: 1.09,
                  fontSize: 36,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, end: 0),

              const SizedBox(height: 18),

              // Subtitle
              Text(
                'Use Face ID every time you open the app to keep your wallet secure.',
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  fontSize: 16,
                  letterSpacing: -0.3,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 100.ms, duration: 400.ms),

              const Spacer(flex: 4),

              // Continue button
              if (_available)
                AuthButton(
                  label: 'Enable Face ID',
                  onPressed: _enable,
                  isLoading: _loading,
                  loadingText: 'Setting up...',
                ).animate().fadeIn(delay: 400.ms),

              const SizedBox(height: 16),

              // Skip button
              TextButton(
                onPressed: _skip,
                child: Text(
                  'Not now',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ).animate().fadeIn(delay: 500.ms),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
