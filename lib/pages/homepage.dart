// lib/pages/homepage.dart
//
// CORRECTED: Added _FeaturedBooksSection (Supabase fetch + fade-cycle + dot indicators)
//            between HeroSection and CategorySection — matching web Index.tsx order.
//            Added bookCount to _Category to match CategorySection TSX.
//            PromoBanner now passes {sale: true} argument to /books route.
//            No Scaffold / bottomNavigationBar — Shell in main.dart owns those.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intercen_app/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HOME PAGE
// ─────────────────────────────────────────────────────────────────────────────

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroSection(),
          _FeaturedBooksSection(),   // ← NEW (matches web FeaturedBooks.tsx)
          _CategorySection(),
          _PromoBanner(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HERO SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  const _HeroSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: AppColors.warmGradient),
      child: Stack(
        children: [
          // Decorative blurred circles
          Positioned(
            top: 20,
            left: 10,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.06),
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            right: 10,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.secondary.withOpacity(0.04),
              ),
            ),
          ),

          // Main content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Eyebrow label
                Column(
                  children: [
                    const Text(
                      'PUBLISHING EXCELLENCE SINCE 2019',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3.5,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(width: 60, height: 1, color: AppColors.primary),
                  ],
                ),

                const SizedBox(height: 24),

                // Headline
                RichText(
                  textAlign: TextAlign.center,
                  text: const TextSpan(
                    style: TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 34,
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                      color: AppColors.foreground,
                    ),
                    children: [
                      TextSpan(text: 'Your Partner in\n'),
                      TextSpan(
                        text: 'Publishing Success',
                        style: TextStyle(color: AppColors.primary),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Body
                const Text(
                  'Intercen Books is a leading publisher and book marketplace in East Africa. '
                  'We help authors bring their stories to life and connect readers with exceptional literature.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.6,
                    color: AppColors.mutedForeground,
                  ),
                ),

                const SizedBox(height: 28),

                // CTA Buttons
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/books'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.primaryForeground,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Browse Books',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward, size: 20),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/publish'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(
                              color: AppColors.primary, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Publish With Us',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Trust badges
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _TrustBadge(
                      icon: Icons.local_shipping_outlined,
                      title: 'Fast Delivery',
                      subtitle: 'Across East Africa',
                    ),
                    SizedBox(width: 24),
                    _TrustBadge(
                      icon: Icons.menu_book_outlined,
                      title: '500+ Titles',
                      subtitle: 'Quality Publications',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TRUST BADGE
// ─────────────────────────────────────────────────────────────────────────────

class _TrustBadge extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _TrustBadge({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent.withOpacity(0.15),
          ),
          child: Icon(icon, size: 20, color: AppColors.primary),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.foreground,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FEATURED BOOKS — DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────

class _BookItem {
  final String id;
  final String title;
  final String author;
  final double price;
  final double? originalPrice;
  final String description;
  final String coverImage;
  final double rating;
  final int reviewCount;
  final bool bestseller;

  const _BookItem({
    required this.id,
    required this.title,
    required this.author,
    required this.price,
    this.originalPrice,
    required this.description,
    required this.coverImage,
    required this.rating,
    required this.reviewCount,
    required this.bestseller,
  });

  factory _BookItem.fromMap(Map<String, dynamic> m) => _BookItem(
        id: m['id']?.toString() ?? '',
        title: m['title'] ?? '',
        author: m['author'] ?? '',
        price: (m['price'] as num? ?? 0).toDouble(),
        originalPrice: m['original_price'] != null
            ? (m['original_price'] as num).toDouble()
            : null,
        description: m['description'] ?? '',
        coverImage: m['cover_image_url'] ?? '',
        rating: (m['average_rating'] as num? ?? 0).toDouble(),
        reviewCount: (m['total_reviews'] as num? ?? 0).toInt(),
        bestseller: m['is_bestseller'] as bool? ?? false,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// FEATURED BOOKS SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _FeaturedBooksSection extends StatefulWidget {
  const _FeaturedBooksSection();

  @override
  State<_FeaturedBooksSection> createState() => _FeaturedBooksSectionState();
}

class _FeaturedBooksSectionState extends State<_FeaturedBooksSection> {
  List<_BookItem> _books = [];
  bool _loading = true;
  int _currentIndex = 0;
  bool _visible = true;
  Timer? _timer;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _fetchFeaturedBooks();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ── Data ─────────────────────────────────────────────────────────────────

  Future<void> _fetchFeaturedBooks() async {
    try {
      final data = await Supabase.instance.client
          .from('content')
          .select('*')
          .eq('is_featured', true)
          .eq('status', 'published')
          .order('published_at', ascending: false)
          .limit(9);

      if (!mounted) return;
      setState(() {
        _books = (data as List<dynamic>)
            .map((item) => _BookItem.fromMap(item as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
      _startCycle();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Cycling ───────────────────────────────────────────────────────────────
  // Matches web: 15 s display + 1.2 s crossfade = 16.2 s interval.

  void _startCycle() {
    if (_books.length <= 1) return;
    _timer = Timer.periodic(const Duration(milliseconds: 16200), (_) {
      if (!mounted) return;
      setState(() => _visible = false);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        setState(() {
          _currentIndex = (_currentIndex + 1) % _books.length;
          _visible = true;
        });
      });
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CURATED SELECTION',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3.5,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(width: 60, height: 1, color: AppColors.primary),
                    const SizedBox(height: 12),
                    const Text(
                      'Featured Books',
                      style: TextStyle(
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 26,
                        fontWeight: FontWeight.w400,
                        color: AppColors.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Hand-picked selections from our editors',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/books'),
                child: const Row(
                  children: [
                    Text(
                      'View All',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward, size: 16, color: AppColors.primary),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Content ─────────────────────────────────────────────────────
          if (_loading)
            const SizedBox(
              height: 280,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2.5,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading featured books…',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_books.isEmpty)
            const SizedBox(
              height: 200,
              child: Center(
                child: Text(
                  'No featured books available at the moment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ),
            )
          else
            AnimatedOpacity(
              opacity: _visible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 600),
              child: _FeaturedBookCard(book: _books[_currentIndex]),
            ),

          // ── Dot indicators ───────────────────────────────────────────────
          if (!_loading && _books.length > 1) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_books.length, (i) {
                final active = i == _currentIndex;
                return GestureDetector(
                  onTap: () {
                    _timer?.cancel();
                    setState(() {
                      _visible = false;
                    });
                    Future.delayed(const Duration(milliseconds: 300), () {
                      if (!mounted) return;
                      setState(() {
                        _currentIndex = i;
                        _visible = true;
                      });
                      _startCycle();
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 22 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.primary
                          : AppColors.muted,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FEATURED BOOK CARD  (variant="featured" equivalent)
// ─────────────────────────────────────────────────────────────────────────────

class _FeaturedBookCard extends StatelessWidget {
  final _BookItem book;
  const _FeaturedBookCard({required this.book});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/book/${book.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cover image ───────────────────────────────────────────────
            SizedBox(
              width: 130,
              height: 200,
              child: book.coverImage.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: book.coverImage,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: AppColors.muted,
                        child: const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.muted,
                        child: const Icon(
                          Icons.book_outlined,
                          size: 36,
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    )
                  : Container(
                      color: AppColors.muted,
                      child: const Icon(
                        Icons.book_outlined,
                        size: 36,
                        color: AppColors.mutedForeground,
                      ),
                    ),
            ),

            // ── Details ───────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Bestseller badge
                    if (book.bestseller) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'BESTSELLER',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: AppColors.gold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Title
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.foreground,
                        height: 1.3,
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Author
                    Text(
                      book.author,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.mutedForeground,
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Star rating
                    if (book.rating > 0) ...[
                      Row(
                        children: [
                          ...List.generate(5, (i) {
                            if (i < book.rating.floor()) {
                              return const Icon(Icons.star,
                                  size: 13, color: AppColors.gold);
                            } else if (i < book.rating) {
                              return const Icon(Icons.star_half,
                                  size: 13, color: AppColors.gold);
                            }
                            return const Icon(Icons.star_outline,
                                size: 13, color: AppColors.gold);
                          }),
                          const SizedBox(width: 4),
                          Text(
                            '(${book.reviewCount})',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Description
                    Text(
                      book.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: AppColors.mutedForeground,
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Price + cart button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'KES ${book.price.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                            if (book.originalPrice != null)
                              Text(
                                'KES ${book.originalPrice!.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.mutedForeground,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                          ],
                        ),
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.add_shopping_cart_outlined,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CATEGORY SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _CategorySection extends StatelessWidget {
  const _CategorySection();

  static const _categories = [
    _Category('Fiction', 'fiction', 84,
        'https://images.unsplash.com/photo-1481627834876-b7833e8f5570?w=400&h=300&fit=crop'),
    _Category('Non-Fiction', 'non-fiction', 62,
        'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&h=300&fit=crop'),
    _Category('Mystery & Thriller', 'mystery-thriller', 47,
        'https://images.unsplash.com/photo-1509021436665-8f07dbf5bf1d?w=400&h=300&fit=crop'),
    _Category('Romance', 'romance', 55,
        'https://images.unsplash.com/photo-1518199266791-5375a83190b7?w=400&h=300&fit=crop'),
    _Category('Science Fiction', 'science-fiction', 38,
        'https://images.unsplash.com/photo-1446776653964-20c1d3a81b06?w=400&h=300&fit=crop'),
    _Category('Biography', 'biography', 29,
        'https://images.unsplash.com/photo-1516979187457-637abb4f9353?w=400&h=300&fit=crop'),
    _Category('Self-Help', 'self-help', 43,
        'https://images.unsplash.com/photo-1589829085413-56de8ae18c73?w=400&h=300&fit=crop'),
    _Category("Children's Books", 'childrens', 31,
        'https://images.unsplash.com/photo-1629992101753-56d196c8aabb?w=400&h=300&fit=crop'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.muted.withOpacity(0.3),
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Column(
        children: [
          // Header
          Column(
            children: [
              const Text(
                'CATEGORIES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3.5,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Container(width: 60, height: 1, color: AppColors.primary),
              const SizedBox(height: 16),
              const Text(
                'Browse by Category',
                style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 28,
                  fontWeight: FontWeight.w400,
                  color: AppColors.foreground,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Explore our curated collection across diverse genres',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.mutedForeground,
                  height: 1.5,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 2-column grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _categories.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 4 / 3,
            ),
            itemBuilder: (context, index) =>
                _CategoryCard(category: _categories[index]),
          ),
        ],
      ),
    );
  }
}

class _Category {
  final String name;
  final String slug;
  final int bookCount;
  final String imageUrl;
  const _Category(this.name, this.slug, this.bookCount, this.imageUrl);
}

class _CategoryCard extends StatelessWidget {
  final _Category category;
  const _CategoryCard({required this.category});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(
        context,
        '/books',
        arguments: {'category': category.slug},
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background image
            CachedNetworkImage(
              imageUrl: category.imageUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                color: AppColors.muted,
                child: const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                color: AppColors.muted,
                child: const Icon(Icons.image,
                    size: 32, color: AppColors.mutedForeground),
              ),
            ),

            // Gradient overlay
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Color(0x66262626),
                    Color(0xE6262626),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),

            // Text (name + book count)
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.name,
                    style: const TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${category.bookCount} books',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.75),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROMO BANNER
// ─────────────────────────────────────────────────────────────────────────────

class _PromoBanner extends StatelessWidget {
  const _PromoBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: AppColors.promoBannerGradient,
          ),
          child: Stack(
            children: [
              // Decorative circles
              Positioned(
                top: -60,
                right: -60,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
              ),
              Positioned(
                bottom: -40,
                left: -40,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Limited Time pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.percent, size: 14, color: Colors.white),
                          SizedBox(width: 6),
                          Text(
                            'Limited Time Offer',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Headline
                    const Text(
                      'Up to 40% Off\nSelected Books',
                      style: TextStyle(
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 30,
                        fontWeight: FontWeight.w400,
                        height: 1.2,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Body
                    Text(
                      "Don't miss out on our biggest sale of the year. "
                      'Discover amazing deals on bestsellers and new releases.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // CTA — passes sale:true argument to /books (matches TSX ?sale=true)
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pushNamed(
                          context,
                          '/books',
                          arguments: {'sale': true},
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          foregroundColor: AppColors.foreground,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Shop the Sale',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}