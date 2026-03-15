// lib/main.dart

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';

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
import 'pages/profile_page.dart';
import 'pages/profile_setup_page.dart';
import 'pages/settingsPage.dart';
import 'pages/content_management_page.dart';
import 'pages/content_reader_page.dart';
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
// NAVIGATOR KEY
// ─────────────────────────────────────────────────────────────────────────────

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ─────────────────────────────────────────────────────────────────────────────
// DEEP LINK SERVICE
// ─────────────────────────────────────────────────────────────────────────────

class DeepLinkService {
  DeepLinkService._();

  static final AppLinks _appLinks = AppLinks();
  static StreamSubscription<Uri>? _sub;

  static void init() {
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        debugPrint('[DeepLink] Cold-start URI: $uri');
        _handle(uri);
      }
    }).catchError((e) {
      debugPrint('[DeepLink] getInitialLink error: $e');
    });

    _sub?.cancel();
    _sub = _appLinks.uriLinkStream.listen(
      (uri) {
        debugPrint('[DeepLink] Foreground URI: $uri');
        _handle(uri);
      },
      onError: (e) => debugPrint('[DeepLink] Stream error: $e'),
    );
  }

  static void dispose() {
    _sub?.cancel();
    _sub = null;
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
    final orderId     = uri.queryParameters['order_id']     ?? '';
    final orderNumber = uri.queryParameters['order_number'] ?? '';
    debugPrint('[DeepLink] payment-callback → orderId: $orderId');
    if (orderId.isEmpty) return;
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/payment-success',
      (_) => false,
      arguments: {'order_id': orderId, 'order_number': orderNumber},
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://nnljrawwhibazudjudht.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5ubGpyYXd3aGliYXp1ZGp1ZGh0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkwNjc1ODQsImV4cCI6MjA4NDY0MzU4NH0.wMMeffZGj7mbStjglTE5ZOknO-QKjX9aAG1xcjKBl5c',
  );

  DeepLinkService.init();
  runApp(const IntercenApp());
}

// ─────────────────────────────────────────────────────────────────────────────
// ROLE GATE
//
// Loads and caches the user's role, then ALWAYS navigates to /home.
// Dashboards are never used as the root page — reachable from Settings only.
// ─────────────────────────────────────────────────────────────────────────────

class _RoleGate extends StatefulWidget {
  const _RoleGate();
  @override
  State<_RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<_RoleGate> {
  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    await RoleService.instance.load();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF9F5EF),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'lib/assets/intercenlogo.png',
                height: 56,
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.menu_book_rounded,
                    size: 56,
                    color: Color(0xFFB11226)),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor:
                      AlwaysStoppedAnimation(Color(0xFFB11226)),
                ),
              ),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// APP
// ─────────────────────────────────────────────────────────────────────────────

class IntercenApp extends StatefulWidget {
  const IntercenApp({super.key});
  @override
  State<IntercenApp> createState() => _IntercenAppState();
}

