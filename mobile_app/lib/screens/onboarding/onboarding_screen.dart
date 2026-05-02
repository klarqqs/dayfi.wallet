// lib/screens/onboarding/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // backgroundColor: DayFiColors.background,
      body: Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Spacer(flex: 1),

                    Opacity(
                      opacity: .45,
                      child: Image.asset(
                        "assets/images/word_logo.png",
                        width: 88,
                      ),
                    ),
                    const Spacer(flex: 2),

                    ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withOpacity(.8),
                          Colors.white.withOpacity(.1),
                        ],
                      ).createShader(bounds),
                      blendMode: BlendMode.modulate,
                      child: Image.asset(
                        "assets/images/stellar_onb.png",
                        width: 300,
                      ),
                    ),

                    // .animate().fadeIn(duration: 600.ms),
                    const Spacer(flex: 2),
                    // Headline
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                                'Naira, Digital Dollar\nand Native.',
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

                          const SizedBox(height: 24),
                          Text(
                            'The wallet designed for your business.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(height: 1.2, color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                          // .animate().fadeIn(delay: 200.ms, duration: 600.ms),
                          Text(
                            'Get your virtual account instantly and start getting paid today.',
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(height: 1.2),
                            textAlign: TextAlign.center,
                          ),
                          // .animate().fadeIn(delay: 200.ms, duration: 600.ms),
                        ],
                      ),
                    ),

                    const Spacer(flex: 2),

                    // Buttons
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          // Create wallet
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: Size(
                                  MediaQuery.of(context).size.width,
                                  48,
                                ),
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
                              onPressed: () => context.push(
                                '/auth/email',
                                extra: {'isNewUser': true},
                              ),
                              icon: SvgPicture.asset(
                                "assets/icons/svgs/wallet.svg",
                                height: 20,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(.90),
                              ),
                              label: Text(
                                'Create a New Account',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(.95),
                                      fontSize: 15,
                                    ),
                              ),
                            ),
                            // .animate().fadeIn(delay: 500.ms),
                          ),
                          const SizedBox(height: 8),

                          // Create wallet
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: Size(
                                  MediaQuery.of(context).size.width,
                                  48,
                                ),
                                side: BorderSide(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0),
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () => context.push(
                                '/auth/email',
                                extra: {'isNewUser': true},
                              ),
                              icon: RotatedBox(
                                quarterTurns: 1,
                                child: SvgPicture.asset(
                                  "assets/icons/svgs/login.svg",
                                  height: 20,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(.90),
                                ),
                              ),
                              label: Text(
                                'Log in to existing account',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(.95),
                                      fontSize: 15,
                                    ),
                              ),
                            ),
                            // .animate().fadeIn(delay: 500.ms),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
