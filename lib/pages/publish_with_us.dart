import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PUBLISH WITH US PAGE  (includes inline Manuscript Submission form)
//
// Route:  /publish
// Access: public
//
// Sections:
//   LANDING:
//     1. Hero — headline + two primary CTAs
//     2. Stats strip — 500+ books, 200+ authors, 15+ years, 10M+ readers
//     3. Publishing paths — Traditional / Self-Publishing / Vendor (card grid)
//     4. Submission process — 4-step timeline
//     5. Why Intercen Books — trust signals with feature rows
//     6. Dark CTA — final call-to-action on charcoal bg
//
//   FORM (shown when user taps a publishing-path CTA):
//     Author info, Book info, Manuscript details, File uploads, Agreements
//
//   SUCCESS (shown after form submission):
//     Confirmation screen with navigation options
//
// Navigation strategy:
//   _PageView enum drives which "page" is visible inside a single Scaffold.
//   No Navigator.push — we swap widgets to keep one clean scroll root.
//
// Responsive strategy:
//   < 600 px (phone)  → single-column, compact padding
//   ≥ 600 px (tablet) → two-column grids where appropriate
//
// Design language:
//   • PlayfairDisplay for all display / heading text
//   • DM Sans for body / labels
//   • AppColors.primary (#B11226) for accents
//   • Warm parchment (#F9F5EF) background
//   • Charcoal (#1A1A2E) for the dark CTA band
// ─────────────────────────────────────────────────────────────────────────────

// ── Enums & data models ───────────────────────────────────────────────────────

enum _PageView { landing, form, success }

enum PublishingType { traditional, self }

class _PublishOption {
  final IconData icon;
  final String title;
  final String description;
  final List<String> features;
  final String cta;

  /// null = vendor (email flow, no form)
  final PublishingType? publishingType;

  const _PublishOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.features,
    required this.cta,
    this.publishingType,
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
    cta: 'Submit Manuscript',
    publishingType: PublishingType.traditional,
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
    publishingType: PublishingType.self,
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
    publishingType: null, // → email
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

const _email = 'info.intercenbooks@gmail.com';

// ─────────────────────────────────────────────────────────────────────────────
// ROOT PAGE WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class PublishWithUsPage extends StatefulWidget {
  const PublishWithUsPage({super.key});

  @override
  State<PublishWithUsPage> createState() => _PublishWithUsPageState();
}