class _IntercenAppState extends State<IntercenApp> {
  @override
  void dispose() {
    DeepLinkService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Intercen Book Store',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'PlayfairDisplay',
        scaffoldBackgroundColor: const Color(0xFFF9F5EF),
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFB11226)),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFB11226),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        textTheme: ThemeData.light().textTheme.apply(
            bodyColor: Colors.black, displayColor: Colors.black),
      ),

      // ── Entry: session exists → /home, else → onboarding ─────────────────
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session =
              Supabase.instance.client.auth.currentSession;
          if (session != null) return const _RoleGate();
          RoleService.instance.clear();
          return const OnboardingPage();
        },
      ),

      routes: {
        // ── Auth ─────────────────────────────────────────────────────────
        '/onboarding':       (_) => const OnboardingPage(),
        '/login':            (_) => const LoginPage(),
        '/signup':           (_) => const SignUpPage(),
        '/reset-password':   (_) => const ResetPasswordPage(),
        '/otp':              (_) => const OtpPage(),
        '/confirm-password': (_) => const ConfirmPasswordPage(),

        // ── Home (Shell) — canonical root after login ─────────────────────
        // Shell owns Home/Books in-place and routes Cart+Profile away via
        // pushNamed so Back always returns here with the correct nav.
        '/home': (_) => const AuthGuard(child: Shell()),

        // ── Role dashboards ───────────────────────────────────────────────
        // Reachable from Settings → "My Dashboard" tile (pushNamed).
        // All three accept an optional {'initialTab': int} argument so
        // Settings can deep-link to a specific tab:
        //   Admin  → tab 0 = Users | 1 = Submissions | 2 = Content
        //             3 = Orders   | 4 = My Profile
        //   Author → tab 0 = Overview | 1 = Submissions | 2 = My Works
        //             3 = My Orders   | 4 = Edit Profile
        //   Reader → tab 0 = My Profile | 1 = Orders | 2 = Browse
        '/dashboard/admin':  (_) =>
            const AuthGuard(child: AdminDashboardPage()),
        '/dashboard/author': (_) =>
            const AuthGuard(child: AuthorDashboardPage()),
        '/dashboard/reader': (_) =>
            const AuthGuard(child: ReaderDashboardPage()),

        // ── Books ─────────────────────────────────────────────────────────
        '/books':       (_) => const AuthGuard(child: BooksPage()),
        '/book-detail': (_) => const AuthGuard(child: BookDetailPage()),

        // ── Cart & checkout ───────────────────────────────────────────────
        '/cart':     (_) => const AuthGuard(child: CartPage()),
        '/checkout': (_) => AuthGuard(child: CheckoutFlowPage()),

        // ── About ─────────────────────────────────────────────────────────
        '/about': (_) => const AboutPage(),

        // ── Profile / Settings ────────────────────────────────────────────
        // Both routes point to SettingsPage so pushNamed('/profile') from
        // any page always lands in the right place with the right navbar.
        '/profile':       (_) => const AuthGuard(child: SettingsPage()),
        '/settings':      (_) => const AuthGuard(child: SettingsPage()),
        '/profile-setup': (_) =>
            const AuthGuard(child: ProfileSetupPage()),

        // ── Notifications ─────────────────────────────────────────────────
        '/notifications': (_) =>
            const AuthGuard(child: NotificationsPage()),

        // ── Publication Requests (admin only — guard inside page) ─────────
        '/publication-requests': (_) =>
            const AuthGuard(child: PublicationRequestsPage()),

        // ── Publishing (public) ───────────────────────────────────────────
        '/publish': (_) => const PublishWithUsPage(),

        // ── Content Management (admin only) ───────────────────────────────
        // AdminGuard wraps AuthGuard — requires login AND admin role.
        // The role check is also inside each page itself as a second layer.
        '/content-management': (_) =>
            const AdminGuard(child: ContentManagementPage()),

        // ── Content Upload (admin only) ───────────────────────────────────
        '/upload': (_) => const AdminGuard(child: ContentUploadPage()),
      },

      // ── Dynamic / parameterised routes ───────────────────────────────────
      onGenerateRoute: (settings) {
        final name = settings.name ?? '';

        // ── /checkout/payment  or  /checkout/payment/<orderId> ────────────
        if (RegExp(r'^/checkout/payment').hasMatch(name)) {
          final args = settings.arguments;
          String orderId = '';
          if (args is Map<String, dynamic>) {
            orderId = args['order_id'] as String? ?? '';
          } else if (args is String) {
            orderId = args;
          }
          return MaterialPageRoute(
            settings: settings,
            builder: (_) =>
                AuthGuard(child: CheckoutPaymentPage(orderId: orderId)),
          );
        }

        // ── /paystack-webview ─────────────────────────────────────────────
        if (name == '/paystack-webview') {
          final args =
              settings.arguments as Map<String, dynamic>? ?? {};
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => PaystackLaunchPage(
              url:         args['url']          as String? ?? '',
              orderId:     args['order_id']     as String? ?? '',
              orderNumber: args['order_number'] as String? ?? '',
            ),
          );
        }

        // ── /payment-success ──────────────────────────────────────────────
        if (name == '/payment-success') {
          final args =
              settings.arguments as Map<String, dynamic>? ?? {};
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => PaymentSuccessPage(
              orderId:     args['order_id']     as String? ?? '',
              orderNumber: args['order_number'] as String? ?? '',
            ),
          );
        }

        // ── /payment-failure ──────────────────────────────────────────────
        if (name == '/payment-failure') {
          final args =
              settings.arguments as Map<String, dynamic>? ?? {};
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => PaymentFailurePage(
              orderId:     args['order_id']     as String? ?? '',
              orderNumber: args['order_number'] as String? ?? '',
            ),
          );
        }

        // ── /content/update/<id>  (ADMIN ONLY) ───────────────────────────
        // ⚠️ This MUST be checked BEFORE the generic /content/<id> matcher
        // below, otherwise /content/update/abc matches /content/(.+) first
        // and gets routed to ContentViewPage instead.
        final contentUpdateMatch =
            RegExp(r'^/content/update/(.+)$').firstMatch(name);
        if (contentUpdateMatch != null) {
          final contentId = contentUpdateMatch.group(1) ?? '';
          return MaterialPageRoute(
            settings: RouteSettings(name: name, arguments: contentId),
            builder: (_) =>
                const AdminGuard(child: ContentUpdatePage()),
          );
        }

        // ── /content/<id>  or  /content-view/<id>  (ADMIN ONLY) ──────────
        // Shows the full detail view page (ContentViewPage).
        // Non-admins are redirected inside AdminGuard → /home.
        final contentMatch =
            RegExp(r'^/content(?:-view)?/(.+)$').firstMatch(name);
        if (contentMatch != null) {
          final contentId = contentMatch.group(1) ?? '';
          return MaterialPageRoute(
            settings: RouteSettings(name: name, arguments: contentId),
            builder: (_) => const AdminGuard(child: ContentViewPage()),
          );
        }

        // ── /book-detail/<id> ─────────────────────────────────────────────
        final bookMatch =
            RegExp(r'^/book-detail/(.+)$').firstMatch(name);
        if (bookMatch != null) {
          final bookId = bookMatch.group(1) ?? '';
          return MaterialPageRoute(
            settings: RouteSettings(name: name, arguments: bookId),
            builder: (_) => const AuthGuard(child: BookDetailPage()),
          );
        }

        // ── 404 fallback ──────────────────────────────────────────────────
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: const Color(0xFFF9F5EF),
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              leading: Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      size: 20, color: Color(0xFF1A1A2E)),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.explore_off_rounded,
                        size: 64, color: Color(0xFFD1D5DB)),
                    const SizedBox(height: 16),
                    const Text('Page Not Found',
                        style: TextStyle(
                            fontFamily: 'PlayfairDisplay',
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827))),
                    const SizedBox(height: 8),
                    Text(name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 12,
                            color: Color(0xFF9CA3AF))),
                    const SizedBox(height: 28),
                    Builder(
                      builder: (ctx) => ElevatedButton(
                        onPressed: () =>
                            Navigator.pushNamedAndRemoveUntil(
                                ctx, '/home', (_) => false),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12))),
                        child: const Text('Go to Home',
                            style: TextStyle(
                                fontFamily: 'DM Sans')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AUTH GUARD
//
// Requires a valid Supabase session.
// Redirects to /onboarding if no session exists.
// Used for all authenticated pages regardless of role.
// ─────────────────────────────────────────────────────────────────────────────

class AuthGuard extends StatelessWidget {
  final Widget child;
  const AuthGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) =>
          Navigator.of(context).pushNamedAndRemoveUntil(
              '/onboarding', (_) => false));
      return const Scaffold(
        backgroundColor: Color(0xFFF9F5EF),
        body: Center(
          child: CircularProgressIndicator(
              valueColor:
                  AlwaysStoppedAnimation(Color(0xFFB11226))),
        ),
      );
    }
    return child;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN GUARD
