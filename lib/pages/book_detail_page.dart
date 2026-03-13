import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/content.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';

// ─── Supporting models ────────────────────────────────────────────────────────
class _Category {
  final String id;
  final String name;
  final String slug;
  _Category({required this.id, required this.name, required this.slug});
  factory _Category.fromJson(Map<String, dynamic> j) => _Category(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        slug: j['slug'] as String? ?? '',
      );
}

class _DetailRow {
  final String label;
  final String value;
  _DetailRow(this.label, this.value);
}

const String _kFallback =
    'https://images.unsplash.com/photo-1544947950-fa07a98d237f?w=400';

// ─── Page ─────────────────────────────────────────────────────────────────────
class BookDetailPage extends StatefulWidget {
  const BookDetailPage({super.key});

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends State<BookDetailPage>
    with SingleTickerProviderStateMixin {
  final SupabaseService _service = SupabaseService();
  final _supabase = Supabase.instance.client;

  Content? _book;
  _Category? _category;
  List<Content> _related = [];
  bool _loading = true;
  String? _error;

  int _quantity = 1;
  int _selectedImage = 0;
  bool _addingToCart = false;
  int _activeTab = 0;

  late TabController _tabController;
  late PageController _pageController;

  // ── Responsive helpers ──
  static double _hPad(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    if (w >= 900) return 48;
    if (w >= 600) return 28;
    return 16;
  }

  static bool _isWide(BuildContext ctx) =>
      MediaQuery.of(ctx).size.width >= 700;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _activeTab = _tabController.index);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Content) {
        _loadFromContent(args);
      } else if (args is String) {
        _fetchById(args);
      } else {
        setState(() {
          _error = 'No book provided.';
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // ── Data loading ──
  Future<void> _loadFromContent(Content book) async {
    setState(() {
      _book = book;
      _loading = false;
    });
    await _loadExtras(book);
  }

  Future<void> _fetchById(String id) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _supabase
          .from('content')
          .select('*')
          .eq('id', id)
          .eq('status', 'published')
          .eq('visibility', 'public')
          .single();
      final book =
          Content.fromJson(Map<String, dynamic>.from(data as Map));
      if (!mounted) return;
      setState(() {
        _book = book;
        _loading = false;
      });
      await _loadExtras(book);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Book not found.';
        _loading = false;
      });
    }
  }

  Future<void> _loadExtras(Content book) async {
    if (book.categoryId == null) return;

    // Category
    try {
      final catData = await _supabase
          .from('categories')
          .select('id, name, slug')
          .eq('id', book.categoryId!)
          .single();
      if (!mounted) return;
      setState(() {
        _category =
            _Category.fromJson(Map<String, dynamic>.from(catData as Map));
      });
    } catch (_) {}

    // Related books
    try {
      final relData = await _supabase
          .from('content')
          .select('*')
          .eq('category_id', book.categoryId!)
          .eq('status', 'published')
          .eq('visibility', 'public')
          .eq('is_for_sale', true)
          .neq('id', book.id)
          .limit(4);
      if (!mounted) return;
      final list =
          List<dynamic>.from(relData);
      setState(() {
        _related = list
            .map((item) => Content.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList();
      });
    } catch (_) {}
  }

  // ── Actions ──
  Future<void> _handleAddToCart() async {
    if (_book == null || _addingToCart) return;
    if (_service.currentUser == null) {
      _showSnack('Please log in to add items to your cart.');
      Navigator.pushNamed(context, '/login');
      return;
    }
    if (_book!.stockQuantity == 0) {
      _showSnack('This item is out of stock.');
      return;
    }
    setState(() => _addingToCart = true);
    try {
      await _service.addToCart(_book!.id, _quantity);
      if (!mounted) return;
      _showSnack(
          'Added $_quantity × ${_book!.title} to cart',
          color: AppColors.secondary);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to add to cart. Please try again.');
    } finally {
      if (mounted) setState(() => _addingToCart = false);
    }
  }

  void _handleShare() {
    final book = _book;
    if (book == null) return;
    Clipboard.setData(ClipboardData(
        text:
            '${book.title} by ${book.author ?? 'Unknown Author'} — intercenbooks.com/books/${book.id}'));
    _showSnack('Link copied to clipboard!');
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

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_loading) return _scaffoldLoading();
    if (_error != null || _book == null) return _scaffoldError();
    return _scaffoldMain();
  }

  // ── Loading ──
  Widget _scaffoldLoading() => Scaffold(
        backgroundColor: AppColors.background,
        appBar: _simpleAppBar(),
        body: Center(
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
              const Text('Loading...',
                  style: TextStyle(
                      color: AppColors.mutedForeground,
                      fontSize: 14)),
            ],
          ),
        ),
      );

  // ── Error ──
  Widget _scaffoldError() => Scaffold(
        backgroundColor: AppColors.background,
        appBar: _simpleAppBar(),
        body: Center(
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
                  child: const Icon(Icons.book_outlined,
                      size: 36, color: AppColors.primary),
                ),
                const SizedBox(height: 16),
                const Text('Book Not Found',
                    style: TextStyle(
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.foreground)),
                const SizedBox(height: 8),
                Text(
                  _error ??
                      "The book you're looking for doesn't exist.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.mutedForeground,
                      fontSize: 14),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () =>
                      Navigator.pushNamedAndRemoveUntil(
                          context, '/books', (r) => false),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Back to Shop'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  PreferredSizeWidget _simpleAppBar() => AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back,
              color: AppColors.foreground),
          onPressed: () => Navigator.pop(context),
        ),
      );

  // ── Main ──
  Widget _scaffoldMain() {
    final book = _book!;
    final hPad = _hPad(context);
    final isWide = _isWide(context);
    final screenW = MediaQuery.of(context).size.width;

    final images = <String>[
      book.coverImageUrl?.isNotEmpty == true
          ? book.coverImageUrl!
          : _kFallback,
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: _bottomNav(),
      body: CustomScrollView(
        slivers: [
          // ── App bar ──
          SliverAppBar(
            pinned: true,
            elevation: 0,
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.black.withOpacity(0.06),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back,
                  color: AppColors.foreground, size: 22),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w700,
                fontFamily: 'PlayfairDisplay',
                fontSize: screenW < 360 ? 14 : 16,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(
                    Icons.shopping_cart_outlined,
                    color: AppColors.foreground,
                    size: 22),
                onPressed: () =>
                    Navigator.pushNamed(context, '/cart'),
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Breadcrumb
                Padding(
                  padding:
                      EdgeInsets.fromLTRB(hPad, 14, hPad, 0),
                  child: _breadcrumb(book),
                ),

                const SizedBox(height: 20),

                // ── Main product section ──
                isWide
                    ? Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: hPad),
                        child: Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 340,
                              child: _imageGallery(
                                  book, images,
                                  isWide: true),
                            ),
                            const SizedBox(width: 40),
                            Expanded(
                              child: _bookDetails(book,
                                  isWide: true),
                            ),
                          ],
                        ),
                      )
                    : Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: hPad),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            _imageGallery(book, images,
                                isWide: false),
                            const SizedBox(height: 24),
                            _bookDetails(book, isWide: false),
                          ],
                        ),
                      ),

                const SizedBox(height: 32),

                // ── Tabs ──
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: hPad),
                  child: _tabsSection(book),
                ),

                const SizedBox(height: 32),

                // ── Related ──
                if (_related.isNotEmpty) ...[
                  Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: hPad),
                    child: _relatedBooks(isWide),
                  ),
                  const SizedBox(height: 40),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BREADCRUMB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _breadcrumb(Content book) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _crumb('Home', () => Navigator.pushNamedAndRemoveUntil(
            context, '/home', (r) => false)),
        _sep(),
        _crumb('Shop', () => Navigator.pushNamedAndRemoveUntil(
            context, '/books', (r) => false)),
        if (_category != null) ...[
          _sep(),
          _crumb(_category!.name, () => Navigator.pushNamed(
              context, '/books',
              arguments: _category!.slug)),
        ],
        _sep(),
        SizedBox(
          width: 160,
          child: Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: AppColors.foreground,
                fontSize: 12,
                fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _crumb(String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Text(label,
            style: const TextStyle(
                color: AppColors.mutedForeground,
                fontSize: 12)),
      );

  Widget _sep() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Icon(Icons.chevron_right,
            size: 13, color: AppColors.mutedForeground),
      );

  // ══════════════════════════════════════════════════════════════════════════
  // IMAGE GALLERY — FIXED: BoxFit.contain + taller container + neutral bg
  // ══════════════════════════════════════════════════════════════════════════

  Widget _imageGallery(Content book, List<String> images,
      {required bool isWide}) {
    final screenW = MediaQuery.of(context).size.width;

    // FIXED: Taller image area so book covers are not cramped.
    // Book covers are typically portrait ~2:3 ratio. We give enough
    // height so the full cover fits without cropping.
    final imageHeight =
        isWide ? 420.0 : (screenW < 360 ? 300.0 : 340.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Main image container ──
        SizedBox(
          height: imageHeight,
          child: Stack(
            children: [
              // PageView — FIXED: neutral background + BoxFit.contain
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: images.length,
                  onPageChanged: (i) =>
                      setState(() => _selectedImage = i),
                  itemBuilder: (_, i) => Container(
                    // Neutral warm-grey background so the full cover
                    // is always visible with no cropping on either axis.
                    color: const Color(0xFFF2EFE9),
                    child: CachedNetworkImage(
                      imageUrl: images[i],
                      // FIXED: contain instead of cover — shows entire cover
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                      placeholder: (_, __) => Container(
                        color: AppColors.muted,
                        child: const Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.mutedForeground),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.muted,
                        child: const Center(
                          child: Icon(Icons.book,
                              size: 64,
                              color: AppColors.mutedForeground),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Arrows — only when multiple images
              if (images.length > 1) ...[
                if (_selectedImage > 0)
                  Positioned(
                    left: 8,
                    top: 0,
                    bottom: 0,
                    child: Center(
                        child: _arrowBtn(
                            Icons.chevron_left, () {
                      _pageController.previousPage(
                          duration:
                              const Duration(milliseconds: 300),
                          curve: Curves.easeInOut);
                    })),
                  ),
                if (_selectedImage < images.length - 1)
                  Positioned(
                    right: 8,
                    top: 0,
                    bottom: 0,
                    child: Center(
                        child: _arrowBtn(
                            Icons.chevron_right, () {
                      _pageController.nextPage(
                          duration:
                              const Duration(milliseconds: 300),
                          curve: Curves.easeInOut);
                    })),
                  ),

                // Dot indicators
                Positioned(
                  bottom: 10,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      images.length,
                      (i) => AnimatedContainer(
                        duration:
                            const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(
                            horizontal: 3),
                        width: _selectedImage == i ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _selectedImage == i
                              ? AppColors.primary
                              : Colors.white.withOpacity(0.7),
                          borderRadius:
                              BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ],

              // Badges — top left
              Positioned(
                top: 10,
                left: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (book.isBestseller) ...[
                      _imgBadge(
                          'Bestseller', AppColors.secondary),
                      const SizedBox(height: 5),
                    ],
                    if (book.isFeatured) ...[
                      _imgBadge('Featured', AppColors.accent),
                      const SizedBox(height: 5),
                    ],
                    if (book.isNewArrival)
                      _imgBadge('New Arrival',
                          AppColors.intercenBlue),
                  ],
                ),
              ),

              if (book.isFree)
                Positioned(
                  bottom: 10,
                  left: 10,
                  child: _imgBadge(
                      'Free', const Color(0xFF16A34A)),
                ),
            ],
          ),
        ),

        // ── Thumbnail strip — FIXED: contain + bg ──
        if (images.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            children: images.asMap().entries.map((e) {
              final sel = _selectedImage == e.key;
              return GestureDetector(
                onTap: () => _pageController.animateToPage(
                    e.key,
                    duration:
                        const Duration(milliseconds: 300),
                    curve: Curves.easeInOut),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  // FIXED: Wider thumbnail with correct book-cover ratio (2:3)
                  width: 56,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2EFE9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: sel
                          ? AppColors.primary
                          : Colors.grey.shade300,
                      width: sel ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: CachedNetworkImage(
                      imageUrl: e.value,
                      // FIXED: contain so thumbnail shows the full cover
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _arrowBtn(IconData icon, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.88),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Icon(icon,
              size: 20, color: AppColors.foreground),
        ),
      );

  Widget _imgBadge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(5),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ],
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3)),
      );

  // ══════════════════════════════════════════════════════════════════════════
  // BOOK DETAILS PANEL
  // ══════════════════════════════════════════════════════════════════════════

  Widget _bookDetails(Content book, {required bool isWide}) {
    final screenW = MediaQuery.of(context).size.width;
    final titleSize =
        isWide ? 26.0 : (screenW < 360 ? 20.0 : 22.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category
        Text(
          _category?.name ?? book.contentType,
          style: const TextStyle(
              color: AppColors.mutedForeground, fontSize: 13),
        ),
        const SizedBox(height: 6),

        // Title
        Text(
          book.title,
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            color: AppColors.foreground,
            height: 1.2,
          ),
        ),

        // Subtitle
        if (book.subtitle != null &&
            book.subtitle!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(book.subtitle!,
              style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.mutedForeground,
                  height: 1.3)),
        ],

        const SizedBox(height: 5),

        // Author
        Text('by ${book.author ?? 'Unknown Author'}',
            style: const TextStyle(
                fontSize: 14,
                color: AppColors.mutedForeground)),

        const SizedBox(height: 14),

        // Stars
        if (book.averageRating > 0) ...[
          Row(
            children: [
              ...List.generate(
                  5,
                  (i) => Icon(
                        i < book.averageRating.floor()
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 17,
                        color: AppColors.primary,
                      )),
              const SizedBox(width: 6),
              Text(book.averageRating.toStringAsFixed(1),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.foreground)),
              if (book.totalReviews > 0) ...[
                const SizedBox(width: 4),
                Text('(${book.totalReviews})',
                    style: const TextStyle(
                        color: AppColors.mutedForeground,
                        fontSize: 12)),
              ],
            ],
          ),
          const SizedBox(height: 14),
        ],

        // Price
        Text(
          book.isFree
              ? 'FREE'
              : 'KSH ${book.price.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            color: book.isFree
                ? const Color(0xFF16A34A)
                : AppColors.primary,
            letterSpacing: -0.5,
          ),
        ),

        const SizedBox(height: 10),

        // Stats
        if (book.viewCount > 0 || book.totalDownloads > 0) ...[
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              if (book.viewCount > 0)
                _statPill(Icons.visibility_outlined,
                    '${_fmt(book.viewCount)} views'),
              if (book.totalDownloads > 0)
                _statPill(Icons.download_outlined,
                    '${_fmt(book.totalDownloads)} downloads'),
            ],
          ),
          const SizedBox(height: 16),
        ],

        Divider(color: Colors.grey.shade200, height: 1),
        const SizedBox(height: 16),

        // Quantity + icons
        if (book.isForSale) ...[
          Row(
            children: [
              // Quantity picker
              Container(
                decoration: BoxDecoration(
                  border:
                      Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _qtyBtn(
                        Icons.remove,
                        _quantity > 1,
                        () => setState(() => _quantity--)),
                    SizedBox(
                      width: 36,
                      child: Center(
                        child: Text('$_quantity',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.foreground)),
                      ),
                    ),
                    _qtyBtn(
                        Icons.add,
                        _quantity < book.stockQuantity,
                        () => setState(() => _quantity++)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _outlineIconBtn(
                  Icons.favorite_border, () {}),
              const SizedBox(width: 8),
              _outlineIconBtn(
                  Icons.share_outlined, _handleShare),
            ],
          ),
          const SizedBox(height: 14),

          // Add to cart
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed:
                  (book.stockQuantity == 0 || _addingToCart)
                      ? null
                      : _handleAddToCart,
              icon: _addingToCart
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white))
                  : const Icon(
                      Icons.shopping_cart_outlined,
                      size: 18),
              label: Text(
                book.stockQuantity == 0
                    ? 'Out of Stock'
                    : book.isFree
                        ? 'Get Free Copy'
                        : 'Add to Cart',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: book.stockQuantity == 0
                    ? Colors.grey.shade400
                    : AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],

        // Free download
        if (book.isFree && book.fileUrl != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: () => _showSnack(
                  'Download started for ${book.title}'),
              icon: const Icon(Icons.download_outlined,
                  size: 16),
              label: const Text('Download Now',
                  style: TextStyle(
                      fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.foreground,
                side: BorderSide(
                    color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _qtyBtn(
          IconData icon, bool enabled, VoidCallback onTap) =>
      GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 36,
          height: 38,
          alignment: Alignment.center,
          child: Icon(icon,
              size: 16,
              color: enabled
                  ? AppColors.foreground
                  : AppColors.mutedForeground),
        ),
      );

  Widget _outlineIconBtn(
          IconData icon, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            border:
                Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon,
              color: AppColors.primary, size: 18),
        ),
      );

  Widget _statPill(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 13,
              color: AppColors.mutedForeground),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: AppColors.mutedForeground,
                  fontSize: 12)),
        ],
      );

  String _fmt(int n) {
    if (n >= 1000000) {
      return '${(n / 1000000).toStringAsFixed(1)}M';
    }
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TABS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _tabsSection(Content book) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TabBar(
          controller: _tabController,
          labelColor: AppColors.foreground,
          unselectedLabelColor: AppColors.mutedForeground,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 14),
          unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.normal, fontSize: 14),
          indicatorColor: AppColors.primary,
          indicatorWeight: 2,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.grey.shade200,
          tabs: [
            const Tab(text: 'Description'),
            const Tab(text: 'Details'),
            Tab(text: 'Reviews (${book.totalReviews})'),
          ],
        ),
        const SizedBox(height: 20),
        IndexedStack(
          index: _activeTab,
          children: [
            _tabDescription(book),
            _tabDetails(book),
            _tabReviews(book),
          ],
        ),
      ],
    );
  }

  // ── Description tab ──
  Widget _tabDescription(Content book) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: book.description != null &&
                book.description!.isNotEmpty
            ? Text(
                book.description!,
                style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.mutedForeground,
                    height: 1.75),
              )
            : const Text(
                'No description available for this item.',
                style: TextStyle(
                    fontSize: 14,
                    color: AppColors.mutedForeground,
                    fontStyle: FontStyle.italic),
              ),
      );

  // ── Details tab ──
  Widget _tabDetails(Content book) {
    final rows = <_DetailRow>[];
    if (book.author != null) {
      rows.add(_DetailRow('Author', book.author!));
    }
    if (book.publisher != null) {
      rows.add(_DetailRow('Publisher', book.publisher!));
    }
    if (book.pageCount != null) {
      rows.add(_DetailRow('Pages', '${book.pageCount}'));
    }
    rows.add(_DetailRow(
        'Language', (book.language ?? 'en').toUpperCase()));
    if (book.format != null) {
      rows.add(_DetailRow('Format', book.format!.toUpperCase()));
    }
    if (_category != null) {
      rows.add(_DetailRow('Category', _category!.name));
    }
    if (book.publishedDate != null) {
      try {
        final d = DateTime.parse(book.publishedDate!);
        rows.add(_DetailRow(
            'Published', '${d.day}/${d.month}/${d.year}'));
      } catch (_) {
        rows.add(_DetailRow('Published', book.publishedDate!));
      }
    }
    if (book.isbn != null) {
      rows.add(_DetailRow('ISBN', book.isbn!));
    }
    if (book.fileSizeBytes != null) {
      rows.add(_DetailRow('File Size',
          '${(book.fileSizeBytes! / 1024 / 1024).toStringAsFixed(2)} MB'));
    }
    rows.add(_DetailRow('Version', book.version));

    return LayoutBuilder(builder: (ctx, constraints) {
      final wide = constraints.maxWidth > 460;
      if (wide) {
        final left = <_DetailRow>[];
        final right = <_DetailRow>[];
        for (var i = 0; i < rows.length; i++) {
          if (i.isEven) {
            left.add(rows[i]);
          } else {
            right.add(rows[i]);
          }
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                child: Column(
                    children:
                        left.map(_detailTile).toList())),
            const SizedBox(width: 24),
            Expanded(
                child: Column(
                    children:
                        right.map(_detailTile).toList())),
          ],
        );
      }
      return Column(
          children: rows.map(_detailTile).toList());
    });
  }

  Widget _detailTile(_DetailRow r) => Container(
        padding:
            const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: Border(
              bottom:
                  BorderSide(color: Colors.grey.shade100)),
        ),
        child: Row(
          mainAxisAlignment:
              MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.label,
                style: const TextStyle(
                    color: AppColors.mutedForeground,
                    fontSize: 13)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(r.value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.foreground,
                      fontSize: 13)),
            ),
          ],
        ),
      );

  // ── Reviews tab ──
  Widget _tabReviews(Content book) {
    if (book.totalReviews == 0) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.muted,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            const Icon(Icons.rate_review_outlined,
                size: 36,
                color: AppColors.mutedForeground),
            const SizedBox(height: 10),
            const Text('No reviews yet',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.foreground)),
            const SizedBox(height: 4),
            const Text(
                'Be the first to share your thoughts',
                style: TextStyle(
                    color: AppColors.mutedForeground,
                    fontSize: 13)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                if (_service.currentUser == null) {
                  Navigator.pushNamed(context, '/login');
                } else {
                  _showSnack('Review form coming soon!');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(8)),
              ),
              child: const Text('Write a Review'),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            book.averageRating.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w900,
              color: AppColors.foreground,
              height: 1,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: List.generate(
                    5,
                    (i) => Icon(
                          i < book.averageRating.floor()
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 20,
                          color: AppColors.primary,
                        )),
              ),
              const SizedBox(height: 4),
              Text('${book.totalReviews} reviews',
                  style: const TextStyle(
                      color: AppColors.mutedForeground,
                      fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RELATED BOOKS — FIXED: contain + bg + corrected aspect ratio
  // ══════════════════════════════════════════════════════════════════════════

  Widget _relatedBooks(bool isWide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'You May Also Like',
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.foreground,
          ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate:
              SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isWide ? 4 : 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
            // FIXED: Increased childAspectRatio denominator so each card
            // is tall enough to show the full cover + text without clipping.
            // Previously 0.54 was too short and forced the image to crop.
            childAspectRatio: isWide ? 0.48 : 0.50,
          ),
          itemCount: _related.length,
          itemBuilder: (ctx, i) {
            final rel = _related[i];
            return GestureDetector(
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const BookDetailPage(),
                  settings: RouteSettings(
                      name: '/book-detail',
                      arguments: rel),
                ),
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  // FIXED: AspectRatio matches a standard book cover (2:3)
                  // and uses BoxFit.contain so the entire cover is visible.
                  AspectRatio(
                    aspectRatio: 0.67, // 2:3 portrait — standard book cover
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(8),
                      child: Container(
                        // Neutral background so contain doesn't show
                        // awkward transparent letterboxing
                        color: const Color(0xFFF2EFE9),
                        child: CachedNetworkImage(
                          imageUrl: rel.coverImageUrl
                                      ?.isNotEmpty ==
                                  true
                              ? rel.coverImageUrl!
                              : _kFallback,
                          // FIXED: contain — never crops the cover
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: (_, __) =>
                              Container(
                                  color: AppColors.muted),
                          errorWidget: (_, __, ___) =>
                              Container(
                            color: AppColors.muted,
                            child: const Center(
                              child: Icon(Icons.book,
                                  color: AppColors
                                      .mutedForeground),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(rel.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: 'PlayfairDisplay',
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          height: 1.2,
                          color: AppColors.foreground)),
                  const SizedBox(height: 3),
                  Text(rel.author ?? 'Unknown',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11,
                          color:
                              AppColors.mutedForeground)),
                  const SizedBox(height: 5),
                  Text(
                    rel.isFree
                        ? 'Free'
                        : 'Ksh ${rel.price.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: AppColors.primary),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BOTTOM NAV
  // ══════════════════════════════════════════════════════════════════════════

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
            mainAxisAlignment:
                MainAxisAlignment.spaceAround,
            children: [
              _navItem(Icons.home_outlined, 'Home',
                  false, () {
                Navigator.pushNamedAndRemoveUntil(
                    context, '/home', (r) => false);
              }),
              _navItem(Icons.menu_book_outlined, 'Books',
                  false, () {
                Navigator.pushNamedAndRemoveUntil(
                    context, '/books', (r) => false);
              }),
              _navItem(Icons.shopping_cart_outlined,
                  'Cart', false, () {
                Navigator.pushNamed(context, '/cart');
              }),
            ],
          ),
        ),
      );

  Widget _navItem(IconData icon, String label,
          bool active, VoidCallback onTap) =>
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