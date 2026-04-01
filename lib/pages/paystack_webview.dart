import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../theme/app_colors.dart';

class PaystackWebviewPage extends StatefulWidget {
  final String url;
  final String orderId;
  final String orderNumber;

  const PaystackWebviewPage({
    super.key,
    required this.url,
    required this.orderId,
    required this.orderNumber,
  });

  @override
  State<PaystackWebviewPage> createState() => _PaystackWebviewPageState();
}

class _PaystackWebviewPageState extends State<PaystackWebviewPage> {
  final _supabase = Supabase.instance.client;

  late final WebViewController _controller;
  bool _isLoading = true;
  Timer? _pollTimer;
  Timer? _pollTimeout;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _startPolling();
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  // ── Polling ─────────────────────────────────────────────────────────────────

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      try {
        final data = await _supabase
            .from('orders')
            .select('payment_status, order_number')
            .eq('id', widget.orderId)
            .single();
        if (data['payment_status'] == 'paid') {
          _stopPolling();
          _goToSuccess();
        }
      } catch (_) {}
    });

    // Stop polling after 10 minutes (Paystack sessions can take a while)
    _pollTimeout = Timer(const Duration(minutes: 10), _stopPolling);
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimeout?.cancel();
  }

  // ── WebView setup ───────────────────────────────────────────────────────────

  void _initWebView() {
    late final PlatformWebViewControllerCreationParams params;

    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params);

    if (_controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(kDebugMode);
      (_controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.navigate;

            final path = uri.path.toLowerCase();
            final query = uri.queryParameters;

            // Paystack redirects to callback URL after payment
            if (path.contains('payment-success') ||
                path.contains('callback') ||
                query.containsKey('trxref') ||
                query.containsKey('reference')) {
              _stopPolling();
              _goToSuccess();
              return NavigationDecision.prevent;
            }

            // User cancelled
            if (path.contains('cancel') ||
                path.contains('payment-cancel') ||
                path.contains('close')) {
              _stopPolling();
              if (mounted) Navigator.pop(context);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _goToSuccess() {
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/payment-success',
      (_) => false,
      arguments: {
        'order_id':     widget.orderId,
        'order_number': widget.orderNumber,
      },
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, size: 22),
          color: const Color(0xFF1A1A2E),
          onPressed: () {
            _stopPolling();
            Navigator.pop(context);
          },
        ),
        title: const Row(
          children: [
            Icon(Icons.lock_rounded, color: Color(0xFF16A34A), size: 18),
            SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Secure Checkout',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                Text(
                  'Powered by Paystack',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5E7EB)),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Container(
              color: Colors.white,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(AppColors.primary),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Loading payment page…',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 14,
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
}