//
// Double-layer protection for admin-only pages:
//   Layer 1 — session must exist (same as AuthGuard).
//   Layer 2 — role cached in RoleService must be 'admin'.
//
// If either check fails the user is redirected to /home immediately.
// An additional role check also lives inside each admin page itself
// as a third safety net (in case the page is reached via a deep link
// that bypasses this guard).
//
// Why a separate guard instead of reusing AuthGuard?
//   AuthGuard only checks for a session. AdminGuard additionally verifies
//   the role, which requires RoleService to have been loaded (it is always
//   loaded by _RoleGate on login). This keeps the admin check declarative
//   at the route level so it's impossible to forget.
// ─────────────────────────────────────────────────────────────────────────────

class AdminGuard extends StatefulWidget {
  final Widget child;
  const AdminGuard({super.key, required this.child});
  @override
  State<AdminGuard> createState() => _AdminGuardState();
}

class _AdminGuardState extends State<AdminGuard> {
  bool _checking = true;
  bool _allowed  = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    // 1 — session check
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
            '/onboarding', (_) => false);
      }
      return;
    }

    // 2 — role check (load if not yet cached)
    await RoleService.instance.load();
    final role = RoleService.instance.role;

    if (role != 'admin') {
      if (mounted) {
        // Redirect non-admins silently to home with a brief message
        Navigator.of(context).pushNamedAndRemoveUntil(
            '/home', (_) => false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Access denied. Admin only.',
              style: TextStyle(
                  fontFamily: 'DM Sans', fontWeight: FontWeight.w500),
            ),
            backgroundColor: const Color(0xFFB11226),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // 3 — all good
    if (mounted) setState(() { _checking = false; _allowed = true; });
  }

  @override
  Widget build(BuildContext context) {
    // Show a branded loading screen while verifying — never flash the
    // child widget to a non-admin user even for a single frame.
    if (_checking || !_allowed) {
      return Scaffold(
        backgroundColor: const Color(0xFFF9F5EF),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFB11226).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_rounded,
                    size: 32, color: Color(0xFFB11226)),
              ),
              const SizedBox(height: 20),
              const SizedBox(
                width: 28, height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor:
                      AlwaysStoppedAnimation(Color(0xFFB11226)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Verifying access…',
                  style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                  )),
            ],
          ),
        ),
      );
    }
    return widget.child;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHELL — canonical root page after login
//
// Manages Home (index 0) and Books (index 1) in-place.
// Cart and Profile navigate away via pushNamed so their own Scaffolds
// handle their navbars — Back always returns here with the correct nav.
// ─────────────────────────────────────────────────────────────────────────────

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

// AFTER — Books is a pushed route, Shell only holds Home
class _ShellState extends State<Shell> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const HomePage(),
      bottomNavigationBar: _AppBottomNav(
        currentIndex: 0,           // Home always active while Shell shows
        onHome:    () {},           // no-op — already on Home
        onBooks:   () => Navigator.pushNamed(context, '/books'),  // pushes route
        onCart:    () => Navigator.pushNamed(context, '/cart'),
        onProfile: () => Navigator.pushNamed(context, '/settings'),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED BOTTOM NAV (Shell only)
// Every other page (BooksPage, CartPage, SettingsPage, etc.) defines its
// own inline nav — this widget is exclusively for Shell.
// ─────────────────────────────────────────────────────────────────────────────

class _AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final VoidCallback onHome, onBooks, onCart, onProfile;

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
            top: BorderSide(color: Color(0xFFE5E7EB))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
              icon: Icons.home_outlined,
              label: 'Home',
              active: currentIndex == 0,
              onTap: onHome),
          _NavItem(
              icon: Icons.menu_book_outlined,
              label: 'Books',
              active: currentIndex == 1,
              onTap: onBooks),
          _NavItem(
              icon: Icons.shopping_cart_outlined,
              label: 'Cart',
              active: false,
              onTap: onCart),
          _NavItem(
              icon: Icons.person_outline,
              label: 'Profile',
              active: false,
              onTap: onProfile),
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
    final color = active ? const Color(0xFFB11226) : Colors.grey;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 11,
                color: color,
                fontWeight:
                    active ? FontWeight.w700 : FontWeight.normal,
              )),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PAYSTACK LAUNCH PAGE
// ═════════════════════════════════════════════════════════════════════════════

class PaystackLaunchPage extends StatefulWidget {
  final String url, orderId, orderNumber;
  const PaystackLaunchPage({
    super.key,
    required this.url,
    required this.orderId,
    required this.orderNumber,
  });
  @override
  State<PaystackLaunchPage> createState() =>
      _PaystackLaunchPageState();
}

