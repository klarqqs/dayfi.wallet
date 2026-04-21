// lib/screens/auth/email_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';
import '../../widgets/auth_button.dart';
import '../../widgets/app_background.dart';
// import '../../theme/app_theme.dart';

class EmailScreen extends StatefulWidget {
  final bool isNewUser;
  const EmailScreen({super.key, this.isNewUser = true});

  @override
  State<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends State<EmailScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final result = await apiService.sendOtp(_emailController.text.trim());
      if (mounted) {
        context.push(
          '/auth/otp',
          extra: {
            'email': _emailController.text.trim(),
            'isNewUser': result['isNewUser'] ?? false,
          },
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiService.parseError(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Form(
              key: _formKey,
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
                        widget.isNewUser
                            ? 'Enter your Email'
                            : 'Login with Email',
                        style: GoogleFonts.bricolageGrotesque(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -1,
                          height: 1.09,
                        ),
                        textAlign: TextAlign.center,
                      )
                      .animate()
                      .fadeIn(duration: 600.ms)
                      .slideY(begin: 0.2, end: 0),
                  const SizedBox(height: 18),

                  Text(
                    widget.isNewUser
                        ? 'If this email is new, we\'ll continue creating your wallet. If it already has a wallet, we\'ll help you sign in.'
                        : 'If this email already has an account, we\'ll proceed with login. If it\'s new, we\'ll start creating your wallet.',
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      fontSize: 17,
                      letterSpacing: -.5,
                      height: 1.3,
                      color: Theme.of(context).textTheme.bodyMedium?.color!,
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 100.ms, duration: 400.ms),

                  const SizedBox(height: 32),

                  // Email field
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _continue(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(.85),
                      fontSize: 15,
                      letterSpacing: -.1,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Type your Email',
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
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'Email required';
                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(val)) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
                  const Spacer(flex: 4),

                  // Continue button
                  AuthButton(
                    label: 'Continue',
                    onPressed: _continue,
                    isLoading: _loading,
                    loadingText: 'Authenticating...',
                    isValid: _emailController.text.isNotEmpty,
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
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
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
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
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
      ),
    );
  }
}
