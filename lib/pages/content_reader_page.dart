import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONTENT READER PAGE
//
// Route  : /content/:contentId
//
// VIEWER ROUTING (auto-detected from file_url extension):
//   .pdf / .epub           → Browser iframe (HtmlElementView) — web-native, no plugin
//   .jpg/.jpeg/.png/.webp  → _ImagePageViewer  (swipeable, pinch-to-zoom)
//   no file / text only    → scrollable paragraph reader
//
// pubspec.yaml — dependencies required:
//   cached_network_image: ^3.3.1
//
// ACCESS MODEL (tiered):
//   Tier 0  public + free          → no login
//   Tier 1  public + auth          → login required, no purchase
//   Tier 2  paid (is_for_sale/price > 0) → must have paid order_item
//   Tier 3  org-restricted (private) → must be org member
// ─────────────────────────────────────────────────────────────────────────────

// ── Viewer mode ───────────────────────────────────────────────────────────────

enum _ViewerMode { pdf, image, text }

// ── Reader theme ──────────────────────────────────────────────────────────────

enum _ReaderTheme { parchment, white, dark, sepia }

extension _ReaderThemeX on _ReaderTheme {
  Color get bg => switch (this) {
        _ReaderTheme.white => const Color(0xFFFFFFFF),
        _ReaderTheme.dark => const Color(0xFF141420),
        _ReaderTheme.sepia => const Color(0xFFF6ECD8),
        _ => const Color(0xFFF8F4EE),
      };
  Color get surface => switch (this) {
        _ReaderTheme.dark => const Color(0xFF1E1E2E),
        _ReaderTheme.sepia => const Color(0xFFEEDFC4),
        _ReaderTheme.white => const Color(0xFFF8F8F8),
        _ => const Color(0xFFF0EAE0),
      };
  Color get text => switch (this) {
        _ReaderTheme.dark => const Color(0xFFE4E2D8),
        _ => const Color(0xFF1C1C28),
      };
  Color get subText => switch (this) {
        _ReaderTheme.dark => const Color(0xFF8B8FA8),
        _ReaderTheme.sepia => const Color(0xFF7A6A52),
        _ => const Color(0xFF6B7080),
      };
  Color get divider => switch (this) {
        _ReaderTheme.dark => const Color(0xFF2E2E40),
        _ => const Color(0xFFE0DAD2),
      };
  String get label => switch (this) {
        _ReaderTheme.white => 'White',
        _ReaderTheme.dark => 'Dark',
        _ReaderTheme.sepia => 'Sepia',
        _ => 'Parchment',
      };
  bool get isDark => this == _ReaderTheme.dark;
}

// ── Reader settings ───────────────────────────────────────────────────────────

class _ReaderSettings {
  double fontSize;
  String fontFamily;
  double lineHeight;
  _ReaderTheme theme;
  bool immersive;