class _PaystackLaunchPageState extends State<PaystackLaunchPage>
    with WidgetsBindingObserver {
  final _sb = Supabase.instance.client;
  Timer? _pollTimer;
  Timer? _pollTimeout;
  bool _launched  = false;
  bool _polling   = false;
  bool _timedOut  = false;
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
    if (state == AppLifecycleState.resumed &&
        _polling &&
        !_confirmed) {
      _checkNow();
    }
  }

  Future<void> _launch() async {
    final uri = Uri.parse(widget.url);
    final ok  = await launchUrl(uri,
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not open payment page.')));
      return;
    }
    if (mounted) setState(() { _launched = true; _polling = true; });
    _startPoll();
  }

  void _startPoll() {
    _stopPoll();
    _pollTimer = Timer.periodic(
        const Duration(seconds: 4), (_) => _checkNow());
    _pollTimeout = Timer(const Duration(minutes: 3), () {
      _stopPoll();
      if (mounted) setState(() { _timedOut = true; _polling = false; });
    });
  }

  Future<void> _checkNow() async {
    if (_confirmed || !mounted) return;
    try {
      final d = await _sb
          .from('orders')
          .select('payment_status, order_number')
          .eq('id', widget.orderId)
          .single();
      if (d['payment_status'] == 'paid') {
        _confirmed = true;
        _stopPoll();
        _goSuccess(widget.orderId,
            d['order_number'] as String? ?? widget.orderNumber);
      }
    } catch (e) {
      debugPrint('[PaystackLaunch] Poll error: $e');
    }
  }

  void _stopPoll() {
    _pollTimer?.cancel();
    _pollTimeout?.cancel();
    _pollTimer   = null;
    _pollTimeout = null;
  }

  void _goSuccess(String id, String num) {
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context, '/payment-success', (_) => false,
      arguments: {'order_id': id, 'order_number': num},
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: Color(0xFF1A1A2E)),
          onPressed: () { _stopPoll(); Navigator.pop(context); },
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paystack Payment',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E))),
            Text('Complete payment in your browser',
                style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w400)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
              height: 1, color: const Color(0xFFE5E7EB)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90, height: 90,
              decoration: const BoxDecoration(
                  color: Color(0xFFEFF6FF),
                  shape: BoxShape.circle),
              child: const Icon(Icons.open_in_browser_rounded,
                  size: 44, color: Color(0xFF2563EB)),
            ),
            const SizedBox(height: 28),
            if (!_timedOut) ...[
              const Text('Payment Page Opened',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827))),
              const SizedBox(height: 12),
              const Text(
                'Complete your payment in the browser.\n\n'
                'This screen will automatically update once your '
                'payment is confirmed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                    height: 1.65),
              ),
              const SizedBox(height: 32),
              if (_polling)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      border: Border.all(
                          color: const Color(0xFFBBF7D0)),
                      borderRadius: BorderRadius.circular(12)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(
                                Color(0xFF16A34A))),
                      ),
                      SizedBox(width: 12),
                      Text('Waiting for payment confirmation…',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF15803D))),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(widget.url),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_browser_rounded,
                    size: 18),
                label: const Text('Reopen Payment Page'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2563EB),
                    side: const BorderSide(
                        color: Color(0xFF2563EB)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(10))),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _checkNow,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text(
                    "I've completed payment — check now"),
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280)),
              ),
            ] else ...[
              const Text('Payment Not Confirmed',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827))),
              const SizedBox(height: 12),
              const Text(
                "We haven't received confirmation yet.\n"
                "If you completed the payment it may still be "
                "processing.",
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                    height: 1.65),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _timedOut = false;
                      _polling  = true;
                    });
                    _startPoll();
                    launchUrl(Uri.parse(widget.url),
                        mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(12))),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pushNamed(context, '/orders'),
                  icon: const Icon(Icons.list_alt_rounded,
                      size: 18),
                  label: const Text('Check My Orders'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      side: const BorderSide(
                          color: Color(0xFFD1D5DB)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(10))),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back',
                    style: TextStyle(
                        color: Color(0xFF6B7280))),
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
  final String orderId, orderNumber;
  const PaymentSuccessPage(
      {super.key, required this.orderId, required this.orderNumber});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (_, v, child) =>
                    Transform.scale(scale: v, child: child),
                child: Container(
                  width: 110, height: 110,
                  decoration: const BoxDecoration(
                      color: Color(0xFFF0FDF4),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF16A34A), size: 70),
                ),
              ),
              const SizedBox(height: 28),
              const Text('Payment Successful!',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827))),
              const SizedBox(height: 12),
              const Text(
                'Your order has been placed and your payment confirmed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                    height: 1.6),
              ),
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ]),
                child: Column(children: [
                  _DetailRow('Order Number',
                      orderNumber.isNotEmpty ? orderNumber : '—'),
                  const Divider(height: 20),
                  _DetailRow('Order ID',
                      orderId.length > 8
                          ? '…${orderId.substring(orderId.length - 8)}'
                          : orderId),
                  const Divider(height: 20),
                  _DetailRow('Status', 'Confirmed',
                      valueColor: const Color(0xFF16A34A)),
                ]),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      Navigator.pushNamedAndRemoveUntil(
                          context, '/books', (_) => false),
                  icon: const Icon(
                      Icons.shopping_bag_outlined, size: 20),
                  label: const Text('Continue Shopping',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(14))),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () =>
                    Navigator.pushNamed(context, '/orders'),
                child: const Text('View Order Details',
                    style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  const _DetailRow(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF6B7280))),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? const Color(0xFF111827))),
        ],
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// PAYMENT FAILURE PAGE
// ═════════════════════════════════════════════════════════════════════════════

