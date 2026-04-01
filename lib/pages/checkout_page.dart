import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// STATE PERSISTENCE KEYS
// ─────────────────────────────────────────────────────────────────────────────

const _kPrefStep      = 'checkout_step';
const _kPrefFullName  = 'checkout_full_name';
const _kPrefPhone     = 'checkout_phone';
const _kPrefAddress   = 'checkout_address';
const _kPrefCity      = 'checkout_city';
const _kPrefPostal    = 'checkout_postal';
const _kPrefDelivery  = 'checkout_delivery';
const _kPrefOrderJson = 'checkout_order_json';
const _kPrefAuthUrl   = 'checkout_auth_url';

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────

class OrderItem {
  final String id;
  final String contentId;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
  final String title;
  final String author;
  final String? coverImageUrl;

  OrderItem({
    required this.id,
    required this.contentId,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    required this.title,
    required this.author,
    this.coverImageUrl,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final content = json['content'] as Map<String, dynamic>? ?? {};
    return OrderItem(
      id:            json['id']           as String? ?? '',
      contentId:     json['content_id']   as String? ?? '',
      quantity:      (json['quantity']    as num?)?.toInt()    ?? 1,
      unitPrice:     (json['unit_price']  as num?)?.toDouble() ?? 0.0,
      totalPrice:    (json['total_price'] as num?)?.toDouble() ?? 0.0,
      title:         content['title']           as String? ?? 'Unknown Title',
      author:        content['author']          as String? ?? '',
      coverImageUrl: content['cover_image_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id':         id,
    'content_id': contentId,
    'quantity':   quantity,
    'unit_price': unitPrice,
    'total_price': totalPrice,
    'content': {
      'title':           title,
      'author':          author,
      'cover_image_url': coverImageUrl,
    },
  };
}

class Order {
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
  final String? paymentMethod;
  final String createdAt;
  final List<OrderItem> items;

  Order({
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
    this.paymentMethod,
    required this.createdAt,
    required this.items,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    final rawItems = json['order_items'] as List<dynamic>? ?? [];
    return Order(
      id:              json['id']               as String? ?? '',
      orderNumber:     json['order_number']     as String? ?? '—',
      totalPrice:      (json['total_price']     as num?)?.toDouble() ?? 0.0,
      subTotal:        (json['sub_total']       as num?)?.toDouble() ?? 0.0,
      tax:             (json['tax']             as num?)?.toDouble() ?? 0.0,
      shipping:        (json['shipping']        as num?)?.toDouble() ?? 0.0,
      discount:        (json['discount']        as num?)?.toDouble() ?? 0.0,
      status:          json['status']           as String? ?? 'pending',
      paymentStatus:   json['payment_status']   as String? ?? 'pending',
      shippingAddress: json['shipping_address'] as String? ?? '',
      paymentMethod:   json['payment_method']   as String?,
      createdAt:       json['created_at']       as String? ?? '',
      items: rawItems
          .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id':              id,
    'order_number':    orderNumber,
    'total_price':     totalPrice,
    'sub_total':       subTotal,
    'tax':             tax,
    'shipping':        shipping,
    'discount':        discount,
    'status':          status,
    'payment_status':  paymentStatus,
    'shipping_address': shippingAddress,
    'payment_method':  paymentMethod,
    'created_at':      createdAt,
    'order_items':     items.map((i) => i.toJson()).toList(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// CHECKOUT FLOW PAGE
// ─────────────────────────────────────────────────────────────────────────────

class CheckoutFlowPage extends StatefulWidget {
  const CheckoutFlowPage({super.key});

  @override
  State<CheckoutFlowPage> createState() => _CheckoutFlowPageState();
}

class _CheckoutFlowPageState extends State<CheckoutFlowPage> {
  final _supabase = Supabase.instance.client;

  // ── Stepper & loading ────────────────────────────────────────────────────────
  int     _currentStep = 0;
  bool    _isLoading   = false;
  bool    _isRestoring = true;
  String? _errorMessage;

  // ── Order & cached payment URL ───────────────────────────────────────────────
  Order?  _order;
  String? _cachedAuthUrl;

  // ── Polling (fallback when deep link doesn't fire) ───────────────────────────
  Timer?  _pollTimer;
  Timer?  _pollTimeout;

  // ── Form ─────────────────────────────────────────────────────────────────────
  final _formKey              = GlobalKey<FormState>();
  final _fullNameController   = TextEditingController();
  final _phoneController      = TextEditingController();
  final _addressController    = TextEditingController();
  final _cityController       = TextEditingController();
  final _postalCodeController = TextEditingController();
  String _deliveryMethod      = 'standard';

  @override
  void initState() {
    super.initState();
    for (final c in _formControllers) {
      c.addListener(_persistFormFields);
    }
    _restoreState();
  }

  List<TextEditingController> get _formControllers => [
    _fullNameController,
    _phoneController,
    _addressController,
    _cityController,
    _postalCodeController,
  ];

  @override
  void dispose() {
    _stopPolling();
    for (final c in _formControllers) {
      c.removeListener(_persistFormFields);
      c.dispose();
    }
    super.dispose();
  }

  // ── Persist / restore ────────────────────────────────────────────────────────

  Future<void> _persistFormFields() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPrefFullName, _fullNameController.text);
    await p.setString(_kPrefPhone,    _phoneController.text);
    await p.setString(_kPrefAddress,  _addressController.text);
    await p.setString(_kPrefCity,     _cityController.text);
    await p.setString(_kPrefPostal,   _postalCodeController.text);
    await p.setString(_kPrefDelivery, _deliveryMethod);
  }

  Future<void> _persistStep(int step) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kPrefStep, step);
  }

  Future<void> _persistOrder(Order order) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPrefOrderJson, jsonEncode(order.toJson()));
  }

  Future<void> _persistAuthUrl(String url) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPrefAuthUrl, url);
  }

