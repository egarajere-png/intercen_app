import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PublishWithUsPage extends StatelessWidget {
  const PublishWithUsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Publish With Us',
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
          'Information about publishing with Intercen will appear here.',
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