  _ReaderSettings({
    this.fontSize = 16.0,
    this.fontFamily = 'DM Sans',
    this.lineHeight = 1.5,
    this.theme = _ReaderTheme.white,
    this.immersive = false,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE
// ─────────────────────────────────────────────────────────────────────────────

class ContentReaderPage extends StatefulWidget {
  final String contentId;
  const ContentReaderPage({super.key, required this.contentId});

  @override
  State<ContentReaderPage> createState() => _ContentReaderPageState();
}

class _ContentReaderPageState extends State<ContentReaderPage>
    with WidgetsBindingObserver {
  final _sb = Supabase.instance.client;
  final _scrollCtrl = ScrollController();
  final _settings = _ReaderSettings();
  // Web PDF viewer — unique view-type ID per page load
  String? _pdfViewId;

  // ── State ────────────────────────────────────────────────────────────────
  Map<String, dynamic>? _content;
  String? _bodyText;
  bool _loading = true;
  String? _accessError;

  // Viewer
  _ViewerMode _viewerMode = _ViewerMode.text;
  String? _fileUrl;
  bool _pdfLoaded = false;

  // Toolbar
  bool _toolbarVisible = true;
  Timer? _toolbarTimer;

  // Progress
  double _readProgress = 0;
  bool _reviewPrompted = false;
  bool _showSettings = false;
  bool _bookmarked = false;

  // Reading progress sync (debounced — saves to reading_progress table)
  Timer? _progressSaveTimer;

  // ── Helpers ───────────────────────────────────────────────────────────────
  int get _estMinutes {
    if (_bodyText == null || _viewerMode != _ViewerMode.text) return 0;
    return (_bodyText!.trim().split(RegExp(r'\s+')).length / 250).ceil();
  }

  double get _progress => _readProgress;

  static _ViewerMode _detectMode(
    String? fileUrl,
    String? contentType,
    String? coverImageUrl,
  ) {
    // ── File URL present — detect by extension then content_type ──────────
    if (fileUrl != null && fileUrl.isNotEmpty) {
      final q = fileUrl.toLowerCase().split('?').first; // strip signed-URL params
      if (q.endsWith('.pdf') || q.endsWith('.epub')) return _ViewerMode.pdf;
      if (q.endsWith('.jpg') || q.endsWith('.jpeg') ||
          q.endsWith('.png')  || q.endsWith('.webp')) {
        return _ViewerMode.image;
      }
      final ct = (contentType ?? '').toLowerCase();
      if (ct.contains('image')) return _ViewerMode.image;
      if (ct.contains('pdf')  || ct.contains('epub') ||
          ct.contains('doc')   || ct.contains('text')) {
        return _ViewerMode.pdf;
      }
      // Has a file but unknown type — try PDF viewer
      return _ViewerMode.pdf;
    }

    // ── No file_url (e.g. content-upload sets file_url: null) ─────────────
    // If a cover image exists, show it as the visual content (image viewer).
    // This handles ebook cards where the cover IS the content preview.
    if (coverImageUrl != null && coverImageUrl.isNotEmpty) {
      return _ViewerMode.image;
    }

    // Nothing to show — fall back to description text
    return _ViewerMode.text;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollCtrl.addListener(_onScroll);
    _loadAndVerify();
  }

  @override
  void dispose() {
    _toolbarTimer?.cancel();
    _progressSaveTimer?.cancel();
    // Save final progress synchronously before widget is removed
    _saveReadingProgress();
    _scrollCtrl
      ..removeListener(_onScroll)
      ..dispose();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACCESS VERIFICATION
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _loadAndVerify() async {
    setState(() { _loading = true; _accessError = null; });

    try {
      final data = await _sb.from('content').select('''
        id, title, subtitle, author, content_type, description,
        cover_image_url, backpage_image_url, page_count, language,
        publisher, file_url, isbn, version,
        total_downloads, total_reviews, created_at, updated_at,
        visibility, access_level, is_free, is_for_sale, price,
        organization_id, status, uploaded_by
      ''').eq('id', widget.contentId).eq('status', 'published').maybeSingle();

      if (data == null) {
        setState(() { _accessError = 'not_found'; _loading = false; });
        return;
      }

      final visibility = data['visibility'] as String? ?? 'private';
      final isFree     = data['is_free']    as bool?   ?? false;
      final price      = (data['price']     as num?)?.toDouble() ?? 0.0;
      final isForSale  = data['is_for_sale'] as bool?  ?? false;
      final orgId      = data['organization_id'] as String?;
      final isPublicFree = visibility == 'public' && (isFree || price == 0.0) && !isForSale;

      if (!isPublicFree) {
        // Auth required
        final session = _sb.auth.currentSession;
        if (session == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.pushNamedAndRemoveUntil(
                context, '/login', (_) => false,
                arguments: {'redirect': '/content/${widget.contentId}'});
            }
          });
          return;
        }
        try { await _sb.auth.refreshSession(); }
        catch (_) {
          if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
          return;
        }

        final uid = _sb.auth.currentUser!.id;

        // Org gate
        if (visibility == 'private' && orgId != null) {
          final orgCheck = await _sb.from('organization_members')
              .select('role').eq('organization_id', orgId)
              .eq('user_id', uid).maybeSingle();
          if (orgCheck == null) {
            setState(() { _accessError = 'org_required'; _loading = false; });
            return;
          }
        }

        // Purchase gate
        if (isForSale || price > 0.0) {
          final purchase = await _sb.from('order_items')
              .select('id, orders!inner(user_id, payment_status)')
              .eq('content_id', widget.contentId)
              .eq('orders.user_id', uid)
              .eq('orders.payment_status', 'paid')
              .limit(1);
          final isUploader = data['uploaded_by'] == uid;
          if (purchase.isEmpty && !isUploader) {
            setState(() {
              _accessError = 'purchase_required';
              _content = data;
              _loading = false;
            });
            return;
          }
        }
      }

      // Record view (best-effort)
      final downloads = (data['total_downloads'] as int?) ?? 0;
      _sb.from('content').update({'total_downloads': downloads + 1})
          .eq('id', widget.contentId).ignore();

      final fileUrl     = data['file_url']     as String?;
      final contentType = data['content_type'] as String?;
      final description = data['description']  as String?;
      final coverUrl    = data['cover_image_url'] as String?;
      final backpageUrl = data['backpage_image_url'] as String?;
      final mode = _detectMode(fileUrl, contentType, coverUrl);

      // Debug: log what was detected so blank-screen issues are traceable
      debugPrint('[Reader] contentId=${widget.contentId}');
      debugPrint('[Reader] file_url=$fileUrl  cover=$coverUrl  backpage=$backpageUrl');
      debugPrint('[Reader] content_type=$contentType  mode=$mode');
      debugPrint('[Reader] description length=${description?.length ?? 0}');

      if (mounted) {
        setState(() {
          _content    = data;
          _fileUrl    = fileUrl;
          _viewerMode = mode;
          _bodyText   = (description != null && description.isNotEmpty) ? description : null;
          _loading    = false;
        });
      }
      // Load ancillary data after content is visible
      _loadBookmarkState();
      _loadReadingProgress();
    } catch (e) {
      debugPrint('ContentReaderPage error: $e');
      if (mounted) setState(() { _accessError = 'not_found'; _loading = false; });
    }
  }

  // ── Bookmark (table: bookmarks) ──────────────────────────────────────────
  Future<void> _loadBookmarkState() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    try {
      // bookmarks table has: id, user_id, content_id, page_number, note, created_at
      // We query for any bookmark on this content — presence = bookmarked
      final r = await _sb
          .from('bookmarks')
          .select('id')
          .eq('user_id', user.id)
          .eq('content_id', widget.contentId)
          .limit(1)
          .maybeSingle();
      if (mounted) setState(() => _bookmarked = r != null);
    } catch (e) {
      debugPrint('loadBookmarkState error: $e');
    }
  }

  Future<void> _toggleBookmark() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    final was = _bookmarked;
    setState(() => _bookmarked = !_bookmarked);
    try {
      if (was) {
        // Delete all bookmarks for this user+content
        await _sb
            .from('bookmarks')
            .delete()
            .eq('user_id', user.id)
            .eq('content_id', widget.contentId);
      } else {
        // Insert new bookmark (page_number and note are optional)
        await _sb.from('bookmarks').insert({
          'user_id': user.id,
          'content_id': widget.contentId,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('toggleBookmark error: $e');
      if (mounted) setState(() => _bookmarked = was);
    }
  }

  // ── Reading progress (table: reading_progress) ─────────────────────────────
  // Loads saved progress on open; saves debounced on every scroll tick.
  Future<void> _loadReadingProgress() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    try {
      final r = await _sb
          .from('reading_progress')
          .select('percentage, current_page, total_pages')
          .eq('user_id', user.id)
          .eq('content_id', widget.contentId)
          .maybeSingle();
      if (r != null && mounted) {
        final pct = (r['percentage'] as num?)?.toDouble() ?? 0;
        setState(() => _readProgress = (pct / 100).clamp(0.0, 1.0));
        // Restore text scroll position
        if (_viewerMode == _ViewerMode.text && _scrollCtrl.hasClients) {
          final max = _scrollCtrl.position.maxScrollExtent;
          _scrollCtrl.jumpTo((_readProgress * max).clamp(0, max));
        }
      }
    } catch (e) {
      debugPrint('loadReadingProgress error: $e');
    }
  }

  void _scheduleProgressSave() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(const Duration(seconds: 3), _saveReadingProgress);
  }

  Future<void> _saveReadingProgress() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    try {
      final pct = (_readProgress * 100).clamp(0.0, 100.0);
      await _sb.from('reading_progress').upsert({
        'user_id': user.id,
        'content_id': widget.contentId,
        'percentage': double.parse(pct.toStringAsFixed(2)),
        'completed': _readProgress >= 0.98,
        'last_read_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,content_id');
    } catch (e) {
      debugPrint('saveReadingProgress error: $e');
    }
  }

