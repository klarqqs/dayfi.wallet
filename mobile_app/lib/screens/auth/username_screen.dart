// lib/screens/auth/username_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_button.dart';
import '../../widgets/app_background.dart';
import 'dart:async';

class UsernameScreen extends StatefulWidget {
  final String setupToken;

  const UsernameScreen({super.key, required this.setupToken});

  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  bool _checking = false;
  bool? _available;
  String? _errorMsg;
  Timer? _debounce;

  // Wallet creation steps
  int _currentStep = 0;
  final List<String> _steps = [
    'Authenticating...',
    'Creating Stellar wallet...',
    'Funding your account...',
    'Adding USDC trustline...',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onUsernameChanged(String value) {
    _debounce?.cancel();
    setState(() {
      _available = null;
      _errorMsg = null;
    });

    if (value.length < 3) return;

    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
      setState(() => _errorMsg = 'Only letters, numbers, underscores');
      return;
    }

    _debounce = Timer(
      const Duration(milliseconds: 600),
      () => _checkUsername(value),
    );
  }

  Future<void> _checkUsername(String username) async {
    setState(() => _checking = true);
    try {
      final result = await apiService.checkUsername(username);
      if (mounted) {
        setState(() {
          _available = result['available'] == true;
          _errorMsg = _available == false
              ? (result['reason'] ?? 'Username taken')
              : null;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _continue() async {
    if (_loading) return;
    if (_available != true || _loading) return;
    setState(() => _loading = true);

    try {
      // Step 1: Authenticating
      setState(() => _currentStep = 0);
      await Future.delayed(const Duration(milliseconds: 500));

      // Step 2: Creating wallet
      setState(() => _currentStep = 1);

      // Main API call (does wallet creation + funding + trustlines)
      final result = await apiService.setupUsername(
        _controller.text.trim().toLowerCase(),
        widget.setupToken,
      );

      if (!mounted) return;

      // Step 3: Funding account
      setState(() => _currentStep = 2);
      await Future.delayed(const Duration(milliseconds: 600));

      // Step 4: Adding trustline
      setState(() => _currentStep = 3);
      await Future.delayed(const Duration(milliseconds: 800));

      // Complete
      await apiService.saveToken(result['token']);
      if (mounted) context.go('/auth/biometric');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(apiService.parseError(e)),
            backgroundColor: DayFiColors.red,
          ),
        );
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final username = _controller.text.trim();

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
                    child: InkWell(
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      onTap: () => context.pop(),
                      child: const Icon(Icons.arrow_back_ios, size: 20),
                    ),
                  ),

                const Spacer(flex: 1),

                // Title
                Text(
                  'Claim your dayfi.me username',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    fontSize: 36,
                    height: 1.09,
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, end: 0),
                const SizedBox(height: 18),

                Text(
                  'This will be your payment username. It\'s not an email address.',
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    fontSize: 16,
                    letterSpacing: -0.3,
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 100.ms, duration: 400.ms),

                const SizedBox(height: 32),

                // Username input
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autocorrect: false,
                        textInputAction: TextInputAction.done,
                        onChanged: _onUsernameChanged,
                        onSubmitted: (_) => _continue(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(.85),
                          fontSize: 15,
                          letterSpacing: -.1,
                        ),
                        decoration: InputDecoration(
                          hintText: 'yourname',
                          hintStyle: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(.35),
                                fontSize: 15,
                                letterSpacing: -.1,
                              ),
                          fillColor: Theme.of(
                            context,
                          ).textTheme.bodySmall?.color?.withOpacity(0.2),
                          filled: true,
                          errorText: _errorMsg,
                          suffixIcon: _checking
                              ? const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : _available == true
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14.0,
                                  ),
                                  child: SvgPicture.asset(
                                    "assets/icons/svgs/circle_check.svg",
                                    color: DayFiColors.green,
                                    height: 20,
                                  ),
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          disabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '@dayfi.me',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(.85),
                        fontSize: 15,
                        letterSpacing: -.1,
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

                const Spacer(flex: 4),

                // Continue button
                AuthButton(
                  label: 'Continue',
                  onPressed: _available == true ? _continue : null,
                  isLoading: _loading,
                  loadingText: _steps[_currentStep],
                  isValid: _available == true,
                ),

                const SizedBox(height: 16),

                // Terms agreement text
                Text.rich(
                  TextSpan(
                    text: 'By continuing, I agree to the ',
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                      letterSpacing: -.1,
                      fontSize: 12,
                      height: 1.4,
                    ),
                    children: [
                      TextSpan(
                        text: 'Terms of Service',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          decoration: TextDecoration.underline,
                          letterSpacing: -.1,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                      const TextSpan(text: ' & '),
                      TextSpan(
                        text: 'Privacy Statement',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          decoration: TextDecoration.underline,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.8),
                          letterSpacing: -.1,
                          fontSize: 12,
                        ),
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                  textAlign: TextAlign.center,
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
