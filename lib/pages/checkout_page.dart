import 'package:flutter/material.dart';

const Color kRed = Color(0xFFB11226);
const Color kBg = Color(0xFFF4F4F4);

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  String? selectedPaymentMethod;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Complete Your Payment",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _orderDetailsCard(),
            const SizedBox(height: 16),
            _orderItemsCard(),
            const SizedBox(height: 16),
            _shippingAddressCard(),
            const SizedBox(height: 16),
            _paymentMethodCard(),
            const SizedBox(height: 16),
            _paymentSummaryCard(),
            const SizedBox(height: 24),
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
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: child,
    );
  }

  // =========================================================
  // ORDER DETAILS
  // =========================================================

  Widget _orderDetailsCard() {
    return _cardWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Order Details",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _detailRow("Order Number", "ORD-20260301-E5FN"),
          _detailRow("Order Date", "March 1, 2026"),
          _detailRow("Status", "Pending"),
          _detailRow("Payment Status", "Pending", highlight: true),
        ],
      ),
    );
  }

  // =========================================================
  // ORDER ITEMS
  // =========================================================

  Widget _orderItemsCard() {
    return _cardWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Order Items",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _orderItem("When We Speak", "by Rafini", "KES 500", 1),
          const Divider(height: 24),
          _orderItem("Wanjira and the Hitlers", "by Peter Amuka", "KES 1,000", 2),
        ],
      ),
    );
  }

  Widget _orderItem(
      String title, String author, String price, int qty) {
    return Row(
      children: [
        Container(
          height: 70,
          width: 50,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(8),
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
              Text(author, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Text("Qty: $qty",
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        Text(price,
            style:
                const TextStyle(fontWeight: FontWeight.bold, color: kRed)),
      ],
    );
  }

  // =========================================================
  // SHIPPING ADDRESS (FULL WIDTH)
  // =========================================================

  Widget _shippingAddressCard() {
    return _cardWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text("Shipping Address",
              style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 12),
          Text(
            "Kahawa Sukari, Nairobi, 00100",
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // PAYMENT METHOD (SELECTABLE)
  // =========================================================

  Widget _paymentMethodCard() {
    return _cardWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Choose Payment Method",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _paymentOption("mpesa", Icons.phone_android, "M-Pesa",
              "Safaricom Daraja"),
          const SizedBox(height: 12),
          _paymentOption("paystack", Icons.credit_card, "Paystack",
              "Card / Bank Transfer"),
        ],
      ),
    );
  }

  Widget _paymentOption(
    String value,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final bool selected = selectedPaymentMethod == value;

    return GestureDetector(
      onTap: () {
        setState(() => selectedPaymentMethod = value);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? kRed : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? kRed : Colors.black),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: selected ? kRed : Colors.black)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey)),
              ],
            )
          ],
        ),
      ),
    );
  }

  // =========================================================
  // PAYMENT SUMMARY + PAY BUTTON
  // =========================================================

  Widget _paymentSummaryCard() {
    final bool canPay = selectedPaymentMethod != null;

    return _cardWrapper(
      child: Column(
        children: [
          _detailRow("Subtotal", "KES 1,500"),
          _detailRow("Shipping", "KES 500"),
          const Divider(height: 24),
          _detailRow("Total", "KES 2,000", bold: true, red: true),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: canPay ? kRed : Colors.grey.shade400,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: canPay ? _payNow : null,
              child: Text(
                canPay ? "Pay Now" : "Select a Payment Method",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _payNow() {
    // Payment logic will be added next
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            "Proceeding with ${selectedPaymentMethod == "mpesa" ? "M-Pesa" : "Paystack"}"),
        backgroundColor: kRed,
      ),
    );
  }

  // =========================================================
  // REUSABLE DETAIL ROW
  // =========================================================

  Widget _detailRow(String title, String value,
      {bool bold = false, bool red = false, bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: red
                  ? kRed
                  : highlight
                      ? Colors.orange
                      : Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}