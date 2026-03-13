import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PUBLISH WITH US PAGE
//
// Route:  /publish
// Access: public (no auth required — this is a marketing/onboarding page)
//
// Sections (mirrors the web version exactly):
//   1. Hero — headline + two primary CTAs
//   2. Stats strip — 500+ books, 200+ authors, 15+ years, 10M+ readers
//   3. Publishing paths — Traditional / Self-Publishing / Vendor (card grid)
//   4. Submission process — 4-step timeline
//   5. Why Intercen Books — trust signals with feature rows
//   6. Dark CTA — final call-to-action on charcoal bg
//
// Responsive strategy:
//   • < 600 px (phone) → single-column, compact padding
//   • ≥ 600 px (tablet/wide) → two-column grids where appropriate
//
// Design language:
//   • PlayfairDisplay for all display/heading text
//   • DM Sans for body / labels
//   • AppColors.primary (#B11226) for accents
//   • Warm parchment (#F9F5EF) background
//   • Charcoal (#1A1A2E) for the dark CTA band
// ─────────────────────────────────────────────────────────────────────────────

// ── Data models ───────────────────────────────────────────────────────────────

class _PublishOption {
  final IconData icon;
  final String title;
  final String description;
  final List<String> features;
  final String cta;
  final String emailSubject;

  const _PublishOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.features,
    required this.cta,
    required this.emailSubject,
  });
}

class _Step {
  final int step;
  final String title;
  final String description;
  const _Step(this.step, this.title, this.description);
}

class _Stat {
  final String value, label;
  const _Stat(this.value, this.label);
}

class _TrustItem {
  final IconData icon;
  final String title;
  final String body;
  const _TrustItem(this.icon, this.title, this.body);
}

// ── Static data ───────────────────────────────────────────────────────────────

const _options = [
  _PublishOption(
    icon: Icons.menu_book_rounded,
    title: 'Traditional Publishing',
    description:
        'Partner with us for full editorial, design, and distribution support. '
        'We handle everything from manuscript to market.',
    features: [
      'Professional editing & proofreading',
      'Cover design and layout',
      'ISBN registration',
      'Wide distribution network',
      'Marketing support',
    ],
    cta: 'Learn More',
    emailSubject: 'Manuscript Submission',
  ),
  _PublishOption(
    icon: Icons.edit_note_rounded,
    title: 'Self-Publishing Support',
    description:
        'Maintain creative control while leveraging our expertise. '
        'We provide the tools and guidance you need to succeed.',
    features: [
      'Editorial consultation',
      'Design services',
      'Print-on-demand options',
      'Digital publishing',
      'Author retains rights',
    ],
    cta: 'Get Started',
    emailSubject: 'Manuscript Submission',
  ),
  _PublishOption(
    icon: Icons.store_rounded,
    title: 'Vendor Partnership',
    description:
        'Join our marketplace as a vendor. Reach thousands of readers '
        'and expand your book distribution network.',
    features: [
      'Access to our customer base',
      'Integrated payment processing',
      'Inventory management',
      'Sales analytics',
      'Marketing opportunities',
    ],
    cta: 'Become a Vendor',
    emailSubject: 'Vendor Partnership Inquiry',
  ),
];

const _steps = [
  _Step(1, 'Prepare Your Manuscript',
      'Ensure your manuscript is complete and formatted according to our submission guidelines.'),
  _Step(2, 'Submit Your Proposal',
      'Fill out our submission form with your manuscript summary, author bio, and sample chapters.'),
  _Step(3, 'Editorial Review',
      'Our editorial team will review your submission and provide feedback within 4–6 weeks.'),
  _Step(4, 'Contract & Onboarding',
      'If selected, we\'ll discuss terms and begin the publishing journey together.'),
];

const _stats = [
  _Stat('500+', 'Books Published'),
  _Stat('200+', 'Authors Partnered'),
  _Stat('15+', 'Years Experience'),
  _Stat('10M+', 'Readers Reached'),
];

const _trust = [
  _TrustItem(Icons.public_rounded, 'Pan-African Reach',
      'Distribution across Kenya, East Africa, and international markets.'),
  _TrustItem(Icons.emoji_events_rounded, 'Award-Winning Publications',
      'Our authors have received national and international literary recognition.'),
  _TrustItem(Icons.groups_rounded, 'Author-First Approach',
      'Fair contracts, transparent royalties, and ongoing author support.'),
];

// ─────────────────────────────────────────────────────────────────────────────
// PAGE WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class PublishWithUsPage extends StatefulWidget {
  const PublishWithUsPage({super.key});

  @override
  State<PublishWithUsPage> createState() => _PublishWithUsPageState();
}