  // ── Scroll / progress (text mode) ─────────────────────────────────────────
  void _onScroll() {
    final max = _scrollCtrl.position.maxScrollExtent;
    if (max <= 0) return;
    final p = (_scrollCtrl.offset / max).clamp(0.0, 1.0);
    if ((p - _readProgress).abs() > 0.005) {
      setState(() => _readProgress = p);
      _scheduleProgressSave(); // debounced — saves after 3s of no scrolling
    }
    if (p >= 0.30 && !_reviewPrompted) {
      _reviewPrompted = true;
      Future.delayed(const Duration(seconds: 2), _showReviewPrompt);
    }
    _scheduleToolbarHide();
  }

  // ── Toolbar ───────────────────────────────────────────────────────────────
  void _scheduleToolbarHide() {
    _toolbarTimer?.cancel();
    if (!_toolbarVisible) return;
    _toolbarTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toolbarVisible = false);
    });
  }

  void _toggleToolbar() {
    _toolbarTimer?.cancel();
    setState(() {
      _toolbarVisible = !_toolbarVisible;
      if (_showSettings && !_toolbarVisible) _showSettings = false;
    });
    if (_toolbarVisible) _scheduleToolbarHide();
  }

  void _setImmersive(bool on) {
    setState(() => _settings.immersive = on);
    SystemChrome.setEnabledSystemUIMode(
        on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  // ── Review ────────────────────────────────────────────────────────────────
  void _showReviewPrompt() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ReviewSheet(
        contentId: widget.contentId,
        title: _content?['title'] as String? ?? '',
        onSubmit: (rating, text) async {
          final user = _sb.auth.currentUser;
          if (user == null) return;
          await _sb.from('reviews').insert({
            'content_id': widget.contentId,
            'user_id': user.id,
            'rating': rating,
            'review_text': text,
            'created_at': DateTime.now().toIso8601String(),
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('Thank you for your review!',
                  style: TextStyle(fontFamily: 'DM Sans', fontSize: 13)),
              backgroundColor: const Color(0xFF16A34A),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(12),
            ));
          }
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) return _loadingView();
    if (_accessError != null) {
      debugPrint('[Reader] Access error: $_accessError');
      return _accessGateView();
    }
    // Guard: content not loaded yet (shouldn't happen, but prevents _content! crash)
    if (_content == null) {
      debugPrint('[Reader] Content is null');
      return _loadingView();
    }

    final theme = _settings.theme;

    // Fallback: If viewer mode is unknown, show detail page
    Widget mainViewer;
    switch (_viewerMode) {
      case _ViewerMode.pdf:
        mainViewer = _buildPdfViewer();
        break;
      case _ViewerMode.image:
        mainViewer = _buildImageViewer();
        break;
      case _ViewerMode.text:
        mainViewer = _buildTextViewer(theme);
        break;
      default:
        debugPrint('[Reader] Unknown viewer mode, showing detail page');
        mainViewer = _buildContentDetailPage(
          _content?['cover_image_url'] as String?,
          _content?['backpage_image_url'] as String?
        );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: theme.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _viewerMode == _ViewerMode.pdf
            ? const Color(0xFF3A3A3A)
            : (_viewerMode == _ViewerMode.image ? Colors.black : theme.bg),
        body: GestureDetector(
          onTap: _toggleToolbar,
          behavior: HitTestBehavior.translucent,
          child: Stack(children: [
            // ────── MAIN VIEWER ────────────────────────────────────────────
            Positioned.fill(child: mainViewer),

            // ────── THIN PROGRESS LINE (top edge, always visible) ──────────
            Positioned(
              top: 0, left: 0, right: 0,
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 2.5,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),

            // ────── TOP TOOLBAR ────────────────────────────────────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeInOut,
              top: _toolbarVisible ? 0 : -80,
              left: 0, right: 0,
              child: _buildTopBar(theme),
            ),

            // ────── BOTTOM BAR ─────────────────────────────────────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeInOut,
              bottom: _toolbarVisible ? 0 : -80,
              left: 0, right: 0,
              child: _buildBottomBar(theme),
            ),

            // ────── SETTINGS PANEL ─────────────────────────────────────────
            (_showSettings && _viewerMode == _ViewerMode.text)
                ? _buildSettingsPanel(theme)
                : const SizedBox.shrink(),
          ]),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PDF VIEWER — Web (iframe)
  //
  // Flutter Web cannot use native plugins like Syncfusion. Instead we inject
  // the browser's own built-in PDF renderer via an <iframe> using
  // HtmlElementView + dart:ui_web's platformViewRegistry.
  //
  // • Chrome / Edge  → native PDF viewer with toolbar
  // • Firefox        → native PDF viewer (pdf.js based)
  // • Safari         → native PDF renderer
  //
  // The iframe URL is the raw Supabase file_url. Supabase storage sets
  // Access-Control-Allow-Origin: * on public buckets so no CORS issues.
  // Signed URLs also work because auth is embedded in the URL params.
  // ═══════════════════════════════════════════════════════════════════════════
  Timer? _pdfTimeoutTimer;
  bool _pdfTimeout = false;

  Widget _buildPdfViewer() {
    // Guard: null/empty fileUrl → fall back to text viewer
    if (_fileUrl == null || _fileUrl!.isEmpty) {
      return _buildTextViewer(_settings.theme);
    }
    final viewId = 'pdf-${_fileUrl!.hashCode}';
    // Only register view factory once
    if (_pdfViewId != viewId) {
      _pdfViewId = viewId;
      _pdfTimeout = false;
      _pdfTimeoutTimer?.cancel();
      _pdfTimeoutTimer = Timer(const Duration(seconds: 10), () {
        if (mounted && !_pdfLoaded) {
          setState(() => _pdfTimeout = true);
        }
      });
      try {
        ui.platformViewRegistry.registerViewFactory(viewId, (int id) {
          final iframe = html.IFrameElement()
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.backgroundColor = '#3a3a3a'
            ..allowFullscreen = true
            ..src = '$_fileUrl#toolbar=1&navpanes=0&scrollbar=1';

          iframe.onLoad.listen((_) {
            if (mounted) {
              _pdfTimeoutTimer?.cancel();
              setState(() => _pdfLoaded = true);
              Future.delayed(const Duration(seconds: 5), () {
                if (mounted) setState(() => _toolbarVisible = false);
              });
            }
          });
          iframe.onError.listen((_) {
            if (mounted) {
              _pdfTimeoutTimer?.cancel();
              setState(() {
                _pdfLoaded = false;
                _pdfTimeout = true;
              });
            }
          });
          return iframe;
        });
      } catch (_) {
        // Already registered — safe to ignore
      }
    }

    // Show loading indicator while PDF loads
    return Stack(
      children: [
        HtmlElementView(viewType: viewId),
        if (!_pdfLoaded && !_pdfTimeout)
          Positioned.fill(
            child: Container(
              color: const Color(0xFF3A3A3A),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.primary),
                    const SizedBox(height: 18),
                    const Text(
                      'Opening your book...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'DM Sans',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if ((_pdfLoaded == false && _fileUrl != null && _pdfTimeout) || _pdfTimeout)
          Positioned.fill(
            child: Container(
              color: const Color(0xFF3A3A3A),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 18),
                    const Text(
                      'Failed to load PDF file.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontFamily: 'DM Sans',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _fileUrl ?? '',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontFamily: 'DM Sans',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // IMAGE VIEWER / CONTENT DETAIL VIEW
  //
  // Two modes:
  //   A) Real multi-page image content (file_url is an image) → swipeable pages
  //   B) Ebook/document with no uploaded file (file_url = null) → rich detail
  //      page: full-bleed cover + metadata + description, like Wattpad's
  //      book landing page when a chapter hasn't been added yet.
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildImageViewer() {
    final cover    = _content?['cover_image_url']    as String?;
    final backpage = _content?['backpage_image_url'] as String?;
    final hasRealFile = _fileUrl != null && _fileUrl!.isNotEmpty;

    // Mode A: actual image file(s) → swipeable page viewer
    if (hasRealFile) {
      final images = <String>[];
      if (cover    != null && cover.isNotEmpty)                       images.add(cover);
      if (_fileUrl != null && _fileUrl!.isNotEmpty && _fileUrl != cover) images.add(_fileUrl!);
      if (backpage != null && backpage.isNotEmpty && backpage != cover)  images.add(backpage);

      if (images.isNotEmpty) {
        return _ImagePageViewer(
          imageUrls: images,
          onPageChanged: (page, total) {
            final p = total > 0 ? page / total : 0.0;
            setState(() => _readProgress = p);
            if (p >= 0.30 && !_reviewPrompted) {
              _reviewPrompted = true;
              Future.delayed(const Duration(seconds: 2), _showReviewPrompt);
            }
            _scheduleToolbarHide();
          },
          onTap: _toggleToolbar,
        );
      }
    }

    // Mode B: no real file — show rich scrollable content detail page.
    // cover + backpage are shown as the visual content.
    return _buildContentDetailPage(cover, backpage);
  }

  // ── Rich content detail page (no uploadable file yet) ────────────────────
  // Shown when content_upload sets file_url = null.
  // Displays: full-bleed cover → metadata → description → backpage.
  Widget _buildContentDetailPage(String? cover, String? backpage) {
    final theme = _settings.theme;
    final c = _content!;
    final title       = c['title']        as String? ?? 'Untitled';
    final subtitle    = c['subtitle']     as String?;
    final author      = c['author']       as String?;
    final publisher   = c['publisher']    as String?;
    final description = c['description'] as String?;
    final ct          = c['content_type'] as String? ?? '';
    final language    = c['language']     as String? ?? 'en';
    final pageCount   = c['page_count']   as int?;
    final isbn        = c['isbn']         as String?;

    return CustomScrollView(
      controller: _scrollCtrl,
      physics: const BouncingScrollPhysics(),
      slivers: [

        // ── Full-bleed cover hero ──────────────────────────────────────────
        SliverToBoxAdapter(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.62,
            child: Stack(fit: StackFit.expand, children: [
              if (cover != null && cover.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: cover,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.primary.withOpacity(0.08),
                    child: Center(child: Icon(Icons.menu_book_rounded,
                        size: 80, color: AppColors.primary.withOpacity(0.3))),
                  ),
                )
              else
                Container(
                  color: AppColors.primary.withOpacity(0.06),
                  child: Center(child: Icon(Icons.menu_book_rounded,
                      size: 80, color: AppColors.primary.withOpacity(0.25))),
                ),
              // Gradient fade into content below
              Positioned(bottom: 0, left: 0, right: 0,
                child: Container(height: 180, decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, theme.bg],
                  ),
                )),
              ),
              // Top padding for toolbar
              SizedBox(height: MediaQuery.of(context).padding.top + 56),
            ]),
          ),
        ),

        // ── Metadata card ──────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Content type badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(ct.toUpperCase(),
                    style: TextStyle(fontFamily: 'DM Sans', fontSize: 10,
                        fontWeight: FontWeight.w800, letterSpacing: 1.1,
                        color: AppColors.primary)),
              ),
              const SizedBox(height: 10),
              // Title
              Text(title,
                  style: TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 28,
                      fontWeight: FontWeight.w800, color: theme.text, height: 1.2)),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(subtitle, style: TextStyle(fontFamily: 'DM Sans', fontSize: 16,
                    color: theme.subText, fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 14),
              // Author / publisher row
              Wrap(spacing: 16, runSpacing: 8, children: [
                if (author != null && author.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.person_outline_rounded, size: 14, color: theme.subText),
                    const SizedBox(width: 4),
                    Text(author, style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                        fontWeight: FontWeight.w600, color: theme.text)),
                  ]),
                if (publisher != null && publisher.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.business_outlined, size: 14, color: theme.subText),
                    const SizedBox(width: 4),
                    Text(publisher, style: TextStyle(fontFamily: 'DM Sans',
                        fontSize: 13, color: theme.subText)),
                  ]),
              ]),
              const SizedBox(height: 14),
              // Stats chips
              Wrap(spacing: 16, runSpacing: 8, children: [
                if (pageCount != null)
                  _statChip(Icons.menu_book_outlined, '$pageCount pages', theme),
                _statChip(Icons.language_rounded, language.toUpperCase(), theme),
                if (isbn != null && isbn.isNotEmpty)
                  _statChip(Icons.qr_code_rounded, isbn, theme),
                if ((c['total_reviews'] as int? ?? 0) > 0)
                  _statChip(Icons.star_rounded, '${c['total_reviews']} reviews', theme,
                      iconColor: const Color(0xFFF59E0B)),
              ]),
              const SizedBox(height: 24),

              // ── Divider ─────────────────────────────────────────────────
              Row(children: [
                Expanded(child: Divider(color: theme.divider, thickness: 1)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text('ABOUT THIS CONTENT',
                        style: TextStyle(fontFamily: 'DM Sans', fontSize: 10,
                            fontWeight: FontWeight.w700, letterSpacing: 1.4,
                            color: theme.subText))),
                Expanded(child: Divider(color: theme.divider, thickness: 1)),
              ]),
              const SizedBox(height: 20),

              // ── Description ──────────────────────────────────────────────
              if (description != null && description.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: (description?.split(RegExp(r'\n{2,}')) ?? []).map((p) {
                    final t = p.trim();
                    if (t.isEmpty) return const SizedBox(height: 8);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Text(
                        t,
                        style: TextStyle(
                          fontFamily: _settings.fontFamily,
                          fontSize: _settings.fontSize,
                          height: _settings.lineHeight,
                          color: theme.text,
                          letterSpacing: 0.12,
                        ),
                      ),
                    );
                  }).toList(),
                )
              else
                Text('No description available.',
                    style: TextStyle(fontFamily: 'DM Sans', fontSize: 14,
                        color: theme.subText, fontStyle: FontStyle.italic)),
            ]),
          ),
        ),

        // ── Back cover image ───────────────────────────────────────────────
        if (backpage != null && backpage.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 32, 22, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Divider(color: theme.divider, thickness: 1)),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text('BACK COVER',
                          style: TextStyle(fontFamily: 'DM Sans', fontSize: 10,
                              fontWeight: FontWeight.w700, letterSpacing: 1.4,
                              color: theme.subText))),
                  Expanded(child: Divider(color: theme.divider, thickness: 1)),
                ]),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: backpage,
                    width: double.infinity,
                    fit: BoxFit.fitWidth,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ]),
            ),
          ),

        // ── Bottom padding ─────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.of(context).padding.bottom + 100),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TEXT VIEWER
  // Wattpad-style scrollable paragraphs. Used when there is no file,
  // or as fallback if PDF/image fails. Respects all reader settings.
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildTextViewer(_ReaderTheme theme) {
    return CustomScrollView(
      controller: _scrollCtrl,
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.top + 56)),
        SliverToBoxAdapter(child: _buildCoverHeader(theme)),
        SliverToBoxAdapter(child: _buildChapterDivider(theme)),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
              22, 4, 22, MediaQuery.of(context).padding.bottom + 80),
          sliver: SliverToBoxAdapter(
            child: _bodyText != null && _bodyText!.isNotEmpty
                ? _buildParagraphs(theme)
                : _buildNoPreviewCard(theme),
          ),
        ),
      ],
    );
  }

  Widget _buildParagraphs(_ReaderTheme theme) {
    final paras = _bodyText!.split(RegExp(r'\n\n+'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: paras.map((p) {
        final t = p.trim();
        if (t.isEmpty) return const SizedBox(height: 8);
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Text(t,
              style: TextStyle(
                fontFamily: _settings.fontFamily,
                fontSize: _settings.fontSize,
                height: _settings.lineHeight,
                color: theme.text,
                letterSpacing: 0.12,
              )),
        );
      }).toList(),
    );
  }

  Widget _buildNoPreviewCard(_ReaderTheme theme) => Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: theme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.divider)),
      child: Column(children: [
        Container(width: 64, height: 64,
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle),
            child: Icon(Icons.info_outline_rounded, size: 30, color: AppColors.primary)),
        const SizedBox(height: 14),
        Text('No Preview Available',
            style: TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 17,
                fontWeight: FontWeight.w800, color: theme.text)),
        const SizedBox(height: 8),
        Text('No readable content available for this item. '
            'Please contact the publisher for access.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                color: theme.subText, height: 1.6)),
      ]));

  // ── Cover header widget (text mode) ───────────────────────────────────────
  Widget _buildCoverHeader(_ReaderTheme theme) {
    final c         = _content!;
    final cover     = c['cover_image_url'] as String?;
    final title     = c['title']           as String? ?? 'Untitled';
    final subtitle  = c['subtitle']        as String?;
    final author    = c['author']          as String?;
    final ct        = c['content_type']    as String? ?? '';
    final pageCount = c['page_count']      as int?;
    final publisher = c['publisher']       as String?;
    final language  = c['language']        as String? ?? 'en';

    return Container(
      color: theme.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (cover != null && cover.isNotEmpty)
          Stack(children: [
            CachedNetworkImage(imageUrl: cover, width: double.infinity,
                height: 260, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _coverPlaceholder(theme, 260)),
            Positioned(bottom: 0, left: 0, right: 0,
                child: Container(height: 100, decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.transparent, theme.surface.withOpacity(0.95)])))),
          ])
        else _coverPlaceholder(theme, 160),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(ct.toUpperCase(),
                  style: TextStyle(fontFamily: 'DM Sans', fontSize: 10,
                      fontWeight: FontWeight.w800, letterSpacing: 1.1,
                      color: AppColors.primary)),
            ),
            const SizedBox(height: 10),
            Text(title, style: TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 26,
                fontWeight: FontWeight.w800, color: theme.text, height: 1.2)),
            if (subtitle != null && subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(subtitle, style: TextStyle(fontFamily: 'DM Sans', fontSize: 15,
                  color: theme.subText, fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 12),
            Row(children: [
              if (author != null && author.isNotEmpty) ...[
                Icon(Icons.person_outline_rounded, size: 14, color: theme.subText),
                const SizedBox(width: 4),
                Text(author, style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                    fontWeight: FontWeight.w600, color: theme.text)),
              ],
              if (publisher != null && publisher.isNotEmpty)
                Text('  ·  $publisher', style: TextStyle(fontFamily: 'DM Sans',
                    fontSize: 13, color: theme.subText)),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 16, runSpacing: 8, children: [
              _statChip(Icons.schedule_rounded, '~$_estMinutes min read', theme),
              if (pageCount != null)
                _statChip(Icons.menu_book_outlined, '$pageCount pages', theme),
              _statChip(Icons.language_rounded, language.toUpperCase(), theme),
              if ((c['total_reviews'] as int? ?? 0) > 0)
                _statChip(Icons.star_rounded, '${c['total_reviews']} reviews', theme,
                    iconColor: const Color(0xFFF59E0B)),
            ]),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                  value: _readProgress, minHeight: 6,
                  backgroundColor: theme.divider,
                  valueColor: AlwaysStoppedAnimation(AppColors.primary)),
            ),
            const SizedBox(height: 6),
            Text('${(_readProgress * 100).toStringAsFixed(0)}% read',
                style: TextStyle(fontFamily: 'DM Sans', fontSize: 11,
                    fontWeight: FontWeight.w600, color: AppColors.primary)),
          ]),
        ),
      ]),
    );
  }

  Widget _coverPlaceholder(_ReaderTheme theme, double h) => Container(
      width: double.infinity, height: h,
      color: AppColors.primary.withOpacity(0.06),
      child: Center(child: Icon(Icons.menu_book_rounded, size: 56,
          color: AppColors.primary.withOpacity(0.3))));

  Widget _statChip(IconData icon, String label, _ReaderTheme theme, {Color? iconColor}) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: iconColor ?? theme.subText),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontFamily: 'DM Sans', fontSize: 12, color: theme.subText)),
      ]);

  Widget _buildChapterDivider(_ReaderTheme theme) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
      child: Row(children: [
        Expanded(child: Divider(color: theme.divider, thickness: 1)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text('BEGIN READING',
                style: TextStyle(fontFamily: 'DM Sans', fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 1.4, color: theme.subText))),
        Expanded(child: Divider(color: theme.divider, thickness: 1)),
      ]));

  // ─────────────────────────────────────────────────────────────────────────
  // TOP BAR
  // Semi-transparent dark overlay in PDF/image mode; themed surface in text mode.
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildTopBar(_ReaderTheme theme) {
    final isMedia = _viewerMode != _ViewerMode.text;
    final barBg    = isMedia ? const Color(0xCC141420) : theme.surface;
    final titleClr = isMedia ? Colors.white : (theme.isDark ? const Color(0xFFE4E2D8) : const Color(0xFF111827));
    final iconClr  = isMedia ? Colors.white70 : theme.subText;

    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top, left: 4, right: 4),
      decoration: BoxDecoration(
        color: barBg,
        border: isMedia ? null : Border(bottom: BorderSide(color: theme.divider, width: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isMedia ? 0.35 : 0.06),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: SizedBox(height: 52, child: Row(children: [
        // Back
        IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: titleClr),
          onPressed: () => Navigator.pop(context),
        ),
        // Title
        Expanded(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_content?['title'] as String? ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 14,
                      fontWeight: FontWeight.w700, color: titleClr)),
              // PDF on web: page tracking unavailable (cross-origin iframe)
              if (_viewerMode == _ViewerMode.pdf && _pdfLoaded)
                Text('Use PDF toolbar to navigate pages',
                    style: TextStyle(fontFamily: 'DM Sans', fontSize: 10, color: iconClr)),
            ])),
        // Bookmark
        IconButton(
          icon: Icon(
              _bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              size: 20,
              color: _bookmarked ? AppColors.primary : iconClr),
          onPressed: _toggleBookmark,
        ),
        // Text settings (text mode only)
        if (_viewerMode == _ViewerMode.text)
          IconButton(
            icon: Icon(Icons.text_fields_rounded, size: 20, color: iconClr),
            onPressed: () => setState(() => _showSettings = !_showSettings),
            tooltip: 'Reader settings',
          ),
      ])),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BOTTOM BAR
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBottomBar(_ReaderTheme theme) {
    final isMedia = _viewerMode != _ViewerMode.text;
    final barBg   = isMedia ? const Color(0xCC141420) : theme.surface;
    final subClr  = isMedia ? Colors.white54 : theme.subText;

    return Container(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 6,
          left: 20, right: 20, top: 10),
      decoration: BoxDecoration(
        color: barBg,
        border: isMedia ? null : Border(top: BorderSide(color: theme.divider, width: 0.5)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        // Progress label
        Text(
          _viewerMode == _ViewerMode.pdf
              ? (_pdfLoaded ? 'PDF loaded ✓' : 'Loading…')
              : '${(_progress * 100).toStringAsFixed(0)}%  ·  $_estMinutes min',
          style: TextStyle(fontFamily: 'DM Sans', fontSize: 12, color: subClr),
        ),
        // Focus mode
        GestureDetector(
          onTap: () => _setImmersive(!_settings.immersive),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _settings.immersive ? AppColors.primary : AppColors.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_settings.immersive ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                  size: 14,
                  color: _settings.immersive ? Colors.white : AppColors.primary),
              const SizedBox(width: 4),
              Text(_settings.immersive ? 'Exit Focus' : 'Focus Mode',
                  style: TextStyle(fontFamily: 'DM Sans', fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _settings.immersive ? Colors.white : AppColors.primary)),
            ]),
          ),
        ),
        // Review CTA
        GestureDetector(
          onTap: _showReviewPrompt,
          child: Text('Rate & Review',
              style: TextStyle(fontFamily: 'DM Sans', fontSize: 12,
                  fontWeight: FontWeight.w600, color: AppColors.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.primary)),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SETTINGS PANEL (text mode only)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildSettingsPanel(_ReaderTheme theme) {
    return Positioned(
      top: 0, left: 0, right: 0, bottom: 0,
      child: GestureDetector(
        onTap: () => setState(() => _showSettings = false),
        child: Container(
          color: Colors.black45, alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 52),
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.14),
                    blurRadius: 24, offset: const Offset(0, 10))],
              ),
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Reader Settings', style: TextStyle(fontFamily: 'PlayfairDisplay',
                      fontSize: 17, fontWeight: FontWeight.w800, color: theme.text)),
                  GestureDetector(onTap: () => setState(() => _showSettings = false),
                      child: Icon(Icons.close_rounded, color: theme.subText)),
                ]),
                const SizedBox(height: 22),
                _SettingsRow(label: 'Font Size', theme: theme,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _SettingsIconBtn(icon: Icons.remove_rounded, theme: theme,
                          onTap: () => setState(() =>
                          _settings.fontSize = (_settings.fontSize - 1).clamp(12, 30))),
                      const SizedBox(width: 10),
                      SizedBox(width: 28, child: Text('${_settings.fontSize.toInt()}',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'DM Sans', fontSize: 14,
                              fontWeight: FontWeight.w700, color: theme.text))),
                      const SizedBox(width: 10),
                      _SettingsIconBtn(icon: Icons.add_rounded, theme: theme,
                          onTap: () => setState(() =>
                          _settings.fontSize = (_settings.fontSize + 1).clamp(12, 30))),
                    ])),
                const SizedBox(height: 18),
                _SettingsRow(label: 'Font', theme: theme,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _FontChip(label: 'Sans', fontFamily: 'DM Sans',
                          current: _settings.fontFamily, theme: theme,
                          onTap: () => setState(() => _settings.fontFamily = 'DM Sans')),
                      const SizedBox(width: 8),
                      _FontChip(label: 'Serif', fontFamily: 'PlayfairDisplay',
                          current: _settings.fontFamily, theme: theme,
                          onTap: () => setState(() => _settings.fontFamily = 'PlayfairDisplay')),
                      const SizedBox(width: 8),
                      _FontChip(label: 'Mono', fontFamily: 'RobotoMono',
                          current: _settings.fontFamily, theme: theme,
                          onTap: () => setState(() => _settings.fontFamily = 'RobotoMono')),
                    ])),
                const SizedBox(height: 18),
                _SettingsRow(label: 'Line Height', theme: theme,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _SettingsIconBtn(icon: Icons.density_small_rounded, theme: theme,
                          onTap: () => setState(() =>
                          _settings.lineHeight = (_settings.lineHeight - 0.1).clamp(1.3, 2.5))),
                      const SizedBox(width: 10),
                      Text(_settings.lineHeight.toStringAsFixed(1),
                          style: TextStyle(fontFamily: 'DM Sans', fontSize: 14,
                              fontWeight: FontWeight.w700, color: theme.text)),
                      const SizedBox(width: 10),
                      _SettingsIconBtn(icon: Icons.density_large_rounded, theme: theme,
                          onTap: () => setState(() =>
                          _settings.lineHeight = (_settings.lineHeight + 0.1).clamp(1.3, 2.5))),
                    ])),
                const SizedBox(height: 20),
                _SettingsRow(label: 'Theme', theme: theme,
                    child: Row(mainAxisSize: MainAxisSize.min,
                        children: _ReaderTheme.values.map((t) => _ThemeSwatch(
                            readerTheme: t, selected: _settings.theme == t,
                            onTap: () => setState(() => _settings.theme = t))).toList())),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACCESS GATE VIEW
  // ─────────────────────────────────────────────────────────────────────────
  Widget _accessGateView() {
    final isPurchase = _accessError == 'purchase_required';
    final isOrg      = _accessError == 'org_required';
    final cover  = _content?['cover_image_url'] as String?;
    final title  = _content?['title']           as String?;
    final author = _content?['author']          as String?;
    final price  = (_content?['price'] as num?)?.toDouble() ?? 0.0;

    final gateIcon  = isPurchase ? Icons.lock_outline_rounded
        : isOrg ? Icons.corporate_fare_rounded : Icons.search_off_rounded;
    final gateTitle = isPurchase ? 'Purchase Required'
        : isOrg ? 'Restricted Access' : 'Content Not Found';
    final gateBody  = isPurchase
        ? 'Unlock the full content to start reading. Your progress will be saved automatically.'
        : isOrg
        ? 'This content is restricted to organisation members. Contact your administrator.'
        : 'This content could not be found or is no longer available.';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F4EE),
      body: CustomScrollView(slivers: [
        SliverAppBar(
          backgroundColor: Colors.white, elevation: 0, pinned: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF1A1A2E)),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(gateTitle,
              style: const TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 16,
                  fontWeight: FontWeight.w700, color: Color(0xFF111827))),
        ),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(children: [
            const SizedBox(height: 12),
            if (cover != null && title != null) ...[
              Stack(alignment: Alignment.center, children: [
                ClipRRect(borderRadius: BorderRadius.circular(16),
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                          Colors.black.withOpacity(0.45), BlendMode.darken),
                      child: CachedNetworkImage(imageUrl: cover, width: 140, height: 200,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(width: 140, height: 200,
                              decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(16)))),
                    )),
                Container(width: 52, height: 52,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: Icon(gateIcon, size: 26, color: AppColors.primary)),
              ]),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 20,
                      fontWeight: FontWeight.w800, color: Color(0xFF111827))),
              if (author != null)
                Text('by $author', style: const TextStyle(fontFamily: 'DM Sans',
                    fontSize: 14, color: Color(0xFF6B7080))),
              if (isPurchase && price > 0) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                      color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                  child: Text('KSH ${price.toStringAsFixed(0)}',
                      style: const TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                          fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ],
              const SizedBox(height: 28),
            ] else ...[
              Container(width: 90, height: 90,
                  decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.07), shape: BoxShape.circle),
                  child: Icon(gateIcon, size: 44, color: AppColors.primary)),
              const SizedBox(height: 24),
            ],
            Text(gateTitle, style: const TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 22,
                fontWeight: FontWeight.w800, color: Color(0xFF111827))),
            const SizedBox(height: 10),
            Text(gateBody, textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14,
                    color: Color(0xFF6B7080), height: 1.6)),
            const SizedBox(height: 36),
            if (isPurchase) ...[
              SizedBox(width: double.infinity, height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/book-detail',
                        arguments: widget.contentId),
                    icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                    label: const Text('View & Purchase',
                        style: TextStyle(fontFamily: 'DM Sans', fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white, elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  )),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, height: 52,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pushNamed(context, '/browse'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary.withOpacity(0.35)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    child: const Text('Browse Other Content',
                        style: TextStyle(fontFamily: 'DM Sans', fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  )),
            ] else
              SizedBox(width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white, elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    child: const Text('Go Back',
                        style: TextStyle(fontFamily: 'DM Sans', fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  )),
          ]),
        )),
      ]),
    );
  }

  // ── Loading ───────────────────────────────────────────────────────────────
  Widget _loadingView() => Scaffold(
      backgroundColor: const Color(0xFFF8F4EE),
      body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(AppColors.primary), strokeWidth: 2.5),
        const SizedBox(height: 20),
        const Text('Opening your book…',
            style: TextStyle(fontFamily: 'DM Sans', color: Color(0xFF6B7080), fontSize: 14)),
      ])));
}