class PaymentFailurePage extends StatelessWidget {
  final String orderId, orderNumber;
  const PaymentFailurePage(
      {super.key, required this.orderId, required this.orderNumber});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (_, v, child) =>
                    Transform.scale(scale: v, child: child),
                child: Container(
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle),
                  child: Icon(Icons.cancel_rounded,
                      color: AppColors.primary, size: 70),
                ),
              ),
              const SizedBox(height: 28),
              const Text('Payment Failed',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827))),
              const SizedBox(height: 12),
              const Text(
                'Something went wrong while processing your payment.\n'
                'No charges were made to your account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                    height: 1.6),
              ),
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    border: Border.all(
                        color: const Color(0xFFFECACA)),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Please try again or choose a different '
                        'payment method.',
                        style: TextStyle(
                            color: Color(0xFF991B1B),
                            fontSize: 13,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/checkout/payment',
                          (_) => false,
                          arguments: {'order_id': orderId}),
                  icon: const Icon(Icons.refresh_rounded,
                      size: 20),
                  label: const Text('Retry Payment',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(14))),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () =>
                    Navigator.pushNamedAndRemoveUntil(
                        context, '/home', (_) => false),
                child: const Text('Back to Home',
                    style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w600)),
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
  final String  id, contentId, title, author;
  final int     quantity;
  final double  unitPrice, totalPrice;
  final String? coverImageUrl;

  _CpOrderItem({
    required this.id,          required this.contentId,
    required this.title,       required this.author,
    required this.quantity,    required this.unitPrice,
    required this.totalPrice,  this.coverImageUrl,
  });

  factory _CpOrderItem.fromJson(Map<String, dynamic> j) {
    final c = (j['content'] as Map<String, dynamic>?) ?? {};
    return _CpOrderItem(
      id:            j['id']           as String? ?? '',
      contentId:     j['content_id']   as String? ?? '',
      quantity:      (j['quantity']    as num?)?.toInt()    ?? 1,
      unitPrice:     (j['unit_price']  as num?)?.toDouble() ?? 0,
      totalPrice:    (j['total_price'] as num?)?.toDouble() ?? 0,
      title:         c['title']        as String? ?? 'Unknown',
      author:        c['author']       as String? ?? '',
      coverImageUrl: c['cover_image_url'] as String?,
    );
  }
}

class _CpOrder {
  final String id, orderNumber, status, paymentStatus,
      shippingAddress, createdAt;
  final double totalPrice, subTotal, tax, shipping, discount;
  final List<_CpOrderItem> items;

  _CpOrder({
    required this.id,              required this.orderNumber,
    required this.status,          required this.paymentStatus,
    required this.shippingAddress, required this.createdAt,
    required this.totalPrice,      required this.subTotal,
    required this.tax,             required this.shipping,
    required this.discount,        required this.items,
  });

