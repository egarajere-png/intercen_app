// lib/pages/publication_requests_page.dart
//
// Admin-only page that mirrors the React/TSX PublicationRequests page exactly.
// Reads from the publications table (or publication_requests_view if available).
// Allows: view all, filter by status, approve, mark under_review, reject,
// view manuscript/cover links. Sends notifications to submitters on action.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/role_service.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _kPrimary  = Color(0xFFB11226);
const _kBg       = Color(0xFFF9F5EF);
const _kWhite    = Colors.white;
const _kBorder   = Color(0xFFE5E7EB);
const _kMuted    = Color(0xFF6B7280);
const _kMutedLt  = Color(0xFF9CA3AF);
const _kGreen    = Color(0xFF16A34A);
const _kGreenBg  = Color(0xFFF0FDF4);
const _kBlue     = Color(0xFF2563EB);
const _kBlueBg   = Color(0xFFEFF6FF);
const _kAmber    = Color(0xFFD97706);
const _kAmberBg  = Color(0xFFFFFBEB);
const _kRed      = Color(0xFFDC2626);
const _kRedBg    = Color(0xFFFEF2F2);

// ─────────────────────────────────────────────────────────────────────────────
class PublicationRequestsPage extends StatefulWidget {
  const PublicationRequestsPage({super.key});
  @override
  State<PublicationRequestsPage> createState() =>
      _PublicationRequestsPageState();
}

class _PublicationRequestsPageState extends State<PublicationRequestsPage> {
  final _sb = Supabase.instance.client;

  List<Map<String, dynamic>> _pubs     = [];
  bool   _loading      = true;
  String _statusFilter = 'all';