class _PublishWithUsPageState extends State<PublishWithUsPage>
    with SingleTickerProviderStateMixin {
  // ── page state ─────────────────────────────────────────────────────────────
  _PageView _currentPage = _PageView.landing;
  PublishingType _selectedType = PublishingType.traditional;

  // ── hero animation ─────────────────────────────────────────────────────────
  late final AnimationController _heroCtrl;
  late final Animation<double> _heroFade;
  late final Animation<Offset> _heroSlide;

  // ── scroll controllers (one per page so position is preserved) ─────────────
  final _landingScroll = ScrollController();
  final _formScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _heroCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _heroFade =
        CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut);
    _heroSlide =
        Tween<Offset>(begin: const Offset(0, 0.10), end: Offset.zero).animate(
            CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutCubic));
    _heroCtrl.forward();
  }

  @override
  void dispose() {
    _heroCtrl.dispose();
    _landingScroll.dispose();
    _formScroll.dispose();
    super.dispose();
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  void _navigateTo(_PageView page, {PublishingType? type}) {
    if (type != null) _selectedType = type;
    setState(() => _currentPage = page);
    // scroll both controllers back to top
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_formScroll.hasClients) _formScroll.jumpTo(0);
      if (_landingScroll.hasClients) _landingScroll.jumpTo(0);
    });
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
      await Clipboard.setData(ClipboardData(text: _email));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Email copied to clipboard: $_email',
              style: const TextStyle(fontFamily: 'DM Sans')),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    }
  }

  void _onOptionTap(_PublishOption option) {
    if (option.publishingType != null) {
      _navigateTo(_PageView.form, type: option.publishingType);
    } else {
      _launchEmail('Vendor Partnership Inquiry');
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F5EF),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: switch (_currentPage) {
          _PageView.landing => _LandingView(
              key: const ValueKey('landing'),
              heroFade: _heroFade,
              heroSlide: _heroSlide,
              scrollController: _landingScroll,
              onOptionTap: _onOptionTap,
              onSubmitTap: () =>
                  _navigateTo(_PageView.form, type: PublishingType.traditional),
              onVendorTap: () => _launchEmail('Vendor Partnership Inquiry'),
              onContactTap: () => _launchEmail('General Inquiry'),
              onBack: () => Navigator.pop(context),
            ),
          _PageView.form => _FormView(
              key: const ValueKey('form'),
              scrollController: _formScroll,
              selectedType: _selectedType,
              onBack: () => _navigateTo(_PageView.landing),
              onSuccess: () => _navigateTo(_PageView.success),
            ),
          _PageView.success => _SuccessView(
              key: const ValueKey('success'),
              onHome: () => _navigateTo(_PageView.landing),
              onAnother: () =>
                  _navigateTo(_PageView.form, type: PublishingType.traditional),
            ),
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LANDING VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _LandingView extends StatelessWidget {
  final Animation<double> heroFade;
  final Animation<Offset> heroSlide;
  final ScrollController scrollController;
  final void Function(_PublishOption) onOptionTap;
  final VoidCallback onSubmitTap;
  final VoidCallback onVendorTap;
  final VoidCallback onContactTap;
  final VoidCallback onBack;

  const _LandingView({
    super.key,
    required this.heroFade,
    required this.heroSlide,
    required this.scrollController,
    required this.onOptionTap,
    required this.onSubmitTap,
    required this.onVendorTap,
    required this.onContactTap,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 600;
    final hPad = isWide ? 32.0 : 20.0;

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        // App bar
        SliverAppBar(
          pinned: true,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 20, color: Color(0xFF1A1A2E)),
            onPressed: onBack,
          ),
          title: const Text('Publish With Us',
              style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                  color: Color(0xFF111827))),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: const Color(0xFFE5E7EB)),
          ),
        ),

        SliverToBoxAdapter(
          child: Column(children: [
            _buildHero(hPad),
            _buildStats(hPad),
            _buildOptions(hPad, isWide),
            _buildSteps(hPad, isWide),
            _buildWhyUs(hPad, isWide),
            _buildDarkCta(hPad, isWide),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 32),
          ]),
        ),
      ],
    );
  }

  // ── Section 1: Hero ─────────────────────────────────────────────────────────

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
        Positioned(
          top: 20,
          right: -20,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.06)),
          ),
        ),
        Positioned(
          bottom: 0,
          left: -30,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFD4A853).withOpacity(0.06)),
          ),
        ),

        // Animated content
        FadeTransition(
          opacity: heroFade,
          child: SlideTransition(
            position: heroSlide,
            child: Padding(
              padding: EdgeInsets.fromLTRB(hPad, 40, hPad, 48),
              child: Column(children: [

                // Eyebrow pill
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
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

                _PrimaryButton(
                  icon: Icons.description_outlined,
                  label: 'Submit Your Manuscript',
                  onTap: onSubmitTap,
                ),
                const SizedBox(height: 12),
                _OutlineButton(
                  icon: Icons.groups_outlined,
                  label: 'Become a Vendor',
                  onTap: onVendorTap,
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Section 2: Stats ────────────────────────────────────────────────────────

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

  // ── Section 3: Publishing options ──────────────────────────────────────────

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
        isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _options
                    .map((o) => Expanded(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6),
                            child: _OptionCard(
                                option: o,
                                onTap: () => onOptionTap(o)),
                          ),
                        ))
                    .toList(),
              )
            : Column(
                children: _options
                    .map((o) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _OptionCard(
                              option: o, onTap: () => onOptionTap(o)),
                        ))
                    .toList(),
              ),
      ]),
    );
  }

  // ── Section 4: Submission steps ────────────────────────────────────────────

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

  // ── Section 5: Why Intercen ────────────────────────────────────────────────

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
                        size: 56,
                        color: AppColors.primary.withOpacity(0.3)),
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
                Row(
                    children: List.generate(
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

  // ── Section 6: Dark CTA band ───────────────────────────────────────────────

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
        SizedBox(
          width: isWide ? 320 : double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: onSubmitTap,
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
        SizedBox(
          width: isWide ? 320 : double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: onContactTap,
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
        GestureDetector(
          onTap: onContactTap,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.email_outlined, size: 15, color: Color(0xFF9CA3AF)),
              SizedBox(width: 6),
              Text(
                _email,
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 13,
                    color: Color(0xFF9CA3AF),
                    decoration: TextDecoration.underline,
                    decorationColor: Color(0xFF9CA3AF)),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FORM VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _FormView extends StatefulWidget {
  final ScrollController scrollController;
  final PublishingType selectedType;
  final VoidCallback onBack;
  final VoidCallback onSuccess;

  const _FormView({
    super.key,
    required this.scrollController,
    required this.selectedType,
    required this.onBack,
    required this.onSuccess,
  });

  @override
  State<_FormView> createState() => _FormViewState();
}

class _FormViewState extends State<_FormView> {
  final _formKey = GlobalKey<FormState>();

  // controllers
  final _authorName = TextEditingController();
  final _authorEmail = TextEditingController();
  final _authorPhone = TextEditingController();
  final _authorBio = TextEditingController();
  final _title = TextEditingController();
  final _subtitle = TextEditingController();
  final _language = TextEditingController(text: 'English');
  final _pages = TextEditingController();
  final _isbn = TextEditingController();
  final _description = TextEditingController();
  final _targetAudience = TextEditingController();
  final _keywords = TextEditingController();

  String? _categoryId;
  late String _publishingType;
  bool _rightsConfirmed = false;
  bool _termsAgreed = false;

  // file state — real PlatformFile objects for Supabase upload
  PlatformFile? _manuscriptFile;
  PlatformFile? _coverFile;

  bool _isSubmitting = false;

 // fetched from Supabase — id + name pairs
  List<Map<String, String>> _categories = [];

 @override
  void initState() {
    super.initState();
    _publishingType =
        widget.selectedType == PublishingType.self ? 'self' : 'traditional';
    _fetchCategories();
  }

  Future<void> _fetchCategories() async {
    final res = await Supabase.instance.client
        .from('categories')
        .select('id, name')
        .order('name');
    if (mounted) {
      setState(() {
        _categories = (res as List)
            .map((c) => {'id': c['id'] as String, 'name': c['name'] as String})
            .toList();
      });
    }
  }

  @override
  void dispose() {
    for (final c in [
      _authorName, _authorEmail, _authorPhone, _authorBio,
      _title, _subtitle, _language, _pages, _isbn,
      _description, _targetAudience, _keywords,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── submit ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    // Trigger form validation
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_manuscriptFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select your manuscript file (PDF or DOCX).',
            style: TextStyle(fontFamily: 'DM Sans')),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    if (!_rightsConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please confirm you hold all publishing rights.',
            style: TextStyle(fontFamily: 'DM Sans')),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    if (!_termsAgreed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please agree to the Terms and Conditions.',
            style: TextStyle(fontFamily: 'DM Sans')),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;

      if (userId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Please sign in to submit your manuscript.',
                style: TextStyle(fontFamily: 'DM Sans')),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ));
        }
        return;
      }

      // Upload files
      String? manuscriptUrl;
      String? coverUrl;

      if (_manuscriptFile != null) {
        manuscriptUrl = await _uploadFile(_manuscriptFile!, 'manuscripts', userId);
      }
      if (_coverFile != null) {
        coverUrl = await _uploadFile(_coverFile!, 'book-covers', userId);
      }

      final keywords = _keywords.text
          .split(',')
          .map((k) => k.trim())
          .where((k) => k.isNotEmpty)
          .toList();

      // Insert publication
      final insertedPub = await client
          .from('publications')
          .insert({
            'title':               _title.text.trim(),
            'subtitle':            _subtitle.text.trim().isEmpty ? null : _subtitle.text.trim(),
            'author_name':         _authorName.text.trim(),
            'author_email':        _authorEmail.text.trim(),
            'author_phone':        _authorPhone.text.trim().isEmpty ? null : _authorPhone.text.trim(),
            'author_bio':          _authorBio.text.trim(),
            'category_id':         _categoryId,
            'description':         _description.text.trim(),
            'language':            _language.text.trim(),
            'pages':               int.tryParse(_pages.text),
            'isbn':                _isbn.text.trim().isEmpty ? null : _isbn.text.trim(),
            'manuscript_file_url': manuscriptUrl,
            'cover_image_url':     coverUrl,
            'publishing_type':     _publishingType,
            'keywords':            keywords,
            'target_audience':     _targetAudience.text.trim(),
            'rights_confirmed':    _rightsConfirmed,
            'status':              'pending',
            'submitted_by':        userId,
          })
          .select('id')
          .single();

      final publicationId = insertedPub['id'] as String;

      // Insert in-app notification for the author
      await client.from('notifications').insert({
        'user_id': userId,
        'type':    'submission_received',
        'title':   'Manuscript Submitted',
        'message': 'Your manuscript "${_title.text.trim()}" has been received. '
                   "We'll review it within 4–6 weeks.",
      });

      // Trigger confirmation email — non-fatal if it fails
      try {
        await client.functions.invoke(
          'send-manuscript-confirmation',
          body: {'publication_id': publicationId},
        );
      } catch (emailErr) {
        debugPrint('Email function failed (non-fatal): $emailErr');
      }

      if (mounted) widget.onSuccess();

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Submission failed: ${e.toString()}',
              style: const TextStyle(fontFamily: 'DM Sans')),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── file picker simulation ─────────────────────────────────────────────────
  // Replace this with file_picker package in production:
  //   final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf','doc','docx']);
  //   if (result != null) setState(() => _manuscriptFileName = result.files.single.name);

  // ── file upload helper ────────────────────────────────────────────────────
  Future<String> _uploadFile(PlatformFile file, String bucket, String uid) async {
    final client = Supabase.instance.client;
    final ext    = file.extension ?? 'bin';
    final path   = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await client.storage.from(bucket).uploadBinary(path, file.bytes!);
    return client.storage.from(bucket).getPublicUrl(path);
  }

  // ── file pickers ──────────────────────────────────────────────────────────
  Future<void> _pickManuscript() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx'],
      withData: true,
    );
    if (result != null) setState(() => _manuscriptFile = result.files.single);
  }

  Future<void> _pickCover() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result != null) setState(() => _coverFile = result.files.single);
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 600;
    final hPad = isWide ? 40.0 : 20.0;
    final typeLabel = _publishingType == 'self'
        ? 'Self-Publishing Support'
        : 'Traditional Publishing';

    return CustomScrollView(
      controller: widget.scrollController,
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 20, color: Color(0xFF1A1A2E)),
            onPressed: widget.onBack,
          ),
          title: const Text('Submit Manuscript',
              style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                  color: Color(0xFF111827))),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: const Color(0xFFE5E7EB)),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 60),
            child: Column(children: [

              // Form hero
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(typeLabel,
                    style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        letterSpacing: 1.0)),
              ),
              const SizedBox(height: 14),
              const Text('Submit Your Manuscript',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827))),
              const SizedBox(height: 8),
              const Text(
                'Fill in the details below and our team will be in touch within 4–6 weeks.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                    height: 1.55),
              ),

              const SizedBox(height: 28),

              // ── FIX 1: removed `const` — isWide is a runtime variable ──
              Container(
                padding: EdgeInsets.all(isWide ? 32 : 20),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 16,
                          offset: const Offset(0, 4))
                    ]),
                child: Form(
                  key: _formKey,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // ── Author Information ──────────────────────────────
                        // ── FIX 2: _FormField → _LabeledField throughout ───
                        _FormSection(label: 'Author Information', children: [
                          isWide
                              ? Row(children: [
                                  Expanded(
                                    child: _LabeledField(
                                      label: 'Full Name',
                                      required: true,
                                      child: TextFormField(
                                        controller: _authorName,
                                        decoration: _inputDecor('Jane Muthoni'),
                                        validator: (v) =>
                                            (v?.trim().length ?? 0) < 2
                                                ? 'Full name required'
                                                : null,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _LabeledField(
                                      label: 'Email',
                                      required: true,
                                      child: TextFormField(
                                        controller: _authorEmail,
                                        keyboardType:
                                            TextInputType.emailAddress,
                                        decoration:
                                            _inputDecor('jane@example.com'),
                                        validator: (v) {
                                          final re = RegExp(
                                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                                          return re.hasMatch(v?.trim() ?? '')
                                              ? null
                                              : 'Valid email required';
                                        },
                                      ),
                                    ),
                                  ),
                                ])
                              : Column(children: [
                                  _LabeledField(
                                    label: 'Full Name',
                                    required: true,
                                    child: TextFormField(
                                      controller: _authorName,
                                      decoration: _inputDecor('Jane Muthoni'),
                                      validator: (v) =>
                                          (v?.trim().length ?? 0) < 2
                                              ? 'Full name required'
                                              : null,
                                    ),
                                  ),
                                  _LabeledField(
                                    label: 'Email',
                                    required: true,
                                    child: TextFormField(
                                      controller: _authorEmail,
                                      keyboardType: TextInputType.emailAddress,
                                      decoration:
                                          _inputDecor('jane@example.com'),
                                      validator: (v) {
                                        final re = RegExp(
                                            r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                                        return re.hasMatch(v?.trim() ?? '')
                                            ? null
                                            : 'Valid email required';
                                      },
                                    ),
                                  ),
                                ]),
                          _LabeledField(
                            label: 'Phone',
                            child: TextFormField(
                              controller: _authorPhone,
                              keyboardType: TextInputType.phone,
                              decoration:
                                  _inputDecor('+254 700 000 000'),
                            ),
                          ),
                          _LabeledField(
                            label: 'Author Biography',
                            required: true,
                            child: TextFormField(
                              controller: _authorBio,
                              maxLines: 4,
                              decoration: _inputDecor(
                                  'Tell us about yourself and your writing background…'),
                              validator: (v) =>
                                  (v?.trim().length ?? 0) < 30
                                      ? 'At least 30 characters required'
                                      : null,
                            ),
                          ),
                        ]),

                        // ── Book Information ────────────────────────────────
                        _FormSection(label: 'Book Information', children: [
                          _LabeledField(
                            label: 'Book Title',
                            required: true,
                            child: TextFormField(
                              controller: _title,
                              decoration: _inputDecor('The Silent River'),
                              validator: (v) => v?.trim().isEmpty ?? true
                                  ? 'Book title required'
                                  : null,
                            ),
                          ),
                          _LabeledField(
                            label: 'Subtitle (optional)',
                            child: TextFormField(
                              controller: _subtitle,
                              decoration: _inputDecor(
                                  'A Story of Hope and Resilience'),
                            ),
                          ),
                          isWide
                              ? Row(children: [
                                  Expanded(
                                    child: _LabeledField(
                                      label: 'Category',
                                      required: true,
                                      child: DropdownButtonFormField<String>(
                                        value: _categoryId,
                                        decoration:
                                            _inputDecor('Select category'),
                                        items: _categories
                                            .map((c) => DropdownMenuItem(
                                                value: c['id'], child: Text(c['name']!)))
                                            .toList(),
                                        onChanged: (v) =>
                                            setState(() => _categoryId = v),
                                        validator: (v) => v == null
                                            ? 'Please select a category'
                                            : null,
                                        style: const TextStyle(
                                            fontFamily: 'DM Sans',
                                            fontSize: 14,
                                            color: Color(0xFF111827)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _LabeledField(
                                      label: 'Language',
                                      required: true,
                                      child: TextFormField(
                                        controller: _language,
                                        decoration: _inputDecor('English'),
                                        validator: (v) =>
                                            v?.trim().isEmpty ?? true
                                                ? 'Language required'
                                                : null,
                                      ),
                                    ),
                                  ),
                                ])
                              : Column(children: [
                                  _LabeledField(
                                    label: 'Category',
                                    required: true,
                                    child: DropdownButtonFormField<String>(
                                      value: _categoryId,
                                      decoration:
                                          _inputDecor('Select category'),
                                      items: _categories
                                      .map((c) => DropdownMenuItem(
                                          value: c['id'], child: Text(c['name']!)))
                                      .toList(),
                                      onChanged: (v) =>
                                          setState(() => _categoryId = v),
                                      validator: (v) => v == null
                                          ? 'Please select a category'
                                          : null,
                                      style: const TextStyle(
                                          fontFamily: 'DM Sans',
                                          fontSize: 14,
                                          color: Color(0xFF111827)),
                                    ),
                                  ),
                                  _LabeledField(
                                    label: 'Language',
                                    required: true,
                                    child: TextFormField(
                                      controller: _language,
                                      decoration: _inputDecor('English'),
                                      validator: (v) =>
                                          v?.trim().isEmpty ?? true
                                              ? 'Language required'
                                              : null,
                                    ),
                                  ),
                                ]),
                          isWide
                              ? Row(children: [
                                  Expanded(
                                    child: _LabeledField(
                                      label: 'Pages',
                                      child: TextFormField(
                                        controller: _pages,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly
                                        ],
                                        decoration: _inputDecor('250'),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _LabeledField(
                                      label: 'ISBN (optional)',
                                      child: TextFormField(
                                        controller: _isbn,
                                        decoration:
                                            _inputDecor('978-3-16-148410-0'),
                                      ),
                                    ),
                                  ),
                                ])
                              : Column(children: [
                                  _LabeledField(
                                    label: 'Pages',
                                    child: TextFormField(
                                      controller: _pages,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly
                                      ],
                                      decoration: _inputDecor('250'),
                                    ),
                                  ),
                                  _LabeledField(
                                    label: 'ISBN (optional)',
                                    child: TextFormField(
                                      controller: _isbn,
                                      decoration:
                                          _inputDecor('978-3-16-148410-0'),
                                    ),
                                  ),
                                ]),
                        ]),

                        // ── Manuscript Details ──────────────────────────────
                        _FormSection(label: 'Manuscript Details', children: [
                          _LabeledField(
                            label: 'Book Description',
                            required: true,
                            child: TextFormField(
                              controller: _description,
                              maxLines: 5,
                              decoration: _inputDecor(
                                  'A compelling overview of your book…'),
                              validator: (v) =>
                                  (v?.trim().length ?? 0) < 100
                                      ? 'At least 100 characters required'
                                      : null,
                            ),
                          ),
                          _LabeledField(
                            label: 'Target Audience',
                            required: true,
                            child: TextFormField(
                              controller: _targetAudience,
                              decoration:
                                  _inputDecor('Young adults aged 16–25…'),
                              validator: (v) =>
                                  (v?.trim().length ?? 0) < 10
                                      ? 'Target audience required'
                                      : null,
                            ),
                          ),
                          _LabeledField(
                            label: 'Publishing Type',
                            required: true,
                            child: DropdownButtonFormField<String>(
                              value: _publishingType,
                              decoration: _inputDecor('Select type'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'traditional',
                                    child: Text('Traditional Publishing')),
                                DropdownMenuItem(
                                    value: 'self',
                                    child: Text('Self-Publishing Support')),
                              ],
                              onChanged: (v) =>
                                  setState(() => _publishingType = v!),
                              style: const TextStyle(
                                  fontFamily: 'DM Sans',
                                  fontSize: 14,
                                  color: Color(0xFF111827)),
                            ),
                          ),

                          // File uploads
                          isWide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                      Expanded(
                                          child: _UploadZone(
                                        label: 'Upload Manuscript *',
                                        hint: 'PDF / DOCX',
                                        icon: Icons.upload_file_rounded,
                                        fileName: _manuscriptFile?.name,
                                        onTap: _pickManuscript,
                                      )),
                                      const SizedBox(width: 16),
                                      Expanded(
                                          child: _UploadZone(
                                        label: 'Book Cover (optional)',
                                        hint: 'JPG / PNG / WebP',
                                        icon: Icons.image_outlined,
                                        fileName: _coverFile?.name,
                                        onTap: _pickCover,
                                      )),
                                    ])
                              : Column(children: [
                                  _UploadZone(
                                    label: 'Upload Manuscript *',
                                    hint: 'PDF / DOCX',
                                    icon: Icons.upload_file_rounded,
                                    fileName: _manuscriptFile?.name,
                                    onTap: _pickManuscript,
                                  ),
                                  const SizedBox(height: 12),
                                  _UploadZone(
                                    label: 'Book Cover (optional)',
                                    hint: 'JPG / PNG / WebP',
                                    icon: Icons.image_outlined,
                                    fileName: _coverFile?.name,
                                    onTap: _pickCover,
                                  ),
                                ]),
                        ]),

                        // ── Additional Information ──────────────────────────
                        _FormSection(
                            label: 'Additional Information',
                            isLast: true,
                            children: [
                              _LabeledField(
                                label: 'Keywords / Tags (comma-separated)',
                                child: TextFormField(
                                  controller: _keywords,
                                  decoration: _inputDecor(
                                      'fiction, Kenya, coming-of-age'),
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Rights checkbox
                              _CheckRow(
                                value: _rightsConfirmed,
                                label:
                                    'I confirm I hold all necessary publishing rights '
                                    'to this manuscript and its contents.',
                                onChanged: (v) =>
                                    setState(() => _rightsConfirmed = v ?? false),
                              ),
                              const SizedBox(height: 8),

                              // Terms checkbox
                              _CheckRow(
                                value: _termsAgreed,
                                label:
                                    'I agree to the Terms and Conditions of Intercen Books.',
                                onChanged: (v) =>
                                    setState(() => _termsAgreed = v ?? false),
                              ),
                            ]),

                        const SizedBox(height: 28),

                        // Submit button
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _submit,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 2,
                                disabledBackgroundColor:
                                    AppColors.primary.withOpacity(0.5),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14))),
                            child: _isSubmitting
                                ? const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2),
                                      ),
                                      SizedBox(width: 10),
                                      Text('Submitting Manuscript…',
                                          style: TextStyle(
                                              fontFamily: 'DM Sans',
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700)),
                                    ],
                                  )
                                : const Text('Submit Manuscript',
                                    style: TextStyle(
                                        fontFamily: 'DM Sans',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ]),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecor(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            fontFamily: 'DM Sans', fontSize: 14, color: Color(0xFFB0B7C3)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        filled: true,
        fillColor: Colors.white,
        errorStyle:
            const TextStyle(fontFamily: 'DM Sans', fontSize: 11),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SUCCESS VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _SuccessView extends StatelessWidget {
  final VoidCallback onHome;
  final VoidCallback onAnother;

  const _SuccessView({
    super.key,
    required this.onHome,
    required this.onAnother,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F5EF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Intercen Books',
            style: TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontWeight: FontWeight.w800,
                fontSize: 19,
                color: Color(0xFF111827))),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5E7EB)),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Success icon
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFD8F3DC)),
                child: const Icon(Icons.check_circle_rounded,
                    size: 48, color: Color(0xFF2D6A4F)),
              ),
              const SizedBox(height: 28),
              const Text('Submission Received!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827))),
              const SizedBox(height: 14),
              const Text(
                'Thank you! Our editorial team will review your manuscript '
                'and get back to you within 4–6 weeks. '
                'A confirmation has been sent to your email address.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                    height: 1.65),
              ),
              const SizedBox(height: 36),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onHome,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      child: const Text('Back to Home',
                          style: TextStyle(
                              fontFamily: 'DM Sans',
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onAnother,
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(
                              color: AppColors.primary.withOpacity(0.5)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      child: const Text('Submit Another',
                          style: TextStyle(
                              fontFamily: 'DM Sans',
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SMALL REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

// ── Section label pill ────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  final bool centered;
  const _SectionLabel(this.text, {this.centered = true});

  @override
  Widget build(BuildContext context) => Align(
        alignment:
            centered ? Alignment.center : Alignment.centerLeft,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
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

// ── Stat cell ─────────────────────────────────────────────────────────────────
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

// ── Option card ───────────────────────────────────────────────────────────────
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
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
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
              // Gold accent bar
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
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(14)),
                      transformAlignment: Alignment.center,
                      transform: _hovered
                          ? (Matrix4.identity()..scale(1.08))
                          : Matrix4.identity(),
                      child: Icon(widget.option.icon,
                          size: 26, color: AppColors.primary),
                    ),
                    const SizedBox(height: 14),

                    Text(widget.option.title,
                        style: const TextStyle(
                            fontFamily: 'PlayfairDisplay',
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827))),
                    const SizedBox(height: 6),

                    Text(widget.option.description,
                        style: const TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 13,
                            color: Color(0xFF6B7280),
                            height: 1.55)),
                    const SizedBox(height: 16),

                    // Feature list
                    ...widget.option.features.map((f) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
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

                    // CTA button
                    SizedBox(
                      width: double.infinity,
                      height: 44,
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
                              const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 15),
                            ]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Step card ─────────────────────────────────────────────────────────────────
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
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: AppColors.primary, shape: BoxShape.circle),
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

// ── Trust row ─────────────────────────────────────────────────────────────────
class _TrustRow extends StatelessWidget {
  final _TrustItem item;
  const _TrustRow({required this.item});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
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

// ── Primary / Outline hero buttons ────────────────────────────────────────────
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

// ── Form section wrapper ───────────────────────────────────────────────────────
class _FormSection extends StatelessWidget {
  final String label;
  final List<Widget> children;
  final bool isLast;
  const _FormSection(
      {required this.label,
      required this.children,
      this.isLast = false});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827))),
              ),
            ]),
          ),
          Container(
            width: double.infinity,
            height: 1,
            color: const Color(0xFFE5E7EB),
            margin: const EdgeInsets.only(bottom: 18),
          ),
          ...children,
          if (!isLast) const SizedBox(height: 24),
        ],
      );
}

