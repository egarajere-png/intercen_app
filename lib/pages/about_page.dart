import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'About',
          style: const TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: AppColors.foreground,
            letterSpacing: 0.2,
          ),
        ),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.foreground,
        elevation: 0.5,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.primary),
      ),
      body: Center(
        child: Text(
          'About Intercen and its mission will appear here.',
          style: const TextStyle(
            fontFamily: 'DM Sans',
            fontSize: 16,
            color: AppColors.charcoal,
          ),
        ),
      ),
    );
  }
}