class _PublishWithUsPageState extends State<PublishWithUsPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _heroCtrl;
  late final Animation<double>   _heroFade;
  late final Animation<Offset>   _heroSlide;

  static const _email = 'info.intercenbooks@gmail.com';

  @override
  void initState() {
    super.initState();
    _heroCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _heroFade = CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut);
    _heroSlide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutCubic));
    _heroCtrl.forward();
  }

  @override
  void dispose() {
    _heroCtrl.dispose();
    super.dispose();
  }

  Future<void> _launchEmail(String subject) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _email,
      query: 'subject=${Uri.encodeComponent(subject)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // Fallback: copy email to clipboard
      await Clipboard.setData(ClipboardData(text: _email));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Email copied to clipboard: $_email',
              style: TextStyle(fontFamily: 'DM Sans')),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final width   = MediaQuery.of(context).size.width;
    final isWide  = width >= 600;
    final hPad    = isWide ? 32.0 : 20.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F5EF),
      body: CustomScrollView(
        slivers: [

          // ── App bar ───────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 20, color: Color(0xFF1A1A2E)),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text('Publish With Us',
                style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontWeight: FontWeight.w800,
                    fontSize: 19,
                    color: Color(0xFF111827))),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(
                  height: 1, color: const Color(0xFFE5E7EB)),
            ),
          ),

          // ── All sections inside one SliverToBoxAdapter ────────────────────
          SliverToBoxAdapter(
            child: Column(children: [

              // ── 1. HERO ───────────────────────────────────────────────────
              _buildHero(hPad),

              // ── 2. STATS STRIP ────────────────────────────────────────────
              _buildStats(hPad),

              // ── 3. PUBLISHING OPTIONS ─────────────────────────────────────
              _buildOptions(hPad, isWide),

              // ── 4. SUBMISSION STEPS ───────────────────────────────────────
              _buildSteps(hPad, isWide),

              // ── 5. WHY INTERCEN ───────────────────────────────────────────
              _buildWhyUs(hPad, isWide),

              // ── 6. DARK CTA ───────────────────────────────────────────────
              _buildDarkCta(hPad, isWide),

              SizedBox(height: MediaQuery.of(context).padding.bottom + 32),
            ]),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // SECTION 1: HERO
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildHero(double hPad) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF9F5EF), Color(0xFFFFF3F0), Color(0xFFF9F5EF)],
        ),
      ),
      child: Stack(children: [
        // Decorative blobs
        Positioned(top: 20, right: -20,
          child: Container(width: 160, height: 160,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.06)))),
        Positioned(bottom: 0, left: -30,
          child: Container(width: 200, height: 200,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFD4A853).withOpacity(0.06)))),

        // Content
        FadeTransition(
          opacity: _heroFade,
          child: SlideTransition(
            position: _heroSlide,
            child: Padding(
              padding: EdgeInsets.fromLTRB(hPad, 40, hPad, 48),
              child: Column(children: [

                // Section label
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('Authors & Publishers',
                      style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                          letterSpacing: 1.0)),
                ),

                const SizedBox(height: 20),

                // Headline
                const Text('Publish Your Story',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                        height: 1.1)),
                const SizedBox(height: 4),
                Text('With Intercen Books',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                        height: 1.1)),

                const SizedBox(height: 18),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Whether you\'re a first-time author or an established publisher, '
                    'we provide the expertise, resources, and reach to bring your books '
                    'to readers across Africa and beyond.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 15,
                        color: Color(0xFF6B7280),
                        height: 1.65),
                  ),
                ),

                const SizedBox(height: 32),

                // CTAs
                _PrimaryButton(
                  icon: Icons.description_outlined,
                  label: 'Submit Your Manuscript',
                  onTap: () => _launchEmail('Manuscript Submission'),
                ),
                const SizedBox(height: 12),
                _OutlineButton(
                  icon: Icons.groups_outlined,
                  label: 'Become a Vendor',
                  onTap: () => _launchEmail('Vendor Partnership Inquiry'),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // SECTION 2: STATS STRIP
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildStats(double hPad) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border.symmetric(
            horizontal: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      padding: EdgeInsets.symmetric(vertical: 28, horizontal: hPad),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: _stats.map((s) => _StatCell(s)).toList(),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // SECTION 3: PUBLISHING OPTIONS
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildOptions(double hPad, bool isWide) {
    return Container(
      color: const Color(0xFFF9F5EF),
      padding: EdgeInsets.fromLTRB(hPad, 48, hPad, 48),
      child: Column(children: [
        _SectionLabel('Publishing Options'),
        const SizedBox(height: 10),
        const Text('Choose Your Publishing Path',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827))),
        const SizedBox(height: 10),
        const Text(
          'We offer flexible publishing solutions tailored to your needs.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 14,
              color: Color(0xFF6B7280),
              height: 1.55),
        ),
        const SizedBox(height: 32),

        // Grid
        isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _options
                    .map((o) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: _OptionCard(
                                option: o,
                                onTap: () => _launchEmail(o.emailSubject)),
                          ),
                        ))
                    .toList(),
              )
            : Column(
                children: _options
                    .map((o) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _OptionCard(
                              option: o,
                              onTap: () => _launchEmail(o.emailSubject)),
                        ))
                    .toList(),
              ),
      ]),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // SECTION 4: SUBMISSION STEPS
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildSteps(double hPad, bool isWide) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(hPad, 48, hPad, 48),
      child: Column(children: [
        _SectionLabel('How It Works'),
        const SizedBox(height: 10),
        const Text('Manuscript Submission Process',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827))),
        const SizedBox(height: 10),
        const Text(
          'Our streamlined submission process ensures your manuscript receives '
          'the attention it deserves from our experienced editorial team.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 14,
              color: Color(0xFF6B7280),
              height: 1.55),
        ),
        const SizedBox(height: 32),

        isWide
            ? GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.8,
                children: _steps.map((s) => _StepCard(s)).toList(),
              )
            : Column(
                children: _steps
                    .map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _StepCard(s),
                        ))
                    .toList(),
              ),
      ]),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // SECTION 5: WHY INTERCEN
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildWhyUs(double hPad, bool isWide) {
    return Container(
      color: const Color(0xFFF9F5EF),
      padding: EdgeInsets.fromLTRB(hPad, 48, hPad, 48),
      child: isWide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _whyUsContent()),
              const SizedBox(width: 40),
              Expanded(child: _whyUsImage()),
            ])
          : Column(children: [
              _whyUsContent(),
              const SizedBox(height: 32),
              _whyUsImage(),
            ]),
    );
  }

  Widget _whyUsContent() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('Why Intercen Books', centered: false),
          const SizedBox(height: 10),
          const Text('A Publisher You Can Trust',
              style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827))),
          const SizedBox(height: 14),
          const Text(
            'With over 15 years of experience in African publishing, we\'ve built '
            'a reputation for quality, integrity, and author-centric partnerships. '
            'Our commitment goes beyond publishing — we nurture literary talent and '
            'champion diverse voices.',
            style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 14,
                color: Color(0xFF6B7280),
                height: 1.65),
          ),
          const SizedBox(height: 28),
          ..._trust.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: _TrustRow(item: t),
              )),
        ],
      );

  Widget _whyUsImage() => Column(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.network(
            'https://images.unsplash.com/photo-1481627834876-b7833e8f5570?w=800&h=600&fit=crop',
            height: 220,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              height: 220,
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(20)),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Icon(Icons.library_books_rounded,
                    size: 56, color: AppColors.primary.withOpacity(0.3)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Testimonial card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ]),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: List.generate(
                5,
                (_) => const Icon(Icons.star_rounded,
                    size: 14, color: Color(0xFFF59E0B)))),
            const SizedBox(height: 10),
            const Text(
              '"Intercen Books believed in my story when others didn\'t."',
              style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                  height: 1.4),
            ),
            const SizedBox(height: 8),
            Row(children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: Text('S',
                    style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
              ),
              const SizedBox(width: 8),
              const Text('Sarah Muthoni, Author',
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 12,
                      color: Color(0xFF9CA3AF))),
            ]),
          ]),
        ),
      ]);

  // ───────────────────────────────────────────────────────────────────────────
  // SECTION 6: DARK CTA BAND
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildDarkCta(double hPad, bool isWide) {
    return Container(
      color: const Color(0xFF1A1A2E),
      padding: EdgeInsets.fromLTRB(hPad, 56, hPad, 56),
      child: Column(children: [
        const Text('Ready to Get Published?',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
        const SizedBox(height: 14),
        const Text(
          'Take the first step towards sharing your story with the world. '
          'Submit your manuscript today or reach out to discuss partnership opportunities.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 14,
              color: Color(0xFFD1D5DB),
              height: 1.65),
        ),
        const SizedBox(height: 32),

        // Gold CTA
        SizedBox(
          width: isWide ? 320 : double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: () => _launchEmail('Manuscript Submission'),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Submit Manuscript',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4A853),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
          ),
        ),
        const SizedBox(height: 12),

        // Outline ghost button
        SizedBox(
          width: isWide ? 320 : double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: () => _launchEmail('General Inquiry'),
            icon: const Icon(Icons.mail_outline_rounded, size: 18),
            label: const Text('Contact Us',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0x4DFFFFFF)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
          ),
        ),

        const SizedBox(height: 28),

        // Contact detail
        GestureDetector(
          onTap: () => _launchEmail('General Inquiry'),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
            Icon(Icons.email_outlined, size: 15, color: Color(0xFF9CA3AF)),
            SizedBox(width: 6),
            Text('info.intercenbooks@gmail.com',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 13,
                    color: Color(0xFF9CA3AF),
                    decoration: TextDecoration.underline,
                    decorationColor: Color(0xFF9CA3AF))),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION LABEL
// ─────────────────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  final bool centered;
  const _SectionLabel(this.text, {this.centered = true});
  @override
  Widget build(BuildContext context) => Container(
        alignment: centered ? Alignment.center : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20)),
          child: Text(text,
              style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  letterSpacing: 0.9)),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// STAT CELL
