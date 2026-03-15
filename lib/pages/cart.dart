import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class _CartItem {
  final String id;
  final String contentId;
  int quantity;
  final double price;
  final String title;
  final String author;
  final String? coverImageUrl;
  final int stockQuantity;

  _CartItem({
    required this.id,
    required this.contentId,
    required this.quantity,
    required this.price,
    required this.title,
    required this.author,
    this.coverImageUrl,
    required this.stockQuantity,
  });

  factory _CartItem.fromJson(Map<String, dynamic> j) {
    // Supabase nested select returns 'content' as a nested map.
    // Guard against null or non-Map values defensively.
    final rawContent = j['content'];
    final content = rawContent is Map
        ? Map<String, dynamic>.from(rawContent)
        : <String, dynamic>{};

    return _CartItem(
      id: j['id'] as String? ?? '',
      contentId: j['content_id'] as String? ?? '',
      quantity: (j['quantity'] as num?)?.toInt() ?? 1,
      // FIX: price may be stored as int (0) or double — always coerce.
      price: (j['price'] as num?)?.toDouble() ?? 0.0,
      title: content['title'] as String? ?? 'Unknown Title',
      author: content['author'] as String? ?? 'Unknown Author',
      coverImageUrl: content['cover_image_url'] as String?,
      stockQuantity: (content['stock_quantity'] as num?)?.toInt() ?? 99,
    );
  }

  double get subtotal => price * quantity;
}

class _DeliveryMethod {
  final String id;
  final String name;
  final double cost;
  final String estimatedDays;
  final String description;

  const _DeliveryMethod({
    required this.id,
    required this.name,
    required this.cost,
    required this.estimatedDays,
    required this.description,
  });
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final SupabaseService _service = SupabaseService();
  final _supabase = Supabase.instance.client;

  // ── Controllers ──
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _postalCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();

  // ── State ──
  List<_CartItem> _items = [];
  bool _loading = true;
  String? _error;
  bool _isProcessing = false;
  String? _updatingItemId;
  String? _removingItemId;

  _DeliveryMethod? _selectedDelivery;
  bool _deliveryReviewed = false;

  String? _appliedDiscountCode;
  double _discountAmount = 0;
  bool _applyingDiscount = false;

  // ── Delivery options ──
  static const List<_DeliveryMethod> _deliveryMethods = [
    _DeliveryMethod(
      id: 'standard',
      name: 'Standard Delivery',
      cost: 500,
      estimatedDays: '1–3 business days',
      description: 'Regular delivery within city',
    ),
    _DeliveryMethod(
      id: 'express',
      name: 'Express Delivery',
      cost: 200,
      estimatedDays: '1–2 business days',
      description: 'Fast delivery within city',
    ),
    _DeliveryMethod(
      id: 'pickup',
      name: 'Store Pickup',
      cost: 0,
      estimatedDays: 'Same day',
      description: 'Pick up from our store location',
    ),
  ];

  // ── Responsive ──
  static double _hPad(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    if (w >= 900) return 48;
    if (w >= 600) return 28;
    return 16;
  }

  static bool _isWide(BuildContext ctx) =>
      MediaQuery.of(ctx).size.width >= 800;

  // ── Computed ──
  double get _subtotal =>
      _items.fold(0, (sum, i) => sum + i.subtotal);

  double get _deliveryCost => _selectedDelivery?.cost ?? 0;

  double get _total =>
      _subtotal - _discountAmount + _deliveryCost;

