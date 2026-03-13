import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────

class _OrderItem {
  final String id;
  final String contentId;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
  final String title;
  final String author;
  final String? coverImageUrl;

  _OrderItem({
    required this.id,
    required this.contentId,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    required this.title,
    required this.author,
    this.coverImageUrl,
  });

  factory _OrderItem.fromJson(Map<String, dynamic> json) {
    final content = (json['content'] as Map<String, dynamic>?) ?? {};
    return _OrderItem(
      id:            json['id']           as String? ?? '',
      contentId:     json['content_id']   as String? ?? '',
      quantity:      (json['quantity']    as num?)?.toInt()    ?? 1,
      unitPrice:     (json['unit_price']  as num?)?.toDouble() ?? 0,
      totalPrice:    (json['total_price'] as num?)?.toDouble() ?? 0,
      title:         content['title']           as String? ?? 'Unknown',
      author:        content['author']          as String? ?? '',
      coverImageUrl: content['cover_image_url'] as String?,
    );
  }
}

class _OrderDetails {
  final String id;
  final String orderNumber;
  final double totalPrice;
  final double subTotal;
  final double tax;
  final double shipping;
  final double discount;
  final String status;
  final String paymentStatus;
  final String shippingAddress;
  final String createdAt;
  final List<_OrderItem> items;

  _OrderDetails({
    required this.id,
    required this.orderNumber,
    required this.totalPrice,
    required this.subTotal,
    required this.tax,
    required this.shipping,
    required this.discount,
    required this.status,
    required this.paymentStatus,
    required this.shippingAddress,
    required this.createdAt,
    required this.items,
  });

