import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

Widget buildLabel(String text) {
  return Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Color(0xFF333333),
    ),
  );
}

Widget buildTextField({
  required TextEditingController controller,
  required String hint,
  required IconData icon,
  TextInputType keyboardType = TextInputType.text,
}) {
  return TextField(
    controller: controller,
    keyboardType: keyboardType,
    style: const TextStyle(fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 14),
      prefixIcon: Icon(icon, color: const Color(0xFF888888), size: 20),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFB11226), width: 1.5),
      ),
    ),
  );
}

Widget buildPasswordField({
  required TextEditingController controller,
  required String hint,
  required bool show,
  required VoidCallback onToggle,
}) {
  return TextField(
    controller: controller,
    obscureText: !show,
    style: const TextStyle(fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 14),
      prefixIcon:
          const Icon(Icons.lock_outline, color: Color(0xFF888888), size: 20),
      suffixIcon: IconButton(
        icon: Icon(
          show ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          color: const Color(0xFF888888),
          size: 20,
        ),
        onPressed: onToggle,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFB11226), width: 1.5),
      ),
    ),
  );
}

Widget buildPrimaryButton({
  required String label,
  required bool isLoading,
  required VoidCallback onPressed,
}) {
  return SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFB11226),
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2),
            )
          : Text(
              label,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold),
            ),
    ),
  );
}

Widget buildDivider(String text) {
  return Row(
    children: [
      const Expanded(child: Divider(color: Color(0xFFDDDDDD))),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          text,
          style: const TextStyle(color: Color(0xFF999999), fontSize: 12),
        ),
      ),
      const Expanded(child: Divider(color: Color(0xFFDDDDDD))),
    ],
  );
}

Widget buildSocialButton({
  required IconData icon,
  required String label,
  required VoidCallback onPressed,
}) {
  return OutlinedButton.icon(
    onPressed: onPressed,
    icon: FaIcon(icon, size: 16),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: const Color(0xFF2D2D2D),
      padding: const EdgeInsets.symmetric(vertical: 14),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle:
          const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
}

Widget buildDarkHeader({
  required String title,
  required String subtitle,
}) {
  return Container(
    width: double.infinity,
    color: const Color(0xFF1E1E1E),
    padding: const EdgeInsets.fromLTRB(28, 60, 28, 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset(
          'lib/assets/intercenlogo.png',
          height: 48,
          errorBuilder: (_, __, ___) => Row(
            children: const [
              Icon(Icons.menu_book_rounded,
                  color: Color(0xFFB11226), size: 28),
              SizedBox(width: 8),
              Text(
                'Intercen Books',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'PlayfairDisplay',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            fontFamily: 'PlayfairDisplay',
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFFAAAAAA),
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
} 