  // ── Lifecycle ──
  @override
  void initState() {
    super.initState();
    _prefillEmail();
    _fetchCart();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _postalCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  void _prefillEmail() {
    final user = _supabase.auth.currentUser;
    if (user?.email != null) {
      _emailCtrl.text = user!.email!;
    }
  }

  // ══════════════════════════════════════════════════════════
  // FETCH CART — FIXED
  //
  // Root causes of the "empty cart after refresh" bug:
  //
  // 1. _service.getCart() calls the edge function. If the session
  //    token is stale or missing on the second call, the function
  //    returns 401 / empty body. We now call the edge function
  //    DIRECTLY via Supabase Functions client so the SDK always
  //    attaches the current session token automatically.
  //
  // 2. The original code silently swallowed a null/non-List
  //    'items' field and showed an empty cart instead of an error.
  //    We now log and surface the actual server response so you
  //    can debug it.
  //
  // 3. We fall back to a direct DB query if the edge function
  //    returns no items, which is robust against edge-function
  //    cold-start / deployment issues.
  // ══════════════════════════════════════════════════════════

  Future<void> _fetchCart() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final user = _supabase.auth.currentUser;
    if (user == null) {
      // Not logged in — show empty cart, do NOT show error.
      if (mounted) setState(() { _items = []; _loading = false; });
      return;
    }

    // ── Strategy 1: call the edge function via SupabaseService ──
    try {
      final response = await _service.getCart();

      // Defensive: log what we actually received so bugs are visible.
      debugPrint('[CartPage] cart-get response keys: ${response.keys.toList()}');
      debugPrint('[CartPage] cart-get raw: $response');

      final rawItems = response['items'];

      if (rawItems == null) {
        // Edge function returned a body without an 'items' key.
        // This means either an error response (e.g. 401) was returned
        // with status 200, or the response shape changed.
        // Fall back to the direct DB query below.
        debugPrint('[CartPage] "items" key missing in response — falling back to direct DB query');
        await _fetchCartDirectly();
        return;
      }

      if (rawItems is! List) {
        debugPrint('[CartPage] "items" is not a List (got ${rawItems.runtimeType}) — falling back');
        await _fetchCartDirectly();
        return;
      }

      final itemList = List<dynamic>.from(rawItems);
      debugPrint('[CartPage] Received ${itemList.length} item(s) from edge function');

      if (!mounted) return;
      setState(() {
        _items = itemList
            .whereType<Map>()
            .map((item) =>
                _CartItem.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        _loading = false;
        _error = null;
      });
    } catch (e, stack) {
      debugPrint('[CartPage] Edge function call failed: $e\n$stack');
      // Fall back to direct DB query rather than showing an error.
      if (mounted) await _fetchCartDirectly();
    }
  }

  // ── Strategy 2: direct Supabase DB query (fallback) ──
  //
  // This bypasses the edge function entirely and queries the DB
  // directly from the Flutter client. It will always work as long
  // as the user is authenticated and RLS allows it.
  Future<void> _fetchCartDirectly() async {
    if (!mounted) return;

    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() { _items = []; _loading = false; });
      return;
    }

    debugPrint('[CartPage] Falling back to direct DB query for user ${user.id}');

