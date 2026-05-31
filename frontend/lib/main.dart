import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/server_config.dart';
import 'core/navigation/router.dart';
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock to dark status/nav bar immediately — prevents white flash on Android
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF0A1628),
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A1628),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  // Phase 1: show splash standalone (no Riverpod needed yet — prevents any init delay)
  runApp(const _SplashApp());
}

// ── Phase 1: pure splash, no providers ───────────────────────────────────────
class _SplashApp extends StatefulWidget {
  const _SplashApp();
  @override
  State<_SplashApp> createState() => _SplashAppState();
}

class _SplashAppState extends State<_SplashApp> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    Future.wait([
      Future.delayed(const Duration(milliseconds: 2600)),
      ServerConfig.init(),
    ]).then((_) {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_done) {
      // During web/hot restart, Flutter forwards the current browser path as
      // the native initial route to this temporary splash MaterialApp.
      // onUnknownRoute absorbs any deep-link URL and shows the splash,
      // preventing "Could not navigate to initial route" warnings.
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        color: const Color(0xFF0A1628),
        home: const _SplashScreen(),
        onUnknownRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => const _SplashScreen(),
        ),
      );
    }
    // Phase 2: hand off to full Riverpod-powered app
    return const ProviderScope(child: _MainApp());
  }
}

// ── Phase 2: main router-based app ────────────────────────────────────────────
class _MainApp extends ConsumerWidget {
  const _MainApp();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router    = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'CyberZeus AMS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}

// ── CyberZeus splash screen ───────────────────────────────────────────────────
class _SplashScreen extends StatefulWidget {
  const _SplashScreen();
  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _textFade;
  late final Animation<double> _textSlide;
  late final Animation<double> _progressAnim;
  late final Animation<double> _bottomFade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();

    _logoFade  = _curved(0.00, 0.30);
    _logoScale = Tween<double>(begin: 0.75, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.00, 0.35, curve: Curves.easeOutBack)));
    _textFade  = _curved(0.28, 0.55);
    _textSlide = Tween<double>(begin: 14.0, end: 0.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.28, 0.55, curve: Curves.easeOut)));
    _progressAnim = _curved(0.45, 1.0);
    _bottomFade   = _curved(0.55, 0.80);
  }

  Animation<double> _curved(double start, double end) =>
      CurvedAnimation(parent: _ctrl, curve: Interval(start, end, curve: Curves.easeOut));

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, _) => Stack(
          children: [
            // ── Ambient glow orbs ───────────────────────────────────
            Positioned(
              top: -size.height * 0.12,
              left: -size.width * 0.25,
              child: Container(
                width: size.width * 0.7,
                height: size.width * 0.7,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x0A3D94F7),
                ),
              ),
            ),
            Positioned(
              bottom: -size.height * 0.1,
              right: -size.width * 0.2,
              child: Container(
                width: size.width * 0.6,
                height: size.width * 0.6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x0800C2FF),
                ),
              ),
            ),

            // ── Centre content ──────────────────────────────────────
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo card
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: Container(
                        width: 110, height: 110,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF0F1E38), Color(0xFF152844)],
                          ),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: const Color(0x583D94F7)),
                          boxShadow: const [
                            BoxShadow(color: Color(0x2E3D94F7), blurRadius: 40, spreadRadius: 2),
                            BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 16)),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Image.asset(
                            'assets/images/cyberzeus_logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const _FallbackCZIcon(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // App name
                  FadeTransition(
                    opacity: _textFade,
                    child: Transform.translate(
                      offset: Offset(0, _textSlide.value),
                      child: RichText(
                        text: const TextSpan(
                          style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                          children: [
                            TextSpan(text: 'Cyber', style: TextStyle(color: Color(0xFFEEF2FF))),
                            TextSpan(text: 'Zeus', style: TextStyle(color: Color(0xFF3D94F7))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),

                  // Sub-title
                  FadeTransition(
                    opacity: _textFade,
                    child: Transform.translate(
                      offset: Offset(0, _textSlide.value),
                      child: const Text(
                        'S O F T W A R E   S Y S T E M S',
                        style: TextStyle(
                          color: Color(0xFF4A6080),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3.0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 52),

                  // Progress bar
                  FadeTransition(
                    opacity: _progressAnim,
                    child: SizedBox(
                      width: 180,
                      height: 2,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: _progressAnim.value,
                          backgroundColor: const Color(0x263D94F7),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3D94F7)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Powered by (bottom) ──────────────────────────────────
            Positioned(
              bottom: 38,
              left: 0, right: 0,
              child: FadeTransition(
                opacity: _bottomFade,
                child: const Text(
                  'P O W E R E D   B Y   C Y B E R Z E U S',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF2A3F58),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FallbackCZIcon extends StatelessWidget {
  const _FallbackCZIcon();
  @override
  Widget build(BuildContext context) => const Center(
    child: Text('CZ',
      style: TextStyle(color: Color(0xFF3D94F7), fontSize: 30, fontWeight: FontWeight.w900)),
  );
}