  Future<void> _clearPersistedState() async {
    final p = await SharedPreferences.getInstance();
    for (final key in [
      _kPrefStep, _kPrefFullName, _kPrefPhone, _kPrefAddress,
      _kPrefCity, _kPrefPostal, _kPrefDelivery, _kPrefOrderJson, _kPrefAuthUrl,
    ]) {
      await p.remove(key);
    }
  }

  Future<void> _restoreState() async {
    final p = await SharedPreferences.getInstance();

    final savedName = p.getString(_kPrefFullName);
    if (savedName != null) {
      _fullNameController.text    = savedName;
      _phoneController.text       = p.getString(_kPrefPhone)    ?? '';
      _addressController.text     = p.getString(_kPrefAddress)  ?? '';
      _cityController.text        = p.getString(_kPrefCity)     ?? '';
      _postalCodeController.text  = p.getString(_kPrefPostal)   ?? '';
      _deliveryMethod             = p.getString(_kPrefDelivery) ?? 'standard';
    } else {
      await _loadUserProfile();
    }

    final orderJson = p.getString(_kPrefOrderJson);
    if (orderJson != null) {
      try {
        _order = Order.fromJson(jsonDecode(orderJson) as Map<String, dynamic>);
      } catch (_) {}
    }

    _cachedAuthUrl = p.getString(_kPrefAuthUrl);

    int step = p.getInt(_kPrefStep) ?? 0;
    if (step >= 1 && _order == null) step = 0;
    if (step >= 2 && _order == null) step = 0;

    if (mounted) setState(() { _currentStep = step; _isRestoring = false; });
  }

