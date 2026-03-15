// lib/pages/books.dart
//
// FIX: BooksPage is pushed via Navigator.pushNamed('/books') from Shell,
// so it IS its own route and needs its own Scaffold.
// The only fix needed here is the Profile nav tap:
//   BEFORE: Navigator.pushNamed(context, '/profile')   ← wrong
//   AFTER:  Navigator.pushNamed(context, '/settings')  ← correct
//
// This ensures that wherever the user taps "Profile" in the books page
// navbar, they always land on SettingsPage with the correct nav bar.

import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/content.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';

class BooksPage extends StatefulWidget {
  const BooksPage({super.key});

  @override
  State<BooksPage> createState() => _BooksPageState();
}

class _BooksPageState extends State<BooksPage>
    with SingleTickerProviderStateMixin {
  final SupabaseService _service = SupabaseService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // ── State ──
  String _searchQuery = '';
  List<String> _selectedCategories = [];
  List<String> _selectedContentTypes = [];
  String _sortBy = 'featured';
  String _priceRange = 'all';
  List<Content> _content = [];
  bool _loading = false;
  int _page = 1;
  int _totalPages = 1;
  int _totalResults = 0;
  String? _error;
  String? _addingToCartId;

  static const int _pageSize = 40;

  static const List<Map<String, String>> _categories = [
    {'slug': 'fiction', 'name': 'Fiction'},
    {'slug': 'non-fiction', 'name': 'Non-Fiction'},
    {'slug': 'mystery-thriller', 'name': 'Mystery & Thriller'},
    {'slug': 'fantasy', 'name': 'Fantasy'},
    {'slug': 'science-fiction', 'name': 'Science Fiction'},
    {'slug': 'academic', 'name': 'Academic & Education'},
    {'slug': 'business', 'name': 'Business & Economics'},
    {'slug': 'technology', 'name': 'Technology & Programming'},
  ];

  static const List<Map<String, String>> _contentTypes = [
    {'value': 'book', 'label': 'Book'},
    {'value': 'ebook', 'label': 'E-Book'},
    {'value': 'document', 'label': 'Document'},
    {'value': 'paper', 'label': 'Paper'},
    {'value': 'report', 'label': 'Report'},
    {'value': 'manual', 'label': 'Manual'},
    {'value': 'guide', 'label': 'Guide'},
  ];

  // ── Responsive breakpoints ──
  static bool _isTablet(BuildContext ctx) =>
      MediaQuery.of(ctx).size.width >= 600 &&
      MediaQuery.of(ctx).size.width < 900;
  static bool _isDesktop(BuildContext ctx) =>
      MediaQuery.of(ctx).size.width >= 900;

  static int _gridColumns(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    if (w >= 1200) return 4;
    if (w >= 900) return 3;
    if (w >= 600) return 3;
    if (w >= 360) return 2;
    return 2;
  }

  static double _cardRatio(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    if (w >= 900) return 0.58;
    if (w >= 600) return 0.55;
    return 0.52;
  }

  static double _horizontalPadding(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    if (w >= 900) return 32;
    if (w >= 600) return 24;
    return 16;
  }

  // ── Lifecycle ──
  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String && args.isNotEmpty) {
        setState(() => _selectedCategories = [args]);
      }
      _fetchContent();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (_searchQuery != query) {
        setState(() {
          _searchQuery = query;
          _page = 1;
        });
        _fetchContent();
      }
    });
  }

  Future<void> _fetchContent() async {
    if (!mounted) return;
    _fadeController.reset();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final String? categorySlug = _selectedCategories.length == 1
          ? _selectedCategories.first
          : null;

      final response = await _service.searchContent(
        query: _searchQuery,
        categorySlug: categorySlug,
        contentTypes:
            _selectedContentTypes.isNotEmpty ? _selectedContentTypes : null,
        priceRange: _priceRange,
        visibility: 'public',
        sortBy: _sortBy,
        page: _page,
        pageSize: _pageSize,
      );

      if (!mounted) return;

      final rawData = response['data'];
      final List<dynamic> dataList =
          rawData is List ? List<dynamic>.from(rawData) : [];

      List<Content> parsed = dataList
          .map((item) =>
              Content.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();

      if (_sortBy == 'price-high') {
        parsed.sort((a, b) => b.price.compareTo(a.price));
      }

      setState(() {
        _content = parsed;
        _totalResults = (response['total'] as num?)?.toInt() ?? 0;
        _totalPages = (response['total_pages'] as num?)?.toInt() ?? 1;
      });

      _fadeController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _content = [];
        _totalResults = 0;
        _totalPages = 1;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleAddToCart(Content book) async {
    if (_addingToCartId != null) return;
    if (_service.currentUser == null) {
      _showSnack('Please log in to add items to your cart.');
      Navigator.pushNamed(context, '/login');
      return;
    }
    setState(() => _addingToCartId = book.id);
    try {
      await _service.addToCart(book.id, 1);
      if (!mounted) return;
      _showSnack('${book.title} added to cart',
          color: AppColors.secondary);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to add to cart. Please try again.');
    } finally {
      if (mounted) setState(() => _addingToCartId = null);
    }
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _selectedCategories = [];
      _selectedContentTypes = [];
      _priceRange = 'all';
      _page = 1;
    });
    _fetchContent();
  }

  bool get _hasActiveFilters =>
      _searchQuery.isNotEmpty ||
      _selectedCategories.isNotEmpty ||
      _selectedContentTypes.isNotEmpty ||
      _priceRange != 'all';

  int get _activeFilterCount =>
      _selectedCategories.length +
      _selectedContentTypes.length +
      (_priceRange != 'all' ? 1 : 0) +
      (_searchQuery.isNotEmpty ? 1 : 0);

  void _showSnack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: const TextStyle(
                fontWeight: FontWeight.w500, fontSize: 14)),
        backgroundColor: color ?? AppColors.foreground,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FilterSheet(
        selectedCategories: List.from(_selectedCategories),
        selectedContentTypes: List.from(_selectedContentTypes),
        priceRange: _priceRange,
        categories: _categories,
        contentTypes: _contentTypes,
        totalResults: _totalResults,
        onApply: ({
          required List<String> categories,
          required List<String> contentTypes,
          required String priceRange,
        }) {
          setState(() {
            _selectedCategories = categories;
            _selectedContentTypes = contentTypes;
            _priceRange = priceRange;
            _page = 1;
          });
          _fetchContent();
        },
        onClear: _clearFilters,
      ),
    );
  }

  // ── BUILD ──
  @override
  Widget build(BuildContext context) {
    final hPad = _horizontalPadding(context);
    final isTabletOrDesktop = _isTablet(context) || _isDesktop(context);
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: AppColors.background,
      // ✅ Profile tap now routes to /settings — NOT /profile
      bottomNavigationBar: _bottomNav(context),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // ── Sticky App Bar ──
          SliverAppBar(
            pinned: true,
            floating: false,
            elevation: 0,
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.black.withOpacity(0.08),
            leading: Navigator.canPop(context)
                ? IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: AppColors.foreground),
                    onPressed: () => Navigator.pop(context),
                  )
                : null,
            title: Row(
              children: [
                const Icon(Icons.menu_book_rounded,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Intercen Books',
                  style: TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'PlayfairDisplay',
                    fontSize: screenWidth < 360 ? 16 : 18,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: _openFilterSheet,
                icon: Stack(
                  children: [
                    const Icon(Icons.tune,
                        color: AppColors.foreground),
                    if (_hasActiveFilters)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          // ── Page Header Banner ──
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.muted.withOpacity(0.6),
                border: Border(
                  bottom: BorderSide(
                      color: Colors.grey.shade200, width: 1),
                ),
              ),
              padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Breadcrumb
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () =>
                            Navigator.pushNamedAndRemoveUntil(
                                context, '/home', (r) => false),
                        child: const Text(
                          'Home',
                          style: TextStyle(
                            color: AppColors.mutedForeground,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.chevron_right,
                            size: 14,
                            color: AppColors.mutedForeground),
                      ),
                      const Text(
                        'Content Library',
                        style: TextStyle(
                          color: AppColors.foreground,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Browse Our Content Library',
                    style: TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: isTabletOrDesktop ? 30 : 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.foreground,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      key: ValueKey(
                          '$_loading$_error$_totalResults'),
                      _loading
                          ? 'Loading content...'
                          : _error != null
                              ? 'Error loading content'
                              : 'Discover ${_totalResults > 0 ? '$_totalResults+' : '0'} books, documents, papers, and more',
                      style: TextStyle(
                        color: _error != null
                            ? AppColors.primary
                            : AppColors.mutedForeground,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Search + Sort + Chips ──
          SliverToBoxAdapter(
            child: Container(
              color: AppColors.background,
              padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(builder: (ctx, constraints) {
                    final isNarrow = constraints.maxWidth < 420;
                    if (isNarrow) {
                      return Column(
                        children: [
                          _searchBar(),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: _sortDropdown()),
                              const SizedBox(width: 10),
                              _filterButton(),
                            ],
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: _searchBar()),
                        const SizedBox(width: 10),
                        _sortDropdown(width: 160),
                        const SizedBox(width: 10),
                        _filterButton(),
                      ],
                    );
                  }),

                  if (_hasActiveFilters) ...[
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (_searchQuery.isNotEmpty)
                            _chip(
                              label: '"$_searchQuery"',
                              icon: Icons.search,
                              onRemove: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                            ),
                          ..._selectedContentTypes.map((t) =>
                              _chip(
                                label: _contentTypes.firstWhere(
                                        (e) => e['value'] == t,
                                        orElse: () =>
                                            {'label': t})['label'] ??
                                    t,
                                onRemove: () {
                                  setState(() {
                                    _selectedContentTypes.remove(t);
                                    _page = 1;
                                  });
                                  _fetchContent();
                                },
                              )),
                          ..._selectedCategories.map((slug) =>
                              _chip(
                                label: _categories.firstWhere(
                                        (e) => e['slug'] == slug,
                                        orElse: () =>
                                            {'name': slug})['name'] ??
                                    slug,
                                onRemove: () {
                                  setState(() {
                                    _selectedCategories.remove(slug);
                                    _page = 1;
                                  });
                                  _fetchContent();
                                },
                              )),
                          if (_priceRange != 'all')
                            _chip(
                              label: _priceLabel(_priceRange),
                              icon: Icons.attach_money,
                              onRemove: () {
                                setState(() {
                                  _priceRange = 'all';
                                  _page = 1;
                                });
                                _fetchContent();
                              },
                            ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: _clearFilters,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius:
                                    BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Clear all',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (!_loading &&
                      _error == null &&
                      _content.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Showing ${(_page - 1) * _pageSize + 1}–${(_page * _pageSize) > _totalResults ? _totalResults : (_page * _pageSize)} of $_totalResults results',
                      style: const TextStyle(
                        color: AppColors.mutedForeground,
                        fontSize: 13,
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // ── Content body ──
          if (_loading)
            const SliverFillRemaining(
              child: _LoadingState(),
            )
          else if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(_horizontalPadding(context)),
                child: _ErrorState(
                  error: _error!,
                  onRetry: _fetchContent,
                ),
              ),
            )
          else if (_content.isEmpty)
            SliverFillRemaining(
              child: _EmptyState(
                hasFilters: _hasActiveFilters,
                onClear: _clearFilters,
              ),
            )
          else ...[
            SliverPadding(
              padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 16),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => FadeTransition(
                    opacity: _fadeAnimation,
                    child: _BookCard(
                      book: _content[i],
                      addingToCartId: _addingToCartId,
                      onTap: () => Navigator.pushNamed(
                          context, '/book-detail',
                          arguments: _content[i]),
                      onAddToCart: () =>
                          _handleAddToCart(_content[i]),
                    ),
                  ),
                  childCount: _content.length,
                ),
                gridDelegate:
                    SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _gridColumns(context),
                  crossAxisSpacing:
                      _isTablet(context) || _isDesktop(context)
                          ? 20
                          : 14,
                  mainAxisSpacing:
                      _isTablet(context) || _isDesktop(context)
                          ? 28
                          : 20,
                  childAspectRatio: _cardRatio(context),
                ),
              ),
            ),

            if (_totalPages > 1)
              SliverToBoxAdapter(
                child: _Pagination(
                  page: _page,
                  totalPages: _totalPages,
                  onPrev: () {
                    setState(() => _page--);
                    _scrollController.animateTo(0,
                        duration:
                            const Duration(milliseconds: 400),
                        curve: Curves.easeOut);
                    _fetchContent();
                  },
                  onNext: () {
                    setState(() => _page++);
                    _scrollController.animateTo(0,
                        duration:
                            const Duration(milliseconds: 400),
                        curve: Curves.easeOut);
                    _fetchContent();
                  },
                ),
              ),

            const SliverToBoxAdapter(
                child: SizedBox(height: 32)),
          ],
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.search,
                color: AppColors.mutedForeground, size: 18),
          ),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Search content, authors, titles...',
                hintStyle: TextStyle(
                    color: AppColors.mutedForeground, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                _onSearchChanged('');
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.close,
                    size: 16, color: AppColors.mutedForeground),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sortDropdown({double? width}) {
    Widget dropdown = Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _sortBy,
          isExpanded: true,
          icon: const Icon(Icons.expand_more,
              color: AppColors.mutedForeground, size: 18),
          style: const TextStyle(
              color: AppColors.foreground,
              fontSize: 13,
              fontWeight: FontWeight.w500),
          items: const [
            DropdownMenuItem(
                value: 'featured', child: Text('Featured')),
            DropdownMenuItem(
                value: 'newest', child: Text('Newest')),
            DropdownMenuItem(
                value: 'price-low',
                child: Text('Price: Low → High')),
            DropdownMenuItem(
                value: 'price-high',
                child: Text('Price: High → Low')),
            DropdownMenuItem(
                value: 'rating', child: Text('Highest Rated')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _sortBy = val;
                _page = 1;
              });
              _fetchContent();
            }
          },
        ),
      ),
    );

    if (width != null) {
      return SizedBox(width: width, child: dropdown);
    }
    return dropdown;
  }

  Widget _filterButton() {
    return GestureDetector(
      onTap: _openFilterSheet,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: _hasActiveFilters ? AppColors.primary : Colors.white,
          border: Border.all(
            color: _hasActiveFilters
                ? AppColors.primary
                : Colors.grey.shade300,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune,
              size: 16,
              color: _hasActiveFilters
                  ? Colors.white
                  : AppColors.foreground,
            ),
            const SizedBox(width: 6),
            Text(
              'Filters${_hasActiveFilters ? ' ($_activeFilterCount)' : ''}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _hasActiveFilters
                    ? Colors.white
                    : AppColors.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required VoidCallback onRemove,
    IconData? icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.muted,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: AppColors.mutedForeground),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.foreground)),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close,
                size: 12, color: AppColors.mutedForeground),
          ),
        ],
      ),
    );
  }

  String _priceLabel(String range) {
    switch (range) {
      case 'free':
        return 'Free';
      case 'under-15':
        return '< Ksh 2,000';
      case '15-25':
        return 'Ksh 2k–3.5k';
      case '25-50':
        return 'Ksh 3.5k–7k';
      case 'over-50':
        return '> Ksh 7,000';
      default:
        return range;
    }
  }

  // ✅ Profile tap fixed: /profile → /settings
  Widget _bottomNav(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
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
            onTap: () => Navigator.pushNamedAndRemoveUntil(
                context, '/home', (r) => false),
          ),
          const _NavItem(
            icon: Icons.menu_book,
            label: 'Books',
            active: true,
          ),
          _NavItem(
            icon: Icons.shopping_cart_outlined,
            label: 'Cart',
            onTap: () => Navigator.pushNamed(context, '/cart'),
          ),
          _NavItem(
            icon: Icons.person_outline,
            label: 'Profile',
            // ✅ FIXED: was '/profile', now '/settings'
            onTap: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
// BOOK CARD
// ════════════════════════════════════════════════════════

class _BookCard extends StatelessWidget {
  final Content book;
  final String? addingToCartId;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;

  const _BookCard({
    required this.book,
    required this.addingToCartId,
    required this.onTap,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final titleSize = screenW < 360 ? 12.0 : 14.0;
    final authorSize = screenW < 360 ? 11.0 : 12.0;
    final priceSize = screenW < 360 ? 13.0 : 14.0;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: book.coverImageUrl ??
                        'https://images.unsplash.com/photo-1544947950-fa07a98d237f?w=400',
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    placeholder: (_, __) => Container(
                      decoration: BoxDecoration(
                        color: AppColors.muted,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      decoration: BoxDecoration(
                        color: AppColors.muted,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Icon(Icons.book,
                            size: 36,
                            color: AppColors.mutedForeground),
                      ),
                    ),
                  ),
                ),

                if (book.isBestseller)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _badge('Bestseller', AppColors.secondary),
                  )
                else if (book.isNewArrival)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _badge('New', AppColors.accent),
                  ),

                if (book.isFree)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _badge('Free', AppColors.intercenBlue),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              const Icon(Icons.star_rounded,
                  size: 13, color: AppColors.primary),
              const SizedBox(width: 3),
              Text(
                book.averageRating.toStringAsFixed(1),
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 3),
              Text(
                '(${book.totalReviews})',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.mutedForeground),
              ),
            ],
          ),

          const SizedBox(height: 4),

          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'PlayfairDisplay',
              fontWeight: FontWeight.w700,
              fontSize: titleSize,
              color: AppColors.foreground,
              height: 1.25,
            ),
          ),

          const SizedBox(height: 3),

          Text(
            book.author ?? 'Unknown Author',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: authorSize,
              color: AppColors.mutedForeground,
            ),
          ),

          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  book.isFree
                      ? 'Free'
                      : 'Ksh ${book.price.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: priceSize,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
              if (book.isForSale)
                GestureDetector(
                  onTap: onAddToCart,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: addingToCartId == book.id
                          ? AppColors.primary.withOpacity(0.1)
                          : AppColors.muted,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: addingToCartId == book.id
                            ? AppColors.primary.withOpacity(0.3)
                            : Colors.transparent,
                      ),
                    ),
                    child: addingToCartId == book.id
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : const Icon(
                            Icons.shopping_cart_outlined,
                            size: 14,
                            color: AppColors.foreground,
                          ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
// FILTER SHEET
// ════════════════════════════════════════════════════════

class _FilterSheet extends StatefulWidget {
  final List<String> selectedCategories;
  final List<String> selectedContentTypes;
  final String priceRange;
  final List<Map<String, String>> categories;
  final List<Map<String, String>> contentTypes;
  final int totalResults;
  final void Function({
    required List<String> categories,
    required List<String> contentTypes,
    required String priceRange,
  }) onApply;
  final VoidCallback onClear;

  const _FilterSheet({
    required this.selectedCategories,
    required this.selectedContentTypes,
    required this.priceRange,
    required this.categories,
    required this.contentTypes,
    required this.totalResults,
    required this.onApply,
    required this.onClear,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late List<String> _cats;
  late List<String> _types;
  late String _price;

  @override
  void initState() {
    super.initState();
    _cats = List.from(widget.selectedCategories);
    _types = List.from(widget.selectedContentTypes);
    _price = widget.priceRange;
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    return Container(
      height: screenH * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
            child: Row(
              children: [
                const Icon(Icons.filter_list,
                    color: AppColors.foreground, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Filters',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.foreground,
                  ),
                ),
                const Spacer(),
                if (_cats.isNotEmpty ||
                    _types.isNotEmpty ||
                    _price != 'all')
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _cats = [];
                        _types = [];
                        _price = 'all';
                      });
                    },
                    child: const Text('Reset',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                  ),
                IconButton(
                  icon: const Icon(Icons.close,
                      color: AppColors.foreground),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: Colors.grey.shade200),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              children: [
                _sectionTitle('Content Type'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.contentTypes.map((type) {
                    final val = type['value']!;
                    final selected = _types.contains(val);
                    return _selectableChip(
                      label: type['label']!,
                      selected: selected,
                      onTap: () {
                        setState(() {
                          if (selected) {
                            _types.remove(val);
                          } else {
                            _types.add(val);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),

                const SizedBox(height: 24),
                Divider(color: Colors.grey.shade200),
                const SizedBox(height: 20),

                _sectionTitle('Categories'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.categories.map((cat) {
                    final slug = cat['slug']!;
                    final selected = _cats.contains(slug);
                    return _selectableChip(
                      label: cat['name']!,
                      selected: selected,
                      onTap: () {
                        setState(() {
                          if (selected) {
                            _cats.remove(slug);
                          } else {
                            _cats.add(slug);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),

                const SizedBox(height: 24),
                Divider(color: Colors.grey.shade200),
                const SizedBox(height: 20),

                _sectionTitle('Price Range'),
                const SizedBox(height: 12),
                ...[
                  {'value': 'all', 'label': 'All Prices'},
                  {'value': 'free', 'label': 'Free'},
                  {'value': 'under-15', 'label': 'Under Ksh 2,000'},
                  {'value': '15-25', 'label': 'Ksh 2,000 – Ksh 3,500'},
                  {'value': '25-50', 'label': 'Ksh 3,500 – Ksh 7,000'},
                  {'value': 'over-50', 'label': 'Over Ksh 7,000'},
                ].map((range) {
                  final selected = _price == range['value'];
                  return InkWell(
                    onTap: () =>
                        setState(() => _price = range['value']!),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 4),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
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
                          Text(
                            range['label']!,
                            style: TextStyle(
                              fontSize: 14,
                              color: selected
                                  ? AppColors.foreground
                                  : AppColors.mutedForeground,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 16),
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              border:
                  Border(top: BorderSide(color: Colors.grey.shade200)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    widget.onApply(
                      categories: _cats,
                      contentTypes: _types,
                      priceRange: _price,
                    );
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    widget.totalResults > 0
                        ? 'View ${widget.totalResults} Results'
                        : 'Apply Filters',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: AppColors.foreground,
        ),
      );

  Widget _selectableChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.muted,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : AppColors.foreground,
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
// PAGINATION
// ════════════════════════════════════════════════════════

class _Pagination extends StatelessWidget {
  final int page;
  final int totalPages;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _Pagination({
    required this.page,
    required this.totalPages,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _pageBtn(
            label: 'Previous',
            icon: Icons.arrow_back_ios_new,
            enabled: page > 1,
            onTap: onPrev,
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.muted,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$page / $totalPages',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.foreground,
              ),
            ),
          ),
          const SizedBox(width: 16),
          _pageBtn(
            label: 'Next',
            icon: Icons.arrow_forward_ios,
            enabled: page < totalPages,
            onTap: onNext,
            iconAfter: true,
          ),
        ],
      ),
    );
  }

  Widget _pageBtn({
    required String label,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    bool iconAfter = false,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.3,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: enabled ? AppColors.foreground : AppColors.muted,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!iconAfter) ...[
                Icon(icon, size: 12, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: enabled
                      ? Colors.white
                      : AppColors.mutedForeground,
                ),
              ),
              if (iconAfter) ...[
                const SizedBox(width: 6),
                Icon(icon, size: 12, color: Colors.white),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
// LOADING / EMPTY / ERROR STATES
// ════════════════════════════════════════════════════════

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 3,
              backgroundColor: AppColors.primary.withOpacity(0.1),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Loading content...',
            style: TextStyle(
              color: AppColors.mutedForeground,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasFilters;
  final VoidCallback onClear;

  const _EmptyState({required this.hasFilters, required this.onClear});

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
              child: const Icon(Icons.search_off,
                  size: 40, color: AppColors.mutedForeground),
            ),
            const SizedBox(height: 20),
            const Text(
              'No content found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.foreground,
                fontFamily: 'PlayfairDisplay',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try adjusting your filters or\nsearch query',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.mutedForeground,
                height: 1.5,
              ),
            ),
            if (hasFilters) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Clear All Filters'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline,
                  color: AppColors.primary, size: 18),
              SizedBox(width: 8),
              Text(
                'Failed to load content',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: const TextStyle(
                color: AppColors.primary, fontSize: 12),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
// NAV ITEM
// ════════════════════════════════════════════════════════

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : Colors.grey;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight:
                  active ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}