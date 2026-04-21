// lib/screens/auth/backup_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_button.dart';
import '../../widgets/app_background.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _loading = false;

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
                'assets/icons/svgs/alert.svg',
                height: 80,
                color: DayFiColors.green,
              ).animate().scale(delay: 100.ms),

              const SizedBox(height: 28),

              // Title
              Text(
                'Back up your wallet',
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
                'Save your 12-word recovery phrase. Without it, you cannot recover your wallet if you lose your phone.',
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  fontSize: 16,
                  letterSpacing: -0.3,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 100.ms, duration: 400.ms),

              const Spacer(flex: 4),

              // Continue button
              AuthButton(
                label: 'Back Up Now',
                onPressed: _loading
                    ? null
                    : () => context.push('/security/phrase'),
                isLoading: _loading,
                loadingText: 'Backing up...',
              ),

              const SizedBox(height: 16),

              // Skip button
              TextButton(
                onPressed: () => context.go('/home'),
                child: Text(
                  'Skip for now',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
