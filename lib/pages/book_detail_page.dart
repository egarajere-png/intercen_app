import 'package:flutter/material.dart';
import 'cart.dart';

class BookDetailPage extends StatefulWidget {
  const BookDetailPage({super.key});

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends State<BookDetailPage> {
  int quantity = 1;

  void _addToCart() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Item added to cart"),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F5EF),
      body: CustomScrollView(
        slivers: [
          /// 🔝 TOP APP BAR (appears on scroll)
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xFFF9F5EF),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Image(
              image: AssetImage("lib/assets/intercenlogo.png"),
              height: 40,
            ),
            centerTitle: true,
            
            actions: [
              IconButton(
                icon: const Icon(Icons.shopping_cart_outlined,
                    color: Colors.black),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => CartPage()),
                    );
                  },
              ),
            ],
          ),

          /// 📘 BOOK IMAGE (half screen, zoomed out)
          SliverToBoxAdapter(
            child: Container(
              height: MediaQuery.of(context).size.height * 0.5,
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Image.asset(
                  "lib/assets/image.png",
                  fit: BoxFit.contain, // 👈 zoomed out
                ),
              ),
            ),
          ),

          /// 📄 CONTENT
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Academic & Education",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),

                  const Text(
                    "Tell It to the Birds",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),

                  const Text(
                    "by Barasa Waswa",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    "KSH 500.00",
                    style: TextStyle(
                      color: Color(0xFFB11226),
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 24),

                  /// ➖➕ QUANTITY
                  Container(
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: () {
                            if (quantity > 1) {
                              setState(() => quantity--);
                            }
                          },
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              quantity.toString(),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            setState(() => quantity++);
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  /// 🛒 ADD TO CART BUTTON
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.shopping_cart_outlined),
                      label: const Text(
                        "Add to Cart",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFFB11226),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: _addToCart,
                    ),
                  ),

                  const SizedBox(height: 20),

                  /// ❤️ SHARE BUTTONS
                  Row(
                    children: [
                      _ActionIcon(icon: Icons.favorite_border),
                      const SizedBox(width: 14),
                      _ActionIcon(icon: Icons.share),
                    ],
                  ),

                  const SizedBox(height: 30),

                  /// 📑 TABS
                  Row(
                    children: const [
                      _TabItem(title: "Description", selected: true),
                      _TabItem(title: "Details"),
                      _TabItem(title: "Reviews (0)"),
                    ],
                  ),

                  const SizedBox(height: 20),

                  /// 📝 DESCRIPTION
                  const Text(
                    "A poetic and reflective literary work that captures human emotions, personal struggles, and silent hopes through symbolic storytelling. With lyrical depth and emotional resonance, the book explores themes of longing, healing, and inner reflection.",
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: Colors.grey,
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ❤️ ICON BUTTON
class _ActionIcon extends StatelessWidget {
  final IconData icon;

  const _ActionIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      width: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Color(0xFFB11226)),
      ),
      child: Icon(icon, color: Color(0xFFB11226)),
    );
  }
}

/// 📑 TAB ITEM
class _TabItem extends StatelessWidget {
  final String title;
  final bool selected;

  const _TabItem({
    required this.title,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? Colors.black : Colors.grey,
            ),
          ),
          const SizedBox(height: 6),
          if (selected)
            Container(
              height: 2,
              width: 40,
              color: Color(0xFFB11226),
            ),
        ],
      ),
    );
  }
}