// ─────────────────────────────────────────────────────────────────────────────
class _StatCell extends StatelessWidget {
  final _Stat stat;
  const _StatCell(this.stat);
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(stat.value,
              style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary)),
          const SizedBox(height: 3),
          Text(stat.label,
              style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 11,
                  color: Color(0xFF9CA3AF))),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// OPTION CARD — one publishing path
// ─────────────────────────────────────────────────────────────────────────────
class _OptionCard extends StatefulWidget {
  final _PublishOption option;
  final VoidCallback onTap;
  const _OptionCard({required this.option, required this.onTap});
  @override
  State<_OptionCard> createState() => _OptionCardState();
}

class _OptionCardState extends State<_OptionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: Colors.black
                      .withOpacity(_hovered ? 0.10 : 0.05),
                  blurRadius: _hovered ? 20 : 10,
                  offset: const Offset(0, 4)),
            ]),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Gold accent top bar
            Container(
              height: 4,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [Color(0xFFD4A853), Color(0xFFB8922A)]),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(14)),
                    child: Icon(widget.option.icon,
                        size: 26, color: AppColors.primary),
                    transform: _hovered
                        ? (Matrix4.identity()..scale(1.08))
                        : Matrix4.identity(),
                  ),
                  const SizedBox(height: 14),

                  // Title
                  Text(widget.option.title,
                      style: const TextStyle(
                          fontFamily: 'PlayfairDisplay',
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827))),
                  const SizedBox(height: 6),

                  // Description
                  Text(widget.option.description,
                      style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                          height: 1.55)),
                  const SizedBox(height: 16),

                  // Features list
                  ...widget.option.features.map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Icon(Icons.check_circle_rounded,
                              size: 16, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(f,
                                style: const TextStyle(
                                    fontFamily: 'DM Sans',
                                    fontSize: 12,
                                    color: Color(0xFF6B7280))),
                          ),
                        ]),
                      )),
                  const SizedBox(height: 16),

                  // CTA
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      child: ElevatedButton(
                        onPressed: widget.onTap,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _hovered
                                ? AppColors.primary
                                : Colors.white,
                            foregroundColor: _hovered
                                ? Colors.white
                                : AppColors.primary,
                            elevation: 0,
                            side: BorderSide(
                                color: AppColors.primary
                                    .withOpacity(0.4)),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(10))),
                        child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                          Text(widget.option.cta,
                              style: const TextStyle(
                                  fontFamily: 'DM Sans',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward_rounded,
                              size: 15),
                        ]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP CARD
// ─────────────────────────────────────────────────────────────────────────────
class _StepCard extends StatelessWidget {
  final _Step step;
  const _StepCard(this.step);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: const Color(0xFFF9F5EF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Step number circle
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle),
            child: Center(
              child: Text('${step.step}',
                  style: const TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(step.title,
                  style: const TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827))),
              const SizedBox(height: 4),
              Text(step.description,
                  style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                      height: 1.55)),
            ]),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// TRUST ROW
// ─────────────────────────────────────────────────────────────────────────────
class _TrustRow extends StatelessWidget {
  final _TrustItem item;
  const _TrustRow({required this.item});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.07),
                borderRadius: BorderRadius.circular(11)),
            child: Icon(item.icon, size: 21, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(item.title,
                  style: const TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827))),
              const SizedBox(height: 3),
              Text(item.body,
                  style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                      height: 1.55)),
            ]),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// BUTTON HELPERS
// ─────────────────────────────────────────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label,
              style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14))),
        ),
      );
}

class _OutlineButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _OutlineButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label,
              style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14))),
        ),
      );
}