  factory _CpOrder.fromJson(Map<String, dynamic> j) {
    final raw = (j['order_items'] as List<dynamic>?) ?? [];
    return _CpOrder(
      id:              j['id']               as String? ?? '',
      orderNumber:     j['order_number']     as String? ?? '—',
      totalPrice:      (j['total_price']     as num?)?.toDouble() ?? 0,
      subTotal:        (j['sub_total']       as num?)?.toDouble() ?? 0,
      tax:             (j['tax']             as num?)?.toDouble() ?? 0,
      shipping:        (j['shipping']        as num?)?.toDouble() ?? 0,
      discount:        (j['discount']        as num?)?.toDouble() ?? 0,
      status:          j['status']           as String? ?? 'pending',
      paymentStatus:   j['payment_status']   as String? ?? 'pending',
      shippingAddress: j['shipping_address'] as String? ?? '',
      createdAt:       j['created_at']       as String? ?? '',
      items: raw
          .map((e) =>
              _CpOrderItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

enum _PMethod { none, paystack, mpesa }
enum _MStep   { idle, promptSent, timedOut }

class CheckoutPaymentPage extends StatefulWidget {
  final String orderId;
  const CheckoutPaymentPage({super.key, required this.orderId});
  @override
  State<CheckoutPaymentPage> createState() =>
      _CheckoutPaymentPageState();
}

class _CheckoutPaymentPageState extends State<CheckoutPaymentPage>
    with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;

  _CpOrder? _order;
  bool      _loading    = true;
  bool      _processing = false;
  String?   _error;
  _PMethod  _method = _PMethod.none;
  _MStep    _mstep  = _MStep.idle;

  final _phoneCtrl = TextEditingController();
  Timer? _pollTimer, _pollTimeout;

  late final AnimationController _fadeCtrl;
  late final Animation<double>    _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 450));
    _fadeAnim =
        CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
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
    setState(() { _loading = true; _error = null; });
    try {
      final s = _sb.auth.currentSession;
      if (s == null) {
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }
      final data = await _sb.from('orders').select('''
        *, order_items(id,content_id,quantity,unit_price,total_price,
          content:content_id(title,author,cover_image_url))
      ''').eq('id', widget.orderId).eq('user_id', s.user.id).single();

      final o = _CpOrder.fromJson(data);
      if (o.paymentStatus == 'paid') {
        _goSuccess(o.id, o.orderNumber);
        return;
      }
      setState(() => _order = o);
      _fadeCtrl.forward();
    } catch (_) {
      setState(() => _error = 'Order not found or failed to load.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _payPaystack() async {
    if (_order == null) return;
    setState(() { _processing = true; _error = null; });
    try {
      final s = _sb.auth.currentSession;
      if (s == null) throw Exception('Session expired.');
      final r = await _sb.functions.invoke(
        'checkout-process-payment',
        body: {'order_id': _order!.id, 'platform': 'mobile'},
        headers: {'Authorization': 'Bearer ${s.accessToken}'},
      );
      if (r.status != 200) {
        throw Exception(
            (r.data as Map?)?['error'] ?? 'Failed');
      }
      final url =
          (r.data as Map?)?['authorization_url'] as String?;
      if (url == null || url.isEmpty) {
        throw Exception('No payment URL received');
      }
      if (mounted) {
        Navigator.pushNamed(context, '/paystack-webview',
            arguments: {
          'url':          url,
          'order_id':     _order!.id,
          'order_number': _order!.orderNumber,
        });
      }
    } catch (e) {
      setState(() =>
          _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _payMpesa() async {
    if (_order == null || _phoneCtrl.text.trim().length < 9) return;
    setState(() { _processing = true; _error = null; });
    try {
      final s = _sb.auth.currentSession;
      if (s == null) throw Exception('Session expired.');
      final r = await _sb.functions.invoke(
        'checkout-mpesa-stk-push',
        body: {
          'order_id':     _order!.id,
          'phone_number': '+254${_phoneCtrl.text.trim()}',
          'amount':       _order!.totalPrice,
        },
        headers: {'Authorization': 'Bearer ${s.accessToken}'},
      );
      if (r.status != 200) {
        throw Exception(
            (r.data as Map?)?['error'] ?? 'Failed');
      }
      setState(() => _mstep = _MStep.promptSent);
      _startPoll();
    } catch (e) {
      setState(() =>
          _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _startPoll() {
    _stopPoll();
    _pollTimer = Timer.periodic(
        const Duration(seconds: 4), (_) async {
      try {
        final d = await _sb
            .from('orders')
            .select('payment_status, order_number')
            .eq('id', widget.orderId)
            .single();
        if (d['payment_status'] == 'paid') {
          _stopPoll();
          _goSuccess(widget.orderId,
              d['order_number'] as String? ?? '');
        }
      } catch (e) {
        debugPrint('[Checkout] Poll error: $e');
      }
    });
    _pollTimeout = Timer(const Duration(minutes: 3), () {
      _stopPoll();
      if (mounted) setState(() => _mstep = _MStep.timedOut);
    });
  }

  void _stopPoll() {
    _pollTimer?.cancel();
    _pollTimeout?.cancel();
    _pollTimer   = null;
    _pollTimeout = null;
  }

  void _goSuccess(String id, String num) {
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
        context, '/payment-success', (_) => false,
        arguments: {'order_id': id, 'order_number': num});
  }

  void _handlePay() {
    if (_method == _PMethod.paystack) _payPaystack();
    if (_method == _PMethod.mpesa)    _payMpesa();
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
          children: [
            _orderInfoCard(),
            const SizedBox(height: 16),
            if ((_order?.items ?? []).isNotEmpty) ...[
              _orderItemsCard(),
              const SizedBox(height: 16),
            ],
            _shippingCard(),
            const SizedBox(height: 16),
            if (_order?.paymentStatus != 'paid') ...[
              _paymentMethodCard(),
              const SizedBox(height: 16),
            ],
            _summaryCard(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _errBanner(_error!),
            ],
          ],
        ),
      ),
      bottomNavigationBar: _order?.paymentStatus == 'paid'
          ? _paidBar()
          : _payButton(),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: Color(0xFF1A1A2E)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Complete Payment',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E))),
            if (_order != null)
              Text('Order #${_order!.orderNumber}',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w400)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
              height: 1, color: const Color(0xFFE5E7EB)),
        ),
      );

  Widget _orderInfoCard() {
    final o  = _order!;
    final dt = DateTime.tryParse(o.createdAt);
    final ds = dt != null
        ? '${_mon(dt.month)} ${dt.day}, ${dt.year}'
        : o.createdAt;
    final sc = o.paymentStatus == 'paid'
        ? const Color(0xFF16A34A)
        : o.paymentStatus == 'pending'
            ? const Color(0xFFD97706)
            : const Color(0xFFDC2626);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _H(Icons.inventory_2_outlined, 'Order Details'),
          const SizedBox(height: 16),
          _KV('Order Number', o.orderNumber, mono: true),
          _KV('Date', ds),
          _KV('Status', _cap(o.status)),
          _KV('Payment', _cap(o.paymentStatus), vc: sc),
        ],
      ),
    );
  }

