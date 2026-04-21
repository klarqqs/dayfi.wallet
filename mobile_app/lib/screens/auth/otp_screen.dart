// lib/screens/auth/otp_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_button.dart';
import '../../widgets/app_background.dart';
import 'dart:async';

class OtpScreen extends StatefulWidget {
  final String email;
  final bool isNewUser;

  const OtpScreen({super.key, required this.email, required this.isNewUser});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _pinController = TextEditingController();
  final _pinFocusNode = FocusNode();

  bool _loading = false;
  bool _resending = false;
  int _resendCountdown = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pinFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _resendCountdown = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendCountdown <= 0) {
        t.cancel();
      } else {
        setState(() => _resendCountdown--);
      }
    });
  }

  String get _otp => _pinController.text;

  Future<void> _verify() async {
    if (_otp.length < 6) return;
    setState(() => _loading = true);

    try {
      final result = await apiService.verifyOtp(widget.email, _otp);
      if (!mounted) return;

      final step = result['step'];

      if (step == 'setup_username') {
        context.push(
          '/auth/username',
          extra: {'setupToken': result['setupToken']},
        );
      } else if (step == 'complete') {
        await apiService.saveToken(result['token']);
        context.go('/home');
      } else {
        context.push('/auth/biometric');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(apiService.parseError(e)),
            backgroundColor: DayFiColors.red,
          ),
        );
        _pinController.clear();
        _pinFocusNode.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_loading) return;
    if (_resendCountdown > 0) return;
    setState(() => _resending = true);
    try {
      await apiService.sendOtp(widget.email);
      _startCountdown();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('New code sent!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiService.parseError(e))));
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final masked = widget.email.replaceRange(
      3,
      widget.email.indexOf('@'),
      '***',
    );

    // Match your original TextFormField styling
    final borderColor = Theme.of(
      context,
    ).colorScheme.onSurface.withOpacity(0.05);
    final focusedColor = Theme.of(context).colorScheme.primary;

    final defaultPinTheme = PinTheme(
      width: 50,
      height: 56,
      textStyle: Theme.of(context).textTheme.headlineMedium,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyWith(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: focusedColor, width: 1.5),
      ),
    );

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

                Text(
                  'Enter the 6-digit code',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -1,
                    height: 1.09,
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, end: 0),

                const SizedBox(height: 18),

                Text(
                  'Enter the code we\'ve sent to $masked',
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    fontSize: 17,
                    letterSpacing: -.5,
                    height: 1.3,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 100.ms, duration: 400.ms),

                const SizedBox(height: 32),

                // ── Pinput replaces the manual Row of TextFormFields ──
                Pinput(
                  length: 6,
                  controller: _pinController,
                  focusNode: _pinFocusNode,
                  defaultPinTheme: defaultPinTheme,
                  focusedPinTheme: focusedPinTheme,
                  showCursor: true,
                  // cursor: Column(
                  //   mainAxisAlignment: MainAxisAlignment.end,
                  //   children: [
                  //     Container(
                  //       margin: const EdgeInsets.only(bottom: 9),
                  //       width: 16,
                  //       height: 1.5,
                  //       decoration: BoxDecoration(
                  //         color: focusedColor,
                  //         borderRadius: BorderRadius.circular(8),
                  //       ),
                  //     ),
                  //   ],
                  // ),
                  // Drives the Continue button enable/disable + auto-submit
                  onChanged: (_) => setState(() {}),
                  onCompleted: (_) => _verify(),
                ).animate().fadeIn(delay: 200.ms),

                const SizedBox(height: 32),

                // Resend
                Center(
                  child: _resending
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : InkWell(
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          hoverColor: Colors.transparent,
                          onTap: _resendCountdown == 0 ? _resend : null,
                          child: Text.rich(
                            TextSpan(
                              text: _resendCountdown > 0
                                  ? 'Didn\'t get the code? Request a new one in '
                                  : 'Didn\'t get the code? ',
                              style: Theme.of(context).textTheme.bodySmall,
                              children: [
                                TextSpan(
                                  text: _resendCountdown > 0
                                      ? '00:${_resendCountdown.toString().padLeft(2, '0')}'
                                      : 'Resend',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: _resendCountdown == 0
                                            ? focusedColor
                                            : null,
                                        letterSpacing: -.1,
                                        fontSize: 12,
                                      ),
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                ),

                const Spacer(flex: 3),

                AuthButton(
                  label: 'Continue',
                  onPressed: _otp.length == 6 ? _verify : null,
                  isLoading: _loading,
                  loadingText: 'Verifying...',
                  isValid: _otp.length == 6,
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
