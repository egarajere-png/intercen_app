
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  // Data from About.tsx
  static const stats = [
    {'value': '15+', 'label': 'Years of Excellence'},
    {'value': '500+', 'label': 'Books Published'},
    {'value': '200+', 'label': 'Authors Partnered'},
    {'value': '10M+', 'label': 'Readers Reached'},
  ];

  static const values = [
    {
      'icon': Icons.lightbulb_outline,
      'title': 'Innovation',
      'description': 'Embracing new ideas and technologies to revolutionize African publishing.',
    },
    {
      'icon': Icons.favorite_outline,
      'title': 'Passion',
      'description': 'A deep love for literature drives everything we do.',
    },
    {
      'icon': Icons.handshake,
      'title': 'Integrity',
      'description': 'Honest, transparent relationships with authors, vendors, and readers.',
    },
    {
      'icon': Icons.public,
      'title': 'Impact',
      'description': 'Creating meaningful change through the power of stories.',
    },
  ];

  static const team = [
    {
      'name': 'Barack Wandera',
      'role': 'Founder & CEO',
      'image': 'assets/team/barak.jpeg',
    },
    {
      'name': 'Miriam Achiso',
      'role': 'Operations Manager',
      'image': null,
    },
    {
      'name': 'Chelangat Naomi',
      'role': 'Editorial Director',
      'image': 'assets/team/chelangatnaomi.jpeg',
    },
    {
      'name': 'Robert Mutugi',
      'role': 'Design Operations Lead',
      'image': null,
    },
    {
      'name': 'Betty Atiemo',
      'role': 'Marketing Lead',
      'image': 'assets/team/bettyatiemo.jpeg',
    },
    {
      'name': 'Jere Egara',
      'role': 'Digital Publishing Systems Manager',
      'image': 'assets/team/bahati.jpeg',
    },
  ];

  static const translationDocuments = [
    "Books and manuscripts",
    "Educational and academic materials",
    "Contracts and legal documents",
    "Brochures and press releases",
    "Reference materials",
    "PowerPoint presentations",
    "Internal corporate communications",
    "User manuals and newsletters"
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'About',
          style: textTheme.titleLarge?.copyWith(
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
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hero Section
            Container(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary.withOpacity(0.15), AppColors.secondary.withOpacity(0.10)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Our Story',
                    style: textTheme.titleMedium?.copyWith(
                      color: AppColors.primary,
                      fontFamily: 'DM Sans',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Championing African Literary Excellence',
                    textAlign: TextAlign.center,
                    style: textTheme.headlineMedium?.copyWith(
                      color: AppColors.primary,
                      fontFamily: 'PlayfairDisplay',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "InterCEN Books is more than a publishing house—we're a movement dedicated to amplifying African voices and bringing world-class literature to readers everywhere.",
                    textAlign: TextAlign.center,
                    style: textTheme.bodyLarge?.copyWith(
                      color: AppColors.charcoal,
                      fontFamily: 'DM Sans',
                    ),
                  ),
                ],
              ),
            ),

            // Stats Section
            Container(
              color: AppColors.background.withOpacity(0.03),
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: stats.map((stat) => Column(
                  children: [
                    Text(
                      stat['value']!,
                      style: textTheme.headlineSmall?.copyWith(
                        color: AppColors.primary,
                        fontFamily: 'PlayfairDisplay',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      stat['label']!,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.charcoal,
                        fontFamily: 'DM Sans',
                      ),
                    ),
                  ],
                )).toList(),
              ),
            ),

            // Mission & Vision
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        'https://images.unsplash.com/photo-1481627834876-b7833e8f5570?w=800&h=600&fit=crop',
                        height: 180,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.flag, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Text('Mission', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'To discover, nurture, and publish exceptional literary works that reflect the richness of African culture and experience, while making quality books accessible to readers across the continent and beyond.',
                          style: textTheme.bodyMedium?.copyWith(color: AppColors.charcoal),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Icon(Icons.visibility, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Text('Vision', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'To be the leading publisher of African literature, recognized for quality, innovation, and impact.',
                          style: textTheme.bodyMedium?.copyWith(color: AppColors.charcoal),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Publishing Philosophy
            Container(
              color: AppColors.background.withOpacity(0.03),
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              child: Column(
                children: [
                  Text('Philosophy', style: textTheme.titleMedium?.copyWith(color: AppColors.primary)),
                  const SizedBox(height: 8),
                  Text('Our Publishing Philosophy', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    'We believe that great books have the power to transform minds, bridge cultures, and inspire change. Our publishing approach is guided by these core principles.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(color: AppColors.charcoal),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _philosophyCard(
                        context,
                        icon: Icons.book,
                        title: 'Quality',
                        description: 'We uphold the highest standards in editing, design, and production.'
                      ),
                      _philosophyCard(
                        context,
                        icon: Icons.people,
                        title: 'Collaboration',
                        description: 'We work closely with authors and partners to achieve shared goals.'
                      ),
                      _philosophyCard(
                        context,
                        icon: Icons.public,
                        title: 'Global Reach',
                        description: 'We connect African stories to readers worldwide.'
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Values
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              child: Column(
                children: [
                  Text('What Drives Us', style: textTheme.titleMedium?.copyWith(color: AppColors.primary)),
                  const SizedBox(height: 8),
                  Text('Our Core Values', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: values.map((value) => _valueCard(context, value)).toList(),
                  ),
                ],
              ),
            ),

            // Translation Services
            Container(
              color: AppColors.background.withOpacity(0.03),
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              child: Column(
                children: [
                  Text('Global Reach', style: textTheme.titleMedium?.copyWith(color: AppColors.primary)),
                  const SizedBox(height: 8),
                  Text('Translation Services', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    'At InterCEN Books, we collaborate with a global network of highly skilled native-language translators, carefully selected based on their subject-matter expertise.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(color: AppColors.charcoal),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _translationCard(
                              context,
                              title: 'Expert Translators',
                              description: 'Our translators are native speakers with deep subject-matter expertise.'
                            ),
                            const SizedBox(height: 16),
                            _translationCard(
                              context,
                              title: 'Quality Assurance',
                              description: 'Every translation undergoes rigorous review for accuracy and clarity.'
                            ),
                            const SizedBox(height: 16),
                            _translationCard(
                              context,
                              title: 'Confidentiality',
                              description: 'We ensure strict confidentiality and data security for all documents.'
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.description, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Text('Document Types', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text('We translate a wide range of documents in any format, including:', style: textTheme.bodyMedium?.copyWith(color: AppColors.charcoal)),
                            const SizedBox(height: 8),
                            ...translationDocuments.map((doc) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text('• $doc', style: textTheme.bodyMedium?.copyWith(color: AppColors.charcoal)),
                            )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Team Section
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              child: Column(
                children: [
                  Text('Leadership', style: textTheme.titleMedium?.copyWith(color: AppColors.primary)),
                  const SizedBox(height: 8),
                  Text('Meet Our Team', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    'Our experienced team combines publishing expertise with a passion for African literature.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(color: AppColors.charcoal),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: team.map((member) => _teamCard(context, member)).toList(),
                  ),
                ],
              ),
            ),

            // CTA Section
            Container(
              color: AppColors.charcoal,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              child: Column(
                children: [
                  Text('Ready to Work With Us?', style: textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    "Whether you're an author looking to publish, a vendor seeking partnership, or a reader exploring great books—we'd love to hear from you.",
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {},
                        child: Text('Publish with Us', style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.secondary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {},
                        child: Text('Explore Books', style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _philosophyCard(BuildContext context, {required IconData icon, required String title, required String description}) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 32),
            const SizedBox(height: 8),
            Text(title, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(description, textAlign: TextAlign.center, style: textTheme.bodyMedium?.copyWith(color: AppColors.charcoal)),
          ],
        ),
      ),
    );
  }

  static Widget _valueCard(BuildContext context, Map<String, dynamic> value) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(value['icon'], color: AppColors.primary, size: 32),
            const SizedBox(height: 8),
            Text(value['title'], style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(value['description'], textAlign: TextAlign.center, style: textTheme.bodyMedium?.copyWith(color: AppColors.charcoal)),
          ],
        ),
      ),
    );
  }

  static Widget _translationCard(BuildContext context, {required String title, required String description}) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(description, style: textTheme.bodyMedium?.copyWith(color: AppColors.charcoal)),
          ],
        ),
      ),
    );
  }

  static Widget _teamCard(BuildContext context, Map<String, dynamic> member) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundImage: AssetImage(member['image']),
              backgroundColor: AppColors.background,
            ),
            const SizedBox(height: 8),
            Text(member['name'], style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(member['role'], style: textTheme.bodySmall?.copyWith(color: AppColors.charcoal)),
          ],
        ),
      ),
    );
  }
}