  Widget _orderItemsCard() => _Card(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: _H(Icons.menu_book_rounded, 'Order Items'),
            ),
            ..._order!.items.asMap().entries.map((e) =>
                Column(children: [
                  if (e.key > 0)
                    const Divider(
                        height: 1, indent: 20, endIndent: 20),
                  _itemRow(e.value),
                ])),
            const SizedBox(height: 8),
          ],
        ),
      );

  Widget _itemRow(_CpOrderItem item) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 54, height: 74,
                child: CachedNetworkImage(
                  imageUrl: item.coverImageUrl ?? '',
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                      color: const Color(0xFFE5E7EB),
                      child: const Icon(Icons.book_outlined,
                          color: Color(0xFF9CA3AF))),
                  errorWidget: (_, __, ___) => Container(
                      color: const Color(0xFFE5E7EB),
                      child: const Icon(Icons.book_outlined,
                          color: Color(0xFF9CA3AF))),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827))),
                  if (item.author.isNotEmpty)
                    Text('by ${item.author}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280))),
                  const SizedBox(height: 8),
                  Row(children: [
                    _ChipW('Qty: ${item.quantity}'),
                    const SizedBox(width: 8),
                    Text('KES ${_f(item.unitPrice)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500)),
                  ]),
                ],
              ),
            ),
            Text('KES ${_f(item.totalPrice)}',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827))),
          ],
        ),
      );

  Widget _shippingCard() => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _H(Icons.local_shipping_outlined, 'Shipping Address'),
            const SizedBox(height: 12),
            Text(_order!.shippingAddress,
                style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF4B5563),
                    height: 1.5)),
          ],
        ),
      );

  Widget _paymentMethodCard() => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _H(Icons.payment_rounded, 'Choose Payment Method'),
            const SizedBox(height: 16),
            _MethodCard(
              selected:  _method == _PMethod.paystack,
              icon:      Icons.credit_card_rounded,
              iconColor: const Color(0xFF2563EB),
              iconBg:    const Color(0xFFEFF6FF),
              title:     'Paystack',
              subtitle:  'Card / Bank Transfer',
              accent:    const Color(0xFF2563EB),
              onTap: () => setState(() {
                _method = _PMethod.paystack;
                _mstep  = _MStep.idle;
                _error  = null;
              }),
            ),
            const SizedBox(height: 10),
            _MethodCard(
              selected:  _method == _PMethod.mpesa,
              icon:      Icons.smartphone_rounded,
              iconColor: const Color(0xFF16A34A),
              iconBg:    const Color(0xFFF0FDF4),
              title:     'M-Pesa',
              subtitle:  'Safaricom Daraja',
              accent:    const Color(0xFF16A34A),
              onTap: () => setState(() {
                _method = _PMethod.mpesa;
                _mstep  = _MStep.idle;
                _error  = null;
              }),
            ),
            if (_method == _PMethod.mpesa &&
                _mstep == _MStep.idle) ...[
              const SizedBox(height: 20),
              const Text('M-Pesa Phone Number',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF374151))),
              const SizedBox(height: 8),
              Row(children: [
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      border: Border.all(
                          color: const Color(0xFFD1D5DB)),
                      borderRadius:
                          const BorderRadius.horizontal(
                              left: Radius.circular(10))),
                  alignment: Alignment.center,
                  child: const Text('+254',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151))),
                ),
                Expanded(
                  child: TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    onChanged: (_) => setState(() {}),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(9),
                    ],
                    style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF111827)),
                    decoration: InputDecoration(
                      hintText: '7XXXXXXXX',
                      hintStyle: const TextStyle(
                          color: Color(0xFF9CA3AF)),
                      contentPadding:
                          const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                      filled: true,
                      fillColor: Colors.white,
                      border: const OutlineInputBorder(
                          borderRadius:
                              BorderRadius.horizontal(
                                  right: Radius.circular(10)),
                          borderSide: BorderSide(
                              color: Color(0xFFD1D5DB))),
                      enabledBorder: const OutlineInputBorder(
                          borderRadius:
                              BorderRadius.horizontal(
                                  right: Radius.circular(10)),
                          borderSide: BorderSide(
                              color: Color(0xFFD1D5DB))),
                      focusedBorder: const OutlineInputBorder(
                          borderRadius:
                              BorderRadius.horizontal(
                                  right: Radius.circular(10)),
                          borderSide: BorderSide(
                              color: Color(0xFF16A34A),
                              width: 2)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              const Text(
                  'Enter the number registered on your M-Pesa '
                  'account.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280))),
            ],
            if (_method == _PMethod.mpesa &&
                _mstep == _MStep.promptSent) ...[
              const SizedBox(height: 16),
              _BannerW(
                icon:      Icons.smartphone_rounded,
                iconColor: const Color(0xFF16A34A),
                bg:        const Color(0xFFF0FDF4),
                border:    const Color(0xFFBBF7D0),
                title: 'STK Push Sent!',
                body: 'Check your phone (+254 ${_phoneCtrl.text}) '
                    'for the M-Pesa prompt and enter your PIN.',
                footer: const Row(children: [
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(
                            Color(0xFF16A34A))),
                  ),
                  SizedBox(width: 8),
                  Text('Waiting for confirmation…',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF16A34A))),
                ]),
              ),
            ],
            if (_method == _PMethod.mpesa &&
                _mstep == _MStep.timedOut) ...[
              const SizedBox(height: 16),
              _BannerW(
                icon:      Icons.access_time_rounded,
                iconColor: const Color(0xFFD97706),
                bg:        const Color(0xFFFFFBEB),
                border:    const Color(0xFFFDE68A),
                title: 'Payment not confirmed yet',
                body: "We didn't receive a confirmation. If you "
                    "completed the payment, it may still be "
                    "processing.",
                footer: GestureDetector(
                  onTap: () => setState(() {
                    _mstep = _MStep.idle;
                    _error = null;
                  }),
                  child: const Text('Try again',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFD97706),
                          decoration:
                              TextDecoration.underline)),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _summaryCard() {
    final o = _order!;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _H(Icons.receipt_long_rounded, 'Payment Summary'),
          const SizedBox(height: 16),
          _SR('Subtotal', 'KES ${_f(o.subTotal)}'),
          if (o.discount > 0)
            _SR('Discount', '-KES ${_f(o.discount)}',
                c: const Color(0xFF16A34A)),
          if (o.tax > 0) _SR('Tax', 'KES ${_f(o.tax)}'),
          _SR('Shipping',
              o.shipping == 0
                  ? 'FREE'
                  : 'KES ${_f(o.shipping)}'),
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827))),
              Text('KES ${_f(o.totalPrice)}',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _payButton() {
    if (_mstep == _MStep.promptSent)
      return const SizedBox.shrink();
    final isP = _method == _PMethod.paystack;
    final isM = _method == _PMethod.mpesa;
    final ok  = (isP || (isM && _phoneCtrl.text.length >= 9)) &&
        !_processing;
    final col = isM
        ? const Color(0xFF16A34A)
        : isP
            ? const Color(0xFF2563EB)
            : const Color(0xFFD1D5DB);

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
          16, 12, 16,
          12 + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_error != null) ...[
          _errBanner(_error!),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: ok ? _handlePay : null,
            style: ElevatedButton.styleFrom(
                backgroundColor:
                    ok ? col : const Color(0xFFE5E7EB),
                foregroundColor: ok
                    ? Colors.white
                    : const Color(0xFF9CA3AF),
                elevation: ok ? 2 : 0,
                shadowColor: col.withOpacity(0.35),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
            child: _processing
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(
                            Colors.white)))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                    Icon(
                      _method == _PMethod.none
                          ? Icons.touch_app_rounded
                          : isM
                              ? Icons.smartphone_rounded
                              : Icons.credit_card_rounded,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _method == _PMethod.none
                          ? 'Select a Payment Method'
                          : isM
                              ? 'Pay with M-Pesa'
                              : 'Pay with Paystack',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                  ]),
          ),
        ),
      ]),
    );
  }

  Widget _paidBar() => Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(
            16, 12, 16,
            12 + MediaQuery.of(context).padding.bottom),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              border: Border.all(
                  color: const Color(0xFFBBF7D0)),
              borderRadius: BorderRadius.circular(12)),
          child: const Row(children: [
            Icon(Icons.check_circle_rounded,
                color: Color(0xFF16A34A), size: 22),
            SizedBox(width: 10),
            Text('Payment Completed',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF15803D))),
          ]),
        ),
      );

  Widget _loadingView() => Scaffold(
        backgroundColor: const Color(0xFFF5F5F7),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation(AppColors.primary)),
              const SizedBox(height: 20),
              const Text('Loading order details…',
                  style: TextStyle(
                      color: Color(0xFF6B7280), fontSize: 14)),
            ],
          ),
        ),
      );

  Widget _errorView() => Scaffold(
        backgroundColor: const Color(0xFFF5F5F7),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 20),
              onPressed: () => Navigator.pop(context)),
          title: const Text('Checkout'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 72, color: Color(0xFFEF4444)),
                const SizedBox(height: 20),
                const Text('Order Not Found',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827))),
                const SizedBox(height: 8),
                Text(_error ?? 'Something went wrong.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 14, height: 1.5)),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.pushNamedAndRemoveUntil(
                          context, '/books', (_) => false),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(12))),
                  child: const Text('Continue Shopping',
                      style: TextStyle(
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _errBanner(String msg) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            border: Border.all(
                color: const Color(0xFFFECACA)),
            borderRadius: BorderRadius.circular(10)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFDC2626), size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(msg,
                    style: const TextStyle(
                        color: Color(0xFF991B1B),
                        fontSize: 13, height: 1.4))),
          ],
        ),
      );

  String _f(double v) => v
      .toStringAsFixed(0)
      .replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  String _mon(int m) => const [
        '',
        'January',   'February', 'March',    'April',
        'May',       'June',     'July',     'August',
        'September', 'October',  'November', 'December',
      ][m];

  String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED CHECKOUT SUB-WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _Card(
      {required this.child,
      this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ]),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      );
}

