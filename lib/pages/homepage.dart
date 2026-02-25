import 'package:flutter/material.dart';
import '../data/dummydata.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F5EF),
      bottomNavigationBar: _bottomNav(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // =========================
              // TOP BAR
              // =========================
              Row(
                children: [
                  const CircleAvatar(
                    radius: 18,
                    backgroundImage:
                        NetworkImage("https://i.pravatar.cc/150?img=12"),
                  ),
                  const Spacer(),
                  Image.asset(
                    "lib/assets/intercenlogo.png",
                    height: 32,
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.notifications_none, size: 20),
                  ),
                ],
              ),

              const SizedBox(height: 26),

              // =========================
              // HERO TEXT
              // =========================
              const Text(
                "Looking for something inspiring?\nExplore our library!",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),

              const SizedBox(height: 26),

              // =========================
              // FEATURED BOOKS
              // =========================
              const Text(
                "Featured Books",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),

              const SizedBox(height: 14),

              SizedBox(
                height: 240,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: trendingBooks.length,
                  itemBuilder: (_, i) {
                    return _featuredBookCard(trendingBooks[i]);
                  },
                ),
              ),

              const SizedBox(height: 32),

              // =========================
              // NEW RELEASES
              // =========================
              const Text(
                "New Releases",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),

              const SizedBox(height: 14),

              SizedBox(
                height: 180,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: newReleases.length,
                  itemBuilder: (_, i) {
                    return _newReleaseCard(newReleases[i]);
                  },
                ),
              ),

              const SizedBox(height: 32),

              // =========================
              // CONTINUE READING
              // =========================
              if (dummyBooks.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Continue Reading",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 14),
                    _continueReadingCard(dummyBooks.first),
                    const SizedBox(height: 32),
                  ],
                ),

              // =========================
              // KENYAN AUTHORS SPOTLIGHT (FIXED)
              // =========================
              const Text(
                "Kenyan Authors Spotlight",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),

              const SizedBox(height: 14),

              SizedBox(
                height: 150,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: const [
                    _AuthorCard(
                      name: "Barak Wandera",
                      imageUrl: "lib/assets/barak.png",
                    ),
                    _AuthorCard(
                      name: "Egara Kabaji",
                      imageUrl: "lib/assets/egara.jpeg",
                    ),
                    _AuthorCard(
                      name: "Meja Mwangi",
                      imageUrl: "lib/assets/egara.jpeg",
                    ),
                    _AuthorCard(
                      name: "Margaret Ogola",
                      imageUrl: "lib/assets/barak.png",
                    ),
                    _AuthorCard(
                      name: "Binyavanga Wainaina",
                      imageUrl: "lib/assets/barak.png",
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // =========================
              // LOCAL LANGUAGES
              // =========================
              if (localLanguageBooks.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Popular in Kiswahili & Local Languages",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 200,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: localLanguageBooks.length,
                        itemBuilder: (_, i) {
                          return _localLanguageCard(localLanguageBooks[i]);
                        },
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),

              const SizedBox(height: 110),
            ],
          ),
        ),
      ),
    );
  }

  // =========================
  // FEATURED BOOK CARD
  // =========================
  Widget _featuredBookCard(DummyBook book) {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, '/book_detail', arguments: book.id);
      },
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              child: Image.asset(
                book.image,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      book.author,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey),
                    ),
                    const Spacer(),
                    Text(
                      'KES ${book.price.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB11226)),
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

  // =========================
  // NEW RELEASE CARD
  // =========================
  Widget _newReleaseCard(DummyBook book) {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, '/book_detail', arguments: book.id);
      },
      child: Container(
        width: 130,
        margin: const EdgeInsets.only(right: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              child: Image.asset(
                book.image,
                height: 110,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================
  // CONTINUE READING CARD
  // =========================
  Widget _continueReadingCard(DummyBook book) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white,
      ),
      child: Row(
        children: [
          Image.asset(book.image, height: 90, width: 65, fit: BoxFit.cover),
          const SizedBox(width: 14),
          Expanded(
            child: Text(book.title,
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  // =========================
  // LOCAL LANGUAGE CARD
  // =========================
  Widget _localLanguageCard(DummyBook book) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
      ),
      child: Column(
        children: [
          Image.asset(book.image,
              height: 120, width: double.infinity, fit: BoxFit.cover),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(book.title,
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  // =========================
  // BOTTOM NAVIGATION
  // =========================
  Widget _bottomNav(BuildContext context) {
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(icon: Icons.home, label: "Home", active: true),
          _NavItem(
            icon: Icons.menu_book_outlined,
            label: "Books",
            onTap: () => Navigator.pushNamed(context, "/books"),
          ),
          _NavItem(
            icon: Icons.shopping_cart_outlined,
            label: "Cart",
            onTap: () => Navigator.pushNamed(context, "/cart"),
          ),
        ],
      ),
    );
  }
}

// =========================
// AUTHOR CARD (ASSET-BASED)
// =========================
class _AuthorCard extends StatelessWidget {
  final String name;
  final String imageUrl;

  const _AuthorCard({required this.name, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      margin: const EdgeInsets.only(right: 14),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              imageUrl,
              height: 90,
              width: 90,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// =========================
// NAV ITEM
// =========================
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
    final color = active ? const Color(0xFFB11226) : Colors.grey;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight:
                      active ? FontWeight.w600 : FontWeight.normal)),
        ],
      ),
    );
  }
}