// ── FIX 2: Renamed from _FormField → _LabeledField to avoid conflict
//    with Flutter's built-in FormField<T> widget. ───────────────────────────
class _LabeledField extends StatelessWidget {
  final String label;
  final bool required;
  final Widget child;
  const _LabeledField(
      {required this.label,
      this.required = false,
      required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          RichText(
            text: TextSpan(
              text: label,
              style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151)),
              children: required
                  ? const [
                      TextSpan(
                          text: ' *',
                          style: TextStyle(color: Color(0xFFB11226)))
                    ]
                  : [],
            ),
          ),
          const SizedBox(height: 6),
          child,
        ]),
      );
}

// ── Upload zone ───────────────────────────────────────────────────────────────
class _UploadZone extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final String? fileName;
  final VoidCallback onTap;
  const _UploadZone({
    required this.label,
    required this.hint,
    required this.icon,
    required this.fileName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasFile = fileName != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151))),
      const SizedBox(height: 6),
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
          decoration: BoxDecoration(
              color: hasFile
                  ? const Color(0xFFD8F3DC).withOpacity(0.5)
                  : AppColors.primary.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: hasFile
                      ? const Color(0xFF2D6A4F)
                      : AppColors.primary.withOpacity(0.25),
                  width: 1.5,
                  style: BorderStyle.solid)),
          child: Column(children: [
            Icon(hasFile ? Icons.check_circle_rounded : icon,
                size: 28,
                color: hasFile
                    ? const Color(0xFF2D6A4F)
                    : AppColors.primary.withOpacity(0.6)),
            const SizedBox(height: 6),
            Text(
              hasFile ? fileName! : hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 12,
                  fontWeight:
                      hasFile ? FontWeight.w600 : FontWeight.w400,
                  color: hasFile
                      ? const Color(0xFF2D6A4F)
                      : const Color(0xFF9CA3AF)),
            ),
            if (!hasFile) ...[
              const SizedBox(height: 4),
              Text('Tap to upload',
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 11,
                      color: AppColors.primary)),
            ],
          ]),
        ),
      ),
    ]);
  }
}

// ── Checkbox row ──────────────────────────────────────────────────────────────
class _CheckRow extends StatelessWidget {
  final bool value;
  final String label;
  final ValueChanged<bool?> onChanged;
  const _CheckRow(
      {required this.value,
      required this.label,
      required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(!value),
              child: Text(label,
                  style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                      height: 1.55)),
            ),
          ),
        ],
      );
}