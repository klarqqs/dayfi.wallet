// lib/screens/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/main.dart';
import 'package:mobile_app/widgets/app_background.dart';
import 'package:mobile_app/widgets/app_bottomsheet.dart'
    show showDayFiBottomSheet;
import 'package:package_info_plus/package_info_plus.dart';
import '../../services/api_service.dart';
import '../home/home_screen.dart'; // for userProvider

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() => _appVersion = '${info.version} (${info.buildNumber})');
    } catch (_) {
      setState(() => _appVersion = '1.0.0');
    }
  }

  Future<void> _logout() async {
    await apiService.clearToken();
    context.go('/onboarding');
  }

  String _getThemeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'Device';
    }
  }

  void _showThemePicker(
    BuildContext context,
    WidgetRef ref,
    ThemeMode currentTheme,
  ) {
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Opacity(opacity: 0, child: Icon(Icons.close)),
                Text(
                  'Choose Theme',
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ThemeOption(
                  label: 'Light',
                  icon: Icons.light_mode,
                  isSelected: currentTheme == ThemeMode.light,
                  onTap: () {
                    ref.read(themeModeProvider.notifier).state =
                        ThemeMode.light;
                    Navigator.pop(context);
                  },
                ),
                _ThemeOption(
                  label: 'Dark',
                  icon: Icons.dark_mode,
                  isSelected: currentTheme == ThemeMode.dark,
                  onTap: () {
                    ref.read(themeModeProvider.notifier).state = ThemeMode.dark;
                    Navigator.pop(context);
                  },
                ),
                _ThemeOption(
                  label: 'Device',
                  icon: Icons.phone_iphone,
                  isSelected: currentTheme == ThemeMode.system,
                  onTap: () {
                    ref.read(themeModeProvider.notifier).state =
                        ThemeMode.system;
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userProvider);
    final themeMode = ref.watch(themeModeProvider);

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(
            'Settings',
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
              // ── Profile header ────────────────────────────
              userAsync
                  .when(
                    data: (u) => Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0),
                            Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.025),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '@${u['username'] ?? ''}',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 20,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            u['email'] ?? '',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w400,
                                  fontSize: 16,
                                  letterSpacing: -0.1,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          // const SizedBox(height: 8),

                          // Backup warning if not backed up
                          if (u['isBackedUp'] == false) ...[
                            const SizedBox(height: 14),
                            GestureDetector(
                              onTap: () => context.push('/security/phrase'),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SvgPicture.asset(
                                    "assets/icons/svgs/alert2.svg",
                                    color: const Color.fromARGB(
                                      255,
                                      232,
                                      172,
                                      9,
                                    ),
                                    height: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Backup your account to iCloud',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: const Color.fromARGB(
                                            255,
                                            232,
                                            172,
                                            9,
                                          ),
                                          fontSize: 14,
                                          letterSpacing: -0.2,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    loading: () => const SizedBox(
                      height: 80,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  )
                  .animate()
                  .fadeIn(),

              const SizedBox(height: 32),

              _SettingsTile(
                icon: "assets/icons/svgs/theme.svg",
                label: 'Theme',
                subtitle: _getThemeLabel(themeMode),
                onTap: () => _showThemePicker(context, ref, themeMode),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 10),

              _SettingsTile(
                icon: "assets/icons/svgs/faqs.svg",
                label: 'FAQs',
                subtitle: 'Frequently asked questions',
                onTap: () {},
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 10),
              _SettingsTile(
                icon: "assets/icons/svgs/app.svg",
                label: 'App Version',
                subtitle: _appVersion,
                onTap: () {},
                // showChevron: false,
              ).animate().fadeIn(delay: 220.ms),

              const SizedBox(height: 10),

              // ── Log out ───────────────────────────────────
              GestureDetector(
                onTap: _logout,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        "assets/icons/svgs/logout.svg",
                        height: 24,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.95),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Log out',
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
              ).animate().fadeIn(delay: 300.ms),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    this.subtitle,
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
              height: 24,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.95),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w400,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.95),
                  fontSize: 15,
                ),
              ),
            ),

            label == 'Theme'
                ? Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w400,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.95),
                      fontSize: 15,
                    ),
                  )
                : label == 'App Version'
                ? Text(
                    "v1.0.1 (build: 47)",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w400,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.95),
                      fontSize: 15,
                    ),
                  )
                : Icon(
                    Icons.chevron_right,
                    size: 24,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.85),
                  ),
          ],
        ),
      ),
    );
  }
}

// ─── ThemeOption Widget ───────────────────────────────────────

class _ThemeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                width: isSelected ? 2 : 1.5,
              ),
              color: Theme.of(
                context,
              ).textTheme.bodySmall?.color?.withOpacity(0.05),
            ),
            child: Icon(
              icon,
              size: 32,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              fontSize: 13,
              color: isSelected
                  ? Theme.of(context).colorScheme.onSurface.withOpacity(0.95)
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}