  // For the detail sheet
  Map<String, dynamic>? _selected;
  final _feedbackCtrl   = TextEditingController();
  final _adminNotesCtrl = TextEditingController();
  bool  _actionLoading  = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    _adminNotesCtrl.dispose();
    super.dispose();
  }

  // ── Load ──────────────────────────────────────────────────────────────────
  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final data = await _sb
          .from('publications')
          .select('*')
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() =>
          _pubs = List<Map<String, dynamic>>.from(data ?? []));
    } catch (e) {
      _toast('Failed to load: $e', err: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Counts ────────────────────────────────────────────────────────────────
  Map<String, int> get _counts => {
        'all':          _pubs.length,
        'pending':      _pubs.where((p) => p['status'] == 'pending').length,
        'under_review': _pubs.where((p) => p['status'] == 'under_review').length,
        'approved':     _pubs.where((p) => p['status'] == 'approved').length,
        'rejected':     _pubs.where((p) => p['status'] == 'rejected').length,
      };

  List<Map<String, dynamic>> get _filtered => _statusFilter == 'all'
      ? _pubs
      : _pubs.where((p) => p['status'] == _statusFilter).toList();

  // ── Action ────────────────────────────────────────────────────────────────
  Future<void> _updateStatus(String pubId, String newStatus) async {
    setState(() => _actionLoading = true);
    try {
      final uid = RoleService.instance.userId;
      final updates = <String, dynamic>{
        'status':      newStatus,
        'reviewed_by': uid,
        'reviewed_at': DateTime.now().toIso8601String(),
        'admin_notes': _adminNotesCtrl.text.trim().isNotEmpty
            ? _adminNotesCtrl.text.trim()
            : null,
      };
      if (newStatus == 'rejected') {
        updates['rejection_feedback'] =
            _feedbackCtrl.text.trim().isNotEmpty
                ? _feedbackCtrl.text.trim()
                : null;
      }

      await _sb.from('publications').update(updates).eq('id', pubId);

      // Notify submitter
      final submittedBy = _selected?['submitted_by'] as String?;
      final title       = _selected?['title'] as String? ?? 'your manuscript';
      final fb          = _feedbackCtrl.text.trim();

      if (submittedBy != null) {
        final msgs = {
          'approved': {
            'type':    'submission_approved',
            'title':   'Manuscript Approved!',
            'message': 'Congratulations! Your manuscript "$title" has been approved and is now live on Intercen Books.',
          },
          'rejected': {
            'type':    'submission_rejected',
            'title':   'Manuscript Decision',
            'message': 'Your manuscript "$title" was not approved at this time.${fb.isNotEmpty ? ' Feedback: $fb' : ''}',
          },
          'under_review': {
            'type':    'submission_received',
            'title':   'Manuscript Under Review',
            'message': 'Your manuscript "$title" is now under editorial review.',
          },
        };
        final m = msgs[newStatus];
        if (m != null) {
          await _sb.from('notifications').insert({
            'user_id': submittedBy,
            'type':    m['type'],
            'title':   m['title'],
            'message': m['message'],
          });
        }
      }

      setState(() {
        _pubs = _pubs.map((p) =>
            p['id'] == pubId ? {...p, 'status': newStatus} : p).toList();
        _selected = null;
        _feedbackCtrl.clear();
        _adminNotesCtrl.clear();
      });
      _toast('Publication marked as $newStatus');
    } catch (e) {
      _toast('Failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  void _openDetail(Map<String, dynamic> pub) {
    setState(() {
      _selected = pub;
      _feedbackCtrl.text   = pub['rejection_feedback'] as String? ?? '';
      _adminNotesCtrl.text = pub['admin_notes']        as String? ?? '';
    });
  }

  void _toast(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              fontFamily: 'DM Sans', fontWeight: FontWeight.w500)),
      backgroundColor: err ? _kPrimary : _kGreen,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      bottomNavigationBar: _bottomNav(),
      body: Stack(
        children: [
          CustomScrollView(slivers: [
            _appBar(),
            SliverToBoxAdapter(child: _header()),
            SliverToBoxAdapter(child: _filterRow()),
            SliverToBoxAdapter(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 80),
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation(_kPrimary),
                          strokeWidth: 3,
                        ),
                      ),
                    )
                  : _pubList(),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ]),

          // ── Detail sheet overlay ────────────────────────────────────────
          if (_selected != null) _detailSheet(),
        ],
      ),
    );
  }

  // ── App bar ───────────────────────────────────────────────────────────────
  SliverAppBar _appBar() => SliverAppBar(
        pinned: true,
        backgroundColor: const Color(0xFF1A1A2E),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white70, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: _kAmber.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.description_outlined,
                color: _kAmber, size: 16),
          ),
          const SizedBox(width: 10),
          const Text(
            'Publication Requests',
            style: TextStyle(
              fontFamily: 'PlayfairDisplay',
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: _kWhite,
            ),
          ),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: Colors.white70, size: 20),
            onPressed: _load,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
              height: 1, color: Colors.white.withOpacity(0.1)),
        ),
      );

  // ── Page header ───────────────────────────────────────────────────────────
  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _kAmberBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.description_outlined,
                color: _kAmber, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Publication Requests',
                  style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
                Text(
                  'Review and manage manuscript submissions',
                  style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 13,
                      color: _kMuted),
                ),
              ],
            ),
          ),
        ]),
      );

  // ── Filter pills row ──────────────────────────────────────────────────────
  Widget _filterRow() {
    final filters = [
      ('all', 'All'),
      ('pending', 'Pending'),
      ('under_review', 'Under Review'),
      ('approved', 'Approved'),
      ('rejected', 'Rejected'),
    ];
    final counts = _counts;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final active = _statusFilter == f.$1;
            final count  = counts[f.$1] ?? 0;
            return GestureDetector(
              onTap: () => setState(() => _statusFilter = f.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? _kPrimary : _kWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: active ? _kPrimary : _kBorder),
                  boxShadow: active
                      ? [
                          BoxShadow(
                              color: _kPrimary.withOpacity(0.2),
                              blurRadius: 6,
                              offset: const Offset(0, 2))
                        ]
                      : [],
                ),
                child: Text(
                  '${f.$2} ($count)',
                  style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: active ? _kWhite : _kMuted,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Publication list ──────────────────────────────────────────────────────
  Widget _pubList() {
    final filtered = _filtered;
    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined,
                  size: 56,
                  color: _kMutedLt.withOpacity(0.5)),
              const SizedBox(height: 16),
              const Text(
                'No submissions found',
                style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'No manuscript submissions match this filter.',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 13,
                    color: _kMutedLt),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _pubCard(filtered[i]),
      ),
    );
  }

  Widget _pubCard(Map<String, dynamic> pub) {
    final status = pub['status'] as String? ?? 'pending';
    final title  = pub['title']  as String? ?? '—';
    final author = pub['author_name'] as String? ?? '—';
    final type   = pub['publishing_type'] as String? ?? '';
    final date   = _date(pub['created_at']);

    return GestureDetector(
      onTap: () => _openDetail(pub),
      child: Container(
        decoration: BoxDecoration(
          color: _kWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorder),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'PlayfairDisplay',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusPill(status),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    'By $author',
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 13,
                        color: _kMuted),
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    if (type.isNotEmpty)
                      _metaChip(
                          '${type[0].toUpperCase()}${type.substring(1)} Publishing'),
                    _metaChip('Submitted $date'),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _kBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBorder),
              ),
              child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Icon(Icons.visibility_outlined,
                    size: 14, color: _kMuted),
                SizedBox(width: 4),
                Text('Review',
                    style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _kMuted,
                    )),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Detail sheet (Stack overlay, not Dialog) ──────────────────────────────
  Widget _detailSheet() {
    final pub    = _selected!;
    final status = pub['status'] as String? ?? 'pending';
    final isApproved = status == 'approved';
    final canAct = status == 'pending' || status == 'under_review';

    return GestureDetector(
      onTap: () => setState(() {
        _selected = null;
        _feedbackCtrl.clear();
        _adminNotesCtrl.clear();
      }),
      child: Container(
        color: Colors.black.withOpacity(0.5),
        child: Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () {}, // prevent closing when tapping sheet
            child: Container(
              width: MediaQuery.of(context).size.width *
                  (MediaQuery.of(context).size.width >= 600 ? 0.55 : 1.0),
              height: double.infinity,
              color: _kWhite,
              child: Column(children: [
                // Sheet header
                Container(
                  padding: EdgeInsets.fromLTRB(
                      20,
                      MediaQuery.of(context).padding.top + 16,
                      12,
                      16),
                  decoration: const BoxDecoration(
                    color: _kWhite,
                    border: Border(bottom: BorderSide(color: _kBorder)),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pub['title'] as String? ?? '—',
                            style: const TextStyle(
                              fontFamily: 'PlayfairDisplay',
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if ((pub['subtitle'] as String? ?? '')
                              .isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              pub['subtitle'] as String,
                              style: const TextStyle(
                                  fontFamily: 'DM Sans',
                                  fontSize: 13,
                                  color: _kMuted),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: _kMuted),
                      onPressed: () => setState(() {
                        _selected = null;
                        _feedbackCtrl.clear();
                        _adminNotesCtrl.clear();
                      }),
                    ),
                  ]),
                ),

                // Sheet body
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Status badge
                        _StatusPill(status),
                        const SizedBox(height: 16),

                        // Author meta
                        _sheetSection('Author Details', [
                          _metaRow(Icons.person_outline,
                              pub['author_name'] as String? ?? '—'),
                          _metaRow(Icons.email_outlined,
                              pub['author_email'] as String? ?? '—'),
                          if ((pub['author_phone'] as String? ?? '')
                              .isNotEmpty)
                            _metaRow(Icons.phone_outlined,
                                pub['author_phone'] as String),
                          _metaRow(Icons.calendar_today_outlined,
                              'Submitted ${_date(pub['created_at'])}'),
                        ]),
                        const SizedBox(height: 16),

                        // Book details
                        _sheetSection('Manuscript Details', [
                          if ((pub['publishing_type'] as String? ?? '')
                              .isNotEmpty)
                            _metaRow(Icons.auto_stories_outlined,
                                '${pub['publishing_type']} publishing'),
                          if ((pub['language'] as String? ?? '')
                              .isNotEmpty)
                            _metaRow(Icons.language_outlined,
                                pub['language'] as String),
                          if (pub['pages'] != null)
                            _metaRow(Icons.menu_book_outlined,
                                '${pub['pages']} pages'),
                          if ((pub['isbn'] as String? ?? '')
                              .isNotEmpty)
                            _metaRow(Icons.bookmark_outline,
                                'ISBN: ${pub['isbn']}'),
                          if ((pub['target_audience'] as String? ?? '')
                              .isNotEmpty)
                            _metaRow(Icons.group_outlined,
                                'Audience: ${pub['target_audience']}'),
                        ]),

                        // Description
                        if ((pub['description'] as String? ?? '')
                            .isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _sheetLabel('Description'),
                          const SizedBox(height: 6),
                          Text(
                            pub['description'] as String,
                            style: const TextStyle(
                                fontFamily: 'DM Sans',
                                fontSize: 13,
                                color: _kMuted,
                                height: 1.5),
                          ),
                        ],

                        // Files
                        const SizedBox(height: 16),
                        Row(children: [
                          if ((pub['manuscript_file_url']
                                  as String? ??
                              '').isNotEmpty)
                            _fileBtn(
                              'View Manuscript',
                              Icons.description_outlined,
                              pub['manuscript_file_url'] as String,
                            ),
                          const SizedBox(width: 8),
                          if ((pub['cover_image_url']
                                  as String? ??
                              '').isNotEmpty)
                            _fileBtn(
                              'View Cover',
                              Icons.image_outlined,
                              pub['cover_image_url'] as String,
                            ),
                        ]),

                        // Admin notes
                        const SizedBox(height: 20),
                        _sheetLabel('Admin Notes (internal)'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _adminNotesCtrl,
                          maxLines: 2,
                          enabled: !isApproved,
                          style: const TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 13,
                              color: Color(0xFF111827)),
                          decoration: InputDecoration(
                            hintText:
                                'Internal notes about this submission…',
                            hintStyle: const TextStyle(
                                fontFamily: 'DM Sans',
                                fontSize: 13,
                                color: _kMutedLt),
                            border: _inputBorder(),
                            enabledBorder: _inputBorder(),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: _kPrimary, width: 1.5),
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF9FAFB),
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),

                        // Rejection feedback
                        if (!isApproved) ...[
                          const SizedBox(height: 14),
                          _sheetLabel(
                              'Rejection Feedback (sent to author)'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _feedbackCtrl,
                            maxLines: 3,
                            style: const TextStyle(
                                fontFamily: 'DM Sans',
                                fontSize: 13,
                                color: Color(0xFF111827)),
                            decoration: InputDecoration(
                              hintText:
                                  'Explain why this manuscript wasn\'t accepted…',
                              hintStyle: const TextStyle(
                                  fontFamily: 'DM Sans',
                                  fontSize: 13,
                                  color: _kMutedLt),
                              border: _inputBorder(),
                              enabledBorder: _inputBorder(),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: _kRed, width: 1.5),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF9FAFB),
                              contentPadding: const EdgeInsets.all(12),
                            ),
                          ),
                        ],

                        // Approved message
                        if (isApproved) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _kGreenBg,
                              border: Border.all(
                                  color: const Color(0xFFBBF7D0)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(children: [
                              const Icon(Icons.check_circle_rounded,
                                  color: _kGreen, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Approved and published on ${_date(pub['reviewed_at'])}',
                                  style: const TextStyle(
                                      fontFamily: 'DM Sans',
                                      fontSize: 13,
                                      color: _kGreen,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ]),
                          ),
                        ],

                        // Action buttons
                        if (!isApproved && canAct) ...[
                          const SizedBox(height: 24),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            if (status == 'pending')
                              _actionBtn(
                                label: 'Mark Under Review',
                                icon: Icons.access_time_rounded,
                                color: _kBlue,
                                bg: _kBlueBg,
                                onTap: () => _updateStatus(
                                    pub['id'] as String,
                                    'under_review'),
                              ),
                            _actionBtn(
                              label: 'Approve & Publish',
                              icon: Icons.check_circle_outline_rounded,
                              color: _kGreen,
                              bg: _kGreenBg,
                              onTap: () => _updateStatus(
                                  pub['id'] as String, 'approved'),
                            ),
                            if (status != 'rejected')
                              _actionBtn(
                                label: 'Reject',
                                icon: Icons.cancel_outlined,
                                color: _kRed,
                                bg: _kRedBg,
                                onTap: () => _updateStatus(
                                    pub['id'] as String, 'rejected'),
                              ),
                          ]),
                        ],

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── Small helpers ─────────────────────────────────────────────────────────
  Widget _sheetSection(String title, List<Widget> rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sheetLabel(title),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder),
            ),
            child: Column(children: rows),
          ),
        ],
      );

  Widget _sheetLabel(String t) => Text(
        t,
        style: const TextStyle(
          fontFamily: 'DM Sans',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF111827),
        ),
      );

  Widget _metaRow(IconData icon, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, size: 15, color: _kMutedLt),
          const SizedBox(width: 10),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 13,
                    color: _kMuted)),
          ),
        ]),
      );

  Widget _metaChip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 11,
                color: _kMuted)),
      );

  Widget _fileBtn(String label, IconData icon, String url) =>
      OutlinedButton.icon(
        icon: Icon(icon, size: 14),
        label: Text(label,
            style: const TextStyle(
                fontFamily: 'DM Sans', fontSize: 12)),
        onPressed: () async {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) await launchUrl(uri);
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: _kMuted,
          side: const BorderSide(color: _kBorder),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
          textStyle:
              const TextStyle(fontFamily: 'DM Sans', fontSize: 12),
        ),
      );

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required Color color,
    required Color bg,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: _actionLoading ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: color.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: _actionLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: color))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 15, color: color),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color,
                      )),
                ]),
        ),
      );

  OutlineInputBorder _inputBorder() => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _kBorder),
      );

  String _date(dynamic raw) {
    if (raw == null) return '—';
    try {
      final d = DateTime.parse(raw as String).toLocal();
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return '—';
    }
  }

  // ── Bottom nav ────────────────────────────────────────────────────────────
  Widget _bottomNav() => Container(
        height: 64,
        decoration: BoxDecoration(
          color: _kWhite,
          border: const Border(top: BorderSide(color: _kBorder)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(Icons.home_outlined, 'Home', false,
                () => Navigator.pushNamedAndRemoveUntil(
                    context, '/home', (r) => false)),
            _navItem(Icons.menu_book_outlined, 'Books', false,
                () => Navigator.pushNamed(context, '/books')),
            _navItem(Icons.upload_outlined, 'Upload', false,
                () => Navigator.pushNamed(context, '/upload')),
            _navItem(Icons.admin_panel_settings_outlined, 'Admin',
                true,
                () => Navigator.pushNamed(context, '/dashboard/admin')),
          ],
        ),
      );

  Widget _navItem(
      IconData icon, String label, bool active, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: active ? _kPrimary : Colors.grey, size: 22),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 11,
                  color: active ? _kPrimary : Colors.grey,
                  fontWeight: active
                      ? FontWeight.w700
                      : FontWeight.normal,
                )),
          ],
        ),
      );
}

// ── Status pill ───────────────────────────────────────────────────────────────
class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill(this.status);

  Color get _color => switch (status) {
        'approved'     => _kGreen,
        'rejected'     => _kRed,
        'under_review' => _kBlue,
        'pending'      => _kAmber,
        _              => _kMuted,
      };

  Color get _bg => switch (status) {
        'approved'     => _kGreenBg,
        'rejected'     => _kRedBg,
        'under_review' => _kBlueBg,
        'pending'      => _kAmberBg,
        _              => const Color(0xFFF3F4F6),
      };

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _bg,
          border: Border.all(color: _color.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          status.replaceAll('_', ' '),
          style: TextStyle(
            fontFamily: 'DM Sans',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _color,
          ),
        ),
      );
}