import 'package:flutter/material.dart';
import 'dart:math';

// 👉 ADD THIS IMPORT
import 'checkout_page.dart';

const Color kRed = Color(0xFFB11226);
const Color kBg = Color(0xFFF4F4F4);

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  int qtyBook1 = 1;
  int qtyBook2 = 2;

  String selectedDelivery = "Standard Delivery";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Shopping Cart",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _cartItemsCard(),
            const SizedBox(height: 16),
            _customerInformation(),
            const SizedBox(height: 16),
            _shippingAddress(),
            const SizedBox(height: 16),
            _deliveryMethod(),
            const SizedBox(height: 16),
            _orderSummary(),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // CARD WRAPPER
  // =========================================================

  Widget _cardWrapper({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: child,
    );
  }

  // =========================================================
  // CART ITEMS
  // =========================================================

  Widget _cartItemsCard() {
    return _cardWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Cart Items (2)",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _cartItem(
            title: "When We Speak",
            author: "Rafini",
            price: "KSh 500",
            qty: qtyBook1,
            onAdd: () => setState(() => qtyBook1++),
            onRemove: () {
              if (qtyBook1 > 1) {
                setState(() => qtyBook1--);
              }
            },
          ),
          const SizedBox(height: 16),
          _cartItem(
            title: "Wanjira and the Hitlers",
            author: "Peter Amuka",
            price: "KSh 500",
            qty: qtyBook2,
            onAdd: () => setState(() => qtyBook2++),
            onRemove: () {
              if (qtyBook2 > 1) {
                setState(() => qtyBook2--);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _cartItem({
    required String title,
    required String author,
    required String price,
    required int qty,
    required VoidCallback onAdd,
    required VoidCallback onRemove,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 80,
          width: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey.shade300,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(author, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              Text(price,
                  style: const TextStyle(
                      color: kRed, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _qtyButton(Icons.remove, onRemove),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(qty.toString()),
                  ),
                  _qtyButton(Icons.add, onAdd),
                ],
              )
            ],
          ),
        ),
        const Icon(Icons.delete_outline, color: kRed)
      ],
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }

  // =========================================================
  // CUSTOMER INFO
  // =========================================================

  Widget _customerInformation() {
    return _cardWrapper(
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Customer Information",
              style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 16),
          _InputField(label: "Full Name *", hint: "John Doe"),
          SizedBox(height: 12),
          _InputField(label: "Email *", hint: "egarajere@gmail.com"),
          SizedBox(height: 12),
          _InputField(label: "Phone Number *", hint: "+254 700 000 000"),
        ],
      ),
    );
  }

  Widget _shippingAddress() {
    return _cardWrapper(
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Shipping Address",
              style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 16),
          _InputField(label: "Street Address *", hint: "123 Main Street"),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _InputField(label: "City *", hint: "Nairobi"),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _InputField(label: "Postal Code", hint: "00100"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================
  // DELIVERY METHOD
  // =========================================================

  Widget _deliveryMethod() {
    return _cardWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Delivery Method",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _deliveryOption("Standard Delivery", "KSh 500",
              "1–3 business days"),
          const SizedBox(height: 12),
          _deliveryOption("Express Delivery", "KSh 200",
              "1–2 business days"),
          const SizedBox(height: 12),
          _deliveryOption("Store Pickup", "Free", "Same day pickup"),
        ],
      ),
    );
  }

  Widget _deliveryOption(String title, String price, String subtitle) {
    final bool selected = selectedDelivery == title;

    return GestureDetector(
      onTap: () {
        setState(() => selectedDelivery = title);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("$title selected"),
            backgroundColor: kRed,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
              color: selected ? kRed : Colors.grey.shade300, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: selected ? kRed : Colors.black)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            Text(price,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: selected ? kRed : Colors.black)),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // ORDER SUMMARY + NAVIGATION
  // =========================================================

  Widget _orderSummary() {
    return _cardWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Order Summary",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _summaryRow("Subtotal", "KSh 1,500"),
          _summaryRow("Delivery", selectedDelivery),
          const Divider(height: 24),
          _summaryRow("Total", "KSh 1,500", bold: true),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kRed,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _placeOrder,
              child: const Text(
                "Place Order",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _placeOrder() {
    final orderNumber = Random().nextInt(900000) + 100000;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text("Order Placed 🎉"),
        content: Text(
          "Your order #$orderNumber has been placed successfully.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);

              /// 👉 NAVIGATE TO CHECKOUT PAGE
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CheckoutPage(),
                ),
              );
            },
            child: const Text(
              "Proceed to Checkout",
              style: TextStyle(color: kRed),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String title, String value, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title),
        Text(
          value,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: bold ? kRed : Colors.black,
          ),
        ),
      ],
    );
  }
}

// =========================================================
// INPUT FIELD
// =========================================================

class _InputField extends StatelessWidget {
  final String label;
  final String hint;

  const _InputField({required this.label, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          decoration: InputDecoration(
            hintText: hint,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }
}