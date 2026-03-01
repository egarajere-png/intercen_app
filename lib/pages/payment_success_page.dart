import 'package:flutter/material.dart';

const Color kRed = Color(0xFFB11226);
const Color kGreen = Color(0xFF2ECC71);

class PaymentSuccessPage extends StatelessWidget {
  final String orderNumber;

  const PaymentSuccessPage({
    super.key,
    required this.orderNumber,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 90,
                width: 90,
                decoration: BoxDecoration(
                  color: kGreen.withOpacity(.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: kGreen,
                  size: 60,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Payment Successful!",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Your payment has been processed successfully.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Text(
                "Order Number: $orderNumber",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: kRed,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kRed,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.popUntil(context, (route) => route.isFirst);
                  },
                  child: const Text(
                    "Continue Shopping",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  // Future: navigate to order details
                },
                child: const Text(
                  "View Order Details",
                  style: TextStyle(color: kRed),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}