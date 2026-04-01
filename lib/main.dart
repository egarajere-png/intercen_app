// lib/main.dart

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ── Core pages ────────────────────────────────────────────────────────────────
import 'pages/homepage.dart';
import 'pages/books.dart';
import 'pages/book_detail_page.dart';
import 'pages/splashscreen.dart';
import 'pages/cart.dart';
import 'pages/checkout_page.dart';

// ── Auth pages ────────────────────────────────────────────────────────────────
import 'pages/auth/login_page.dart';
import 'pages/auth/signup_page.dart';
import 'pages/auth/reset_passwordpage.dart';
import 'pages/auth/otp_page.dart';
import 'pages/auth/confirm_passpage.dart';

// ── Feature pages ─────────────────────────────────────────────────────────────
import 'pages/profile_setup_page.dart';
import 'pages/settingsPage.dart';
import 'pages/content_management_page.dart';
import 'pages/publish_with_us.dart';
import 'pages/about_page.dart';
import 'pages/notifications_page.dart';
import 'pages/publication_requests_page.dart';

// ── Admin-only content pages ──────────────────────────────────────────────────
import 'pages/content_upload_page.dart';
import 'pages/content_view_page.dart';
import 'pages/content_update_page.dart';

// ── Role dashboards ───────────────────────────────────────────────────────────
import 'pages/dashboard/admin_dashboard.dart';
import 'pages/dashboard/author_dashboard.dart';
import 'pages/dashboard/reader_dashboard.dart';

// ── Services & theme ──────────────────────────────────────────────────────────
import 'services/role_service.dart';
import 'theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GLOBAL KEYS
// ─────────────────────────────────────────────────────────────────────────────

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