  factory _OrderDetails.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['order_items'] as List<dynamic>?) ?? [];
    return _OrderDetails(
      id:              json['id']               as String? ?? '',
      orderNumber:     json['order_number']     as String? ?? '—',
      totalPrice:      (json['total_price']     as num?)?.toDouble() ?? 0,
      subTotal:        (json['sub_total']       as num?)?.toDouble() ?? 0,
      tax:             (json['tax']             as num?)?.toDouble() ?? 0,
      shipping:        (json['shipping']        as num?)?.toDouble() ?? 0,
      discount:        (json['discount']        as num?)?.toDouble() ?? 0,
      status:          json['status']           as String? ?? 'pending',
      paymentStatus:   json['payment_status']   as String? ?? 'pending',
      shippingAddress: json['shipping_address'] as String? ?? '',
      createdAt:       json['created_at']       as String? ?? '',
      items: rawItems
          .map((e) => _OrderItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

enum _PaymentMethod { none, paystack, mpesa }
enum _MpesaStep     { idle, promptSent, timedOut }

// ─────────────────────────────────────────────────────────────────────────────
// PAGE
// ─────────────────────────────────────────────────────────────────────────────

class CheckoutPaymentPage extends StatefulWidget {
  final String orderId;
  const CheckoutPaymentPage({super.key, required this.orderId});

  @override
  State<CheckoutPaymentPage> createState() => _CheckoutPaymentPageState();
}

class _CheckoutPaymentPageState extends State<CheckoutPaymentPage>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  _OrderDetails?  _order;
  bool            _loading    = true;
  bool            _processing = false;
  String?         _error;

  _PaymentMethod  _selectedMethod = _PaymentMethod.none;
  _MpesaStep      _mpesaStep      = _MpesaStep.idle;

  final _mpesaController = TextEditingController();

  // ── Polling ──────────────────────────────────────────────────────────────────
  // Polls Supabase every 4 s after payment is launched.
  // Acts as a reliable fallback when the deep link is delayed or missed.
  Timer? _pollTimer;
  Timer? _pollTimeout;
  bool   _paymentLaunched = false; // true once the browser has been opened

  late final AnimationController _fadeCtrl;
  late final Animation<double>    _fadeAnim;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

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
    _stopPolling();
    _mpesaController.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Fetch order ─────────────────────────────────────────────────────────────

  Future<void> _fetchOrder() async {
    setState(() { _loading = true; _error = null; });
    try {
      final session = _supabase.auth.currentSession;
      if (session == null) {
        Navigator.pushReplacementNamed(context, '/auth');
        return;
      }

      final data = await _supabase
          .from('orders')
          .select('''
            *,
            order_items (
              id, content_id, quantity, unit_price, total_price,
              content:content_id (title, author, cover_image_url)
            )
          ''')
          .eq('id', widget.orderId)
          .eq('user_id', session.user.id)
          .single();

      final order = _OrderDetails.fromJson(data);
      if (order.paymentStatus == 'paid') {
        _goToSuccess(order.id, order.orderNumber);
        return;
      }
      setState(() => _order = order);
      _fadeCtrl.forward();
    } catch (e) {
      setState(() => _error = 'Order not found or failed to load.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Paystack ────────────────────────────────────────────────────────────────

  Future<void> _handlePaystack() async {
    if (_order == null) return;
    setState(() { _processing = true; _error = null; });
    try {
      final session = _supabase.auth.currentSession;
      if (session == null) throw Exception('Session expired. Please log in again.');

      final response = await _supabase.functions.invoke(
        'checkout-process-payment',
        body: {
          'order_id': _order!.id,
          // Tell the edge function this is a mobile call so it uses the
          // deep-link callback URL (intercen://payment-callback).
          'platform': 'mobile',
        },
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );

      if (response.status != 200) {
        final msg = (response.data as Map?)?['error'] ?? 'Payment initialization failed';
        throw Exception(msg);
      }

      final authUrl = (response.data as Map?)?['authorization_url'] as String?;
      if (authUrl == null || authUrl.isEmpty) throw Exception('Payment URL not received');

      // Start polling BEFORE opening the browser so we never miss the
      // webhook update even if the deep link fires late.
      _startPolling(widget.orderId);

      setState(() { _paymentLaunched = true; });

      // Navigate to the webview page. State on *this* page stays intact so
      // the poll continues running in the background.
      Navigator.pushNamed(context, '/paystack-webview', arguments: {
        'url':          authUrl,
        'order_id':     _order!.id,
        'order_number': _order!.orderNumber,
      });

    } catch (e) {
      _stopPolling();
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _paymentLaunched = false;
      });
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  // ── M-Pesa ──────────────────────────────────────────────────────────────────

  Future<void> _handleMpesa() async {
    if (_order == null) return;
    final phone = _mpesaController.text.trim();
    if (phone.length < 9) return;

    setState(() { _processing = true; _error = null; });
    try {
      final session = _supabase.auth.currentSession;
      if (session == null) throw Exception('Session expired. Please log in again.');

      final response = await _supabase.functions.invoke(
        'checkout-mpesa-stk-push',
        body: {
          'order_id':     _order!.id,
          'phone_number': '+254$phone',
          'amount':       _order!.totalPrice,
        },
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );

      if (response.status != 200) {
        final msg = (response.data as Map?)?['error'] ?? 'M-Pesa request failed';
        throw Exception(msg);
      }

      setState(() => _mpesaStep = _MpesaStep.promptSent);
      _startPolling(widget.orderId);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  // ── Polling ─────────────────────────────────────────────────────────────────

  void _startPolling(String orderId) {
    _stopPolling();
    debugPrint('[CheckoutPaymentPage] Starting poll for order $orderId');

    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      try {
        final data = await _supabase
            .from('orders')
            .select('payment_status, order_number')
            .eq('id', orderId)
            .single();

        debugPrint('[CheckoutPaymentPage] Poll: ${data['payment_status']}');

        if (data['payment_status'] == 'paid') {
          _stopPolling();
          _goToSuccess(orderId, data['order_number'] as String);
        }
      } catch (e) {
        debugPrint('[CheckoutPaymentPage] Poll error: $e');
      }
    });

    // Timeout after 3 minutes; show a helpful message instead of hanging.
    _pollTimeout = Timer(const Duration(minutes: 3), () {
      debugPrint('[CheckoutPaymentPage] Poll timeout for order $orderId');
      _stopPolling();
      if (mounted) {
        setState(() => _mpesaStep = _MpesaStep.timedOut);
        if (_selectedMethod == _PaymentMethod.paystack) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Payment confirmation is taking longer than expected. '
                'Check "My Orders" to confirm your status.',
              ),
              duration: const Duration(seconds: 8),
              action: SnackBarAction(
                label: 'My Orders',
                onPressed: () => Navigator.pushNamed(context, '/orders'),
              ),
            ),
          );
        }
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimeout?.cancel();
    _pollTimer   = null;
    _pollTimeout = null;
  }

  void _retryMpesa() => setState(() {
    _mpesaStep      = _MpesaStep.idle;
    _paymentLaunched = false;
    _error          = null;
  });

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _goToSuccess(String orderId, String orderNumber) {
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context, '/payment-success', (_) => false,
      arguments: {'order_id': orderId, 'order_number': orderNumber},
    );
  }

  void _handlePay() {
    if (_selectedMethod == _PaymentMethod.paystack) _handlePaystack();
    if (_selectedMethod == _PaymentMethod.mpesa)    _handleMpesa();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading)                         return _loadingScaffold();
    if (_error != null && _order == null) return _fatalErrorScaffold();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: _appBar(),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            _orderInfoCard(),
            const SizedBox(height: 16),
            if ((_order?.items ?? []).isNotEmpty) _orderItemsCard(),
            if ((_order?.items ?? []).isNotEmpty) const SizedBox(height: 16),
            _shippingCard(),
            const SizedBox(height: 16),
            if (_order?.paymentStatus != 'paid') _paymentMethodCard(),
            if (_order?.paymentStatus != 'paid') const SizedBox(height: 16),
            _summaryCard(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _errorBanner(_error!),
            ],
            // ── Waiting banner shown after Paystack browser has been opened ──
            if (_paymentLaunched &&
                _selectedMethod == _PaymentMethod.paystack &&
                _order?.paymentStatus != 'paid') ...[
              const SizedBox(height: 12),
              _paymentWaitingBanner(),
            ],
          ],
        ),
      ),
      bottomNavigationBar: _order?.paymentStatus == 'paid'
          ? _paidBanner()
          : _bottomPayButton(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PAYMENT WAITING BANNER (replaces stuck "waiting" state)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _paymentWaitingBanner() => _Banner(
    icon: Icons.open_in_browser_rounded,
    iconColor:  const Color(0xFF2563EB),
    bg:         const Color(0xFFEFF6FF),
    border:     const Color(0xFFBFDBFE),
    title:      'Browser opened for payment',
    body:       'Complete the payment in the browser. '
                'This screen will update automatically once confirmed.',
    footer: Row(
      children: [
        const SizedBox(
          width: 14, height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(Color(0xFF2563EB)),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'Waiting for confirmation…',
          style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w500,
            color: Color(0xFF2563EB),
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => Navigator.pushNamed(context, '/orders'),
          child: const Text(
            'Check My Orders',
            style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700,
              color: Color(0xFF2563EB),
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    ),
  );

  // ─────────────────────────────────────────────────────────────────────────
  // APP BAR
  // ─────────────────────────────────────────────────────────────────────────

  PreferredSizeWidget _appBar() => AppBar(
    backgroundColor: Colors.white,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    titleSpacing: 0,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
      color: const Color(0xFF1A1A2E),
      onPressed: () => Navigator.pop(context),
    ),
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Complete Payment',
          style: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E),
          ),
        ),
        if (_order != null)
          Text(
            'Order #${_order!.orderNumber}',
            style: const TextStyle(
              fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w400,
            ),
          ),
      ],
    ),
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(1),
      child: Container(height: 1, color: const Color(0xFFE5E7EB)),
    ),
  );

  // ─────────────────────────────────────────────────────────────────────────
  // ORDER INFO CARD
  // ─────────────────────────────────────────────────────────────────────────

  Widget _orderInfoCard() {
    final o = _order!;
    final dt = DateTime.tryParse(o.createdAt);
    final dateStr = dt != null
        ? '${_month(dt.month)} ${dt.day}, ${dt.year}'
        : o.createdAt;

    Color statusColor;
    if (o.paymentStatus == 'paid')         statusColor = const Color(0xFF16A34A);
    else if (o.paymentStatus == 'pending') statusColor = const Color(0xFFD97706);
    else                                   statusColor = const Color(0xFFDC2626);

    return _Tile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(icon: Icons.inventory_2_outlined, label: 'Order Details'),
          const SizedBox(height: 16),
          _Row(label: 'Order Number', value: o.orderNumber, mono: true),
          _Row(label: 'Date',         value: dateStr),
          _Row(label: 'Status',       value: _cap(o.status)),
          _Row(
            label: 'Payment',
            value: _cap(o.paymentStatus),
            valueColor: statusColor,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ORDER ITEMS CARD
  // ─────────────────────────────────────────────────────────────────────────

  Widget _orderItemsCard() {
    return _Tile(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: _Header(icon: Icons.menu_book_rounded, label: 'Order Items'),
          ),
          ..._order!.items.asMap().entries.map((e) => Column(children: [
            if (e.key > 0)
              const Divider(height: 1, indent: 20, endIndent: 20),
            _itemTile(e.value),
          ])),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _itemTile(_OrderItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  child: const Icon(Icons.book_outlined, color: Color(0xFF9CA3AF)),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: const Color(0xFFE5E7EB),
                  child: const Icon(Icons.book_outlined, color: Color(0xFF9CA3AF)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                if (item.author.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'by ${item.author}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Chip('Qty: ${item.quantity}'),
                    const SizedBox(width: 8),
                    Text(
                      'KES ${_fmt(item.unitPrice)}',
                      style: TextStyle(
                        fontSize: 12, color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            'KES ${_fmt(item.totalPrice)}',
            style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHIPPING CARD
  // ─────────────────────────────────────────────────────────────────────────

  Widget _shippingCard() => _Tile(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(icon: Icons.local_shipping_outlined, label: 'Shipping Address'),
        const SizedBox(height: 12),
        Text(
          _order!.shippingAddress,
          style: const TextStyle(
            fontSize: 14, color: Color(0xFF4B5563), height: 1.5,
          ),
        ),
      ],
    ),
  );

  // ─────────────────────────────────────────────────────────────────────────
  // PAYMENT METHOD CARD
  // ─────────────────────────────────────────────────────────────────────────

  Widget _paymentMethodCard() {
    return _Tile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(icon: Icons.payment_rounded, label: 'Choose Payment Method'),
          const SizedBox(height: 16),

          // Paystack
          _MethodTile(
            selected:   _selectedMethod == _PaymentMethod.paystack,
            icon:       Icons.credit_card_rounded,
            iconColor:  const Color(0xFF2563EB),
            iconBg:     const Color(0xFFEFF6FF),
            title:      'Paystack',
            subtitle:   'Card / Bank Transfer',
            accent:     const Color(0xFF2563EB),
            onTap: () => setState(() {
              _selectedMethod  = _PaymentMethod.paystack;
              _mpesaStep       = _MpesaStep.idle;
              _paymentLaunched = false;
              _error           = null;
            }),
          ),

          const SizedBox(height: 10),

          // M-Pesa
          _MethodTile(
            selected:   _selectedMethod == _PaymentMethod.mpesa,
            icon:       Icons.smartphone_rounded,
            iconColor:  const Color(0xFF16A34A),
            iconBg:     const Color(0xFFF0FDF4),
            title:      'M-Pesa',
            subtitle:   'Safaricom Daraja',
            accent:     const Color(0xFF16A34A),
            onTap: () => setState(() {
              _selectedMethod  = _PaymentMethod.mpesa;
              _mpesaStep       = _MpesaStep.idle;
              _paymentLaunched = false;
              _error           = null;
            }),
          ),

          // Phone input (M-Pesa idle)
          if (_selectedMethod == _PaymentMethod.mpesa &&
              _mpesaStep == _MpesaStep.idle) ...[
            const SizedBox(height: 20),
            const Text(
              'M-Pesa Phone Number',
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
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
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: Color(0xFF374151),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _mpesaController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(9),
                    ],
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
                    decoration: InputDecoration(
                      hintText: '7XXXXXXXX',
                      hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.horizontal(
                          right: Radius.circular(10),
                        ),
                        borderSide: BorderSide(color: Color(0xFFD1D5DB)),
                      ),
                      enabledBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.horizontal(
                          right: Radius.circular(10),
                        ),
                        borderSide: BorderSide(color: Color(0xFFD1D5DB)),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.horizontal(
                          right: Radius.circular(10),
                        ),
                        borderSide: BorderSide(
                          color: Color(0xFF16A34A), width: 2,
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
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ],

          // STK sent
          if (_selectedMethod == _PaymentMethod.mpesa &&
              _mpesaStep == _MpesaStep.promptSent) ...[
            const SizedBox(height: 16),
            _Banner(
              icon: Icons.smartphone_rounded,
              iconColor:   const Color(0xFF16A34A),
              bg:          const Color(0xFFF0FDF4),
              border:      const Color(0xFFBBF7D0),
              title: 'STK Push Sent!',
              body: 'Check your phone (+254 ${_mpesaController.text}) '
                  'for the M-Pesa prompt and enter your PIN.',
              footer: const Row(
                children: [
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation(Color(0xFF16A34A)),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Waiting for confirmation…',
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Timed out
          if (_selectedMethod == _PaymentMethod.mpesa &&
              _mpesaStep == _MpesaStep.timedOut) ...[
            const SizedBox(height: 16),
            _Banner(
              icon: Icons.access_time_rounded,
              iconColor:   const Color(0xFFD97706),
              bg:          const Color(0xFFFFFBEB),
              border:      const Color(0xFFFDE68A),
              title: 'Payment not confirmed yet',
              body: "We didn't receive a confirmation. If you completed "
                  "the payment, it may still be processing.",
              footer: GestureDetector(
                onTap: _retryMpesa,
                child: const Text(
                  'Try again',
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
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

  // ─────────────────────────────────────────────────────────────────────────
  // SUMMARY CARD
  // ─────────────────────────────────────────────────────────────────────────

  Widget _summaryCard() {
    final o = _order!;
    return _Tile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(icon: Icons.receipt_long_rounded, label: 'Payment Summary'),
          const SizedBox(height: 16),
          _SumRow('Subtotal', 'KES ${_fmt(o.subTotal)}'),
          if (o.discount > 0)
            _SumRow('Discount', '-KES ${_fmt(o.discount)}',
                color: const Color(0xFF16A34A)),
          if (o.tax > 0) _SumRow('Tax', 'KES ${_fmt(o.tax)}'),
          _SumRow(
            'Shipping',
            o.shipping == 0 ? 'FREE' : 'KES ${_fmt(o.shipping)}',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              Text(
                'KES ${_fmt(o.totalPrice)}',
                style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BOTTOM PAY BUTTON
  // ─────────────────────────────────────────────────────────────────────────

  Widget _bottomPayButton() {
    // Hide pay button while Paystack browser is open; show waiting state instead
    if (_paymentLaunched && _selectedMethod == _PaymentMethod.paystack) {
      return Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(
          16, 12, 16,
          12 + MediaQuery.of(context).padding.bottom,
        ),
        child: OutlinedButton.icon(
          onPressed: () => Navigator.pushNamed(context, '/orders'),
          icon: const Icon(Icons.list_alt_rounded),
          label: const Text('View My Orders'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );
    }

    if (_mpesaStep == _MpesaStep.promptSent) return const SizedBox.shrink();

    final isPaystack = _selectedMethod == _PaymentMethod.paystack;
    final isMpesa    = _selectedMethod == _PaymentMethod.mpesa;
    final mpesaReady = isMpesa && _mpesaController.text.length >= 9;
    final canPay     = (isPaystack || mpesaReady) && !_processing;

    final Color btnColor = isMpesa
        ? const Color(0xFF16A34A)
        : isPaystack
            ? const Color(0xFF2563EB)
            : const Color(0xFFD1D5DB);

    final String btnLabel = _selectedMethod == _PaymentMethod.none
        ? 'Select a Payment Method'
        : isMpesa
            ? 'Pay with M-Pesa'
            : 'Pay with Paystack';

    final IconData btnIcon = _selectedMethod == _PaymentMethod.none
        ? Icons.touch_app_rounded
        : isMpesa
            ? Icons.smartphone_rounded
            : Icons.credit_card_rounded;

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        16, 12, 16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) ...[
            _errorBanner(_error!),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: canPay ? _handlePay : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: canPay ? btnColor : const Color(0xFFE5E7EB),
                foregroundColor: canPay ? Colors.white : const Color(0xFF9CA3AF),
                elevation: canPay ? 2 : 0,
                shadowColor: btnColor.withOpacity(0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _processing
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor:
                            AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(btnIcon, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          btnLabel,
                          style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700,
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

  Widget _paidBanner() => Container(
    color: Colors.white,
    padding: EdgeInsets.fromLTRB(
      16, 12, 16,
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
        children: [
          Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 22),
          SizedBox(width: 10),
          Text(
            'Payment Completed',
            style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700,
              color: Color(0xFF15803D),
            ),
          ),
        ],
      ),
    ),
  );

  // ─────────────────────────────────────────────────────────────────────────
  // LOADING / FATAL ERROR SCAFFOLDS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _loadingScaffold() => Scaffold(
    backgroundColor: const Color(0xFFF5F5F7),
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(AppColors.primary),
          ),
          const SizedBox(height: 20),
          const Text(
            'Loading order details…',
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
          ),
        ],
      ),
    ),
  );

  Widget _fatalErrorScaffold() => Scaffold(
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
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 72, color: Color(0xFFEF4444)),
            const SizedBox(height: 20),
            const Text(
              'Order Not Found',
              style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF6B7280), fontSize: 14, height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.pushNamedAndRemoveUntil(
                context, '/books', (_) => false,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Continue Shopping',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _errorBanner(String msg) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFEF2F2),
      border: Border.all(color: const Color(0xFFFECACA)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline_rounded,
            color: Color(0xFFDC2626), size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            msg,
            style: const TextStyle(
              color: Color(0xFF991B1B), fontSize: 13, height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  String _fmt(double v) => v.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

  String _month(int m) => const [
        '', 'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ][m];

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _Tile extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _Tile({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class _Header extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Header({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: const Color(0xFF6B7280)),
      const SizedBox(width: 8),
      Text(
        label,
        style: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827),
        ),
      ),
    ],
  );
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  final Color? valueColor;
  const _Row({
    required this.label,
    required this.value,
    this.mono = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
        Text(
          value,
          style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600,
            color: valueColor ?? const Color(0xFF111827),
            fontFamily: mono ? 'monospace' : null,
          ),
        ),
      ],
    ),
  );
}

class _SumRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _SumRow(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
        Text(
          value,
          style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600,
            color: color ?? const Color(0xFF111827),
          ),
        ),
      ],
    ),
  );
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip(this.label);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF374151),
      ),
    ),
  );
}

class _MethodTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _MethodTile({
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
  Widget build(BuildContext context) => GestureDetector(
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
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: iconBg, borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    )),
                Text(subtitle,
                    style: const TextStyle(
                      fontSize: 12, color: Color(0xFF6B7280),
                    )),
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: selected
                ? Icon(Icons.check_circle_rounded,
                    key: const ValueKey('check'), color: accent, size: 22)
                : const Icon(Icons.radio_button_unchecked_rounded,
                    key: ValueKey('empty'),
                    color: Color(0xFFD1D5DB), size: 22),
          ),
        ],
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bg;
  final Color border;
  final String title;
  final String body;
  final Widget footer;

  const _Banner({
    required this.icon,
    required this.iconColor,
    required this.bg,
    required this.border,
    required this.title,
    required this.body,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: bg,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(12),
    ),
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
                    color: iconColor, fontSize: 14,
                  )),
              const SizedBox(height: 4),
              Text(body,
                  style: const TextStyle(
                    fontSize: 13, color: Color(0xFF374151), height: 1.4,
                  )),
              const SizedBox(height: 8),
              footer,
            ],
          ),
        ),
      ],
    ),
  );
}