class _H extends StatelessWidget {
  final IconData icon;
  final String label;
  const _H(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 18, color: const Color(0xFF6B7280)),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
      ]);
}

class _KV extends StatelessWidget {
  final String l, v;
  final bool   mono;
  final Color? vc;
  const _KV(this.l, this.v, {this.mono = false, this.vc});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF6B7280))),
            Text(v,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: vc ?? const Color(0xFF111827),
                    fontFamily: mono ? 'monospace' : null)),
          ],
        ),
      );
}

class _SR extends StatelessWidget {
  final String l, v;
  final Color? c;
  const _SR(this.l, this.v, {this.c});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF6B7280))),
            Text(v,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c ?? const Color(0xFF111827))),
          ],
        ),
      );
}

class _ChipW extends StatelessWidget {
  final String label;
  const _ChipW(this.label);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(6)),
        child: Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF374151))));
}

class _MethodCard extends StatelessWidget {
  final bool     selected;
  final IconData icon;
  final Color    iconColor, iconBg, accent;
  final String   title, subtitle;
  final VoidCallback onTap;

  const _MethodCard({
    required this.selected,  required this.icon,
    required this.iconColor, required this.iconBg,
    required this.title,     required this.subtitle,
    required this.accent,    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: selected ? iconBg : Colors.white,
              border: Border.all(
                  color: selected
                      ? accent
                      : const Color(0xFFE5E7EB),
                  width: selected ? 2 : 1),
              borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: iconColor, size: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827))),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280))),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: selected
                  ? Icon(Icons.check_circle_rounded,
                      key: const ValueKey('c'),
                      color: accent, size: 22)
                  : const Icon(
                      Icons.radio_button_unchecked_rounded,
                      key: ValueKey('e'),
                      color: Color(0xFFD1D5DB),
                      size: 22),
            ),
          ]),
        ),
      );
}

class _BannerW extends StatelessWidget {
  final IconData icon;
  final Color    iconColor, bg, border;
  final String   title, body;
  final Widget   footer;

  const _BannerW({
    required this.icon,   required this.iconColor,
    required this.bg,     required this.border,
    required this.title,  required this.body,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(12)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: iconColor,
                          fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(body,
                      style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF374151),
                          height: 1.4)),
                  const SizedBox(height: 8),
                  footer,
                ],
              ),
            ),
          ],
        ),
      );
}