// ─────────────────────────────────────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exception}');
      debugPrintStack(stackTrace: details.stack);
    };

    await Supabase.initialize(
      url: 'https://nnljrawwhibazudjudht.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5ubGpyYXd3aGliYXp1ZGp1ZGh0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkwNjc1ODQsImV4cCI6MjA4NDY0MzU4NH0.wMMeffZGj7mbStjglTE5ZOknO-QKjX9aAG1xcjKBl5c',
    );

    DeepLinkService.init();
    runApp(const IntercenApp());
  }, (Object error, StackTrace stack) {
    debugPrint('Uncaught zone error: $error');
    debugPrintStack(stackTrace: stack);
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// DEEP LINK SERVICE
// ─────────────────────────────────────────────────────────────────────────────

class DeepLinkService {
  DeepLinkService._();

  static final AppLinks _appLinks = AppLinks();
  static StreamSubscription<Uri>? _sub;

  static Uri? _pendingUri;
  static bool _navigatorReady = false;

  static void init() {
    _appLinks.getInitialLink().then((Uri? uri) {
      if (uri != null) {
        debugPrint('[DeepLink] Cold-start URI: $uri');
        _handleOrQueue(uri);
      }
    }).catchError((Object e) {
      debugPrint('[DeepLink] getInitialLink error: $e');
    });

    _sub?.cancel();
    _sub = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        debugPrint('[DeepLink] Foreground URI: $uri');
        _handleOrQueue(uri);
      },
      onError: (Object e) {
        debugPrint('[DeepLink] Stream error: $e');
      },
    );
  }

  static void markNavigatorReady() {
    _navigatorReady = true;
    if (_pendingUri != null) {
      final Uri uri = _pendingUri!;
      _pendingUri = null;
      _handle(uri);
    }
  }

  static void dispose() {
    _sub?.cancel();
    _sub = null;
    _pendingUri = null;
    _navigatorReady = false;
  }

  static void _handleOrQueue(Uri uri) {
    if (!_navigatorReady || navigatorKey.currentState == null) {
      _pendingUri = uri;
      return;
    }
    _handle(uri);
  }

  static void _handle(Uri uri) {
    if (uri.scheme != 'intercen') return;

    switch (uri.host) {
      case 'payment-callback':
        _handlePaymentCallback(uri);
        break;
      default:
        debugPrint('[DeepLink] Unhandled host: ${uri.host}');
    }
  }

  static void _handlePaymentCallback(Uri uri) {
    final String orderId = uri.queryParameters['order_id'] ?? '';
    final String orderNumber = uri.queryParameters['order_number'] ?? '';

    debugPrint('[DeepLink] payment-callback -> orderId: $orderId');

    if (orderId.isEmpty) return;

    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/payment-success',
      (_) => false,
      arguments: <String, String>{
        'order_id': orderId,
        'order_number': orderNumber,
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APP
// ─────────────────────────────────────────────────────────────────────────────

class IntercenApp extends StatefulWidget {
  const IntercenApp({super.key});

  @override
  State<IntercenApp> createState() => _IntercenAppRootState();
}

class _IntercenAppRootState extends State<IntercenApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkService.markNavigatorReady();
    });
  }

  @override
  void dispose() {
    DeepLinkService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: 'Intercen Book Store',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'PlayfairDisplay',
        scaffoldBackgroundColor: const Color(0xFFF9F5EF),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB11226),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFB11226),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: Colors.black,
              displayColor: Colors.black,
            ),
      ),
      home: const AppEntryGate(),
      routes: <String, WidgetBuilder>{
        '/onboarding': (_) => const OnboardingPage(),
        '/login': (_) => const LoginPage(),
        '/signup': (_) => const SignUpPage(),
        '/reset-password': (_) => const ResetPasswordPage(),
        '/otp': (_) => const OtpPage(),
        '/confirm-password': (_) => const ConfirmPasswordPage(),
        '/home': (_) => const AuthGuard(child: Shell()),
        '/dashboard/admin': (_) => const AuthGuard(child: AdminDashboardPage()),
        '/dashboard/author': (_) =>
            const AuthGuard(child: AuthorDashboardPage()),
        '/dashboard/reader': (_) =>
            const AuthGuard(child: ReaderDashboardPage()),
        '/books': (_) => const AuthGuard(child: BooksPage()),
        '/book-detail': (_) => const AuthGuard(child: BookDetailPage()),
        '/cart': (_) => const AuthGuard(child: CartPage()),
        '/checkout': (_) => const AuthGuard(child: CheckoutFlowPage()),
        '/about': (_) => const AboutPage(),
        '/profile': (_) => const AuthGuard(child: SettingsPage()),
        '/settings': (_) => const AuthGuard(child: SettingsPage()),
        '/profile-setup': (_) => const AuthGuard(child: ProfileSetupPage()),
        '/notifications': (_) => const AuthGuard(child: NotificationsPage()),
        '/publication-requests': (_) =>
            const AuthGuard(child: PublicationRequestsPage()),
        '/publish': (_) => const PublishWithUsPage(),
        '/content-management': (_) =>
            const AdminGuard(child: ContentManagementPage()),
        '/upload': (_) => const AdminGuard(child: ContentUploadPage()),
      },
      onGenerateRoute: _buildGeneratedRoute,
    );
  }

  Route<dynamic> _buildGeneratedRoute(RouteSettings settings) {
    final String name = settings.name ?? '';

    if (RegExp(r'^/checkout/payment').hasMatch(name)) {
      final Object? args = settings.arguments;
      String orderId = '';

      if (args is Map<String, dynamic>) {
        orderId = args['order_id'] as String? ?? '';
      } else if (args is String) {
        orderId = args;
      }

      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => AuthGuard(
          child: CheckoutPaymentPage(orderId: orderId),
        ),
      );
    }

    if (name == '/paystack-webview') {
      final Map<String, dynamic> args =
          settings.arguments as Map<String, dynamic>? ?? <String, dynamic>{};

      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => PaystackLaunchPage(
          url: args['url'] as String? ?? '',
          orderId: args['order_id'] as String? ?? '',
          orderNumber: args['order_number'] as String? ?? '',
        ),
      );
    }

    if (name == '/payment-success') {
      final Map<String, dynamic> args =
          settings.arguments as Map<String, dynamic>? ?? <String, dynamic>{};

      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => PaymentSuccessPage(
          orderId: args['order_id'] as String? ?? '',
          orderNumber: args['order_number'] as String? ?? '',
        ),
      );
    }

    if (name == '/payment-failure') {
      final Map<String, dynamic> args =
          settings.arguments as Map<String, dynamic>? ?? <String, dynamic>{};

      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => PaymentFailurePage(
          orderId: args['order_id'] as String? ?? '',
          orderNumber: args['order_number'] as String? ?? '',
        ),
      );
    }

    final RegExpMatch? contentUpdateMatch =
        RegExp(r'^/content/update/(.+)$').firstMatch(name);
    if (contentUpdateMatch != null) {
      final String contentId = contentUpdateMatch.group(1) ?? '';
      return MaterialPageRoute<void>(
        settings: RouteSettings(name: name, arguments: contentId),
        builder: (_) => const AdminGuard(child: ContentUpdatePage()),
      );
    }

    final RegExpMatch? contentMatch =
        RegExp(r'^/content(?:-view)?/(.+)$').firstMatch(name);
    if (contentMatch != null) {
      final String contentId = contentMatch.group(1) ?? '';
      return MaterialPageRoute<void>(
        settings: RouteSettings(name: name, arguments: contentId),
        builder: (_) => const AdminGuard(child: ContentViewPage()),
      );
    }

    final RegExpMatch? bookMatch =
        RegExp(r'^/book-detail/(.+)$').firstMatch(name);
    if (bookMatch != null) {
      final String bookId = bookMatch.group(1) ?? '';
      return MaterialPageRoute<void>(
        settings: RouteSettings(name: name, arguments: bookId),
        builder: (_) => const AuthGuard(child: BookDetailPage()),
      );
    }

    return MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: const Color(0xFFF9F5EF),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: Builder(
            builder: (BuildContext ctx) => IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 20,
                color: Color(0xFF1A1A2E),
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(
                  Icons.explore_off_rounded,
                  size: 64,
                  color: Color(0xFFD1D5DB),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Page Not Found',
                  style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 12,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
                const SizedBox(height: 28),
                Builder(
                  builder: (BuildContext ctx) => ElevatedButton(
                    onPressed: () => Navigator.pushNamedAndRemoveUntil(
                      ctx,
                      '/home',
                      (_) => false,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Go to Home',
                      style: TextStyle(fontFamily: 'DM Sans'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APP ENTRY GATE
// ─────────────────────────────────────────────────────────────────────────────

class AppEntryGate extends StatefulWidget {
  const AppEntryGate({super.key});

  @override
  State<AppEntryGate> createState() => _AppEntryGateStateSafe();
}

class _AppEntryGateStateSafe extends State<AppEntryGate> {
  late final StreamSubscription<AuthState> _authSub;
  Session? _session;

  @override
  void initState() {
    super.initState();
    _session = Supabase.instance.client.auth.currentSession;

    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
      (AuthState data) {
        if (!mounted) return;

        setState(() {
          _session = data.session;
        });

        if (data.session == null) {
          RoleService.instance.clear();
        }
      },
    );
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_session != null) {
      return const _RoleGate();
    }
    return const OnboardingPage();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ROLE GATE
// ─────────────────────────────────────────────────────────────────────────────

class _RoleGate extends StatefulWidget {
  const _RoleGate();

  @override
  State<_RoleGate> createState() => _RoleGateStateSafe();
}

class _RoleGateStateSafe extends State<_RoleGate> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      await RoleService.instance.load();
    } catch (e) {
      debugPrint('[RoleGate] Failed to load role: $e');
    }

    if (!mounted || _navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F5EF),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Image.asset(
              'lib/assets/intercenlogo.png',
              height: 56,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.menu_book_rounded,
                size: 56,
                color: Color(0xFFB11226),
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(Color(0xFFB11226)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AUTH GUARD
// ─────────────────────────────────────────────────────────────────────────────

class AuthGuard extends StatefulWidget {
  final Widget child;

  const AuthGuard({super.key, required this.child});

  @override
  State<AuthGuard> createState() => _AuthGuardStateSafe();
}

class _AuthGuardStateSafe extends State<AuthGuard> {
  bool _redirecting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final Session? session = Supabase.instance.client.auth.currentSession;
    if (session == null && !_redirecting) {
      _redirecting = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/onboarding',
          (_) => false,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Session? session = Supabase.instance.client.auth.currentSession;

    if (session == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF9F5EF),
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(Color(0xFFB11226)),
          ),
        ),
      );
    }

    return widget.child;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN GUARD
// ─────────────────────────────────────────────────────────────────────────────

class AdminGuard extends StatefulWidget {
  final Widget child;

  const AdminGuard({super.key, required this.child});

  @override
  State<AdminGuard> createState() => _AdminGuardStateSafe();
}

class _AdminGuardStateSafe extends State<AdminGuard> {
  bool _checking = true;
  bool _allowed = false;
  bool _redirected = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final Session? session = Supabase.instance.client.auth.currentSession;

    if (session == null) {
      _redirectTo('/onboarding');
      return;
    }

    try {
      await RoleService.instance.load();
      final String? role = RoleService.instance.role;

      if (role != 'admin') {
        _redirectTo(
          '/home',
          snackBar: SnackBar(
            content: const Text(
              'Access denied. Admin only.',
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: const Color(0xFFB11226),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _checking = false;
        _allowed = true;
      });
    } catch (e) {
      debugPrint('[AdminGuard] Role check error: $e');
      _redirectTo('/home');
    }
  }

  void _redirectTo(String route, {SnackBar? snackBar}) {
    if (_redirected) return;
    _redirected = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil(route, (_) => false);

      if (snackBar != null) {
        scaffoldMessengerKey.currentState?.showSnackBar(snackBar);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking || !_allowed) {
      return Scaffold(
        backgroundColor: const Color(0xFFF9F5EF),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFB11226).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  size: 32,
                  color: Color(0xFFB11226),
                ),
              ),
              const SizedBox(height: 20),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation(Color(0xFFB11226)),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Verifying access...',
                style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return widget.child;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHELL
// ─────────────────────────────────────────────────────────────────────────────

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellStateSafe();
}

class _ShellStateSafe extends State<Shell> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const HomePage(),
      bottomNavigationBar: _AppBottomNav(
        currentIndex: 0,
        onHome: () {},
        onBooks: () => Navigator.pushNamed(context, '/books'),
        onCart: () => Navigator.pushNamed(context, '/cart'),
        onProfile: () => Navigator.pushNamed(context, '/settings'),
      ),
    );
  }
}

class _AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final VoidCallback onHome;
  final VoidCallback onBooks;
  final VoidCallback onCart;
  final VoidCallback onProfile;

  const _AppBottomNav({
    required this.currentIndex,
    required this.onHome,
    required this.onBooks,
    required this.onCart,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: Color(0xFFE5E7EB)),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          _NavItem(
            icon: Icons.home_outlined,
            label: 'Home',
            active: currentIndex == 0,
            onTap: onHome,
          ),
          _NavItem(
            icon: Icons.menu_book_outlined,
            label: 'Books',
            active: currentIndex == 1,
            onTap: onBooks,
          ),
          _NavItem(
            icon: Icons.shopping_cart_outlined,
            label: 'Cart',
            active: false,
            onTap: onCart,
          ),
          _NavItem(
            icon: Icons.person_outline,
            label: 'Profile',
            active: false,
            onTap: onProfile,
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = active ? const Color(0xFFB11226) : Colors.grey;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 11,
              color: color,
              fontWeight: active ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PAYSTACK LAUNCH PAGE
// ═════════════════════════════════════════════════════════════════════════════

class PaystackLaunchPage extends StatefulWidget {
  final String url;
  final String orderId;
  final String orderNumber;

  const PaystackLaunchPage({
    super.key,
    required this.url,
    required this.orderId,
    required this.orderNumber,
  });

  @override
  State<PaystackLaunchPage> createState() => _PaystackLaunchScreenState();
}

class _PaystackLaunchScreenState extends State<PaystackLaunchPage>
    with WidgetsBindingObserver {
  final SupabaseClient _sb = Supabase.instance.client;

  Timer? _pollTimer;
  Timer? _pollTimeout;

  bool _polling = false;
  bool _timedOut = false;
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _launch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPoll();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _polling && !_confirmed) {
      _checkNow();
    }
  }

  Future<void> _launch() async {
    final Uri uri = Uri.parse(widget.url);

    final bool ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!ok && mounted) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Could not open payment page.')),
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      _polling = true;
    });

    _startPoll();
  }

  void _startPoll() {
    _stopPoll();

    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _checkNow(),
    );

    _pollTimeout = Timer(const Duration(minutes: 3), () {
      _stopPoll();
      if (!mounted) return;
      setState(() {
        _timedOut = true;
        _polling = false;
      });
    });
  }

  Future<void> _checkNow() async {
    if (_confirmed || !mounted) return;

    try {
      final dynamic data = await _sb
          .from('orders')
          .select('payment_status, order_number')
          .eq('id', widget.orderId)
          .single();

      if (data['payment_status'] == 'paid') {
        _confirmed = true;
        _stopPoll();
        _goSuccess(
          widget.orderId,
          data['order_number'] as String? ?? widget.orderNumber,
        );
      }
    } catch (e) {
      debugPrint('[PaystackLaunch] Poll error: $e');
    }
  }

  void _stopPoll() {
    _pollTimer?.cancel();
    _pollTimeout?.cancel();
    _pollTimer = null;
    _pollTimeout = null;
  }

  void _goSuccess(String id, String num) {
    if (!mounted) return;

    Navigator.pushNamedAndRemoveUntil(
      context,
      '/payment-success',
      (_) => false,
      arguments: <String, String>{
        'order_id': id,
        'order_number': num,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: Color(0xFF1A1A2E),
          ),
          onPressed: () {
            _stopPoll();
            Navigator.pop(context);
          },
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Paystack Payment',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            Text(
              'Complete payment in your browser',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5E7EB)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 90,
              height: 90,
              decoration: const BoxDecoration(
                color: Color(0xFFEFF6FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.open_in_browser_rounded,
                size: 44,
                color: Color(0xFF2563EB),
              ),
            ),
            const SizedBox(height: 28),
            if (!_timedOut) ...<Widget>[
              const Text(
                'Payment Page Opened',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Complete your payment in the browser.\n\n'
                'This screen will automatically update once your '
                'payment is confirmed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                  height: 1.65,
                ),
              ),
              const SizedBox(height: 32),
              if (_polling)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Color(0xFF16A34A)),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Waiting for payment confirmation...',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(widget.url),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                label: const Text('Reopen Payment Page'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2563EB),
                  side: const BorderSide(color: Color(0xFF2563EB)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _checkNow,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text("I've completed payment — check now"),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6B7280),
                ),
              ),
            ] else ...<Widget>[
              const Text(
                'Payment Not Confirmed',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "We haven't received confirmation yet.\n"
                "If you completed the payment it may still be "
                "processing.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                  height: 1.65,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _timedOut = false;
                      _polling = true;
                    });
                    _startPoll();
                    launchUrl(
                      Uri.parse(widget.url),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/orders'),
                  icon: const Icon(Icons.list_alt_rounded, size: 18),
                  label: const Text('Check My Orders'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280),
                    side: const BorderSide(color: Color(0xFFD1D5DB)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Go Back',
                  style: TextStyle(color: Color(0xFF6B7280)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PAYMENT SUCCESS PAGE
// ═════════════════════════════════════════════════════════════════════════════

class PaymentSuccessPage extends StatelessWidget {
  final String orderId;
  final String orderNumber;

  const PaymentSuccessPage({
    super.key,
    required this.orderId,
    required this.orderNumber,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (_, double v, Widget? child) =>
                    Transform.scale(scale: v, child: child),
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF0FDF4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF16A34A),
                    size: 70,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Payment Successful!',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Your order has been placed and your payment confirmed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: <Widget>[
                    _DetailRow(
                      'Order Number',
                      orderNumber.isNotEmpty ? orderNumber : '—',
                    ),
                    const Divider(height: 20),
                    _DetailRow(
                      'Order ID',
                      orderId.length > 8
                          ? '…${orderId.substring(orderId.length - 8)}'
                          : orderId,
                    ),
                    const Divider(height: 20),
                    const _DetailRow(
                      'Status',
                      'Confirmed',
                      valueColor: Color(0xFF16A34A),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/books',
                    (_) => false,
                  ),
                  icon: const Icon(Icons.shopping_bag_outlined, size: 20),
                  label: const Text(
                    'Continue Shopping',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/orders'),
                child: const Text(
                  'View Order Details',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow(
    this.label,
    this.value, {
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF6B7280),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor ?? const Color(0xFF111827),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PAYMENT FAILURE PAGE
// ═════════════════════════════════════════════════════════════════════════════

class PaymentFailurePage extends StatelessWidget {
  final String orderId;
  final String orderNumber;

  const PaymentFailurePage({
    super.key,
    required this.orderId,
    required this.orderNumber,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (_, double v, Widget? child) =>
                    Transform.scale(scale: v, child: child),
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.cancel_rounded,
                    color: AppColors.primary,
                    size: 70,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Payment Failed',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Something went wrong while processing your payment.\n'
                'No charges were made to your account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  border: Border.all(color: const Color(0xFFFECACA)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.error_outline_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Please try again or choose a different '
                        'payment method.',
                        style: TextStyle(
                          color: Color(0xFF991B1B),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/checkout/payment',
                    (_) => false,
                    arguments: <String, String>{'order_id': orderId},
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: const Text(
                    'Retry Payment',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/home',
                  (_) => false,
                ),
                child: const Text(
                  'Back to Home',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// CHECKOUT PAYMENT PAGE
// ═════════════════════════════════════════════════════════════════════════════

class _CpOrderItem {
  final String id;
  final String contentId;
  final String title;
  final String author;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
  final String? coverImageUrl;

  _CpOrderItem({
    required this.id,
    required this.contentId,
    required this.title,
    required this.author,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.coverImageUrl,
  });

  factory _CpOrderItem.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> content =
        (json['content'] as Map<String, dynamic>?) ?? <String, dynamic>{};

    return _CpOrderItem(
      id: json['id'] as String? ?? '',
      contentId: json['content_id'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
      totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0,
      title: content['title'] as String? ?? 'Unknown',
      author: content['author'] as String? ?? '',
      coverImageUrl: content['cover_image_url'] as String?,
    );
  }
}

class _CpOrder {
  final String id;
  final String orderNumber;
  final String status;
  final String paymentStatus;
  final String shippingAddress;
  final String createdAt;
  final double totalPrice;
  final double subTotal;
  final double tax;
  final double shipping;
  final double discount;
  final List<_CpOrderItem> items;

  _CpOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.paymentStatus,
    required this.shippingAddress,
    required this.createdAt,
    required this.totalPrice,
    required this.subTotal,
    required this.tax,
    required this.shipping,
    required this.discount,
    required this.items,
  });

  factory _CpOrder.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawItems =
        (json['order_items'] as List<dynamic>?) ?? <dynamic>[];

    return _CpOrder(
      id: json['id'] as String? ?? '',
      orderNumber: json['order_number'] as String? ?? '—',
      totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0,
      subTotal: (json['sub_total'] as num?)?.toDouble() ?? 0,
      tax: (json['tax'] as num?)?.toDouble() ?? 0,
      shipping: (json['shipping'] as num?)?.toDouble() ?? 0,
      discount: (json['discount'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? 'pending',
      paymentStatus: json['payment_status'] as String? ?? 'pending',
      shippingAddress: json['shipping_address'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      items: rawItems
          .map((dynamic e) => _CpOrderItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

enum _PaymentMethod { none, paystack, mpesa }

enum _MpesaStep { idle, promptSent, timedOut }

class CheckoutPaymentPage extends StatefulWidget {
  final String orderId;

  const CheckoutPaymentPage({super.key, required this.orderId});

  @override
  State<CheckoutPaymentPage> createState() => _CheckoutPaymentScreenState();
}

class _CheckoutPaymentScreenState extends State<CheckoutPaymentPage>
    with SingleTickerProviderStateMixin {
  final SupabaseClient _sb = Supabase.instance.client;

  _CpOrder? _order;
  bool _loading = true;
  bool _processing = false;
  String? _error;
  _PaymentMethod _method = _PaymentMethod.none;
  _MpesaStep _mpesaStep = _MpesaStep.idle;

  final TextEditingController _phoneCtrl = TextEditingController();
  Timer? _pollTimer;
  Timer? _pollTimeout;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fetchOrder();
  }

  @override
  void dispose() {
    _stopPoll();
    _phoneCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchOrder() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final Session? session = _sb.auth.currentSession;
      if (session == null) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
        return;
      }

      final dynamic data = await _sb.from('orders').select('''
*, order_items(id,content_id,quantity,unit_price,total_price,
content:content_id(title,author,cover_image_url))
''').eq('id', widget.orderId).eq('user_id', session.user.id).single();

      final _CpOrder order = _CpOrder.fromJson(data as Map<String, dynamic>);

      if (order.paymentStatus == 'paid') {
        _goSuccess(order.id, order.orderNumber);
        return;
      }

      if (!mounted) return;

      setState(() {
        _order = order;
      });
      _fadeCtrl.forward();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Order not found or failed to load.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _payPaystack() async {
    if (_order == null) return;

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final Session? session = _sb.auth.currentSession;
      if (session == null) throw Exception('Session expired.');

      final FunctionResponse response = await _sb.functions.invoke(
        'checkout-process-payment',
        body: <String, dynamic>{
          'order_id': _order!.id,
          'platform': 'mobile',
        },
        headers: <String, String>{
          'Authorization': 'Bearer ${session.accessToken}',
        },
      );

      if (response.status != 200) {
        throw Exception((response.data as Map?)?['error'] ?? 'Failed');
      }

      final String? url =
          (response.data as Map?)?['authorization_url'] as String?;

      if (url == null || url.isEmpty) {
        throw Exception('No payment URL received');
      }

      if (!mounted) return;

      Navigator.pushNamed(
        context,
        '/paystack-webview',
        arguments: <String, String>{
          'url': url,
          'order_id': _order!.id,
          'order_number': _order!.orderNumber,
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
        });
      }
    }
  }

  Future<void> _payMpesa() async {
    if (_order == null || _phoneCtrl.text.trim().length < 9) return;

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final Session? session = _sb.auth.currentSession;
      if (session == null) throw Exception('Session expired.');

      final FunctionResponse response = await _sb.functions.invoke(
        'checkout-mpesa-stk-push',
        body: <String, dynamic>{
          'order_id': _order!.id,
          'phone_number': '+254${_phoneCtrl.text.trim()}',
          'amount': _order!.totalPrice,
        },
        headers: <String, String>{
          'Authorization': 'Bearer ${session.accessToken}',
        },
      );

      if (response.status != 200) {
        throw Exception((response.data as Map?)?['error'] ?? 'Failed');
      }

      if (!mounted) return;
      setState(() {
        _mpesaStep = _MpesaStep.promptSent;
      });
      _startPoll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
        });
      }
    }
  }

  void _startPoll() {
    _stopPoll();

    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      try {
        final dynamic data = await _sb
            .from('orders')
            .select('payment_status, order_number')
            .eq('id', widget.orderId)
            .single();

        if (data['payment_status'] == 'paid') {
          _stopPoll();
          _goSuccess(widget.orderId, data['order_number'] as String? ?? '');
        }
      } catch (e) {
        debugPrint('[Checkout] Poll error: $e');
      }
    });

    _pollTimeout = Timer(const Duration(minutes: 3), () {
      _stopPoll();
      if (!mounted) return;
      setState(() {
        _mpesaStep = _MpesaStep.timedOut;
      });
    });
  }

  void _stopPoll() {
    _pollTimer?.cancel();
    _pollTimeout?.cancel();
    _pollTimer = null;
    _pollTimeout = null;
  }

  void _goSuccess(String id, String num) {
    if (!mounted) return;

    Navigator.pushNamedAndRemoveUntil(
      context,
      '/payment-success',
      (_) => false,
      arguments: <String, String>{
        'order_id': id,
        'order_number': num,
      },
    );
  }

  void _handlePay() {
    if (_method == _PaymentMethod.paystack) {
      _payPaystack();
    } else if (_method == _PaymentMethod.mpesa) {
      _payMpesa();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _loadingView();
    if (_error != null && _order == null) return _errorView();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: _buildAppBar(),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: <Widget>[
            _orderInfoCard(),
            const SizedBox(height: 16),
            if ((_order?.items ?? <_CpOrderItem>[]).isNotEmpty) ...<Widget>[
              _orderItemsCard(),
              const SizedBox(height: 16),
            ],
            _shippingCard(),
            const SizedBox(height: 16),
            if (_order?.paymentStatus != 'paid') ...<Widget>[
              _paymentMethodCard(),
              const SizedBox(height: 16),
            ],
            _summaryCard(),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              _errorBanner(_error!),
            ],
          ],
        ),
      ),
      bottomNavigationBar:
          _order?.paymentStatus == 'paid' ? _paidBar() : _payButton(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 20,
          color: Color(0xFF1A1A2E),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Complete Payment',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
          ),
          if (_order != null)
            Text(
              'Order #${_order!.orderNumber}',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w400,
              ),
            ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: const Color(0xFFE5E7EB)),
      ),
    );
  }

  Widget _orderInfoCard() {
    final _CpOrder order = _order!;
    final DateTime? dt = DateTime.tryParse(order.createdAt);
    final String ds = dt != null
        ? '${_monthName(dt.month)} ${dt.day}, ${dt.year}'
        : order.createdAt;

    final Color statusColor = order.paymentStatus == 'paid'
        ? const Color(0xFF16A34A)
        : order.paymentStatus == 'pending'
            ? const Color(0xFFD97706)
            : const Color(0xFFDC2626);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionHeader(Icons.inventory_2_outlined, 'Order Details'),
          const SizedBox(height: 16),
          _KeyValueRow('Order Number', order.orderNumber, mono: true),
          _KeyValueRow('Date', ds),
          _KeyValueRow('Status', _capitalize(order.status)),
          _KeyValueRow(
            'Payment',
            _capitalize(order.paymentStatus),
            vc: statusColor,
          ),
        ],
      ),
    );
  }

  Widget _orderItemsCard() {
    return _Card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: _SectionHeader(Icons.menu_book_rounded, 'Order Items'),
          ),
          ..._order!.items.asMap().entries.map((MapEntry<int, _CpOrderItem> e) {
            return Column(
              children: <Widget>[
                if (e.key > 0)
                  const Divider(height: 1, indent: 20, endIndent: 20),
                _itemRow(e.value),
              ],
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _itemRow(_CpOrderItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 54,
              height: 74,
              child: CachedNetworkImage(
                imageUrl: item.coverImageUrl ?? '',
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: const Color(0xFFE5E7EB),
                  child: const Icon(
                    Icons.book_outlined,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: const Color(0xFFE5E7EB),
                  child: const Icon(
                    Icons.book_outlined,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                if (item.author.isNotEmpty)
                  Text(
                    'by ${item.author}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    _MiniChip('Qty: ${item.quantity}'),
                    const SizedBox(width: 8),
                    Text(
                      'KES ${_money(item.unitPrice)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            'KES ${_money(item.totalPrice)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shippingCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionHeader(Icons.local_shipping_outlined, 'Shipping Address'),
          const SizedBox(height: 12),
          Text(
            _order!.shippingAddress,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF4B5563),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentMethodCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionHeader(Icons.payment_rounded, 'Choose Payment Method'),
          const SizedBox(height: 16),
          _MethodCard(
            selected: _method == _PaymentMethod.paystack,
            icon: Icons.credit_card_rounded,
            iconColor: const Color(0xFF2563EB),
            iconBg: const Color(0xFFEFF6FF),
            title: 'Paystack',
            subtitle: 'Card / Bank Transfer',
            accent: const Color(0xFF2563EB),
            onTap: () => setState(() {
              _method = _PaymentMethod.paystack;
              _mpesaStep = _MpesaStep.idle;
              _error = null;
            }),
          ),
          const SizedBox(height: 10),
          _MethodCard(
            selected: _method == _PaymentMethod.mpesa,
            icon: Icons.smartphone_rounded,
            iconColor: const Color(0xFF16A34A),
            iconBg: const Color(0xFFF0FDF4),
            title: 'M-Pesa',
            subtitle: 'Safaricom Daraja',
            accent: const Color(0xFF16A34A),
            onTap: () => setState(() {
              _method = _PaymentMethod.mpesa;
              _mpesaStep = _MpesaStep.idle;
              _error = null;
            }),
          ),
          if (_method == _PaymentMethod.mpesa &&
              _mpesaStep == _MpesaStep.idle) ...<Widget>[
            const SizedBox(height: 20),
            const Text(
              'M-Pesa Phone Number',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    border: Border.all(color: const Color(0xFFD1D5DB)),
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(10),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '+254',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF374151),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    onChanged: (_) => setState(() {}),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(9),
                    ],
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF111827),
                    ),
                    decoration: const InputDecoration(
                      hintText: '7XXXXXXXX',
                      hintStyle: TextStyle(color: Color(0xFF9CA3AF)),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.horizontal(
                          right: Radius.circular(10),
                        ),
                        borderSide: BorderSide(color: Color(0xFFD1D5DB)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.horizontal(
                          right: Radius.circular(10),
                        ),
                        borderSide: BorderSide(color: Color(0xFFD1D5DB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.horizontal(
                          right: Radius.circular(10),
                        ),
                        borderSide: BorderSide(
                          color: Color(0xFF16A34A),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter the number registered on your M-Pesa account.',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
          if (_method == _PaymentMethod.mpesa &&
              _mpesaStep == _MpesaStep.promptSent) ...<Widget>[
            const SizedBox(height: 16),
            _BannerBox(
              icon: Icons.smartphone_rounded,
              iconColor: const Color(0xFF16A34A),
              bg: const Color(0xFFF0FDF4),
              border: const Color(0xFFBBF7D0),
              title: 'STK Push Sent!',
              body:
                  'Check your phone (+254 ${_phoneCtrl.text}) for the M-Pesa prompt and enter your PIN.',
              footer: const Row(
                children: <Widget>[
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Color(0xFF16A34A)),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Waiting for confirmation...',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_method == _PaymentMethod.mpesa &&
              _mpesaStep == _MpesaStep.timedOut) ...<Widget>[
            const SizedBox(height: 16),
            _BannerBox(
              icon: Icons.access_time_rounded,
              iconColor: const Color(0xFFD97706),
              bg: const Color(0xFFFFFBEB),
              border: const Color(0xFFFDE68A),
              title: 'Payment not confirmed yet',
              body:
                  "We didn't receive a confirmation. If you completed the payment, it may still be processing.",
              footer: GestureDetector(
                onTap: () => setState(() {
                  _mpesaStep = _MpesaStep.idle;
                  _error = null;
                }),
                child: const Text(
                  'Try again',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFD97706),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryCard() {
    final _CpOrder order = _order!;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionHeader(Icons.receipt_long_rounded, 'Payment Summary'),
          const SizedBox(height: 16),
          _SummaryRow('Subtotal', 'KES ${_money(order.subTotal)}'),
          if (order.discount > 0)
            _SummaryRow(
              'Discount',
              '-KES ${_money(order.discount)}',
              c: const Color(0xFF16A34A),
            ),
          if (order.tax > 0) _SummaryRow('Tax', 'KES ${_money(order.tax)}'),
          _SummaryRow(
            'Shipping',
            order.shipping == 0 ? 'FREE' : 'KES ${_money(order.shipping)}',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text(
                'Total',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              Text(
                'KES ${_money(order.totalPrice)}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _payButton() {
    if (_mpesaStep == _MpesaStep.promptSent) {
      return const SizedBox.shrink();
    }

    final bool isPaystack = _method == _PaymentMethod.paystack;
    final bool isMpesa = _method == _PaymentMethod.mpesa;
    final bool canPay =
        (isPaystack || (isMpesa && _phoneCtrl.text.length >= 9)) &&
            !_processing;

    final Color buttonColor = isMpesa
        ? const Color(0xFF16A34A)
        : isPaystack
            ? const Color(0xFF2563EB)
            : const Color(0xFFD1D5DB);

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_error != null) ...<Widget>[
            _errorBanner(_error!),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: canPay ? _handlePay : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: canPay ? buttonColor : const Color(0xFFE5E7EB),
                foregroundColor:
                    canPay ? Colors.white : const Color(0xFF9CA3AF),
                elevation: canPay ? 2 : 0,
                shadowColor: buttonColor.withOpacity(0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _processing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          _method == _PaymentMethod.none
                              ? Icons.touch_app_rounded
                              : isMpesa
                                  ? Icons.smartphone_rounded
                                  : Icons.credit_card_rounded,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _method == _PaymentMethod.none
                              ? 'Select a Payment Method'
                              : isMpesa
                                  ? 'Pay with M-Pesa'
                                  : 'Pay with Paystack',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paidBar() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          border: Border.all(color: const Color(0xFFBBF7D0)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: <Widget>[
            Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF16A34A),
              size: 22,
            ),
            SizedBox(width: 10),
            Text(
              'Payment Completed',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF15803D),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadingView() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(AppColors.primary),
            ),
            const SizedBox(height: 20),
            const Text(
              'Loading order details...',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorView() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Checkout'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(
                Icons.error_outline_rounded,
                size: 72,
                color: Color(0xFFEF4444),
              ),
              const SizedBox(height: 20),
              const Text(
                'Order Not Found',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/books',
                  (_) => false,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Continue Shopping',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorBanner(String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        border: Border.all(color: const Color(0xFFFECACA)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFDC2626),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _money(double value) {
    return value
        .toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  }

  String _monthName(int month) {
    return const <String>[
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ][month];
  }

  String _capitalize(String s) {
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED CHECKOUT SUB-WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _Card({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionHeader(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: const Color(0xFF6B7280)),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
          ),
        ),
      ],
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  final Color? vc;

  const _KeyValueRow(
    this.label,
    this.value, {
    this.mono = false,
    this.vc,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7280),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: vc ?? const Color(0xFF111827),
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? c;

  const _SummaryRow(this.label, this.value, {this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: c ?? const Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;

  const _MiniChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Color(0xFF374151),
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MethodCard({
    required this.selected,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? iconBg : Colors.white,
          border: Border.all(
            color: selected ? accent : const Color(0xFFE5E7EB),
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: selected
                  ? Icon(
                      Icons.check_circle_rounded,
                      key: const ValueKey<String>('selected'),
                      color: accent,
                      size: 22,
                    )
                  : const Icon(
                      Icons.radio_button_unchecked_rounded,
                      key: ValueKey<String>('unselected'),
                      color: Color(0xFFD1D5DB),
                      size: 22,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerBox extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bg;
  final Color border;
  final String title;
  final String body;
  final Widget footer;

  const _BannerBox({
    required this.icon,
    required this.iconColor,
    required this.bg,
    required this.border,
    required this.title,
    required this.body,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: iconColor,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF374151),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                footer,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
