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
    final rawContent = j['content'];
    final content = rawContent is Map
        ? Map<String, dynamic>.from(rawContent)
        : <String, dynamic>{};

    return _CartItem(
      id: j['id'] as String? ?? '',
      contentId: j['content_id'] as String? ?? '',
      quantity: (j['quantity'] as num?)?.toInt() ?? 1,
      price: (j['price'] as num?)?.toDouble() ?? 0.0,
      title: content['title'] as String? ?? 'Unknown Title',
      author: content['author'] as String? ?? 'Unknown Author',
      coverImageUrl: content['cover_image_url'] as String?,
      stockQuantity: (content['stock_quantity'] as num?)?.toInt() ?? 99,
    );
  }

  double get subtotal => price * quantity;
}

class _DeliveryRegion {
  final String id;
  final String name;
  final String description;
  final double baseCost;
  final double minCost;
  final double maxCost;
  final String estDays;
  final int sortOrder;

  const _DeliveryRegion({
    required this.id,
    required this.name,
    required this.description,
    required this.baseCost,
    required this.minCost,
    required this.maxCost,
    required this.estDays,
    required this.sortOrder,
  });

  factory _DeliveryRegion.fromJson(Map<String, dynamic> j) => _DeliveryRegion(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        description: j['description'] as String? ?? '',
        baseCost: (j['base_cost'] as num?)?.toDouble() ?? 0,
        minCost: (j['min_cost'] as num?)?.toDouble() ?? 0,
        maxCost: (j['max_cost'] as num?)?.toDouble() ?? 0,
        estDays: j['est_days'] as String? ?? '',
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );
}

class _DeliveryZone {
  final String id;
  final String regionId;
  final String name;
  final double cost;
  final String? estDays;
  final List<String> keywords;
  final int sortOrder;
  final _DeliveryRegion region;

  const _DeliveryZone({
    required this.id,
    required this.regionId,
    required this.name,
    required this.cost,
    this.estDays,
    required this.keywords,
    required this.sortOrder,
    required this.region,
  });

  factory _DeliveryZone.fromJson(Map<String, dynamic> j) {
    final rawRegion = j['delivery_regions'];
    final regionMap = rawRegion is Map
        ? Map<String, dynamic>.from(rawRegion)
        : <String, dynamic>{};

    final rawKeywords = j['keywords'];
    final keywords = rawKeywords is List
        ? rawKeywords.map((e) => e.toString().toLowerCase()).toList()
        : <String>[];

    return _DeliveryZone(
      id: j['id'] as String? ?? '',
      regionId: j['region_id'] as String? ?? '',
      name: j['name'] as String? ?? '',
      cost: (j['cost'] as num?)?.toDouble() ?? 0,
      estDays: j['est_days'] as String?,
      keywords: keywords,
      sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      region: _DeliveryRegion.fromJson(regionMap),
    );
  }

  String get displayEstDays => estDays?.isNotEmpty == true ? estDays! : region.estDays;

  String get costLabel => cost == 0 ? 'Free' : 'KSh ${cost.toStringAsFixed(0)}';
}

// ─── Process-level cache (mirrors TSX module-level cache) ─────────────────────

List<_DeliveryZone> _zonesCache = [];
List<_DeliveryRegion> _regionsCache = [];
bool _zonesFetched = false;

// ─── Delivery Zone Selector Widget ───────────────────────────────────────────

class _DeliveryZoneSelector extends StatefulWidget {
  final List<_DeliveryZone> zones;
  final List<_DeliveryRegion> regions;
  final _DeliveryZone? selectedZone;
  final ValueChanged<_DeliveryZone?> onSelect;
  final String cityHint;

  const _DeliveryZoneSelector({
    required this.zones,
    required this.regions,
    required this.selectedZone,
    required this.onSelect,
    required this.cityHint,
  });

  @override
  State<_DeliveryZoneSelector> createState() =>
      _DeliveryZoneSelectorState();
}