// ─────────────────────────────────────────────────────────────────────────────
// IMAGE PAGE VIEWER
// Horizontal swipe between pages, pinch-to-zoom, page dots, edge tap zones.
// Mirrors how Wattpad handles manga/comic/magazine content.
// ─────────────────────────────────────────────────────────────────────────────

class _ImagePageViewer extends StatefulWidget {
  final List<String> imageUrls;
  final void Function(int page, int total) onPageChanged;
  final VoidCallback onTap;

  // ignore: prefer_const_constructors_in_immutables
  _ImagePageViewer({
    required this.imageUrls,
    required this.onPageChanged,
    required this.onTap,
  });

  @override
  State<_ImagePageViewer> createState() => _ImagePageViewerState();
}

class _ImagePageViewerState extends State<_ImagePageViewer> {
  late final PageController _pageCtrl;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _pageCtrl.animateToPage(page,
        duration: const Duration(milliseconds: 280), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.imageUrls.length;
    return Stack(children: [

      // ── Pages ────────────────────────────────────────────────────────────
      PageView.builder(
        controller: _pageCtrl,
        onPageChanged: (i) {
          setState(() => _current = i);
          widget.onPageChanged(i + 1, total);
        },
        itemCount: total,
        itemBuilder: (_, i) => GestureDetector(
          onTap: widget.onTap,
          child: InteractiveViewer(
            minScale: 1.0,
            maxScale: 4.0,
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: CachedNetworkImage(
                imageUrl: widget.imageUrls[i],
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
                placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white38))),
                errorWidget: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined,
                        size: 52, color: Colors.white24)),
              ),
            ),
          ),
        ),
      ),

      // ── Page indicator dots ───────────────────────────────────────────────
      if (total > 1)
        Positioned(
          bottom: 88, left: 0, right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(total.clamp(0, 20), (i) =>
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _current ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _current ? AppColors.primary : Colors.white.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                )),
          ),
        ),

      // ── Left / Right invisible tap zones (Wattpad-style page turn) ────────
      Positioned(
        left: 0, top: 60, bottom: 72, width: 72,
        child: GestureDetector(
          onTap: () { if (_current > 0) _goTo(_current - 1); },
          child: Container(color: Colors.transparent),
        ),
      ),
      Positioned(
        right: 0, top: 60, bottom: 72, width: 72,
        child: GestureDetector(
          onTap: () { if (_current < total - 1) _goTo(_current + 1); },
          child: Container(color: Colors.transparent),
        ),
      ),

      // ── Current page label (bottom-centre, subtle) ─────────────────────
      Positioned(
        bottom: 72, left: 0, right: 0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
                color: Colors.black54, borderRadius: BorderRadius.circular(12)),
            child: Text('${_current + 1} / $total',
                style: const TextStyle(fontFamily: 'DM Sans',
                    fontSize: 11, color: Colors.white70)),
          ),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REVIEW BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _ReviewSheet extends StatefulWidget {
  final String contentId, title;
  final Future<void> Function(int rating, String text) onSubmit;

  // ignore: prefer_const_constructors_in_immutables
  _ReviewSheet({
    required this.contentId,
    required this.title,
    required this.onSubmit,
  });

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _rating = 5;
  bool _saving = false;
  final _ctrl = TextEditingController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  String get _label => switch (_rating) {
        1 => 'Poor', 2 => 'Fair', 3 => 'Good', 4 => 'Very Good', _ => 'Outstanding'
      };

  @override
  Widget build(BuildContext context) => Container(
      decoration: const BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(
          24, 8, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(2))),
        const Text('Rate This Content',
            style: TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 18,
                fontWeight: FontWeight.w800, color: Color(0xFF111827))),
        const SizedBox(height: 4),
        Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                color: Color(0xFF9CA3AF))),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) => GestureDetector(
              onTap: () => setState(() => _rating = i + 1),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Icon(i < _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 38,
                      color: i < _rating ? const Color(0xFFF59E0B) : const Color(0xFFD1D5DB))),
            ))),
        const SizedBox(height: 6),
        Text(_label, style: TextStyle(fontFamily: 'DM Sans', fontSize: 12,
            fontWeight: FontWeight.w600, color: AppColors.primary)),
        const SizedBox(height: 16),
        TextField(
          controller: _ctrl, maxLines: 4, maxLength: 500,
          style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Share your thoughts…',
            hintStyle: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 13),
            filled: true, fillColor: const Color(0xFFF9FAFB),
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, height: 50,
            child: ElevatedButton(
              onPressed: _saving ? null : () async {
                setState(() => _saving = true);
                try { await widget.onSubmit(_rating, _ctrl.text.trim()); }
                finally { if (mounted) Navigator.pop(context); }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _saving
                  ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(Colors.white)))
                  : const Text('Submit Review',
                  style: TextStyle(fontFamily: 'DM Sans', fontSize: 15,
                      fontWeight: FontWeight.w700)),
            )),
      ]));
}

