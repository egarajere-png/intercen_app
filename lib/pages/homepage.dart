// lib/pages/homepage.dart
//
// FIX: Removed Scaffold + bottomNavigationBar from HomePage.
// Shell (in main.dart) now owns the single Scaffold and bottom nav bar.
// HomePage is just a scrollable body widget — no nav, no Scaffold.
// This prevents the page from rendering its own navbar that routes
// Profile → /profile instead of /settings.

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intercen_app/theme/app_colors.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ No Scaffold, no bottomNavigationBar.
    // Shell wraps this in a Scaffold and provides the nav bar.
    return const SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroSection(),
          _CategorySection(),
          _PromoBanner(),
        ],
      ),
    );
  }
}

// ── HERO SECTION ────────────────────────────────────────

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
                // Subtitle
                Column(
                  children: [
                    Text(
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
                    Container(
                      width: 60,
                      height: 1,
                      color: AppColors.primary,
                    ),
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

                // Body text
                const Text(
                  'Intercen Books is a leading publisher and book marketplace in East Africa. We help authors bring their stories to life and connect readers with exceptional literature.',
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
                      child: ElevatedButton.icon(
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
                        icon: const SizedBox.shrink(),
                        label: const Row(
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _TrustBadge(
                      icon: Icons.local_shipping_outlined,
                      title: 'Fast Delivery',
                      subtitle: 'Across East Africa',
                    ),
                    const SizedBox(width: 24),
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

// ── TRUST BADGE ─────────────────────────────────────────

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

// ── CATEGORY SECTION ────────────────────────────────────

class _CategorySection extends StatelessWidget {
  const _CategorySection();

  static const _categories = [
    _Category('Fiction', 'fiction',
        'https://images.unsplash.com/photo-1481627834876-b7833e8f5570?w=400&h=300&fit=crop'),
    _Category('Non-Fiction', 'non-fiction',
        'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&h=300&fit=crop'),
    _Category('Mystery & Thriller', 'mystery-thriller',
        'https://images.unsplash.com/photo-1509021436665-8f07dbf5bf1d?w=400&h=300&fit=crop'),
    _Category('Romance', 'romance',
        'https://images.unsplash.com/photo-1518199266791-5375a83190b7?w=400&h=300&fit=crop'),
    _Category('Science Fiction', 'science-fiction',
        'https://images.unsplash.com/photo-1446776653964-20c1d3a81b06?w=400&h=300&fit=crop'),
    _Category('Biography', 'biography',
        'https://images.unsplash.com/photo-1516979187457-637abb4f9353?w=400&h=300&fit=crop'),
    _Category('Self-Help', 'self-help',
        'https://images.unsplash.com/photo-1589829085413-56de8ae18c73?w=400&h=300&fit=crop'),
    _Category("Children's Books", 'childrens',
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
              Text(
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

          // Category Grid — 2 columns
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
            itemBuilder: (context, index) {
              final cat = _categories[index];
              return _CategoryCard(category: cat);
            },
          ),
        ],
      ),
    );
  }
}

class _Category {
  final String name;
  final String slug;
  final String imageUrl;
  const _Category(this.name, this.slug, this.imageUrl);
}

class _CategoryCard extends StatelessWidget {
  final _Category category;
  const _CategoryCard({required this.category});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () =>
          Navigator.pushNamed(context, '/books', arguments: category.slug),
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

            // Dark gradient overlay
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

            // Text
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Text(
                category.name,
                style: const TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── PROMO BANNER ────────────────────────────────────────

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
                    // Limited Time Offer pill
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
                          Icon(Icons.percent,
                              size: 14, color: Colors.white),
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
                      "Don't miss out on our biggest sale of the year. Discover amazing deals on bestsellers and new releases.",
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Shop the Sale button
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/books'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          foregroundColor: AppColors.foreground,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        icon: const SizedBox.shrink(),
                        label: const Row(
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