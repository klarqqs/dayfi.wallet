// lib/main.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mobile_app/widgets/app_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'router.dart';
import 'providers/user_provider.dart';
import 'package:flutter/foundation.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

Future<void> _initFirebase(WidgetRef ref) async {
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);
  final token = await messaging.getToken();
  if (token != null) {
    await ref
        .read(userNotifierProvider.notifier)
        .registerDeviceToken(
          token,
          defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        );
  }
  messaging.onTokenRefresh.listen((newToken) {
    ref
        .read(userNotifierProvider.notifier)
        .registerDeviceToken(
          newToken,
          defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        );
  });
  FirebaseMessaging.onMessage.listen((msg) {
    debugPrint('FCM foreground: ${msg.notification?.title}');
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ProviderScope(child: DayFiApp()));
}

class DayFiApp extends ConsumerStatefulWidget {
  const DayFiApp({super.key});
  @override
  ConsumerState<DayFiApp> createState() => _DayFiAppState();
}

class _DayFiAppState extends ConsumerState<DayFiApp>
    with WidgetsBindingObserver {
  final _auth = LocalAuthentication();
  bool _blurred = false;
  bool _authenticating = false;
  DateTime? _lastAuthTime; // Track last successful authentication
  static const int _sessionTimeoutMinutes = 5; // Grace period before re-auth

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _initFirebase(ref);
      } catch (e) {
        debugPrint('Firebase: $e');
      }
      // Authenticate on first open if Face ID enabled and token valid
      await _tryAuthenticate();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      final prefs = await SharedPreferences.getInstance();
      final faceEnabled = prefs.getBool('faceIdEnabled') ?? false;
      if (faceEnabled) setState(() => _blurred = true);
    } else if (state == AppLifecycleState.resumed) {
      if (_blurred) {
        // Check if session has timed out
        final now = DateTime.now();
        final needsAuth =
            _lastAuthTime == null ||
            now.difference(_lastAuthTime!).inMinutes >= _sessionTimeoutMinutes;

        if (needsAuth) {
          await _tryAuthenticate();
        } else {
          // Session still valid, no Face ID needed
          if (mounted) setState(() => _blurred = false);
        }
      }
    }
  }

  Future<void> _tryAuthenticate() async {
    if (_authenticating) return;
    final prefs = await SharedPreferences.getInstance();
    final faceEnabled = prefs.getBool('faceIdEnabled') ?? false;
    if (!faceEnabled) {
      if (mounted) setState(() => _blurred = false);
      return;
    }

    _authenticating = true;
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Authenticate to open DayFi',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (ok) {
        // Record successful authentication time
        _lastAuthTime = DateTime.now();
        if (mounted) setState(() => _blurred = false);
      } else {
        if (mounted) setState(() => _blurred = true);
      }
    } catch (_) {
      if (mounted) setState(() => _blurred = true);
    } finally {
      _authenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'DayFi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: appRouter,
      builder: (context, child) {
        return Stack(
          children: [
            child ?? const SizedBox(),
            if (_blurred)
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  onTap: _tryAuthenticate,
                  child: AppBackground(
                    child: Scaffold(
                      backgroundColor: Colors.transparent,
                      body: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SvgPicture.asset(
                              'assets/icons/svgs/faceid.svg',
                              height: 64,
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(.85),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('themeMode');
    if (saved == 'light') state = ThemeMode.light;
    else if (saved == 'system') state = ThemeMode.system;
    else state = ThemeMode.dark; // default
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', mode.name); // 'light'/'dark'/'system'
  }
}