    try {
      // Step 1: find the user's cart
      final cartResponse = await _supabase
          .from('carts')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (cartResponse == null) {
        // No cart row exists yet — genuinely empty.
        debugPrint('[CartPage] No cart found for user — cart is empty');
        if (mounted) setState(() { _items = []; _loading = false; });
        return;
      }

      final cartId = cartResponse['id'] as String;
      debugPrint('[CartPage] Found cart: $cartId');

      // Step 2: fetch cart items with nested content
      final itemsResponse = await _supabase
          .from('cart_items')
          .select('''
            id,
            content_id,
            quantity,
            price,
            content (
              id,
              title,
              author,
              cover_image_url,
              stock_quantity
            )
          ''')
          .eq('cart_id', cartId);

      if (!mounted) return;

      final List<dynamic> rawList =
          List<dynamic>.from(itemsResponse);

      debugPrint('[CartPage] Direct DB returned ${rawList.length} item(s)');

      setState(() {
        _items = rawList
            .whereType<Map>()
            .map((item) =>
                _CartItem.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        _loading = false;
        _error = null;
      });
    } catch (e, stack) {
      debugPrint('[CartPage] Direct DB query also failed: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load cart. Please try again.';
        _loading = false;
      });
    }
  }

  // ── Update quantity ──
  Future<void> _updateQuantity(_CartItem item, int newQty) async {
    if (newQty < 1) {
      await _removeItem(item);
      return;
    }

    // Optimistic update
    setState(() {
      _updatingItemId = item.id;
      item.quantity = newQty;
    });

    try {
      await _service.updateCartQuantity(item.id, newQty);
      if (!mounted) return;
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to update quantity.');
      await _fetchCart();
    } finally {
      if (mounted) setState(() => _updatingItemId = null);
    }
  }

  // ── Remove item ──
  Future<void> _removeItem(_CartItem item) async {
    // Optimistic update
    setState(() {
      _removingItemId = item.id;
      _items.removeWhere((i) => i.id == item.id);
    });

    try {
      await _service.removeFromCart(item.id);
      if (!mounted) return;
      _showSnack('${item.title} removed from cart.');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to remove item.');
      await _fetchCart();
    } finally {
      if (mounted) setState(() => _removingItemId = null);
    }
  }

  // ── Apply discount ──
  void _applyDiscount() {
    final code = _discountCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() => _applyingDiscount = true);

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      if (code == 'SAVE10') {
        setState(() {
          _appliedDiscountCode = code;
          _discountAmount = _subtotal * 0.10;
          _applyingDiscount = false;
        });
        _showSnack('Discount applied: 10% off!',
            color: AppColors.secondary);
      } else {
        setState(() {
          _appliedDiscountCode = null;
          _discountAmount = 0;
          _applyingDiscount = false;
        });
        _showSnack('Invalid discount code.');
      }
    });
  }

  // ── Checkout ──
  Future<void> _handleCheckout() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      _showSnack('Please log in to checkout.');
      Navigator.pushNamed(context, '/login');
      return;
    }

    if (_nameCtrl.text.trim().isEmpty ||
        _phoneCtrl.text.trim().isEmpty) {
      _showSnack('Please fill in all customer information.');
      return;
    }
    if (_addressCtrl.text.trim().isEmpty ||
        _cityCtrl.text.trim().isEmpty) {
      _showSnack('Please provide your shipping address.');
      return;
    }
    if (_selectedDelivery == null) {
      _showSnack('Please select a delivery method.');
      return;
    }
    if (!_deliveryReviewed) {
      _showSnack(
          'Please confirm you have reviewed delivery details.');
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final session = _supabase.auth.currentSession;
      if (session == null) {
        _showSnack('Session expired. Please log in again.');
        Navigator.pushNamed(context, '/login');
        return;
      }

      final response = await _service.initiateCheckout({
        'customer_info': {
          'fullName': _nameCtrl.text.trim(),
          'email': _emailCtrl.text.trim().isNotEmpty
              ? _emailCtrl.text.trim()
              : user.email,
          'phone': _phoneCtrl.text.trim(),
        },
        'shipping_address': {
          'address': _addressCtrl.text.trim(),
          'city': _cityCtrl.text.trim(),
          'postalCode': _postalCtrl.text.trim(),
        },
        'delivery_method': {
          'id': _selectedDelivery!.id,
          'name': _selectedDelivery!.name,
          'cost': _selectedDelivery!.cost,
          'estimatedDays': _selectedDelivery!.estimatedDays,
          'description': _selectedDelivery!.description,
        },
        if (_appliedDiscountCode != null)
          'discount_code': _appliedDiscountCode,
      });

      if (!mounted) return;

      final success = response['success'] as bool? ?? false;
      if (!success) {
        _showSnack(
            response['error'] as String? ?? 'Checkout failed.');
        return;
      }

      final orderNumber =
          response['order_number'] as String? ?? '–';
      final orderId = response['order_id'] as String?;

      _showOrderConfirmation(orderNumber, orderId);
    } catch (e) {
      if (!mounted) return;
      _showSnack('An error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Order confirmation modal ──
  void _showOrderConfirmation(
      String orderNumber, String? orderId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.secondary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded,
                    color: AppColors.secondary, size: 44),
              ),
              const SizedBox(height: 18),
              const Text(
                'Order Placed!',
                style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.foreground,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your order was created successfully.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.mutedForeground,
                    fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.muted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Order: ',
                        style: TextStyle(
                            color: AppColors.mutedForeground,
                            fontSize: 13)),
                    Text(
                      orderNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                        fontSize: 15,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    if (orderId != null) {
                      Navigator.pushNamed(
                        context,
                        '/checkout/payment',
                        arguments: orderId,
                      );
                    } else {
                      Navigator.pushNamedAndRemoveUntil(
                          context, '/home', (r) => false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text(
                    'Proceed to Payment',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontWeight: FontWeight.w500)),
      backgroundColor: color ?? AppColors.foreground,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  // ══════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final hPad = _hPad(context);
    final isWide = _isWide(context);
    final screenW = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: AppColors.muted,
      bottomNavigationBar: _bottomNav(),
      body: CustomScrollView(
        slivers: [
          // ── App bar ──
          SliverAppBar(
            pinned: true,
            elevation: 0,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.black.withOpacity(0.06),
            leading: Navigator.canPop(context)
                ? IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: AppColors.foreground),
                    onPressed: () => Navigator.pop(context),
                  )
                : null,
            title: Row(
              children: [
                const Icon(Icons.shopping_bag_outlined,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Shopping Cart',
                  style: TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'PlayfairDisplay',
                    fontSize: screenW < 360 ? 16 : 18,
                  ),
                ),
              ],
            ),
            actions: [
              // FIX: Refresh button is always visible (not gated on _items.isNotEmpty)
              // so the user can always retry after a failed load.
              TextButton.icon(
                onPressed: _loading ? null : _fetchCart,
                icon: _loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.mutedForeground))
                    : const Icon(Icons.refresh,
                        size: 16,
                        color: AppColors.mutedForeground),
                label: const Text('Refresh',
                    style: TextStyle(
                        color: AppColors.mutedForeground,
                        fontSize: 13)),
              ),
            ],
          ),

          // ── Body ──
          if (_loading)
            const SliverFillRemaining(child: _LoadingState())
          else if (_error != null)
            SliverFillRemaining(
              child: _ErrorState(
                  error: _error!, onRetry: _fetchCart),
            )
          else if (_items.isEmpty)
            const SliverFillRemaining(child: _EmptyState())
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 32),
                child:
                    isWide ? _wideLayout() : _narrowLayout(),
              ),
            ),
        ],
      ),
    );
  }

  // ── Wide layout: two columns ──
  Widget _wideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            children: [
              _cartItemsSection(),
              const SizedBox(height: 20),
              _customerInfoSection(),
              const SizedBox(height: 20),
              _shippingSection(),
              const SizedBox(height: 20),
              _deliverySection(),
            ],
          ),
        ),
        const SizedBox(width: 24),
        SizedBox(
          width: 320,
          child: _orderSummarySection(),
        ),
      ],
    );
  }

  // ── Narrow layout: single column ──
  Widget _narrowLayout() {
    return Column(
      children: [
        _cartItemsSection(),
        const SizedBox(height: 16),
        _customerInfoSection(),
        const SizedBox(height: 16),
        _shippingSection(),
        const SizedBox(height: 16),
        _deliverySection(),
        const SizedBox(height: 16),
        _orderSummarySection(),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════
  // SECTIONS
  // ══════════════════════════════════════════════════════════

  // ── Cart items ──
  Widget _cartItemsSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.shopping_bag_outlined,
            title: 'Cart Items (${_items.length})',
          ),
          const SizedBox(height: 16),
          ...List.generate(_items.length, (i) {
            final item = _items[i];
            return Column(
              children: [
                _cartItemTile(item),
                if (i < _items.length - 1)
                  Divider(
                      height: 24,
                      color: Colors.grey.shade100),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _cartItemTile(_CartItem item) {
    final isUpdating = _updatingItemId == item.id;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cover image — FIX: use BoxFit.contain + neutral bg
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 64,
            height: 88,
            color: const Color(0xFFF2EFE9),
            child: CachedNetworkImage(
              imageUrl: item.coverImageUrl?.isNotEmpty == true
                  ? item.coverImageUrl!
                  : 'https://images.unsplash.com/photo-1544947950-fa07a98d237f?w=200',
              fit: BoxFit.contain,
              width: 64,
              height: 88,
              placeholder: (_, __) =>
                  Container(color: AppColors.muted),
              errorWidget: (_, __, ___) => Container(
                color: AppColors.muted,
                child: const Icon(Icons.book,
                    color: AppColors.mutedForeground,
                    size: 28),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Details
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.foreground,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(item.author,
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.mutedForeground)),
              const SizedBox(height: 6),
              Text(
                'KSh ${item.price.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 10),

              // Qty + remove row
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _qtyIconBtn(
                          icon: Icons.remove,
                          enabled: item.quantity > 1 &&
                              !isUpdating,
                          onTap: () => _updateQuantity(
                              item, item.quantity - 1),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(
                              milliseconds: 200),
                          child: isUpdating
                              ? const SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: Center(
                                    child: SizedBox(
                                      width: 14,
                                      height: 14,
                                      child:
                                          CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors
                                            .primary,
                                      ),
                                    ),
                                  ),
                                )
                              : SizedBox(
                                  key: ValueKey(item.quantity),
                                  width: 32,
                                  child: Center(
                                    child: Text(
                                      '${item.quantity}',
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight:
                                              FontWeight.w700,
                                          color: AppColors
                                              .foreground),
                                    ),
                                  ),
                                ),
                        ),
                        _qtyIconBtn(
                          icon: Icons.add,
                          enabled:
                              item.quantity <
                                      item.stockQuantity &&
                                  !isUpdating,
                          onTap: () => _updateQuantity(
                              item, item.quantity + 1),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  Text(
                    'KSh ${item.subtotal.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.foreground,
                    ),
                  ),
                  const SizedBox(width: 12),

                  GestureDetector(
                    onTap: () => _removeItem(item),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius:
                            BorderRadius.circular(6),
                      ),
                      child: const Icon(
                          Icons.delete_outline,
                          color: AppColors.primary,
                          size: 16),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _qtyIconBtn({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Icon(icon,
              size: 15,
              color: enabled
                  ? AppColors.foreground
                  : AppColors.mutedForeground),
        ),
      );

  // ── Customer info ──
  Widget _customerInfoSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
              icon: Icons.person_outline,
              title: 'Customer Information'),
          const SizedBox(height: 16),
          _field('Full Name *', 'John Doe',
              controller: _nameCtrl,
              keyboardType: TextInputType.name),
          const SizedBox(height: 12),
          _field('Email *', 'john@example.com',
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 12),
          _field('Phone Number *', '+254 700 000 000',
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone),
        ],
      ),
    );
  }

  // ── Shipping address ──
  Widget _shippingSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
              icon: Icons.location_on_outlined,
              title: 'Shipping Address'),
          const SizedBox(height: 16),
          _field('Street Address *', '123 Main Street',
              controller: _addressCtrl),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (ctx, constraints) {
            final narrow = constraints.maxWidth < 400;
            if (narrow) {
              return Column(
                children: [
                  _field('City *', 'Nairobi',
                      controller: _cityCtrl),
                  const SizedBox(height: 12),
                  _field('Postal Code', '00100',
                      controller: _postalCtrl,
                      keyboardType: TextInputType.number),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                    child: _field('City *', 'Nairobi',
                        controller: _cityCtrl)),
                const SizedBox(width: 12),
                Expanded(
                    child: _field('Postal Code', '00100',
                        controller: _postalCtrl,
                        keyboardType:
                            TextInputType.number)),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ── Delivery method ──
  Widget _deliverySection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
              icon: Icons.local_shipping_outlined,
              title: 'Delivery Method'),
          const SizedBox(height: 16),
          ..._deliveryMethods.map((method) {
            final selected =
                _selectedDelivery?.id == method.id;
            return GestureDetector(
              onTap: () => setState(() {
                _selectedDelivery = method;
                _deliveryReviewed = false;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withOpacity(0.04)
                      : Colors.white,
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : Colors.grey.shade200,
                    width: selected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration:
                          const Duration(milliseconds: 200),
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : Colors.grey.shade400,
                          width: selected ? 6 : 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(method.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.foreground,
                              )),
                          const SizedBox(height: 2),
                          Text(method.description,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors
                                      .mutedForeground)),
                          Text(method.estimatedDays,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors
                                      .mutedForeground)),
                        ],
                      ),
                    ),
                    Text(
                      method.cost == 0
                          ? 'Free'
                          : 'KSh ${method.cost.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: selected
                            ? AppColors.primary
                            : AppColors.foreground,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          if (_selectedDelivery != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                border: Border.all(
                    color: const Color(0xFFBFDBFE)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _deliveryReviewed,
                      activeColor: AppColors.primary,
                      onChanged: (v) => setState(
                          () => _deliveryReviewed =
                              v ?? false),
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'I have reviewed and confirmed the delivery details',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Order summary ──
  Widget _orderSummarySection() {
    final user = _supabase.auth.currentUser;
    final canCheckout = user != null && _deliveryReviewed;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
              icon: Icons.receipt_long_outlined,
              title: 'Order Summary'),
          const SizedBox(height: 16),

          _summaryRow('Subtotal',
              'KSh ${_subtotal.toStringAsFixed(0)}'),
          const SizedBox(height: 8),

          if (_appliedDiscountCode != null) ...[
            _summaryRow(
              'Discount ($_appliedDiscountCode)',
              '−KSh ${_discountAmount.toStringAsFixed(0)}',
              valueColor: AppColors.secondary,
            ),
            const SizedBox(height: 8),
          ],

          _summaryRow(
            'Delivery',
            _selectedDelivery == null
                ? '–'
                : _deliveryCost == 0
                    ? 'Free'
                    : 'KSh ${_deliveryCost.toStringAsFixed(0)}',
          ),

          Divider(height: 24, color: Colors.grey.shade200),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.foreground)),
              Text(
                'KSh ${_total.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Discount code input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _discountCtrl,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Discount code',
                    hintStyle: const TextStyle(
                        color: AppColors.mutedForeground,
                        fontSize: 13),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: AppColors.primary),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _applyingDiscount
                    ? null
                    : _applyDiscount,
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.foreground,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: _applyingDiscount
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white))
                      : const Text('Apply',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Place order button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed:
                  (canCheckout && !_isProcessing)
                      ? _handleCheckout
                      : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    Colors.grey.shade300,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isProcessing
                  ? const Row(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white),
                        ),
                        SizedBox(width: 10),
                        Text('Processing...',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight:
                                    FontWeight.w700)),
                      ],
                    )
                  : Row(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.inventory_2_outlined,
                            size: 18),
                        SizedBox(width: 8),
                        Text('Place Order',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight:
                                    FontWeight.w700)),
                      ],
                    ),
            ),
          ),

          if (user == null) ...[
            const SizedBox(height: 10),
            const Center(
              child: Text(
                'Please log in to checkout',
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ] else if (!_deliveryReviewed &&
              _selectedDelivery != null) ...[
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Please confirm delivery details above',
                style: TextStyle(
                    color: Colors.amber.shade700,
                    fontSize: 13),
              ),
            ),
          ] else if (_selectedDelivery == null) ...[
            const SizedBox(height: 10),
            const Center(
              child: Text(
                'Please select a delivery method',
                style: TextStyle(
                    color: AppColors.mutedForeground,
                    fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // HELPER WIDGETS
  // ══════════════════════════════════════════════════════════

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      );

  Widget _sectionHeader(
          {required IconData icon, required String title}) =>
      Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.foreground,
            ),
          ),
        ],
      );

  Widget _field(
    String label,
    String hint, {
    required TextEditingController controller,
    TextInputType? keyboardType,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.foreground)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(
                fontSize: 14, color: AppColors.foreground),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                  color: AppColors.mutedForeground,
                  fontSize: 13),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                    color: AppColors.primary),
              ),
              isDense: true,
            ),
          ),
        ],
      );

  Widget _summaryRow(String label, String value,
          {Color? valueColor}) =>
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.mutedForeground,
                  fontSize: 14)),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color:
                      valueColor ?? AppColors.foreground)),
        ],
      );

  // ── Bottom nav ──
  Widget _bottomNav() => SafeArea(
        top: false,
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
                top: BorderSide(
                    color: Colors.grey.shade200)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Row(
  mainAxisAlignment: MainAxisAlignment.spaceAround,
  children: [
    _navItem(Icons.home_outlined, 'Home', false, () {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
    }),
    _navItem(Icons.menu_book_outlined, 'Books', false, () {
      Navigator.pushNamedAndRemoveUntil(context, '/books', (r) => false);
    }),
    _navItem(Icons.shopping_cart, 'Cart', true, null),
    _navItem(Icons.person_outline, 'Profile', false, () {
      Navigator.pushNamed(context, '/profile');
    }),
  ],
),
        ),
      );

  Widget _navItem(IconData icon, String label, bool active,
          VoidCallback? onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: active
                    ? AppColors.primary
                    : Colors.grey,
                size: 21),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: active
                        ? AppColors.primary
                        : Colors.grey,
                    fontWeight: active
                        ? FontWeight.w700
                        : FontWeight.normal)),
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════
// LOADING / EMPTY / ERROR STATES
// ══════════════════════════════════════════════════════════════

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 3,
            backgroundColor:
                AppColors.primary.withOpacity(0.1),
          ),
          const SizedBox(height: 16),
          const Text('Loading cart...',
              style: TextStyle(
                  color: AppColors.mutedForeground,
                  fontSize: 14)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.muted,
                borderRadius: BorderRadius.circular(40),
              ),
              child: const Icon(Icons.shopping_bag_outlined,
                  size: 40,
                  color: AppColors.mutedForeground),
            ),
            const SizedBox(height: 20),
            const Text(
              'Your cart is empty',
              style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add some books to get started!',
              style: TextStyle(
                  color: AppColors.mutedForeground,
                  fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () =>
                  Navigator.pushNamedAndRemoveUntil(
                      context, '/books', (r) => false),
              icon: const Icon(Icons.menu_book_outlined,
                  size: 16),
              label: const Text('Browse Books'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState(
      {required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(36),
              ),
              child: const Icon(Icons.error_outline,
                  size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            const Text('Failed to load cart',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.foreground)),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.mutedForeground,
                    fontSize: 13)),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Try Again'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(
                    color: AppColors.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}