class _DeliveryZoneSelectorState extends State<_DeliveryZoneSelector> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _openRegionId;
  bool _showFallback = false;

  @override
  void initState() {
    super.initState();
    // Auto-populate with city hint if no zone selected yet
    if (widget.selectedZone == null && widget.cityHint.isNotEmpty) {
      _searchCtrl.text = widget.cityHint;
      _query = widget.cityHint.toLowerCase().trim();
    }
  }

  @override
  void didUpdateWidget(_DeliveryZoneSelector old) {
    super.didUpdateWidget(old);
    // When parent city changes and no zone selected, update hint
    if (widget.selectedZone == null &&
        widget.cityHint != old.cityHint &&
        widget.cityHint.isNotEmpty) {
      _searchCtrl.text = widget.cityHint;
      setState(() {
        _query = widget.cityHint.toLowerCase().trim();
        _showFallback = false;
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Live search: match against name and keywords
  List<_DeliveryZone> get _searchResults {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return [];
    return widget.zones.where((z) {
      return z.name.toLowerCase().contains(q) ||
          z.keywords.any((k) => k.contains(q));
    }).toList();
  }

  bool get _isSearching => _query.trim().isNotEmpty;
  bool get _hasResults => _searchResults.isNotEmpty;

  // Group all zones by region for the fallback accordion
  List<({_DeliveryRegion region, List<_DeliveryZone> zones})> get _grouped {
    final sorted = [...widget.regions]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return sorted
        .map((region) {
          final rZones = widget.zones
              .where((z) => z.regionId == region.id)
              .toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
          return (region: region, zones: rZones);
        })
        .where((g) => g.zones.isNotEmpty)
        .toList();
  }

  void _handleSelect(_DeliveryZone zone) {
    widget.onSelect(zone);
    _searchCtrl.text = zone.name;
    setState(() {
      _query = zone.name.toLowerCase().trim();
      _showFallback = false;
    });
  }

  void _clearSelection() {
    widget.onSelect(null);
    _searchCtrl.clear();
    setState(() {
      _query = '';
      _showFallback = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Search input ──
        TextField(
          controller: _searchCtrl,
          onChanged: (v) {
            setState(() {
              _query = v.toLowerCase().trim();
              _showFallback = false;
            });
          },
          style: const TextStyle(fontSize: 14, color: AppColors.foreground),
          decoration: InputDecoration(
            hintText: 'Type your location (e.g. Karen, Mombasa, Thika…)',
            hintStyle: const TextStyle(
                color: AppColors.mutedForeground, fontSize: 13),
            prefixIcon:
                const Icon(Icons.search, color: AppColors.mutedForeground, size: 18),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? GestureDetector(
                    onTap: _clearSelection,
                    child: const Icon(Icons.close,
                        color: AppColors.mutedForeground, size: 18),
                  )
                : null,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
            isDense: true,
          ),
        ),

        // ── Search results dropdown ──
        if (_isSearching) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
              color: Colors.white,
            ),
            child: _hasResults
                ? Column(
                    children: _searchResults.map((zone) {
                      final isSelected =
                          widget.selectedZone?.id == zone.id;
                      return InkWell(
                        onTap: () => _handleSelect(zone),
                        child: Container(
                          color: isSelected
                              ? AppColors.primary.withOpacity(0.08)
                              : Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          zone.name,
                                          style: TextStyle(
                                            fontWeight: isSelected
                                                ? FontWeight.w700
                                                : FontWeight.w600,
                                            fontSize: 14,
                                            color: AppColors.foreground,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            zone.region.name,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color:
                                                    AppColors.mutedForeground),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    zone.costLabel,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    zone.displayEstDays,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.mutedForeground),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  )
                // No match — offer fallback picker
                : Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline,
                                size: 16, color: Color(0xFFB45309)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFFB45309)),
                                  children: [
                                    const TextSpan(
                                        text:
                                            'We don\'t have '),
                                    TextSpan(
                                      text:
                                          '"${_searchCtrl.text}"',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                    const TextSpan(
                                        text:
                                            ' listed yet. Please choose the nearest location below — we\'ll deliver to you from there.'),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () =>
                              setState(() => _showFallback = true),
                          child: const Text(
                            'Browse all delivery areas →',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],

        // ── Fallback accordion (all zones grouped by region) ──
        if (_showFallback ||
            (!_isSearching && widget.selectedZone == null)) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: _grouped.asMap().entries.map((entry) {
                final idx = entry.key;
                final g = entry.value;
                final isOpen = _openRegionId == g.region.id;
                final isLast = idx == _grouped.length - 1;
                final minCost = g.region.minCost;
                final maxCost = g.region.maxCost;
                final costRange = (minCost == 0 && maxCost == 0)
                    ? 'Free'
                    : 'KSh ${minCost.toStringAsFixed(0)}–${maxCost.toStringAsFixed(0)}';

                return Column(
                  children: [
                    // Region header
                    InkWell(
                      onTap: () => setState(() {
                        _openRegionId =
                            isOpen ? null : g.region.id;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: isLast && !isOpen
                              ? const BorderRadius.vertical(
                                  bottom: Radius.circular(8))
                              : BorderRadius.zero,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    g.region.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: AppColors.foreground,
                                    ),
                                  ),
                                  if (g.region.description.isNotEmpty)
                                    Text(
                                      g.region.description,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.mutedForeground),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              costRange,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              isOpen
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: 18,
                              color: AppColors.mutedForeground,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Zone list
                    if (isOpen)
                      Container(
                        color: Colors.white,
                        child: Column(
                          children: g.zones.map((zone) {
                            final isSelected =
                                widget.selectedZone?.id == zone.id;
                            return InkWell(
                              onTap: () => _handleSelect(zone),
                              child: Container(
                                color: isSelected
                                    ? AppColors.primary
                                        .withOpacity(0.07)
                                    : Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 10),
                                child: Row(
                                  children: [
                                    if (isSelected)
                                      const Padding(
                                        padding: EdgeInsets.only(
                                            right: 6),
                                        child: Icon(
                                            Icons
                                                .check_circle_rounded,
                                            size: 14,
                                            color: AppColors.primary),
                                      ),
                                    Expanded(
                                      child: Text(
                                        zone.name,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.normal,
                                          color: AppColors.foreground,
                                        ),
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          zone.costLabel,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Text(
                                          zone.displayEstDays,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors
                                                  .mutedForeground),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                    if (!isLast)
                      Divider(height: 1, color: Colors.grey.shade200),
                  ],
                );
              }).toList(),
            ),
          ),
        ],

        // ── Selected zone summary ──
        if (widget.selectedZone != null) ...[
          const SizedBox(height: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              border: Border.all(color: const Color(0xFFBBF7D0)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    size: 16, color: Color(0xFF16A34A)),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF166534)),
                      children: [
                        const TextSpan(text: 'Delivering to '),
                        TextSpan(
                          text: widget.selectedZone!.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                            text:
                                ' · ${widget.selectedZone!.displayEstDays}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.selectedZone!.costLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF15803D),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Cart Page ────────────────────────────────────────────────────────────────

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

  // ── Cart state ──
  List<_CartItem> _items = [];
  bool _loading = true;
  String? _error;
  bool _isProcessing = false;
  String? _updatingItemId;
  String? _removingItemId;

  // ── Delivery zone state ──
  List<_DeliveryZone> _zones = _zonesCache;
  List<_DeliveryRegion> _regions = _regionsCache;
  bool _zonesLoading = !_zonesFetched;
  _DeliveryZone? _selectedZone;
  bool _deliveryReviewed = false;

  // ── Discount state ──
  String? _appliedDiscountCode;
  double _discountAmount = 0;
  bool _applyingDiscount = false;

  // ── Responsive ──
  static double _hPad(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    if (w >= 900) return 48;
    if (w >= 600) return 28;
    return 16;
  }

  static bool _isWide(BuildContext ctx) =>
      MediaQuery.of(ctx).size.width >= 800;

  // ── Computed totals ──
  double get _subtotal =>
      _items.fold(0, (sum, i) => sum + i.subtotal);

  double get _deliveryCost => _selectedZone?.cost ?? 0;

  double get _total => _subtotal - _discountAmount + _deliveryCost;

  // ── Lifecycle ──
  @override
  void initState() {
    super.initState();
    _prefillEmail();
    _fetchZones();
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

  // ── Fetch delivery zones from Supabase ──
  Future<void> _fetchZones() async {
    if (_zonesFetched) return; // already loaded process-wide
    if (!mounted) return;
    setState(() => _zonesLoading = true);

    try {
      final response = await _supabase
          .from('delivery_zones')
          .select('''
            id, region_id, name, cost, est_days, keywords, sort_order,
            delivery_regions (
              id, name, description, base_cost, min_cost, max_cost, est_days, sort_order
            )
          ''')
          .eq('is_active', true)
          .order('sort_order');

      final rawList = List<dynamic>.from(response);
      final mapped = rawList
          .whereType<Map>()
          .map((row) =>
              _DeliveryZone.fromJson(Map<String, dynamic>.from(row)))
          .toList();

      // Deduplicate regions
      final regionMap = <String, _DeliveryRegion>{};
      for (final z in mapped) {
        regionMap[z.region.id] = z.region;
      }
      final uniqueRegions = regionMap.values.toList();

      // Update process-level cache
      _zonesCache = mapped;
      _regionsCache = uniqueRegions;
      _zonesFetched = true;

      if (!mounted) return;
      setState(() {
        _zones = mapped;
        _regions = uniqueRegions;
        _zonesLoading = false;
      });
    } catch (e) {
      debugPrint('[CartPage] Failed to fetch delivery zones: $e');
      if (mounted) setState(() => _zonesLoading = false);
    }
  }

  // ── Fetch cart (edge function with direct DB fallback) ──
  Future<void> _fetchCart() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() { _items = []; _loading = false; });
      return;
    }

    // Strategy 1: edge function via SupabaseService
    try {
      final response = await _service.getCart();
      debugPrint('[CartPage] cart-get response: ${response.keys.toList()}');

      final rawItems = response['items'];
      if (rawItems == null || rawItems is! List) {
        debugPrint('[CartPage] items missing/invalid — falling back to direct DB');
        await _fetchCartDirectly();
        return;
      }

      final itemList = List<dynamic>.from(rawItems);
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
      debugPrint('[CartPage] Edge function failed: $e\n$stack');
      if (mounted) await _fetchCartDirectly();
    }
  }

  // Strategy 2: direct Supabase DB query (fallback)
  Future<void> _fetchCartDirectly() async {
    if (!mounted) return;
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() { _items = []; _loading = false; });
      return;
    }

    try {
      final cartResponse = await _supabase
          .from('carts')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (cartResponse == null) {
        if (mounted) setState(() { _items = []; _loading = false; });
        return;
      }

      final cartId = cartResponse['id'] as String;
      final itemsResponse = await _supabase
          .from('cart_items')
          .select('''
            id, content_id, quantity, price,
            content ( id, title, author, cover_image_url, stock_quantity )
          ''')
          .eq('cart_id', cartId);

      if (!mounted) return;
      final rawList = List<dynamic>.from(itemsResponse);
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
      debugPrint('[CartPage] Direct DB also failed: $e\n$stack');
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
    if (_selectedZone == null) {
      _showSnack('Please select a delivery location.');
      return;
    }
    if (!_deliveryReviewed) {
      _showSnack('Please confirm you have reviewed delivery details.');
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
          'id': _selectedZone!.id,
          'name': _selectedZone!.name,
          'cost': _selectedZone!.cost,
          'estimatedDays': _selectedZone!.displayEstDays,
          'region': _selectedZone!.region.name,
        },
        if (_appliedDiscountCode != null)
          'discount_code': _appliedDiscountCode,
      });

      if (!mounted) return;

      final success = response['success'] as bool? ?? false;
      if (!success) {
        _showSnack(response['error'] as String? ?? 'Checkout failed.');
        return;
      }

      final orderNumber = response['order_number'] as String? ?? '–';
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
  void _showOrderConfirmation(String orderNumber, String? orderId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                    color: AppColors.mutedForeground, fontSize: 14),
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
                        fontSize: 15, fontWeight: FontWeight.w700),
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
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                        size: 16, color: AppColors.mutedForeground),
                label: const Text('Refresh',
                    style: TextStyle(
                        color: AppColors.mutedForeground, fontSize: 13)),
              ),
            ],
          ),

          // ── Body ──
          if (_loading)
            const SliverFillRemaining(child: _LoadingState())
          else if (_error != null)
            SliverFillRemaining(
                child: _ErrorState(error: _error!, onRetry: _fetchCart))
          else if (_items.isEmpty)
            const SliverFillRemaining(child: _EmptyState())
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 32),
                child: isWide ? _wideLayout() : _narrowLayout(),
              ),
            ),
        ],
      ),
    );
  }

  // ── Wide layout: two columns ──
  Widget _wideLayout() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Column(children: [
              _cartItemsSection(),
              const SizedBox(height: 20),
              _customerInfoSection(),
              const SizedBox(height: 20),
              _shippingSection(),
              const SizedBox(height: 20),
              _deliverySection(),
            ]),
          ),
          const SizedBox(width: 24),
          SizedBox(width: 320, child: _orderSummarySection()),
        ],
      );

  // ── Narrow layout: single column ──
  Widget _narrowLayout() => Column(children: [
        _cartItemsSection(),
        const SizedBox(height: 16),
        _customerInfoSection(),
        const SizedBox(height: 16),
        _shippingSection(),
        const SizedBox(height: 16),
        _deliverySection(),
        const SizedBox(height: 16),
        _orderSummarySection(),
      ]);

  // ══════════════════════════════════════════════════════════
  // SECTIONS
  // ══════════════════════════════════════════════════════════

  // ── Cart items ──
  Widget _cartItemsSection() => _card(
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
              return Column(children: [
                _cartItemTile(item),
                if (i < _items.length - 1)
                  Divider(height: 24, color: Colors.grey.shade100),
              ]);
            }),
          ],
        ),
      );

  Widget _cartItemTile(_CartItem item) {
    final isUpdating = _updatingItemId == item.id;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cover image
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
              placeholder: (_, __) => Container(color: AppColors.muted),
              errorWidget: (_, __, ___) => Container(
                color: AppColors.muted,
                child: const Icon(Icons.book,
                    color: AppColors.mutedForeground, size: 28),
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
                      fontSize: 12, color: AppColors.mutedForeground)),
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
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _qtyIconBtn(
                          icon: Icons.remove,
                          enabled: item.quantity > 1 && !isUpdating,
                          onTap: () =>
                              _updateQuantity(item, item.quantity - 1),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: isUpdating
                              ? const SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: Center(
                                    child: SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.primary),
                                    ),
                                  ),
                                )
                              : SizedBox(
                                  key: ValueKey(item.quantity),
                                  width: 32,
                                  child: Center(
                                    child: Text('${item.quantity}',
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.foreground)),
                                  ),
                                ),
                        ),
                        _qtyIconBtn(
                          icon: Icons.add,
                          enabled: item.quantity < item.stockQuantity &&
                              !isUpdating,
                          onTap: () =>
                              _updateQuantity(item, item.quantity + 1),
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
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.delete_outline,
                          color: AppColors.primary, size: 16),
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
  Widget _customerInfoSection() => _card(
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

  // ── Shipping address ──
  Widget _shippingSection() => _card(
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
                return Column(children: [
                  _field('City *', 'Nairobi', controller: _cityCtrl),
                  const SizedBox(height: 12),
                  _field('Postal Code', '00100',
                      controller: _postalCtrl,
                      keyboardType: TextInputType.number),
                ]);
              }
              return Row(children: [
                Expanded(
                    child: _field('City *', 'Nairobi',
                        controller: _cityCtrl)),
                const SizedBox(width: 12),
                Expanded(
                    child: _field('Postal Code', '00100',
                        controller: _postalCtrl,
                        keyboardType: TextInputType.number)),
              ]);
            }),
          ],
        ),
      );

  // ── Delivery location (dynamic zone selector) ──
  Widget _deliverySection() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
                icon: Icons.local_shipping_outlined,
                title: 'Delivery Location'),
            const SizedBox(height: 4),
            const Text(
              'Search for your area. If it\'s not listed, pick the nearest location.',
              style: TextStyle(
                  fontSize: 12, color: AppColors.mutedForeground),
            ),
            const SizedBox(height: 14),

            // Zones loading state
            if (_zonesLoading)
              Row(children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                const Text('Loading delivery areas…',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.mutedForeground)),
              ])
            else
              // Listen to city field changes and pass as hint
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _cityCtrl,
                builder: (_, cityVal, __) =>
                    _DeliveryZoneSelector(
                  zones: _zones,
                  regions: _regions,
                  selectedZone: _selectedZone,
                  onSelect: (zone) => setState(() {
                    _selectedZone = zone;
                    _deliveryReviewed = false;
                  }),
                  cityHint: cityVal.text,
                ),
              ),

            // Confirm checkbox (shown after a zone is selected)
            if (_selectedZone != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
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
                            () => _deliveryReviewed = v ?? false),
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

  // ── Order summary ──
  Widget _orderSummarySection() {
    final user = _supabase.auth.currentUser;
    final canCheckout = user != null && _deliveryReviewed && _selectedZone != null;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
              icon: Icons.receipt_long_outlined, title: 'Order Summary'),
          const SizedBox(height: 16),

          _summaryRow(
              'Subtotal', 'KSh ${_subtotal.toStringAsFixed(0)}'),
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
            _selectedZone == null
                ? 'Select location'
                : _deliveryCost == 0
                    ? 'Free'
                    : 'KSh ${_deliveryCost.toStringAsFixed(0)}',
          ),

          if (_selectedZone != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _selectedZone!.name,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.mutedForeground),
                ),
              ),
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
                        color: AppColors.mutedForeground, fontSize: 13),
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
                      borderSide:
                          const BorderSide(color: AppColors.primary),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _applyingDiscount ? null : _applyDiscount,
                child: Container(
                  height: 44,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14),
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
                              strokeWidth: 2, color: Colors.white))
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
                  (canCheckout && !_isProcessing) ? _handleCheckout : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isProcessing
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        ),
                        SizedBox(width: 10),
                        Text('Processing...',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ],
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Place Order',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
            ),
          ),

          // Helper messages (mirrors TSX)
          if (user == null) ...[
            const SizedBox(height: 10),
            const Center(
              child: Text('Please log in to checkout',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ),
          ] else if (_selectedZone == null) ...[
            const SizedBox(height: 10),
            const Center(
              child: Text('Select a delivery location',
                  style: TextStyle(
                      color: AppColors.mutedForeground, fontSize: 13)),
            ),
          ] else if (!_deliveryReviewed) ...[
            const SizedBox(height: 10),
            Center(
              child: Text('Please confirm delivery details',
                  style: TextStyle(
                      color: Colors.amber.shade700, fontSize: 13)),
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
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground)),
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
                  color: AppColors.mutedForeground, fontSize: 13),
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
                borderSide:
                    const BorderSide(color: AppColors.primary),
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
                  color: AppColors.mutedForeground, fontSize: 14)),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: valueColor ?? AppColors.foreground)),
        ],
      );

  // ── Bottom nav ──
  Widget _bottomNav() => SafeArea(
        top: false,
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white,
            border:
                Border(top: BorderSide(color: Colors.grey.shade200)),
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
                Navigator.pushNamedAndRemoveUntil(
                    context, '/home', (r) => false);
              }),
              _navItem(Icons.menu_book_outlined, 'Books', false, () {
                Navigator.pushNamedAndRemoveUntil(
                    context, '/books', (r) => false);
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
                color: active ? AppColors.primary : Colors.grey,
                size: 21),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: active ? AppColors.primary : Colors.grey,
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
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 3,
              backgroundColor: AppColors.primary.withOpacity(0.1),
            ),
            const SizedBox(height: 16),
            const Text('Loading cart…',
                style: TextStyle(
                    color: AppColors.mutedForeground, fontSize: 14)),
          ],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
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
                    size: 40, color: AppColors.mutedForeground),
              ),
              const SizedBox(height: 20),
              const Text('Your cart is empty',
                  style: TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.foreground)),
              const SizedBox(height: 8),
              const Text('Add some books to get started!',
                  style: TextStyle(
                      color: AppColors.mutedForeground, fontSize: 14)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                    context, '/books', (r) => false),
                icon: const Icon(Icons.menu_book_outlined, size: 16),
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

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
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
                      color: AppColors.mutedForeground, fontSize: 13)),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Try Again'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      );
}