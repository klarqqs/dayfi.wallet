// lib/screens/security/security_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mobile_app/widgets/app_background.dart';
import 'package:mobile_app/widgets/app_bottomsheet.dart';
import 'package:mobile_app/widgets/app_switch.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});
  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final _auth = LocalAuthentication();
  bool _faceIdEnabled = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _faceIdEnabled = prefs.getBool('faceIdEnabled') ?? false);
  }

  Future<void> _toggleFaceId(bool val) async {
    setState(() => _loading = true);
    try {
      final ok = await _auth.authenticate(
        localizedReason: val
            ? 'Enable Face ID for DayFi'
            : 'Confirm to disable Face ID',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (ok) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('faceIdEnabled', val);
        setState(() => _faceIdEnabled = val);
      }
    } catch (_) {
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDayFiBottomSheet<bool>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),

            // ── Title ──────────────────────────────────────
            const SizedBox(height: 24),
            // Center(
            //   child: Text(
            //     'Delete Account',
            //     style: Theme.of(context).textTheme.titleLarge?.copyWith(
            //       fontSize: 36,
            //       fontWeight: FontWeight.w700,
            //       color: Colors.white,
            //       letterSpacing: -1,
            //       height: 1.09,
            //     ),
            //     textAlign: TextAlign.center,
            //   ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, end: 0),
            // ),
            // const SizedBox(height: 18),

            // ── Body ───────────────────────────────────────
            Center(
              child: Text(
                'This will permanently delete your account and wallet. '
                'Make sure you have saved your recovery phrase before continuing.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 17,
                  letterSpacing: -.5,
                  height: 1.3,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),

            // ── Buttons ────────────────────────────────────
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: Size(MediaQuery.of(context).size.width, 50),
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
              onPressed: () => Navigator.pop(context, true),

              icon: SvgPicture.asset(
                "assets/icons/svgs/delete.svg",
                height: 20,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.90),
              ),
              label: Text(
                'Delete Account',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(.95),
                  fontSize: 15,
                ),
              ),
            ).animate().fadeIn(delay: 500.ms),

            const SizedBox(height: 8),

            // Create wallet
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0),
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () =>
                  context.push('/auth/email', extra: {'isNewUser': true}),

              label: Center(
                child: Text(
                  'Cancel',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(.95),
                    fontSize: 15,
                  ),
                ),
              ),
            ).animate().fadeIn(delay: 500.ms),
          ],
        ),
      ),
    );

    if (confirm == true && mounted) {
      await apiService.clearToken();
      context.go('/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(
            'Security',
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
            onTap: () => context.pop(),
            child: const Icon(Icons.arrow_back_ios, size: 20),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            children: [
              // ── Recovery Phrase ──────────────────────────
              _SettingsTile(
                icon: "assets/icons/svgs/key.svg",
                label: 'Recovery Phrase',
                subtitle: '12-word backup phrase',
                onTap: () => context.push('/security/phrase'),
              ).animate().fadeIn(delay: 100.ms),

              const SizedBox(height: 10),

              // ── Face ID ──────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).textTheme.bodySmall?.color?.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  // border: Border.all(
                  //   color: Theme.of(
                  //     context,
                  //   ).colorScheme.onSurface.withOpacity(0.08),
                  // ),
                ),
                child: Row(
                  children: [
                    SvgPicture.asset(
                      "assets/icons/svgs/faceid.svg",
                      height: 24,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.95),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Face ID',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w400,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.95),
                                ),
                          ),
                        ],
                      ),
                    ),
                    _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : DayFiSwitch(
                            value: _faceIdEnabled,
                            onChanged: _toggleFaceId,
                          ),
                  ],
                ),
              ).animate().fadeIn(delay: 150.ms),

              const SizedBox(height: 10),

              // ── Danger zone ──────────────────────────────
              _SettingsTile(
                icon: "assets/icons/svgs/delete.svg",
                label: 'Delete Account',
                subtitle: 'Permanently remove your account',
                iconColor: DayFiColors.red,
                onTap: _deleteAccount,
              ).animate().fadeIn(delay: 200.ms),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Settings Screen ──────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    ),
  );
}

class _SettingsTile extends StatelessWidget {
  final String icon;
  final String label;
  final String? subtitle;
  final Color? iconColor;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.1),
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              icon,
              height: 22,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.85),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w400,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.95),
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 24,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.85),
            ),
          ],
        ),
      ),
    );
  }
}