  Future<void> _loadUserProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    _fullNameController.text = user.userMetadata?['full_name']?.toString() ?? '';
    _phoneController.text    = user.phone ?? '';
  }

  // ── Create order ─────────────────────────────────────────────────────────────

  Future<void> _createOrderDraft() async {
    if (_order != null && _cachedAuthUrl != null && _cachedAuthUrl!.isNotEmpty) {
      debugPrint('[Checkout] Order already exists, skipping edge-function call.');
      return;
    }

    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final user  = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final email = user.email?.trim();
      if (email == null || email.isEmpty) throw Exception('No email found');

      final fullName = _fullNameController.text.trim();
      final phone    = _phoneController.text.trim();
      final address  = _addressController.text.trim();
      final city     = _cityController.text.trim();
      final postal   = _postalCodeController.text.trim();

      if (fullName.length < 3) throw Exception('Full name is too short');
      if (phone.length < 9)    throw Exception('Invalid phone number');
      if (address.isEmpty || city.isEmpty) throw Exception('Address and city required');

      final response = await _supabase.functions.invoke(
        'checkout-initiate',
        body: {
          'customer_info': {
            'fullName': fullName,
            'email':    email,
            'phone':    phone,
          },
          'shipping_address': {
            'address':    address,
            'city':       city,
            'postalCode': postal,
          },
          'delivery_method': {
            'id':            _deliveryMethod,
            'name':          'Standard Delivery',
            'cost':          250.0,
            'estimatedDays': '3-5',
            'description':   'Standard shipping (3-5 business days)',
          },
          'platform': 'mobile',
        },
        headers: {'Content-Type': 'application/json'},
      );

      debugPrint('[Checkout] checkout-initiate status: ${response.status}');
      debugPrint('[Checkout] checkout-initiate data:   ${jsonEncode(response.data)}');

      if (response.status != 200) {
        final d = response.data;
        final msg = d is Map
            ? (d['error'] ?? d['message'] ?? d['details'] ?? 'Server error ${response.status}').toString()
            : 'Server error ${response.status}';
        throw Exception(msg);
      }

      final data    = response.data as Map<String, dynamic>;
      final orderId = data['order_id']          as String?;
      final authUrl = data['authorization_url'] as String?;

      if (orderId == null)            throw Exception('No order ID returned');
      if (authUrl == null || authUrl.isEmpty) throw Exception('No payment URL returned');

      _cachedAuthUrl = authUrl.trim();
      await _persistAuthUrl(_cachedAuthUrl!);

      final orderData = await _supabase
          .from('orders')
          .select('''
            *,
            order_items (
              id, content_id, quantity, unit_price, total_price,
              content:content_id (title, author, cover_image_url)
            )
          ''')
          .eq('id', orderId)
          .single();

      _order = Order.fromJson(orderData);
      await _persistOrder(_order!);

      debugPrint('[Checkout] Order created: ${_order!.id}');

    } catch (e, stack) {
      debugPrint('[Checkout] ERROR: $e\n$stack');
      setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Polling (fallback if deep link doesn't arrive) ────────────────────────────

  void _startPolling(String orderId) {
    _stopPolling();
    debugPrint('[Checkout] Starting payment poll for order $orderId');

    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      try {
        final data = await _supabase
            .from('orders')
            .select('payment_status, order_number')
            .eq('id', orderId)
            .single();

        debugPrint('[Checkout] Poll result: ${data['payment_status']}');

        if (data['payment_status'] == 'paid') {
          _stopPolling();
          // Clear persisted state ONLY after confirmed success
          await _clearPersistedState();
          _goToSuccess(orderId, data['order_number'] as String);
        }
      } catch (e) {
        debugPrint('[Checkout] Poll error: $e');
      }
    });

    // Stop polling after 3 minutes to avoid battery drain
    _pollTimeout = Timer(const Duration(minutes: 3), () {
      debugPrint('[Checkout] Poll timeout reached for order $orderId');
      _stopPolling();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Payment confirmation is taking longer than expected. '
              'Check "My Orders" to confirm your payment status.',
            ),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'My Orders',
              onPressed: () => Navigator.pushNamed(context, '/orders'),
            ),
          ),
        );
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimeout?.cancel();
    _pollTimer   = null;
    _pollTimeout = null;
  }

  void _goToSuccess(String orderId, String orderNumber) {
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/payment-success',
      (_) => false,
      arguments: {'order_id': orderId, 'order_number': orderNumber},
    );
  }

  // ── Pay now ───────────────────────────────────────────────────────────────────

  Future<void> _handlePayNow() async {
    if (_order == null) return;

    final authUrl = _cachedAuthUrl;
    if (authUrl == null || authUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment session expired. Please restart checkout.')),
      );
      return;
    }

    // Start polling BEFORE launching the browser so we catch the webhook
    // update even if the deep link fires late or is missed entirely.
    _startPolling(_order!.id);

    // NOTE: Do NOT clear persisted state here. Clear it only after
    // confirmed success (in _goToSuccess / payment-success page).
    if (mounted) {
      Navigator.pushNamed(
        context,
        '/paystack-webview',
        arguments: {
          'url':          authUrl,
          'order_id':     _order!.id,
          'order_number': _order!.orderNumber,
        },
      );
    }
  }

  // ── Step navigation ───────────────────────────────────────────────────────────

  Future<void> _onStepContinue() async {
    if (_currentStep == 0) {
      if (!(_formKey.currentState?.validate() ?? false)) return;
      await _persistFormFields();

      if (_order != null && _cachedAuthUrl != null && _cachedAuthUrl!.isNotEmpty) {
        debugPrint('[Checkout] Reusing existing order, skipping edge-function call.');
        if (mounted) { setState(() => _currentStep = 1); await _persistStep(1); }
        return;
      }

      await _createOrderDraft();
      if (_order != null && mounted) {
        setState(() => _currentStep = 1);
        await _persistStep(1);
      }

    } else if (_currentStep == 1) {
      setState(() => _currentStep = 2);
      await _persistStep(2);

    } else if (_currentStep == 2) {
      await _handlePayNow();
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _persistStep(_currentStep);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isRestoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_isLoading && _order == null && _currentStep == 0) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 24),
              Text('Creating order…'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _errorMessage != null
          ? _buildErrorView()
          : Stepper(
              type: MediaQuery.of(context).size.width > 600
                  ? StepperType.horizontal
                  : StepperType.vertical,
              currentStep: _currentStep,
              onStepContinue: _isLoading ? null : _onStepContinue,
              onStepCancel:   _currentStep > 0 ? _onStepCancel : null,
              controlsBuilder: _buildStepControls,
              steps: [
                _buildStep0(),
                _buildStep1(),
                _buildStep2(),
              ],
            ),
    );
  }

  // ── Error view ────────────────────────────────────────────────────────────────

  Widget _buildErrorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(_errorMessage!, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => setState(() => _errorMessage = null),
            child: const Text('Try Again'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Go Back'),
          ),
        ],
      ),
    ),
  );

  // ── Controls ──────────────────────────────────────────────────────────────────

  Widget _buildStepControls(BuildContext context, ControlsDetails details) {
    final isLast = _currentStep == 2;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Row(
        children: [
          if (_currentStep > 0)
            OutlinedButton(
              onPressed: _isLoading ? null : details.onStepCancel,
              child: const Text('Back'),
            ),
          const Spacer(),
          ElevatedButton(
            onPressed: _isLoading ? null : details.onStepContinue,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(isLast ? 'Pay Now' : 'Continue'),
          ),
        ],
      ),
    );
  }

  // ── Step 0 : Contact & Delivery ───────────────────────────────────────────────

  Step _buildStep0() => Step(
    title: const Text('Contact & Delivery'),
    isActive: _currentStep >= 0,
    state: _currentStep > 0 ? StepState.complete : StepState.indexed,
    content: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          TextFormField(
            controller: _fullNameController,
            decoration: const InputDecoration(
                labelText: 'Full Name', border: OutlineInputBorder()),
            textCapitalization: TextCapitalization.words,
            validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phoneController,
            decoration: const InputDecoration(
                labelText: 'Phone Number',
                border: OutlineInputBorder(),
                hintText: '+2547XXXXXXXX'),
            keyboardType: TextInputType.phone,
            validator: (v) {
              final val = v?.trim() ?? '';
              if (val.isEmpty) return 'Required';
              if (!val.startsWith('0') && !val.startsWith('+')) {
                return 'Use international format';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _addressController,
            decoration: const InputDecoration(
                labelText: 'Street Address', border: OutlineInputBorder()),
            validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _cityController,
                decoration: const InputDecoration(
                    labelText: 'City', border: OutlineInputBorder()),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _postalCodeController,
                decoration: const InputDecoration(
                    labelText: 'Postal Code', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
            ),
          ]),
          const SizedBox(height: 24),
          const Text('Delivery Method',
              style: TextStyle(fontWeight: FontWeight.w600)),
          RadioListTile<String>(
            title: const Text('Standard (3-5 days) — KES 250'),
            value: 'standard',
            groupValue: _deliveryMethod,
            onChanged: (v) {
              setState(() => _deliveryMethod = v!);
              _persistFormFields();
            },
          ),
        ],
      ),
    ),
  );

  // ── Step 1 : Summary ──────────────────────────────────────────────────────────

  Step _buildStep1() => Step(
    title: const Text('Summary'),
    isActive: _currentStep >= 1,
    state: _currentStep > 1 ? StepState.complete : StepState.indexed,
    content: _order == null
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            child: Column(children: [
              _buildOrderItemsList(),
              const Divider(height: 32),
              _buildSummaryTotals(),
            ]),
          ),
  );

  // ── Step 2 : Payment ──────────────────────────────────────────────────────────

  Step _buildStep2() => Step(
    title: const Text('Payment'),
    isActive: _currentStep >= 2,
    content: _order == null
        ? const Center(child: CircularProgressIndicator())
        : Column(children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  const Icon(Icons.security, size: 48, color: Colors.green),
                  const SizedBox(height: 16),
                  const Text('Secure Payment via Paystack',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    'Total: KES ${_order!.totalPrice.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary),
                  ),
                  const SizedBox(height: 8),
                  Text('Order #${_order!.orderNumber}',
                      style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Row(children: [
                      Icon(Icons.open_in_browser_rounded,
                          color: Color(0xFF2563EB), size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Tapping "Pay Now" will open Paystack in your browser. '
                          'Return to the app after payment — it will confirm automatically.',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFF1E40AF)),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _handlePayNow,
                icon: const Icon(Icons.lock),
                label: const Text('Pay Securely Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ]),
  );

  // ── Order items ───────────────────────────────────────────────────────────────

  Widget _buildOrderItemsList() {
    final items = _order?.items ?? [];
    if (items.isEmpty) return const Text('No items');
    return Column(
      children: items.map((item) => ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 56, height: 72,
            child: CachedNetworkImage(
              imageUrl: item.coverImageUrl ?? '',
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  const Icon(Icons.book_outlined),
              errorWidget: (_, __, ___) =>
                  const Icon(Icons.book_outlined),
            ),
          ),
        ),
        title: Text(item.title,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
            'Qty: ${item.quantity} × KES ${item.unitPrice.toStringAsFixed(0)}'),
        trailing:
            Text('KES ${item.totalPrice.toStringAsFixed(0)}'),
      )).toList(),
    );
  }

  // ── Summary totals ────────────────────────────────────────────────────────────

  Widget _buildSummaryTotals() {
    final o = _order!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        _summaryLine('Subtotal', o.subTotal),
        if (o.discount > 0)
          _summaryLine('Discount', -o.discount, color: Colors.green),
        _summaryLine('Shipping', o.shipping),
        if (o.tax > 0) _summaryLine('Tax', o.tax),
        const Divider(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Total',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            Text(
              'KES ${o.totalPrice.toStringAsFixed(0)}',
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary),
            ),
          ],
        ),
      ]),
    );
  }

  Widget _summaryLine(String label, double amount, {Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.grey)),
            Text(
              amount >= 0
                  ? 'KES ${amount.toStringAsFixed(0)}'
                  : '-KES ${(-amount).toStringAsFixed(0)}',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: color ?? Colors.black87),
            ),
          ],
        ),
      );
}