// ─────────────────────────────────────────────────────────────────────────────
// SETTINGS SUB-WIDGETS
// Non-const constructors required — these hold _ReaderTheme (non-const type).
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsRow extends StatelessWidget {
  final String label;
  final Widget child;
  final _ReaderTheme theme;
  // ignore: prefer_const_constructors_in_immutables
  _SettingsRow({required this.label, required this.child, required this.theme});

  @override
  Widget build(BuildContext context) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
            fontWeight: FontWeight.w600, color: theme.subText)),
        child,
      ]);
}

class _SettingsIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final _ReaderTheme theme;
  // ignore: prefer_const_constructors_in_immutables
  _SettingsIconBtn({required this.icon, required this.onTap, required this.theme});

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(width: 34, height: 34,
          decoration: BoxDecoration(
              color: theme.isDark ? const Color(0xFF2E2E40) : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16,
              color: theme.isDark ? Colors.white : const Color(0xFF374151))));
}

class _FontChip extends StatelessWidget {
  final String label, fontFamily, current;
  final _ReaderTheme theme;
  final VoidCallback onTap;
  // ignore: prefer_const_constructors_in_immutables
  _FontChip({required this.label, required this.fontFamily,
    required this.current, required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sel = current == fontFamily;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? AppColors.primary
              : (theme.isDark ? const Color(0xFF2E2E40) : const Color(0xFFF3F4F6)),
          borderRadius: BorderRadius.circular(8),
          border: sel ? null : Border.all(
              color: theme.isDark ? const Color(0xFF3E3E52) : const Color(0xFFE5E7EB)),
        ),
        child: Text(label, style: TextStyle(fontFamily: fontFamily, fontSize: 12,
            fontWeight: FontWeight.w600,
            color: sel ? Colors.white
                : (theme.isDark ? Colors.white70 : const Color(0xFF374151)))),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  final _ReaderTheme readerTheme;
  final bool selected;
  final VoidCallback onTap;
  // ignore: prefer_const_constructors_in_immutables
  _ThemeSwatch({required this.readerTheme, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: readerTheme.label,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 34, height: 34,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: readerTheme.bg,
            shape: BoxShape.circle,
            border: Border.all(
                color: selected ? AppColors.primary : const Color(0xFFD1D5DB),
                width: selected ? 2.5 : 1.5),
            boxShadow: selected
                ? [BoxShadow(color: AppColors.primary.withOpacity(0.25), blurRadius: 6)]
                : null,
          ),
          child: selected ? Icon(Icons.check_rounded, size: 16, color: AppColors.primary) : null,
        ),
      ));
}