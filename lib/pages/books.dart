import 'package:flutter/material.dart';

class BooksPage extends StatefulWidget {
  const BooksPage({super.key});

  @override
  State<BooksPage> createState() => _BooksPageState();
}

class _BooksPageState extends State<BooksPage> {
  final TextEditingController _searchController = TextEditingController();

  final List<Map<String, dynamic>> books = [
    {
      "title": "Dear Daughter and Other Stories",
      "author": "Barak Wandera",
      "price": 1200,
      "category": "Fantasy",
      "image": "lib/assets/image.png",
    },
    {
      "title": "In Whispers We Shout",
      "author": "Robert Kiyosaki",
      "price": 1500,
      "category": "Fiction Fantasy",
      "image": "lib/assets/whispers.png",
    },
    {
      "title": "Mourning Glory",
      "author": "Egara Kabaji",
      "price": 600,
      "category": "Fiction",
      "image": "lib/assets/mourning.png",
    },
    {
      "title": "Wanjira and the Hitlers",
      "author": "Peter Amuka",
      "price": 1300,
      "category": "Fantacy",
      "image": "lib/assets/hitlers.png",
    },
  ];

  List<Map<String, dynamic>> filteredBooks = [];

  @override
  void initState() {
    super.initState();
    filteredBooks = books;
  }

  void _searchBooks(String query) {
    setState(() {
      filteredBooks = books.where((book) {
        final titleMatch =
            book["title"].toLowerCase().contains(query.toLowerCase());
        final categoryMatch =
            book["category"].toLowerCase().contains(query.toLowerCase());
        final priceMatch =
            book["price"].toString().contains(query.toLowerCase());

        return titleMatch || categoryMatch || priceMatch;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F5EF),

      // =========================
      // APP BAR
      // =========================
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF9F5EF),
        centerTitle: true,
        title: const Text(
          "Books",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),

      // =========================
      // BODY
      // =========================
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          children: [
            const SizedBox(height: 12),

            // SEARCH BAR
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _searchBooks,
                decoration: const InputDecoration(
                  hintText:
                      "Search by title, category or price...",
                  prefixIcon: Icon(Icons.search),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // GRID
            Expanded(
              child: GridView.builder(
                itemCount: filteredBooks.length,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 18,
                  childAspectRatio: 0.62,
                ),
                itemBuilder: (context, i) {
                  return _bookCard(context, filteredBooks[i]);
                },
              ),
            ),
          ],
        ),
      ),

      // =========================
      // BOTTOM NAVIGATION
      // =========================
      bottomNavigationBar: _bottomNav(),
    );
  }

  // =========================
  // BOOK CARD
  // =========================
  Widget _bookCard(BuildContext context, Map<String, dynamic> book) {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, "/book-detail", arguments: book);
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16), // rounded edges
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  book["image"],
                  fit: BoxFit.cover,
                  width: double.infinity,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              book["title"],
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              book["author"],
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "KES ${book["price"]}",
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFFB11226),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================
  // BOTTOM NAV BAR
  // =========================
  Widget _bottomNav() {
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: const [
          _NavItem(icon: Icons.home, label: "Home"),
          _NavItem(icon: Icons.menu_book, label: "Books", active: true),
          _NavItem(icon: Icons.shopping_cart_outlined, label: "Cart"),
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

  const _NavItem({
    required this.icon,
    required this.label,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFFB11226) : Colors.grey;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight:
                active ? FontWeight.w600 : FontWeight.normal,
          ),
        )
      ],
    );
  }
}
