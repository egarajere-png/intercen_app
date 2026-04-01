// lib/pages/dashboard/admin_dashboard.dart
// ─────────────────────────────────────────────────────────────────────────────
// Full corrected admin dashboard — translated from TSX + AdminWithdrawals.tsx
//
//  ✅ No window.confirm/alert — uses custom on-screen ConfirmDialog overlay
//  ✅ Withdrawals tab — AdminWithdrawals integrated inline
//  ✅ Pending withdrawals badge on tab + alert banner
//  ✅ Content publish/unpublish works + records notification
//  ✅ Dynamic Publish/Unpublish button on each content item
//  ✅ Content delete with confirm dialog
//  ✅ Content grid + list view modes
//  ✅ Toggle featured on content
//  ✅ Order status update + payment status update + records notification
//  ✅ Order notes save
//  ✅ Bulk order select + bulk status update + bulk delete
//  ✅ Order items expand/collapse
//  ✅ Publication approve / reject / under_review + admin notes
//  ✅ Publish approved manuscript as live content (edge function)
//  ✅ User role change + active toggle
//  ✅ Profile edit with avatar
//  ✅ initialTab support via route arguments
//  ✅ FIXED: .eq() called before .order()/.limit() (postgrest v2.x)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/role_service.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _kPrimary    = Color(0xFFB11226);
const _kCharcoal   = Color(0xFF1A1A2E);
const _kBg         = Color(0xFFF9F5EF);
const _kWhite      = Colors.white;
const _kBorder     = Color(0xFFE5E7EB);
const _kMuted      = Color(0xFF6B7280);
const _kMutedLt    = Color(0xFF9CA3AF);
const _kGreen      = Color(0xFF16A34A);
const _kGreenBg    = Color(0xFFF0FDF4);
const _kAmber      = Color(0xFFD97706);
const _kAmberBg    = Color(0xFFFFFBEB);
const _kBlue       = Color(0xFF2563EB);
const _kBlueBg     = Color(0xFFEFF6FF);
const _kPurple     = Color(0xFF7C3AED);
const _kPurpleBg   = Color(0xFFF5F3FF);
const _kRed        = Color(0xFFDC2626);
const _kRedBg      = Color(0xFFFEF2F2);
const _kEmerald    = Color(0xFF059669);
const _kEmeraldBg  = Color(0xFFECFDF5);
const _kOrange     = Color(0xFFEA580C);
const _kOrangeBg   = Color(0xFFFFF7ED);
const _kCard       = 12.0;
const _kMaxBio     = 500;
const _kMaxName    = 100;
const _kMaxAvat    = 5 * 1024 * 1024;

const _adminIds = {
  '5fbc35df-ae08-4f8a-b0b3-dd6bb4610ebd',
  'e2925b0b-c730-484c-b4f1-1361380bccd3',
};

const _roles = [
  'reader', 'author', 'publisher', 'editor',
  'moderator', 'admin', 'corporate_user',
];

const _orderStatuses  = ['pending', 'processing', 'shipped', 'delivered', 'completed', 'cancelled'];
const _paymentStatuses = ['pending', 'paid', 'failed', 'refunded'];
const _contentTypes   = ['book', 'ebook', 'document', 'paper', 'report', 'manual', 'guide'];

// ── Confirm dialog options ───────────────────────────────────────────────────
class _ConfirmOpts {
  final String title, description;
  final String confirmLabel;
  final bool destructive;
  final VoidCallback onConfirm;
  const _ConfirmOpts({
    required this.title,
    required this.description,
    this.confirmLabel = 'Confirm',
    this.destructive = false,
    required this.onConfirm,
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// PAGE
// ═════════════════════════════════════════════════════════════════════════════
class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({Key? key}) : super(key: key);
  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final _sb = Supabase.instance.client;

  // ── data ──────────────────────────────────────────────────────────────────
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _users         = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  List<Map<String, dynamic>> _publications  = [];
  List<Map<String, dynamic>> _contents      = [];
  List<Map<String, dynamic>> _orders        = [];

  // orders expansion + items
  String?                              _expandedOrderId;
  Map<String, List<Map<String,dynamic>>> _orderItemsMap = {};
  Set<String>                          _selectedOrders = {};
  Map<String, String>                  _orderNotes     = {};
  String?                              _updatingOrderId;
  String?                              _deletingOrderId;

  // content
  bool   _contentLoading        = false;
  String _contentSearch         = '';
  String _contentStatusFilter   = 'all';
  String _contentTypeFilter     = 'all';
  bool   _contentGridMode       = true;
  String? _publishingContentId;
  String? _deletingContentId;

  // publications
  String  _pubStatusFilter    = 'all';
  bool    _processingPub      = false;
  String? _deletingPubId;
  String? _publishingAsContentId;
  String? _editingNotesPubId;
  Map<String, dynamic>? _rejectTarget;
  final _feedbackCtrl   = TextEditingController();
  final _adminNotesCtrl = TextEditingController();
  bool _savingNotes = false;

  // orders filter
  String _orderStatusFilter  = 'all';
  String _orderPaymentFilter = 'all';
  String _orderSearch        = '';

  // users
  final _searchCtrl = TextEditingController();
  String _savingRole = '';

  // withdrawals
  List<Map<String, dynamic>> _withdrawals         = [];
  bool   _wdLoading                               = true;
  String _wdStatusFilter                          = 'all';
  String? _wdProcessingId;
  String? _wdConfirmId;
  String? _wdExpandedId;
  Map<String, String> _wdAdminNotes               = {};
  int    _pendingWithdrawalsCount                 = 0;

  // stats
  int    _statUsers   = 0;
  int    _statContent = 0;
  int    _statPending = 0;
  int    _statOrders  = 0;
  double _revenue     = 0;
  bool   _loading     = true;

  // profile
  final _nameCtrl = TextEditingController();
  final _bioCtrl  = TextEditingController();
  final _telCtrl  = TextEditingController();
  final _adrCtrl  = TextEditingController();
  final _orgCtrl  = TextEditingController();
  final _dptCtrl  = TextEditingController();
  String? _avatarUrl;
  File?   _avatarFile;
  String? _avatarB64;
  bool    _saving = false;

  // confirm dialog
  _ConfirmOpts? _confirmOpts;

  // active tab
  // 0=Users 1=Submissions 2=Content 3=Orders 4=Withdrawals 5=MyProfile
  int _tab = 2;

  // ── lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _bioCtrl.addListener(() => setState(() {}));
    _searchCtrl.addListener(_filterUsers);
    _loadAll();
    _loadContent();
    _loadWithdrawals();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        final t = args['initialTab'];
        if (t is int && mounted) setState(() => _tab = t);
      }
    });
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _bioCtrl, _telCtrl, _adrCtrl,
      _orgCtrl, _dptCtrl, _feedbackCtrl, _adminNotesCtrl, _searchCtrl,
    ]) c.dispose();
    super.dispose();
  }

  void _filterUsers() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filteredUsers = q.isEmpty
          ? List.from(_users)
          : _users.where((u) {
              return (u['full_name'] as String? ?? '').toLowerCase().contains(q) ||
                     (u['email']    as String? ?? '').toLowerCase().contains(q) ||
                     (u['role']     as String? ?? '').toLowerCase().contains(q);
            }).toList();
    });
  }

  // ── confirm dialog helper ─────────────────────────────────────────────────
  void _confirm(_ConfirmOpts opts) => setState(() => _confirmOpts = opts);
  void _dismissConfirm()           => setState(() => _confirmOpts = null);

  // ── load orders ───────────────────────────────────────────────────────────
  // FIX: .eq() must be called BEFORE .order()/.limit() in postgrest v2.x
  Future<void> _loadOrders() async {
    if (!mounted) return;
    try {
      List raw;

      var q = _sb.from('orders').select(
        'id,order_number,status,payment_status,payment_method,'
        'total_price,discount,tax,currency,created_at,user_id,notes,'
        'shipping_address,billing_address,payment_reference,paid_at,'
        'completed_at,cancelled_at,'
        'customer:profiles(full_name,email,avatar_url)',
      );

      if (_orderStatusFilter != 'all' && _orderPaymentFilter != 'all') {
        raw = await q
            .eq('status', _orderStatusFilter)
            .eq('payment_status', _orderPaymentFilter)
            .order('created_at', ascending: false)
            .limit(150);
      } else if (_orderStatusFilter != 'all') {
        raw = await q
            .eq('status', _orderStatusFilter)
            .order('created_at', ascending: false)
            .limit(150);
      } else if (_orderPaymentFilter != 'all') {
        raw = await q
            .eq('payment_status', _orderPaymentFilter)
            .order('created_at', ascending: false)
            .limit(150);
      } else {
        raw = await q
            .order('created_at', ascending: false)
            .limit(150);
      }

      if (!mounted) return;
      final ords = _asList(raw);
      setState(() {
        _orders     = ords;
        _statOrders = ords.length;
        _revenue    = ords
            .where((o) => o['payment_status'] == 'paid')
            .fold(0.0, (s, o) => s + (_dbl(o['total_price'])));
      });
    } catch (e) {
      _toast('Failed to load orders: $e', err: true);
    }
  }

  // ── load publications ─────────────────────────────────────────────────────
  Future<void> _loadPublications() async {
    try {
      final raw  = await _sb
          .from('publication_requests_view')
          .select('*')
          .order('created_at', ascending: false);
      final pubs = _asList(raw);
      if (mounted) setState(() {
        _publications = pubs;
        _statPending  = pubs.where((p) => p['status'] == 'pending').length;
      });
    } catch (e) {
      _toast('Failed to reload submissions: $e', err: true);
    }
  }

  // ── edge function caller ──────────────────────────────────────────────────
  Future<Map<String, dynamic>> _callEdge(String name, Map<String, dynamic> body) async {
    final session = _sb.auth.currentSession;
    if (session == null) throw Exception('Not authenticated');
    final res = await _sb.functions.invoke(name, body: body);
    if (res.status != null && res.status! >= 400) {
      final err = res.data is Map ? (res.data['error'] ?? 'Edge function failed') : 'Edge function failed';
      throw Exception(err);
    }
    return Map<String, dynamic>.from(res.data as Map? ?? {});
  }

  // ── load all ──────────────────────────────────────────────────────────────
  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final uid = RoleService.instance.userId;

      final profileRaw = await _sb
          .from('profiles')
          .select('*')
          .eq('id', uid)
          .maybeSingle();
      final p = profileRaw as Map<String, dynamic>?;

      final usersRaw = await _sb
          .from('profiles')
          .select('*')
          .order('created_at', ascending: false);
      final users = _asList(usersRaw);

      final pubsRaw = await _sb
          .from('publication_requests_view')
          .select('*')
          .order('created_at', ascending: false);
      final pubs = _asList(pubsRaw);

      final wdRaw = await _sb
          .from('withdrawal_requests')
          .select('id')
          .eq('status', 'pending');
      final wdCount = _asList(wdRaw).length;

      if (!mounted) return;

      setState(() {
        _profile       = p;
        _avatarUrl     = p?['avatar_url'] as String?;
        _nameCtrl.text = (p?['full_name']    as String?) ?? '';
        _bioCtrl.text  = (p?['bio']          as String?) ?? '';
        _telCtrl.text  = (p?['phone']        as String?) ?? '';
        _adrCtrl.text  = (p?['address']      as String?) ?? '';
        _orgCtrl.text  = (p?['organization'] as String?) ?? '';
        _dptCtrl.text  = (p?['department']   as String?) ?? '';
        _users                   = users;
        _filteredUsers           = List.from(users);
        _publications            = pubs;
        _statUsers               = users.length;
        _statPending             = pubs.where((x) => x['status'] == 'pending').length;
        _pendingWithdrawalsCount = wdCount;
      });

      await Future.wait<void>([_loadContent(), _loadOrders()]);
    } catch (e) {
      _toast('Load failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── load content ──────────────────────────────────────────────────────────
  // FIX: .eq() must be called BEFORE .order()/.limit() in postgrest v2.x
  Future<void> _loadContent() async {
    if (!mounted) return;
    setState(() => _contentLoading = true);
    try {
      var q = _sb.from('content').select(
        'id,title,subtitle,author,content_type,status,cover_image_url,'
        'price,is_free,is_featured,is_for_sale,language,visibility,uploaded_by,content_owner,'
        'average_rating,total_reviews,view_count,total_downloads,created_at,updated_at,published_at',
      );

      List raw;
      if (_contentStatusFilter != 'all' && _contentTypeFilter != 'all') {
        raw = await q
            .eq('status', _contentStatusFilter)
            .eq('content_type', _contentTypeFilter)
            .order('created_at', ascending: false)
            .limit(200);
      } else if (_contentStatusFilter != 'all') {
        raw = await q
            .eq('status', _contentStatusFilter)
            .order('created_at', ascending: false)
            .limit(200);
      } else if (_contentTypeFilter != 'all') {
        raw = await q
            .eq('content_type', _contentTypeFilter)
            .order('created_at', ascending: false)
            .limit(200);
      } else {
        raw = await q
            .order('created_at', ascending: false)
            .limit(200);
      }

      if (!mounted) return;
      setState(() {
        _contents    = _asList(raw);
        _statContent = _contents.length;
      });
    } catch (e) {
      _toast('Failed to load content: $e', err: true);
    } finally {
      if (mounted) setState(() => _contentLoading = false);
    }
  }

  // ── load withdrawals ──────────────────────────────────────────────────────
  Future<void> _loadWithdrawals({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _wdLoading = true);
    try {
      final wrData = await _sb.from('withdrawal_requests')
          .select('*, author:profiles!withdrawal_requests_author_id_fkey(full_name,email,avatar_url)')
          .order('created_at', ascending: false);

      final rows = _asList(wrData);
      if (rows.isEmpty) {
        if (mounted) setState(() { _withdrawals = []; _wdLoading = false; });
        return;
      }

      final authorIds = rows.map((w) => w['author_id'] as String).toSet().toList();
      final walletData = await _sb.from('author_wallets')
          .select('author_id,available_balance,total_earned,commission_rate')
          .inFilter('author_id', authorIds);

      final walletMap = <String, Map<String, dynamic>>{};
      for (final w in _asList(walletData)) {
        walletMap[w['author_id'] as String] = {
          'available_balance': double.tryParse(w['available_balance']?.toString() ?? '0') ?? 0.0,
          'total_earned':      double.tryParse(w['total_earned']?.toString() ?? '0') ?? 0.0,
          'commission_rate':   double.tryParse(w['commission_rate']?.toString() ?? '0') ?? 0.0,
        };
      }

      final merged = rows.map((w) => {
        ...w,
        'amount': double.tryParse(w['amount']?.toString() ?? '0') ?? 0.0,
        'wallet': walletMap[w['author_id'] as String],
      }).toList();

      if (mounted) setState(() {
        _withdrawals = merged;
        _pendingWithdrawalsCount = merged.where((w) => w['status'] == 'pending').length;
        _wdLoading = false;
      });
    } catch (e) {
      if (!silent) _toast('Failed to load withdrawals: $e', err: true);
      if (mounted) setState(() => _wdLoading = false);
    }
  }

  // ── load order items ──────────────────────────────────────────────────────
  Future<void> _loadOrderItems(String orderId) async {
    if (_orderItemsMap.containsKey(orderId)) return;
    try {
      final data = await _sb.from('order_items')
          .select('*, content(title,cover_image_url,content_type)')
          .eq('order_id', orderId);
      if (mounted) setState(() => _orderItemsMap[orderId] = _asList(data));
    } catch (_) {}
  }

  List<Map<String, dynamic>> _asList(dynamic raw) =>
      List<Map<String, dynamic>>.from((raw as List?) ?? []);

  // ── content actions ───────────────────────────────────────────────────────
  Future<void> _publishContent(String contentId, String action) async {
    setState(() => _publishingContentId = contentId);
    try {
      await _callEdge('content-publish', {
        'content_id': contentId, 'action': action, 'send_notification': false,
      });
      final newStatus = action == 'publish' ? 'published' : 'archived';
      final item = _contents.firstWhere((c) => c['id'] == contentId, orElse: () => {});
      setState(() {
        _contents = _contents.map((c) =>
            c['id'] == contentId ? {...c, 'status': newStatus} : c).toList();
      });
      final notifyUserId = item['content_owner'] ?? item['uploaded_by'];
      if (notifyUserId != null) {
        final notifType = action == 'publish' ? 'content_published' : 'content_unpublished';
        await _sb.from('notifications').insert({
          'user_id':    notifyUserId,
          'type':       notifType,
          'title':      action == 'publish' ? 'Content Published' : 'Content Unpublished',
          'message':    action == 'publish'
              ? 'Your content "${item['title']}" has been published and is now live.'
              : 'Your content "${item['title']}" has been unpublished and archived.',
          'content_id': contentId,
          'read':       false,
        });
        try {
          await _callEdge('send-content-status-email', {
            'content_id': contentId, 'action': action, 'content_title': item['title'],
          });
        } catch (_) {}
      }
      _toast(action == 'publish' ? 'Content published' : 'Content unpublished');
    } catch (e) {
      _toast('Action failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _publishingContentId = null);
    }
  }

  Future<void> _doDeleteContent(String contentId) async {
    setState(() => _deletingContentId = contentId);
    try {
      final result = await _callEdge('content-delete', {'content_id': contentId});
      setState(() {
        if (result['action'] == 'deleted') {
          _contents = _contents.where((c) => c['id'] != contentId).toList();
          _statContent = _contents.length;
        } else {
          _contents = _contents.map((c) =>
              c['id'] == contentId ? {...c, 'status': 'archived'} : c).toList();
        }
      });
      _toast(result['action'] == 'deleted' ? 'Content deleted' : 'Content archived (has purchases)');
    } catch (e) {
      _toast('Delete failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _deletingContentId = null);
    }
  }

  Future<void> _toggleFeatured(String contentId, bool current) async {
    try {
      await _sb.from('content').update({
        'is_featured': !current, 'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', contentId);
      setState(() {
        _contents = _contents.map((c) =>
            c['id'] == contentId ? {...c, 'is_featured': !current} : c).toList();
      });
      _toast(!current ? 'Marked as featured' : 'Removed from featured');
    } catch (e) {
      _toast('Failed: $e', err: true);
    }
  }

  // ── order actions ─────────────────────────────────────────────────────────
  Future<void> _updateOrderStatus(String orderId, String newStatus) async {
    setState(() => _updatingOrderId = orderId);
    final updates = <String, dynamic>{
      'status': newStatus, 'updated_at': DateTime.now().toIso8601String(),
    };
    if (newStatus == 'completed') updates['completed_at'] = DateTime.now().toIso8601String();
    if (newStatus == 'cancelled') updates['cancelled_at'] = DateTime.now().toIso8601String();
    try {
      await _sb.from('orders').update(updates).eq('id', orderId);
      final order = _orders.firstWhere((o) => o['id'] == orderId, orElse: () => {});
      setState(() {
        _orders = _orders.map((o) => o['id'] == orderId ? {...o, ...updates} : o).toList();
      });
      final userId = order['user_id'] as String?;
      if (userId != null) {
        final notifType = (newStatus == 'completed' || newStatus == 'delivered')
            ? 'order_completed' : 'general';
        final num = order['order_number'] ?? orderId.substring(0, 8);
        final statusMsgs = {
          'pending':    'Your order #$num has been received and is pending processing.',
          'processing': 'Your order #$num is now being processed.',
          'shipped':    'Your order #$num has been shipped!',
          'delivered':  'Your order #$num has been delivered.',
          'completed':  'Your order #$num is complete. Thank you!',
          'cancelled':  'Your order #$num has been cancelled.',
        };
        await _sb.from('notifications').insert({
          'user_id': userId, 'type': notifType,
          'title':   'Order ${newStatus[0].toUpperCase()}${newStatus.substring(1)}',
          'message': statusMsgs[newStatus] ?? 'Your order status is now "$newStatus".',
          'read':    false,
          'metadata': {'order_id': orderId, 'new_status': newStatus},
        });
        try {
          await _callEdge('send-order-status-email', {'order_id': orderId, 'new_status': newStatus});
        } catch (_) {}
      }
      _toast('Order status → $newStatus');
    } catch (e) {
      _toast('Update failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _updatingOrderId = null);
    }
  }

  Future<void> _updatePaymentStatus(String orderId, String newPayment) async {
    setState(() => _updatingOrderId = orderId);
    final updates = <String, dynamic>{
      'payment_status': newPayment, 'updated_at': DateTime.now().toIso8601String(),
    };
    if (newPayment == 'paid') updates['paid_at'] = DateTime.now().toIso8601String();
    try {
      await _sb.from('orders').update(updates).eq('id', orderId);
      final order = _orders.firstWhere((o) => o['id'] == orderId, orElse: () => {});
      setState(() {
        _orders = _orders.map((o) => o['id'] == orderId ? {...o, ...updates} : o).toList();
      });
      if (newPayment == 'paid' && order['user_id'] != null) {
        final num = order['order_number'] ?? orderId.substring(0, 8);
        await _sb.from('notifications').insert({
          'user_id': order['user_id'], 'type': 'purchase_confirmed',
          'title': 'Payment Confirmed',
          'message': 'Payment for order #$num has been confirmed. Thank you!',
          'read': false,
        });
      }
      _toast('Payment status → $newPayment');
    } catch (e) {
      _toast('Update failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _updatingOrderId = null);
    }
  }

  Future<void> _doDeleteOrder(String orderId, String orderNumber) async {
    setState(() => _deletingOrderId = orderId);
    try {
      await _sb.from('orders').delete().eq('id', orderId);
      setState(() {
        _orders = _orders.where((o) => o['id'] != orderId).toList();
        _selectedOrders.remove(orderId);
        _statOrders = _orders.length;
      });
      _toast('Order #$orderNumber deleted');
    } catch (e) {
      _toast('Delete failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _deletingOrderId = null);
    }
  }

  Future<void> _saveOrderNote(String orderId) async {
    final note = _orderNotes[orderId];
    if (note == null) return;
    try {
      await _sb.from('orders').update({
        'notes': note, 'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', orderId);
      setState(() {
        _orders = _orders.map((o) => o['id'] == orderId ? {...o, 'notes': note} : o).toList();
      });
      _toast('Note saved');
    } catch (e) {
      _toast('Failed to save note: $e', err: true);
    }
  }

  Future<void> _doBulkUpdateOrderStatus(String newStatus) async {
    final ids = _selectedOrders.toList();
    final updates = <String, dynamic>{
      'status': newStatus, 'updated_at': DateTime.now().toIso8601String(),
    };
    if (newStatus == 'completed') updates['completed_at'] = DateTime.now().toIso8601String();
    if (newStatus == 'cancelled') updates['cancelled_at'] = DateTime.now().toIso8601String();
    try {
      await _sb.from('orders').update(updates).inFilter('id', ids);
      setState(() {
        _orders = _orders.map((o) =>
            _selectedOrders.contains(o['id']) ? {...o, ...updates} : o).toList();
        _selectedOrders.clear();
      });
      _toast('${ids.length} orders updated to "$newStatus"');
    } catch (e) {
      _toast('Bulk update failed: $e', err: true);
    }
  }

  Future<void> _doBulkDeleteOrders() async {
    final ids = _selectedOrders.toList();
    try {
      await _sb.from('orders').delete().inFilter('id', ids);
      setState(() {
        _orders = _orders.where((o) => !_selectedOrders.contains(o['id'])).toList();
        _selectedOrders.clear();
        _statOrders = _orders.length;
      });
      _toast('${ids.length} orders deleted');
    } catch (e) {
      _toast('Bulk delete failed: $e', err: true);
    }
  }

  // ── publication actions ───────────────────────────────────────────────────
  Future<void> _pubAction(String pubId, String action) async {
    setState(() => _processingPub = true);
    try {
      final updates = <String, dynamic>{
        'status': action,
        'reviewed_by': RoleService.instance.userId,
        'reviewed_at': DateTime.now().toIso8601String(),
      };
      if (action == 'rejected') updates['rejection_feedback'] = _feedbackCtrl.text.trim();
      await _sb.from('publications').update(updates).eq('id', pubId);

      final pub = _publications.firstWhere((p) => p['id'] == pubId, orElse: () => {});
      final submittedBy = pub['submitted_by'] as String?;
      if (submittedBy != null) {
        final fb = _feedbackCtrl.text.trim();
        final notifType = action == 'approved'
            ? 'submission_approved'
            : action == 'rejected' ? 'submission_rejected' : 'general';
        final msgs = {
          'approved':     'Congratulations! Your manuscript "${pub['title']}" has been approved.',
          'rejected':     'Your manuscript "${pub['title']}" was not approved.'
              '${fb.isNotEmpty ? ' Feedback: $fb' : ''}',
          'under_review': 'Your manuscript "${pub['title']}" is now under review.',
        };
        final titles = {
          'approved':     'Manuscript Approved! 🎉',
          'rejected':     'Submission Decision',
          'under_review': 'Manuscript Under Review',
        };
        await _sb.from('notifications').insert({
          'user_id': submittedBy,
          'type':    notifType,
          'title':   titles[action],
          'message': msgs[action],
          'read':    false,
          'metadata': {'publication_id': pubId, 'title': pub['title']},
        });
      }
      setState(() {
        _publications = _publications
            .map((p) => p['id'] == pubId ? {...p, ...updates} : p).toList();
        _statPending  = _publications.where((p) => p['status'] == 'pending').length;
        _rejectTarget = null;
        _feedbackCtrl.clear();
      });
      _toast('Publication marked as $action');
    } catch (e) {
      _toast('Failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _processingPub = false);
    }
  }

  Future<void> _doDeletePublication(String pubId) async {
    setState(() => _deletingPubId = pubId);
    try {
      await _sb.from('publications').delete().eq('id', pubId);
      setState(() => _publications = _publications.where((p) => p['id'] != pubId).toList());
      _toast('Submission deleted');
    } catch (e) {
      _toast('Delete failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _deletingPubId = null);
    }
  }

  Future<void> _saveAdminNotes(String pubId) async {
    setState(() => _savingNotes = true);
    try {
      final notes = _adminNotesCtrl.text.trim();
      await _sb.from('publications').update({
        'admin_notes': notes, 'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', pubId);
      setState(() {
        _publications = _publications
            .map((p) => p['id'] == pubId ? {...p, 'admin_notes': notes} : p).toList();
        _editingNotesPubId = null;
        _adminNotesCtrl.clear();
      });
      _toast('Admin notes saved');
    } catch (e) {
      _toast('Failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _savingNotes = false);
    }
  }

  Future<void> _doPublishManuscript(Map<String, dynamic> pub) async {
    setState(() => _publishingAsContentId = pub['id'] as String);
    try {
      final result = await _callEdge('publication-publish', {'publication_id': pub['id']});
      try {
        await _callEdge('send-content-status-email', {
          'content_id': result['content_id'], 'action': 'publish', 'content_title': pub['title'],
        });
      } catch (_) {}
      _toast('Manuscript published as live content!');
      _loadContent();
    } catch (e) {
      _toast('Publish failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _publishingAsContentId = null);
    }
  }

  // ── user actions ──────────────────────────────────────────────────────────
  Future<void> _changeRole(String targetId, String newRole) async {
    if (_adminIds.contains(targetId) && newRole != 'admin') {
      _toast('Protected admin — role cannot be changed.', err: true); return;
    }
    setState(() => _savingRole = targetId);
    try {
      await _sb.from('profiles').update({
        'role': newRole, 'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', targetId);
      await _sb.from('notifications').insert({
        'user_id': targetId, 'type': 'role_changed',
        'title':   'Your Account Role Has Been Updated',
        'message': 'An administrator has updated your role to "$newRole".',
        'read':    false, 'metadata': {'new_role': newRole},
      });
      setState(() {
        _users = _users.map((u) =>
            u['id'] == targetId ? {...u, 'role': newRole} : u).toList();
        _filteredUsers = _filteredUsers.map((u) =>
            u['id'] == targetId ? {...u, 'role': newRole} : u).toList();
      });
      _toast('Role updated to $newRole');
    } catch (e) {
      _toast('Failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _savingRole = '');
    }
  }

  Future<void> _toggleActive(String targetId, bool current) async {
    if (_adminIds.contains(targetId)) {
      _toast('Protected admins cannot be deactivated.', err: true); return;
    }
    try {
      await _sb.from('profiles').update({'is_active': !current}).eq('id', targetId);
      setState(() {
        _users = _users.map((u) =>
            u['id'] == targetId ? {...u, 'is_active': !current} : u).toList();
        _filteredUsers = _filteredUsers.map((u) =>
            u['id'] == targetId ? {...u, 'is_active': !current} : u).toList();
      });
    } catch (e) {
      _toast('Failed: $e', err: true);
    }
  }

  // ── withdrawal actions ────────────────────────────────────────────────────
  Future<void> _processWithdrawal(String withdrawalId) async {
    setState(() { _wdProcessingId = withdrawalId; _wdConfirmId = null; });
    try {
      final res = await _callEdge('admin-process-withdrawal', {
        'withdrawal_id': withdrawalId,
        if (_wdAdminNotes[withdrawalId] != null && _wdAdminNotes[withdrawalId]!.isNotEmpty)
          'admin_notes': _wdAdminNotes[withdrawalId],
      });
      _toast('M-Pesa B2C initiated. Conv ID: ${res['conversation_id'] ?? '—'}');
      await _loadWithdrawals(silent: true);
    } catch (e) {
      _toast('Failed to process: $e', err: true);
    } finally {
      if (mounted) setState(() => _wdProcessingId = null);
    }
  }

  // ── profile ───────────────────────────────────────────────────────────────
  Future<void> _pickAvatar() async {
    final p = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (p == null) return;
    final f = File(p.path);
    final b = await f.readAsBytes();
    if (b.lengthInBytes > _kMaxAvat) { _toast('Image must be ≤ 5 MB', err: true); return; }
    setState(() { _avatarFile = f; _avatarB64 = base64Encode(b); });
  }

  ImageProvider? get _avatarImg {
    if (_avatarFile != null) return FileImage(_avatarFile!);
    if (_avatarUrl != null && _avatarUrl!.isNotEmpty)
      return CachedNetworkImageProvider(_avatarUrl!);
    return null;
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      final uid = RoleService.instance.userId;
      final u = <String, dynamic>{
        if (_nameCtrl.text.trim().isNotEmpty) 'full_name':    _nameCtrl.text.trim(),
        if (_bioCtrl.text.trim().isNotEmpty)  'bio':          _bioCtrl.text.trim(),
        if (_telCtrl.text.trim().isNotEmpty)  'phone':        _telCtrl.text.trim(),
        if (_adrCtrl.text.trim().isNotEmpty)  'address':      _adrCtrl.text.trim(),
        if (_orgCtrl.text.trim().isNotEmpty)  'organization': _orgCtrl.text.trim(),
        if (_dptCtrl.text.trim().isNotEmpty)  'department':   _dptCtrl.text.trim(),
      };
      final payload = Map<String, dynamic>.from(u);
      if (_avatarB64 != null) payload['avatar_base64'] = _avatarB64;
      await _callEdge('profile-info-edit', payload);
      final fresh = await _sb.from('profiles').select('*').eq('id', uid).maybeSingle();
      setState(() {
        _profile    = fresh;
        _avatarUrl  = fresh?['avatar_url'] as String?;
        _avatarFile = null;
        _avatarB64  = null;
      });
      _toast('Profile saved');
    } catch (e) {
      _toast('Save failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    await _sb.auth.signOut();
    RoleService.instance.clear();
    if (mounted) Navigator.pushReplacementNamed(context, '/onboarding');
  }

  void _toast(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w500)),
      backgroundColor: err ? _kPrimary : _kGreen,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
  }

  // ── derived helpers ───────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filteredContent {
    final q = _contentSearch.toLowerCase();
    if (q.isEmpty) return _contents;
    return _contents.where((c) =>
        (c['title']        as String? ?? '').toLowerCase().contains(q) ||
        (c['author']       as String? ?? '').toLowerCase().contains(q) ||
        (c['content_type'] as String? ?? '').toLowerCase().contains(q) ||
        (c['language']     as String? ?? '').toLowerCase().contains(q)).toList();
  }

  List<Map<String, dynamic>> get _filteredOrders {
    final q = _orderSearch.toLowerCase();
    var list = _orders;
    if (_orderStatusFilter  != 'all') list = list.where((o) => o['status']         == _orderStatusFilter).toList();
    if (_orderPaymentFilter != 'all') list = list.where((o) => o['payment_status'] == _orderPaymentFilter).toList();
    if (q.isEmpty) return list;
    return list.where((o) =>
        (o['order_number']      as String? ?? '').toLowerCase().contains(q) ||
        (o['payment_reference'] as String? ?? '').toLowerCase().contains(q) ||
        (o['status']            as String? ?? '').toLowerCase().contains(q) ||
        (o['notes']             as String? ?? '').toLowerCase().contains(q)).toList();
  }

  List<Map<String, dynamic>> get _filteredPubs {
    if (_pubStatusFilter == 'all') return _publications;
    return _publications.where((p) => p['status'] == _pubStatusFilter).toList();
  }

  List<Map<String, dynamic>> get _filteredWithdrawals {
    if (_wdStatusFilter == 'all') return _withdrawals;
    return _withdrawals.where((w) => w['status'] == _wdStatusFilter).toList();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_loading) return _loadingScreen();
    final w = MediaQuery.of(context).size.width;
    final pendingPubs = _publications.where((p) => p['status'] == 'pending').toList();

    return Scaffold(
      backgroundColor: _kBg,
      bottomNavigationBar: _bottomNav(),
      body: Stack(
        children: [
          CustomScrollView(
            physics: const ClampingScrollPhysics(),
            slivers: [
              _appBar(w),
              SliverToBoxAdapter(child: _heroBanner(w)),
              SliverToBoxAdapter(child: _statsRow(w)),
              if (pendingPubs.isNotEmpty)
                SliverToBoxAdapter(child: _pendingAlert(pendingPubs.length, w)),
              if (_pendingWithdrawalsCount > 0)
                SliverToBoxAdapter(child: _withdrawalAlert(_pendingWithdrawalsCount, w)),
              SliverToBoxAdapter(child: _tabRow(w)),
              SliverToBoxAdapter(child: _tabBody(w)),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
          if (_rejectTarget != null) _RejectOverlay(
            pub: _rejectTarget!,
            ctrl: _feedbackCtrl,
            processing: _processingPub,
            onConfirm: () => _pubAction(_rejectTarget!['id'] as String, 'rejected'),
            onCancel: () => setState(() { _rejectTarget = null; _feedbackCtrl.clear(); }),
          ),
          if (_confirmOpts != null) _ConfirmDialogOverlay(
            opts: _confirmOpts!,
            onDismiss: () => setState(() => _confirmOpts = null),
          ),
        ],
      ),
    );
  }

  Widget _loadingScreen() => Scaffold(
        backgroundColor: _kBg,
        body: const Center(
          child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(_kPrimary)),
        ),
      );

  SliverAppBar _appBar(double w) => SliverAppBar(
        pinned: true, elevation: 0,
        backgroundColor: _kCharcoal,
        surfaceTintColor: Colors.transparent,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white70),
                onPressed: () => Navigator.pop(context))
            : null,
        title: Row(children: [
          const Icon(Icons.shield_rounded, color: _kRed, size: 18),
          const SizedBox(width: 8),
          Text('Admin Panel', style: TextStyle(
            color: _kWhite, fontWeight: FontWeight.w800,
            fontFamily: 'PlayfairDisplay', fontSize: w < 360 ? 16 : 18)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_rounded, color: Colors.white70, size: 22),
            tooltip: 'Upload Content',
            onPressed: () => Navigator.pushNamed(context, '/upload'),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white54, size: 20),
            onPressed: _signOut,
          ),
        ],
      );

  Widget _heroBanner(double w) {
    final pad   = _hp(w);
    final name  = _nameCtrl.text.isNotEmpty
        ? _nameCtrl.text : (_profile?['full_name'] as String? ?? 'Administrator');
    final initL = name.isNotEmpty ? name[0].toUpperCase() : 'A';
    final email = _profile?['email'] as String? ?? 'Administration Panel';
    return Container(
      color: _kCharcoal,
      padding: EdgeInsets.fromLTRB(pad, 16, pad, 20),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Stack(children: [
          GestureDetector(
            onTap: _pickAvatar,
            child: CircleAvatar(
              radius: 30,
              backgroundColor: _kRed.withOpacity(0.2),
              backgroundImage: _avatarImg,
              child: _avatarImg == null
                  ? Text(initL, style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold,
                      color: _kRed, fontFamily: 'PlayfairDisplay'))
                  : null,
            ),
          ),
          Positioned(bottom: 0, right: 0,
            child: Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                color: _kRed, shape: BoxShape.circle,
                border: Border.all(color: _kCharcoal, width: 2)),
              child: const Icon(Icons.shield_rounded, size: 10, color: _kWhite),
            )),
        ]),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(name, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'PlayfairDisplay',
                    fontSize: 18, fontWeight: FontWeight.w700, color: _kWhite))),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _kRed.withOpacity(0.2), borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kRed.withOpacity(0.4))),
              child: const Text('ADMIN', style: TextStyle(
                  fontFamily: 'DM Sans', fontSize: 10, fontWeight: FontWeight.w800,
                  color: Color(0xFFFCA5A5))),
            ),
          ]),
          const SizedBox(height: 2),
          Text(email, style: const TextStyle(fontFamily: 'DM Sans', fontSize: 12, color: Colors.white54),
              overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }

  Widget _statsRow(double w) {
    final pad  = _hp(w);
    final cols = w >= 700 ? 5 : 3;
    final stats = [
      _StatData('Total Users',    '$_statUsers',                Icons.people_outline,       _kBlue,    _kBlueBg),
      _StatData('Content Items',  '$_statContent',              Icons.book_outlined,         _kGreen,   _kGreenBg),
      _StatData('Pending Review', '$_statPending',              Icons.access_time_rounded,   _kAmber,   _kAmberBg),
      _StatData('Orders',         '$_statOrders',               Icons.shopping_bag_outlined, _kPurple,  _kPurpleBg),
      _StatData('Revenue (KES)',  _revenue.toStringAsFixed(0),  Icons.trending_up_rounded,   _kEmerald, _kEmeraldBg),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 0),
      child: GridView.count(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: cols, crossAxisSpacing: 10, mainAxisSpacing: 10,
        childAspectRatio: w < 400 ? 1.5 : 1.8,
        children: stats.map((s) => _StatCard(s)).toList(),
      ),
    );
  }

  Widget _pendingAlert(int count, double w) {
    final pad = _hp(w);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 16, pad, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kAmberBg, border: Border.all(color: const Color(0xFFFDE68A)),
          borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: _kAmber, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(
            '$count manuscript${count > 1 ? 's' : ''} awaiting review',
            style: const TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w600,
                fontSize: 13, color: Color(0xFF92400E)))),
          GestureDetector(
            onTap: () => setState(() => _tab = 1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: _kAmber, borderRadius: BorderRadius.circular(8)),
              child: const Text('Review Now', style: TextStyle(
                  fontFamily: 'DM Sans', fontSize: 12, fontWeight: FontWeight.w700, color: _kWhite)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _withdrawalAlert(int count, double w) {
    final pad = _hp(w);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 10, pad, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kGreenBg, border: Border.all(color: const Color(0xFFBBF7D0)),
          borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.account_balance_wallet_outlined, color: _kGreen, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(
            '$count author withdrawal${count > 1 ? 's' : ''} awaiting payment',
            style: const TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w600,
                fontSize: 13, color: Color(0xFF14532D)))),
          GestureDetector(
            onTap: () => setState(() => _tab = 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: _kGreen, borderRadius: BorderRadius.circular(8)),
              child: const Text('Process Now', style: TextStyle(
                  fontFamily: 'DM Sans', fontSize: 12, fontWeight: FontWeight.w700, color: _kWhite)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _tabRow(double w) {
    final pad = _hp(w);
    final pending  = _publications.where((p) => p['status'] == 'pending').length;
    final wdPend   = _pendingWithdrawalsCount;
    final tabs = [
      (Icons.people_outline,               'Users'),
      (Icons.description_outlined,         'Submissions${pending > 0 ? ' ($pending)' : ''}'),
      (Icons.book_outlined,                'Content'),
      (Icons.shopping_bag_outlined,        'Orders'),
      (Icons.account_balance_wallet_outlined, 'Withdrawals${wdPend > 0 ? ' ($wdPend)' : ''}'),
      (Icons.person_outline,               'My Profile'),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 24, pad, 0),
      child: Container(
        decoration: BoxDecoration(
          color: _kMuted.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.all(4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(tabs.length, (i) {
              final active = _tab == i;
              return GestureDetector(
                onTap: () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(right: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: active ? _kPrimary : Colors.transparent,
                    borderRadius: BorderRadius.circular(7)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(tabs[i].$1, size: 15, color: active ? _kWhite : _kMuted),
                    const SizedBox(width: 6),
                    Text(tabs[i].$2, style: TextStyle(
                        fontFamily: 'DM Sans', fontSize: 13,
                        fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                        color: active ? _kWhite : _kMuted)),
                  ]),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _tabBody(double w) {
    final pad = _hp(w);
    Widget body;
    switch (_tab) {
      case 0:  body = _usersTab(w);       break;
      case 1:  body = _submissionsTab(w); break;
      case 2:  body = _contentTab(w);     break;
      case 3:  body = _ordersTab(w);      break;
      case 4:  body = _withdrawalsTab(w); break;
      default: body = _profileTab(w);
    }
    return Padding(padding: EdgeInsets.fromLTRB(pad, 20, pad, 0), child: body);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 0 – USERS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _usersTab(double w) => _WCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Wrap(spacing: 12, runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text('User Management', style: TextStyle(
                  fontFamily: 'PlayfairDisplay', fontSize: 18,
                  fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
              SizedBox(width: 220, height: 38,
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(fontFamily: 'DM Sans', fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search users…',
                    hintStyle: const TextStyle(fontFamily: 'DM Sans', fontSize: 13, color: _kMutedLt),
                    prefixIcon: const Icon(Icons.search, size: 16, color: _kMutedLt),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _kBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _kBorder)),
                    filled: true, fillColor: _kWhite),
                )),
              _SmallBtn(label: 'Refresh', icon: Icons.refresh_rounded, onTap: _loadAll),
            ]),
          ),
          const Divider(height: 1, color: _kBorder),
          if (_filteredUsers.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: Text('No users found.',
                  style: TextStyle(fontFamily: 'DM Sans', color: _kMutedLt, fontSize: 14))))
          else
            ListView.separated(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              itemCount: _filteredUsers.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: _kBorder),
              itemBuilder: (_, i) => _userRow(_filteredUsers[i]),
            ),
        ]),
      );

  Widget _userRow(Map<String, dynamic> u) {
    final isProtected = _adminIds.contains(u['id'] as String?);
    final role        = u['role'] as String? ?? 'reader';
    final isActive    = u['is_active'] != false;
    final name        = u['full_name'] as String? ?? '—';
    final email       = u['email'] as String? ?? ((u['id'] as String).substring(0, 12) + '…');
    final avatarUrl   = u['avatar_url'] as String?;
    final initial     = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final acctType    = u['account_type'] as String? ?? 'personal';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(width: 38, height: 38,
          child: ClipOval(child: avatarUrl != null && avatarUrl.isNotEmpty
              ? CachedNetworkImage(imageUrl: avatarUrl, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _initAvatar(initial))
              : _initAvatar(initial))),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(name, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w600,
                    fontSize: 13, color: Color(0xFF1F2937)))),
            if (isProtected) ...[const SizedBox(width: 4), const Icon(Icons.shield_rounded, size: 13, color: _kRed)],
          ]),
          Text(email, style: const TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: _kMutedLt),
              overflow: TextOverflow.ellipsis),
        ])),
        const SizedBox(width: 8),
        Flexible(
          child: isProtected
              ? _RolePill('admin', _roleColor('admin'))
              : _RoleDropdown(value: role, saving: _savingRole == u['id'],
                  onChanged: (r) => _changeRole(u['id'] as String, r ?? role)),
        ),
        const SizedBox(width: 8),
        if (MediaQuery.of(context).size.width >= 600)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(acctType,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: _kMutedLt)))),
        GestureDetector(
          onTap: isProtected ? null : () => _toggleActive(u['id'] as String, isActive),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isActive ? _kGreenBg : _kRedBg, borderRadius: BorderRadius.circular(6)),
            child: Text(isActive ? 'Active' : 'Inactive', style: TextStyle(
                fontFamily: 'DM Sans', fontSize: 10, fontWeight: FontWeight.w700,
                color: isActive ? _kGreen : _kRed)),
          ),
        ),
      ]),
    );
  }

  Widget _initAvatar(String i) => Container(color: const Color(0xFFE5E7EB),
      child: Center(child: Text(i, style: const TextStyle(
          fontFamily: 'DM Sans', fontWeight: FontWeight.w700, fontSize: 15, color: _kMuted))));

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1 – SUBMISSIONS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _submissionsTab(double w) {
    final filtered = _filteredPubs;
    return Column(children: [
      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in ['all', 'pending', 'under_review', 'approved', 'rejected'])
            _FilterChip(
              label: s == 'all' ? 'All (${_publications.length})' : s.replaceAll('_', ' '),
              active: _pubStatusFilter == s,
              onTap: () => setState(() => _pubStatusFilter = s),
            ),
        ]),
        _SmallBtn(label: 'Refresh', icon: Icons.refresh_rounded, onTap: () async {
          setState(() => _loading = true);
          final data = await _sb.from('publication_requests_view')
              .select('*').order('created_at', ascending: false);
          if (mounted) setState(() { _publications = _asList(data); _loading = false; });
        }),
      ]),
      const SizedBox(height: 16),
      if (filtered.isEmpty)
        _WCard(child: Padding(padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.description_outlined, size: 48, color: _kMutedLt.withOpacity(0.5)),
            const SizedBox(height: 12),
            Text(_pubStatusFilter == 'all' ? 'No submissions yet.' : 'No ${_pubStatusFilter.replaceAll('_', ' ')} submissions.',
                style: const TextStyle(fontFamily: 'DM Sans', color: _kMutedLt, fontSize: 14)),
          ]))))
      else
        ListView.separated(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _subCard(filtered[i]),
        ),
    ]);
  }

  Widget _subCard(Map<String, dynamic> pub) {
    final status = pub['status'] as String? ?? 'pending';
    final canAct = status == 'pending' || status == 'under_review';
    final isEditingNotes = _editingNotesPubId == pub['id'];
    final isPublishingThis = _publishingAsContentId == pub['id'];
    final isDeletingThis = _deletingPubId == pub['id'];

    return _WCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (pub['cover_image_url'] != null) ...[
          ClipRRect(borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: pub['cover_image_url'] as String,
              width: 56, height: 80, fit: BoxFit.cover)),
          const SizedBox(width: 12),
        ],
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(pub['title'] as String? ?? '—', style: const TextStyle(
                fontFamily: 'PlayfairDisplay', fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
            _StatusPill(status),
          ]),
          const SizedBox(height: 4),
          Text(
            'By ${pub['author_name'] ?? '—'}'
            '${pub['publishing_type'] != null ? '  ·  ${pub['publishing_type']} publishing' : ''}',
            style: const TextStyle(fontFamily: 'DM Sans', fontSize: 12, color: _kMuted)),
          if ((pub['description'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(pub['description'] as String, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'DM Sans', fontSize: 12, color: _kMutedLt)),
          ],
          const SizedBox(height: 6),
          Wrap(spacing: 12, runSpacing: 4, children: [
            if (pub['language'] != null) _metaTag(pub['language'] as String),
            if (pub['pages'] != null) _metaTag('${pub['pages']} pages'),
            _metaTag('Submitted ${_date(pub['created_at'])}'),
            if (pub['reviewed_at'] != null) _metaTag('Reviewed ${_date(pub['reviewed_at'])}'),
          ]),
        ])),
      ]),

      if (canAct) ...[
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _ActionBtn(label: 'Approve', icon: Icons.check_circle_outline,
              color: _kGreen, onTap: () => _pubAction(pub['id'] as String, 'approved'))),
          const SizedBox(width: 8),
          Expanded(child: _ActionBtn(label: 'Review', icon: Icons.access_time_rounded,
              color: _kBlue, onTap: () => _pubAction(pub['id'] as String, 'under_review'))),
          const SizedBox(width: 8),
          Expanded(child: _ActionBtn(label: 'Reject', icon: Icons.cancel_outlined,
              color: _kRed, onTap: () => setState(() => _rejectTarget = pub))),
        ]),
      ],

      if (status == 'approved') ...[
        const SizedBox(height: 12),
        SizedBox(width: double.infinity,
          child: ElevatedButton.icon(
            icon: isPublishingThis
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _kWhite))
                : const Icon(Icons.rocket_launch_rounded, size: 15),
            label: Text(isPublishingThis ? 'Publishing…' : 'Publish Live',
                style: const TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary, foregroundColor: _kWhite, elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 10)),
            onPressed: isPublishingThis ? null : () => _confirm(_ConfirmOpts(
              title: 'Publish as Live Content',
              description: 'Publish "${pub['title']}" as live content? This will notify the author.',
              confirmLabel: 'Publish Live',
              onConfirm: () => _doPublishManuscript(pub),
            )),
          )),
      ],

      const SizedBox(height: 10),
      Row(children: [
        _SmallBtn(
          label: isEditingNotes ? 'Cancel Notes' : 'Admin Notes',
          icon: Icons.sticky_note_2_outlined,
          onTap: () {
            setState(() {
              if (isEditingNotes) { _editingNotesPubId = null; _adminNotesCtrl.clear(); }
              else { _editingNotesPubId = pub['id'] as String; _adminNotesCtrl.text = pub['admin_notes'] as String? ?? ''; }
            });
          },
        ),
        const SizedBox(width: 8),
        _SmallBtn(
          label: isDeletingThis ? 'Deleting…' : 'Delete',
          icon: Icons.delete_outline,
          onTap: isDeletingThis ? () {} : () => _confirm(_ConfirmOpts(
            title: 'Delete Submission',
            description: 'Delete "${pub['title']}"? This cannot be undone.',
            confirmLabel: 'Delete', destructive: true,
            onConfirm: () => _doDeletePublication(pub['id'] as String),
          )),
        ),
      ]),

      if (isEditingNotes) ...[
        const SizedBox(height: 10),
        TextField(
          controller: _adminNotesCtrl, maxLines: 3,
          style: const TextStyle(fontFamily: 'DM Sans', fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Add internal notes…',
            hintStyle: const TextStyle(fontFamily: 'DM Sans', color: _kMutedLt, fontSize: 13),
            filled: true, fillColor: const Color(0xFFF9FAFB),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kBorder)),
            contentPadding: const EdgeInsets.all(12)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          ElevatedButton(
            onPressed: _savingNotes ? null : () => _saveAdminNotes(pub['id'] as String),
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: _kWhite,
                elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
            child: Text(_savingNotes ? 'Saving…' : 'Save Notes',
                style: const TextStyle(fontFamily: 'DM Sans', fontSize: 12))),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => setState(() { _editingNotesPubId = null; _adminNotesCtrl.clear(); }),
            style: OutlinedButton.styleFrom(foregroundColor: _kMuted,
                side: const BorderSide(color: _kBorder),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'DM Sans', fontSize: 12))),
        ]),
      ],

      if ((pub['admin_notes'] as String? ?? '').isNotEmpty && !isEditingNotes) ...[
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.sticky_note_2_outlined, size: 13, color: _kMutedLt),
          const SizedBox(width: 4),
          Flexible(child: Text(pub['admin_notes'] as String,
              style: const TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: _kMutedLt,
                  fontStyle: FontStyle.italic))),
        ]),
      ],

      if ((pub['rejection_feedback'] as String? ?? '').isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: _kRedBg, border: Border.all(color: const Color(0xFFFECACA)),
              borderRadius: BorderRadius.circular(8)),
          child: RichText(text: TextSpan(style: const TextStyle(fontFamily: 'DM Sans', fontSize: 12, color: _kRed),
            children: [
              const TextSpan(text: 'Feedback: ', style: TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: pub['rejection_feedback'] as String),
            ])),
        ),
      ],
    ]));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2 – CONTENT
  // ══════════════════════════════════════════════════════════════════════════
  Widget _contentTab(double w) {
    final fc = _filteredContent;
    return Column(children: [
      _WCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween, children: [
          SizedBox(width: 220, height: 38,
            child: TextField(
              onChanged: (v) => setState(() => _contentSearch = v),
              style: const TextStyle(fontFamily: 'DM Sans', fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search title, author…',
                hintStyle: const TextStyle(fontFamily: 'DM Sans', fontSize: 13, color: _kMutedLt),
                prefixIcon: const Icon(Icons.search, size: 16, color: _kMutedLt),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _kBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _kBorder)),
                filled: true, fillColor: _kWhite),
            )),
           Wrap(spacing: 8, runSpacing: 8, children: [
  Container(
    decoration: BoxDecoration(
      border: Border.all(color: _kBorder),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        onTap: () => setState(() => _contentGridMode = true),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: _contentGridMode ? _kPrimary : Colors.transparent,
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
          ),
          child: Icon(Icons.grid_view_rounded, size: 15,
              color: _contentGridMode ? _kWhite : _kMuted),
        ),
      ),
      GestureDetector(
        onTap: () => setState(() => _contentGridMode = false),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: !_contentGridMode ? _kPrimary : Colors.transparent,
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
          ),
          child: Icon(Icons.view_list_rounded, size: 15,
              color: !_contentGridMode ? _kWhite : _kMuted),
        ),
      ),
    ]),
  ),
  _SmallBtn(label: '', icon: Icons.refresh_rounded, onTap: _loadContent),
  _SmallBtn(label: 'New', icon: Icons.add_rounded,
      onTap: () => Navigator.pushNamed(context, '/upload')),
]),
        ]),
        const SizedBox(height: 10),
        SingleChildScrollView(scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final s in ['all', 'published', 'draft', 'archived', 'pending_review'])
              Padding(padding: const EdgeInsets.only(right: 6),
                child: _FilterChip(
                  label: s == 'all' ? 'All' : s.replaceAll('_', ' '),
                  active: _contentStatusFilter == s,
                  onTap: () { setState(() => _contentStatusFilter = s); _loadContent(); },
                )),
          ])),
        const SizedBox(height: 8),
        SizedBox(width: 180,
          child: DropdownButtonFormField<String>(
            value: _contentTypeFilter,
            isDense: true,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kBorder)),
              filled: true, fillColor: _kWhite),
            style: const TextStyle(fontFamily: 'DM Sans', fontSize: 12, color: Color(0xFF1F2937)),
            onChanged: (v) { setState(() => _contentTypeFilter = v ?? 'all'); _loadContent(); },
            items: [const DropdownMenuItem(value: 'all', child: Text('All types')),
              ..._contentTypes.map((t) => DropdownMenuItem(value: t, child: Text(t)))],
          )),
        const SizedBox(height: 8),
        Text('Showing ${fc.length} of ${_contents.length} items',
            style: const TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: _kMutedLt)),
      ])),
      const SizedBox(height: 12),
      if (_contentLoading)
        const Padding(padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(_kPrimary))))
      else if (fc.isEmpty)
        _WCard(child: Padding(padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.library_books_outlined, size: 48, color: _kMutedLt.withOpacity(0.5)),
            const SizedBox(height: 12),
            const Text('No content found.', style: TextStyle(fontFamily: 'DM Sans', color: _kMutedLt, fontSize: 14)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.upload_rounded, size: 14),
              label: const Text('Upload Content', style: TextStyle(fontFamily: 'DM Sans')),
              style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: _kWhite,
                  elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () => Navigator.pushNamed(context, '/upload')),
          ]))))
      else if (_contentGridMode)
        GridView.builder(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: w >= 900 ? 6 : w >= 700 ? 5 : w >= 500 ? 4 : w >= 360 ? 3 : 2,
            crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.58),
          itemCount: fc.length,
          itemBuilder: (_, i) => _ContentGridCard(
            item: fc[i],
            publishingId: _publishingContentId,
            deletingId: _deletingContentId,
            onView: (id) => Navigator.pushNamed(context, '/content/$id'),
            onEdit: (id) => Navigator.pushNamed(context, '/content/update/$id'),
            onToggleFeatured: (id, cur) => _toggleFeatured(id, cur),
            onPublish: (id, act) => _publishContent(id, act),
            onDelete: (id, title) => _confirm(_ConfirmOpts(
              title: 'Delete Content', destructive: true,
              description: 'Delete "$title"? Items with existing orders will be archived.',
              confirmLabel: 'Delete', onConfirm: () => _doDeleteContent(id),
            )),
          ))
      else
        _WCard(padding: EdgeInsets.zero,
          child: ListView.separated(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            itemCount: fc.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: _kBorder),
            itemBuilder: (_, i) => _ContentListRow(
              item: fc[i],
              publishingId: _publishingContentId,
              deletingId: _deletingContentId,
              onView: (id) => Navigator.pushNamed(context, '/content/$id'),
              onEdit: (id) => Navigator.pushNamed(context, '/content/update/$id'),
              onToggleFeatured: (id, cur) => _toggleFeatured(id, cur),
              onPublish: (id, act) => _publishContent(id, act),
              onDelete: (id, title) => _confirm(_ConfirmOpts(
                title: 'Delete Content', destructive: true,
                description: 'Delete "$title"? Items with existing orders will be archived.',
                confirmLabel: 'Delete', onConfirm: () => _doDeleteContent(id),
              )),
            ))),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 3 – ORDERS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _ordersTab(double w) {
    final fo = _filteredOrders;
    return Column(children: [
      _WCard(child: Column(children: [
        SizedBox(height: 38, child: TextField(
          onChanged: (v) => setState(() => _orderSearch = v),
          style: const TextStyle(fontFamily: 'DM Sans', fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Search order #, status, notes…',
            hintStyle: const TextStyle(fontFamily: 'DM Sans', fontSize: 13, color: _kMutedLt),
            prefixIcon: const Icon(Icons.search, size: 16, color: _kMutedLt),
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
            filled: true, fillColor: _kWhite),
        )),
        const SizedBox(height: 10),
        SingleChildScrollView(scrollDirection: Axis.horizontal,
          child: Row(children: [
            Padding(padding: const EdgeInsets.only(right: 6),
              child: _FilterChip(label: 'All (${_orders.length})', active: _orderStatusFilter == 'all',
                  onTap: () { setState(() => _orderStatusFilter = 'all'); })),
            for (final s in _orderStatuses)
              Padding(padding: const EdgeInsets.only(right: 6),
                child: _FilterChip(label: s, active: _orderStatusFilter == s,
                    onTap: () => setState(() => _orderStatusFilter = s))),
          ])),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(width: 160,
            child: DropdownButtonFormField<String>(
              value: _orderPaymentFilter, isDense: true,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
                filled: true, fillColor: _kWhite),
              style: const TextStyle(fontFamily: 'DM Sans', fontSize: 12, color: Color(0xFF1F2937)),
              onChanged: (v) => setState(() => _orderPaymentFilter = v ?? 'all'),
              items: [const DropdownMenuItem(value: 'all', child: Text('All payments')),
                ..._paymentStatuses.map((s) => DropdownMenuItem(value: s, child: Text(s)))],
            )),
          const Spacer(),
          _SmallBtn(label: 'Refresh', icon: Icons.refresh_rounded, onTap: _loadAll),
        ]),
        if (_selectedOrders.isNotEmpty) ...[
          const Divider(height: 16, color: _kBorder),
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${_selectedOrders.length} selected', style: const TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w700, fontSize: 13)),
            const Text('Bulk → ', style: TextStyle(fontFamily: 'DM Sans', fontSize: 12, color: _kMutedLt)),
            for (final s in _orderStatuses)
              GestureDetector(
                onTap: () => _confirm(_ConfirmOpts(
                  title: 'Bulk Update ${_selectedOrders.length} Orders',
                  description: 'Set all ${_selectedOrders.length} orders to "$s"?',
                  confirmLabel: 'Update All',
                  onConfirm: () => _doBulkUpdateOrderStatus(s),
                )),
                child: _StatusPill(s)),
            GestureDetector(
              onTap: () => _confirm(_ConfirmOpts(
                title: 'Delete ${_selectedOrders.length} Orders', destructive: true,
                description: 'Permanently delete ${_selectedOrders.length} orders? Cannot be undone.',
                confirmLabel: 'Delete All', onConfirm: _doBulkDeleteOrders,
              )),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: _kRedBg, borderRadius: BorderRadius.circular(6)),
                child: const Text('Delete all', style: TextStyle(fontFamily: 'DM Sans', fontSize: 10, fontWeight: FontWeight.w700, color: _kRed)))),
            TextButton(onPressed: () => setState(() => _selectedOrders.clear()),
              child: const Text('Clear selection', style: TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: _kMutedLt))),
          ]),
        ],
      ])),
      const SizedBox(height: 12),
      if (fo.isEmpty)
        _WCard(child: Padding(padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.shopping_bag_outlined, size: 48, color: _kMutedLt.withOpacity(0.5)),
            const SizedBox(height: 12),
            const Text('No orders found.', style: TextStyle(fontFamily: 'DM Sans', color: _kMutedLt, fontSize: 14)),
          ]))))
      else
        ListView.separated(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          itemCount: fo.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _orderCard(fo[i]),
        ),
    ]);
  }

  Widget _orderCard(Map<String, dynamic> order) {
    final orderId    = order['id'] as String;
    final isExpanded = _expandedOrderId == orderId;
    final isSelected = _selectedOrders.contains(orderId);
    final isUpdating = _updatingOrderId == orderId;
    final isDeleting = _deletingOrderId == orderId;
    final num        = order['order_number'] ?? orderId.substring(0, 8);
    final status     = order['status'] as String? ?? 'pending';
    final payStatus  = order['payment_status'] as String? ?? 'pending';

    return _WCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        Padding(padding: const EdgeInsets.all(14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2),
            child: GestureDetector(
              onTap: () => setState(() {
                if (isSelected) _selectedOrders.remove(orderId);
                else _selectedOrders.add(orderId);
              }),
              child: Container(width: 18, height: 18,
                decoration: BoxDecoration(
                  border: Border.all(color: isSelected ? _kPrimary : _kBorder, width: 1.5),
                  borderRadius: BorderRadius.circular(4),
                  color: isSelected ? _kPrimary : Colors.transparent),
                child: isSelected ? const Icon(Icons.check, size: 12, color: _kWhite) : null),
            )),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('#$num', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1F2937))),
                _StatusPill(status),
                Text(payStatus, style: TextStyle(fontFamily: 'DM Sans', fontSize: 11, fontWeight: FontWeight.w600,
                    color: payStatus == 'paid' ? _kGreen : payStatus == 'failed' ? _kRed : _kAmber)),
              ])),
              Text('KES ${_price(order['total_price'])}',
                  style: const TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w800, fontSize: 15, color: _kPrimary)),
            ]),
            const SizedBox(height: 4),
            Text(_date(order['created_at']),
                style: const TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: _kMutedLt)),
            if (order['payment_method'] != null)
              Text('· ${order['payment_method']}',
                  style: const TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: _kMutedLt)),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Status: ', style: TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: _kMutedLt)),
                const SizedBox(width: 4),
                DropdownButton<String>(
                  value: status, isDense: true, underline: const SizedBox.shrink(),
                  style: const TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: Color(0xFF1F2937)),
                  onChanged: isUpdating ? null : (v) => v != null ? _updateOrderStatus(orderId, v) : null,
                  items: _orderStatuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList()),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Payment: ', style: TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: _kMutedLt)),
                const SizedBox(width: 4),
                DropdownButton<String>(
                  value: payStatus, isDense: true, underline: const SizedBox.shrink(),
                  style: const TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: Color(0xFF1F2937)),
                  onChanged: isUpdating ? null : (v) => v != null ? _updatePaymentStatus(orderId, v) : null,
                  items: _paymentStatuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList()),
              ]),
              if (isUpdating) const SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(_kPrimary))),
              // Spacer is invalid in Wrap — group delete + details into a single min-size Row
              Row(mainAxisSize: MainAxisSize.min, children: [
                GestureDetector(
                  onTap: isDeleting ? null : () => _confirm(_ConfirmOpts(
                    title: 'Delete Order', destructive: true,
                    description: 'Permanently delete order #$num? Cannot be undone.',
                    confirmLabel: 'Delete', onConfirm: () => _doDeleteOrder(orderId, num.toString()),
                  )),
                  child: isDeleting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(_kRed)))
                      : const Icon(Icons.delete_outline, size: 16, color: _kMuted)),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    setState(() => _expandedOrderId = isExpanded ? null : orderId);
                    if (!isExpanded) _loadOrderItems(orderId);
                  },
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(isExpanded ? 'Hide' : 'Details',
                        style: const TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: _kPrimary)),
                    Icon(isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        size: 14, color: _kPrimary),
                  ])),
              ]),
            ]),
          ])),
        ])),

        if (isExpanded) ...[
          const Divider(height: 1, color: _kBorder),
          Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('ORDER ITEMS', style: TextStyle(fontFamily: 'DM Sans', fontSize: 10, fontWeight: FontWeight.w700, color: _kMutedLt, letterSpacing: 1)),
            const SizedBox(height: 8),
            if (!_orderItemsMap.containsKey(orderId))
              const Row(children: [
                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(_kPrimary))),
                SizedBox(width: 8),
                Text('Loading…', style: TextStyle(fontFamily: 'DM Sans', fontSize: 12, color: _kMutedLt)),
              ])
            else if (_orderItemsMap[orderId]!.isEmpty)
              const Text('No items found.', style: TextStyle(fontFamily: 'DM Sans', fontSize: 12, color: _kMutedLt))
            else
              ..._orderItemsMap[orderId]!.map((item) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: _kBg, borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kBorder)),
                child: Row(children: [
                  if ((item['content']?['cover_image_url'] as String?) != null)
                    ClipRRect(borderRadius: BorderRadius.circular(4),
                      child: CachedNetworkImage(imageUrl: item['content']['cover_image_url'] as String,
                          width: 32, height: 44, fit: BoxFit.cover))
                  else
                    Container(width: 32, height: 44, decoration: BoxDecoration(color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(4)),
                        child: const Icon(Icons.book_outlined, size: 14, color: _kMutedLt)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item['title'] ?? item['content']?['title'] ?? 'Unknown',
                        style: const TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w600, fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                    Text(item['content']?['content_type'] as String? ?? '—',
                        style: const TextStyle(fontFamily: 'DM Sans', fontSize: 10, color: _kMutedLt)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('KES ${_price(item['total_price'])}',
                        style: const TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w700, fontSize: 12)),
                    Text('Qty ${item['quantity']} × ${_price(item['unit_price'])}',
                        style: const TextStyle(fontFamily: 'DM Sans', fontSize: 10, color: _kMutedLt)),
                  ]),
                ]))),

            if ((order['shipping_address'] ?? order['billing_address']) != null) ...[
              const SizedBox(height: 12),
              const Text('ADDRESSES', style: TextStyle(fontFamily: 'DM Sans', fontSize: 10, fontWeight: FontWeight.w700, color: _kMutedLt, letterSpacing: 1)),
              const SizedBox(height: 4),
              if (order['shipping_address'] != null)
                Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Shipping: ', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
                  TextSpan(text: order['shipping_address'] as String),
                ]), style: const TextStyle(fontFamily: 'DM Sans', fontSize: 12, color: _kMuted)),
              if (order['billing_address'] != null)
                Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Billing: ', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
                  TextSpan(text: order['billing_address'] as String),
                ]), style: const TextStyle(fontFamily: 'DM Sans', fontSize: 12, color: _kMuted)),
            ],

            const SizedBox(height: 12),
            const Text('INTERNAL NOTE', style: TextStyle(fontFamily: 'DM Sans', fontSize: 10, fontWeight: FontWeight.w700, color: _kMutedLt, letterSpacing: 1)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: SizedBox(height: 36,
                child: TextField(
                  controller: TextEditingController(
                      text: _orderNotes[orderId] ?? (order['notes'] as String? ?? '')),
                  onChanged: (v) => _orderNotes[orderId] = v,
                  style: const TextStyle(fontFamily: 'DM Sans', fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Add internal admin note…',
                    hintStyle: const TextStyle(fontFamily: 'DM Sans', fontSize: 12, color: _kMutedLt),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
                    filled: true, fillColor: _kWhite),
                ))),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _saveOrderNote(orderId),
                style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: _kWhite,
                    elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                child: const Text('Save', style: TextStyle(fontFamily: 'DM Sans', fontSize: 12))),
            ]),

            const SizedBox(height: 12),
            Wrap(spacing: 16, runSpacing: 4, children: [
              if (order['payment_reference'] != null)
                _orderMeta('Reference', order['payment_reference'] as String),
              if (order['paid_at'] != null)
                _orderMeta('Paid', _date(order['paid_at'])),
              if (order['completed_at'] != null)
                _orderMeta('Completed', _date(order['completed_at'])),
              if (order['cancelled_at'] != null)
                _orderMeta('Cancelled', _date(order['cancelled_at'])),
            ]),
          ])),
        ],
      ]),
    );
  }

  Widget _orderMeta(String label, String value) => Text.rich(TextSpan(children: [
    TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
    TextSpan(text: value),
  ]), style: const TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: _kMuted));

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 4 – WITHDRAWALS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _withdrawalsTab(double w) {
    final fw = _filteredWithdrawals;
    final pendingCount = _withdrawals.where((w) => w['status'] == 'pending').length;

    return Column(children: [
      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in ['all', 'pending', 'processing', 'completed', 'failed'])
            _FilterChip(
              label: s == 'all' ? 'All (${_withdrawals.length})' : s,
              active: _wdStatusFilter == s,
              badge: s == 'pending' && pendingCount > 0 && _wdStatusFilter != 'pending' ? pendingCount : null,
              onTap: () => setState(() => _wdStatusFilter = s),
            ),
        ]),
        _SmallBtn(label: 'Refresh', icon: Icons.refresh_rounded, onTap: () => _loadWithdrawals()),
      ]),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: _kBlueBg, border: Border.all(color: const Color(0xFFBFDBFE)),
            borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: _kBlue),
          const SizedBox(width: 8),
          const Expanded(child: Text(
            'Click Process on any pending request to initiate an M-Pesa B2C payment. '
            'The author will be notified once Safaricom confirms.',
            style: TextStyle(fontFamily: 'DM Sans', fontSize: 12, color: _kBlue))),
        ]),
      ),
      const SizedBox(height: 14),
      if (_wdLoading)
        const Padding(padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(_kPrimary))))
      else if (fw.isEmpty)
        _WCard(child: Padding(padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.account_balance_wallet_outlined, size: 48, color: _kMutedLt.withOpacity(0.5)),
            const SizedBox(height: 12),
            Text(_wdStatusFilter == 'all' ? 'No withdrawal requests yet.' : 'No $_wdStatusFilter withdrawals.',
                style: const TextStyle(fontFamily: 'DM Sans', color: _kMutedLt, fontSize: 14)),
          ]))))
      else
        ListView.separated(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          itemCount: fw.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _withdrawalCard(fw[i]),
        ),
    ]);
  }

  Widget _withdrawalCard(Map<String, dynamic> wd) {
    final wdId       = wd['id'] as String;
    final isPending  = wd['status'] == 'pending';
    final isConfirm  = _wdConfirmId == wdId;
    final isProcess  = _wdProcessingId == wdId;
    final isExpanded = _wdExpandedId == wdId;
    final amount     = (wd['amount'] as num?)?.toDouble() ?? 0.0;
    final status     = wd['status'] as String? ?? 'pending';
    final author     = wd['author'] as Map<String, dynamic>?;
    final wallet     = wd['wallet'] as Map<String, dynamic>?;
    final phone      = wd['mpesa_phone'] as String? ?? '';
    final txId       = wd['mpesa_transaction_id'] as String?;
    final errMsg     = wd['mpesa_result_desc'] as String?;
    final adminNote  = wd['admin_notes'] as String?;
    final name       = author?['full_name'] as String? ?? 'Unknown Author';
    final email      = author?['email'] as String? ?? '';
    final avatarUrl  = author?['avatar_url'] as String?;
    final initial    = name.isNotEmpty ? name[0].toUpperCase() : '?';

    final statusColors = {
      'pending':    _kAmber,    'processing': _kBlue,
      'completed':  _kGreen,   'failed':     _kRed,
      'cancelled':  _kMuted,
    };
    final sColor = statusColors[status] ?? _kMuted;

    return Container(
      decoration: BoxDecoration(
        color: _kWhite,
        borderRadius: BorderRadius.circular(_kCard),
        border: isPending ? Border.all(color: const Color(0xFFFDE68A), width: 1.5) : Border.all(color: _kBorder),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))]),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 40, height: 40, child: ClipOval(child:
            avatarUrl != null && avatarUrl.isNotEmpty
                ? CachedNetworkImage(imageUrl: avatarUrl, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _initAvatar(initial))
                : _initAvatar(initial))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(name, style: const TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1F2937))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: sColor.withOpacity(0.1), border: Border.all(color: sColor.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(status, style: TextStyle(fontFamily: 'DM Sans', fontSize: 10, fontWeight: FontWeight.w700, color: sColor))),
            ]),
            if (email.isNotEmpty) Text(email, style: const TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: _kMutedLt)),
            Row(children: [
              const Icon(Icons.phone_android_rounded, size: 12, color: _kMutedLt),
              const SizedBox(width: 4),
              Text(_formatPhone(phone), style: const TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: _kMutedLt)),
              if (wd['mpesa_name'] != null) Text('  · ${wd['mpesa_name']}',
                  style: const TextStyle(fontFamily: 'DM Sans', fontSize: 10, color: _kMutedLt)),
            ]),
          ])),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('KES ${amount.toStringAsFixed(2)}',
                    style: const TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w800, fontSize: 17, color: Color(0xFF1F2937)))),
              Text(_date(wd['created_at']), style: const TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: _kMutedLt)),
            ]),
          ),
        ]),

        if (wallet != null) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 4, children: [
            _metaTag('Balance: KES ${(wallet['available_balance'] as num).toStringAsFixed(0)}'),
            _metaTag('Earned: KES ${(wallet['total_earned'] as num).toStringAsFixed(0)}'),
            _metaTag('Rate: ${((wallet['commission_rate'] as num) * 100).round()}%'),
          ]),
        ],

        if (txId != null) ...[
          const SizedBox(height: 6),
          Text('✓ M-Pesa TxID: $txId',
              style: const TextStyle(fontFamily: 'DM Sans', fontSize: 12, color: _kGreen, fontWeight: FontWeight.w600)),
        ],
        if (status == 'failed' && errMsg != null) ...[
          const SizedBox(height: 4),
          Text(errMsg, style: const TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: _kRed)),
        ],
        if (adminNote != null && adminNote.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Note: $adminNote', style: const TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: _kMutedLt, fontStyle: FontStyle.italic)),
        ],

        if (isPending) ...[
          const SizedBox(height: 14),
          const Text('Admin Notes (optional)', style: TextStyle(fontFamily: 'DM Sans', fontSize: 11, fontWeight: FontWeight.w600, color: _kMutedLt)),
          const SizedBox(height: 6),
          TextField(
            onChanged: (v) => _wdAdminNotes[wdId] = v,
            maxLines: 2,
            style: const TextStyle(fontFamily: 'DM Sans', fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Internal notes about this payout…',
              hintStyle: const TextStyle(fontFamily: 'DM Sans', fontSize: 12, color: _kMutedLt),
              filled: true, fillColor: const Color(0xFFF9FAFB),
              contentPadding: const EdgeInsets.all(10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder))),
          ),
          const SizedBox(height: 10),
          if (isConfirm)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _kAmberBg, border: Border.all(color: const Color(0xFFFDE68A)), borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: _kAmber),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Send KES ${amount.toStringAsFixed(2)} to ${_formatPhone(phone)}?',
                      style: const TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF92400E)))),
                ]),
                const Text('This will initiate a real M-Pesa B2C transfer.',
                    style: TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: _kAmber)),
                const SizedBox(height: 10),
                Row(children: [
                  OutlinedButton(
                    onPressed: () => setState(() => _wdConfirmId = null),
                    style: OutlinedButton.styleFrom(foregroundColor: _kMuted, side: const BorderSide(color: _kBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                    child: const Text('Cancel', style: TextStyle(fontFamily: 'DM Sans', fontSize: 12))),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    icon: isProcess
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _kWhite))
                        : const Icon(Icons.account_balance_wallet_outlined, size: 14),
                    label: Text(isProcess ? 'Sending…' : 'Confirm & Send',
                        style: const TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w700, fontSize: 12)),
                    style: ElevatedButton.styleFrom(backgroundColor: _kGreen, foregroundColor: _kWhite, elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                    onPressed: isProcess ? null : () => _processWithdrawal(wdId)),
                ]),
              ]))
          else
            SizedBox(width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.account_balance_wallet_outlined, size: 16),
                label: Text('Process M-Pesa Payout · KES ${amount.toStringAsFixed(0)}',
                    style: const TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(backgroundColor: _kGreen, foregroundColor: _kWhite, elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                onPressed: isProcess ? null : () => setState(() => _wdConfirmId = wdId))),
        ],

        Align(alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () => setState(() => _wdExpandedId = isExpanded ? null : wdId),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(isExpanded ? 'Less' : 'Details',
                  style: const TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: _kMutedLt)),
              Icon(isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  size: 14, color: _kMutedLt),
            ]),
          )),

        if (isExpanded) ...[
          const Divider(height: 16, color: _kBorder),
          Wrap(spacing: 16, runSpacing: 4, children: [
            _orderMeta('Request ID', wdId),
            if (wd['mpesa_conversation_id'] != null) _orderMeta('Conv ID', wd['mpesa_conversation_id'] as String),
            if (wd['processed_at'] != null) _orderMeta('Processed', _date(wd['processed_at'])),
            if (wd['completed_at'] != null) _orderMeta('Completed', _date(wd['completed_at'])),
            if (wd['failed_at'] != null) _orderMeta('Failed', _date(wd['failed_at'])),
          ]),
        ],
      ])),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 5 – MY PROFILE
  // ══════════════════════════════════════════════════════════════════════════
  Widget _profileTab(double w) => _WCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('My Profile', style: TextStyle(fontFamily: 'PlayfairDisplay', fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
    const SizedBox(height: 24),
    const Text('Profile Picture', style: TextStyle(fontFamily: 'DM Sans', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
    const SizedBox(height: 12),
    Row(children: [
      GestureDetector(onTap: _pickAvatar,
        child: Stack(children: [
          CircleAvatar(radius: 40, backgroundColor: _kRed.withOpacity(0.1), backgroundImage: _avatarImg,
            child: _avatarImg == null
                ? Text(_nameCtrl.text.isNotEmpty ? _nameCtrl.text[0].toUpperCase() : 'A',
                    style: const TextStyle(fontSize: 32, color: _kRed, fontFamily: 'PlayfairDisplay'))
                : null),
          Positioned(bottom: 4, right: 4,
            child: CircleAvatar(radius: 13, backgroundColor: _kPrimary,
                child: const Icon(Icons.camera_alt, size: 14, color: _kWhite))),
        ])),
      const SizedBox(width: 20),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.upload_file, size: 14),
          label: const Text('Change Photo', style: TextStyle(fontFamily: 'DM Sans', fontSize: 13)),
          onPressed: _pickAvatar,
          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1F2937),
              side: const BorderSide(color: _kBorder), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 4),
        const Text('PNG, JPG, WebP · max 5 MB', style: TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: _kMutedLt)),
      ]),
    ]),
    const SizedBox(height: 20),
    _lbl('Email'),
    const SizedBox(height: 6),
    TextField(
      controller: TextEditingController(text: _profile?['email'] as String? ?? ''),
      readOnly: true,
      style: const TextStyle(fontFamily: 'DM Sans', color: _kMuted, fontSize: 14),
      decoration: InputDecoration(border: _inputBorder(), enabledBorder: _inputBorder(),
          filled: true, fillColor: const Color(0xFFF3F4F6),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          suffixIcon: const Icon(Icons.lock_outline, size: 15, color: _kMutedLt))),
    const SizedBox(height: 14),
    LayoutBuilder(builder: (_, c) {
      final wide = c.maxWidth >= 500;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (wide) _row2([_field(_nameCtrl, 'Full Name', hint: 'Your name', maxLen: _kMaxName),
                         _field(_telCtrl, 'Phone', hint: '+254 7xx xxx xxx')])
        else ...[_field(_nameCtrl, 'Full Name', hint: 'Your name', maxLen: _kMaxName), const SizedBox(height: 14),
                 _field(_telCtrl, 'Phone', hint: '+254 7xx xxx xxx')],
        const SizedBox(height: 14),
        _field(_adrCtrl, 'Address', hint: 'P.O. Box …', lines: 2),
        const SizedBox(height: 14),
        if (wide) _row2([_field(_orgCtrl, 'Organization', hint: 'Intercen Books'),
                         _field(_dptCtrl, 'Department', hint: 'Editorial')])
        else ...[_field(_orgCtrl, 'Organization', hint: 'Intercen Books'), const SizedBox(height: 14),
                 _field(_dptCtrl, 'Department', hint: 'Editorial')],
        const SizedBox(height: 14),
        _lbl('Role'), const SizedBox(height: 6),
        TextField(controller: TextEditingController(text: RoleService.instance.role), readOnly: true,
            style: const TextStyle(fontFamily: 'DM Sans', color: _kMuted, fontSize: 14),
            decoration: InputDecoration(border: _inputBorder(), enabledBorder: _inputBorder(),
                filled: true, fillColor: const Color(0xFFF3F4F6),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                suffixIcon: const Icon(Icons.lock_outline, size: 15, color: _kMutedLt))),
        const SizedBox(height: 14),
        Row(children: [
          _lbl('Bio'), const Spacer(),
          Text('${_bioCtrl.text.length}/$_kMaxBio', style: const TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: _kMutedLt)),
        ]),
        const SizedBox(height: 6),
        TextField(controller: _bioCtrl, maxLines: 4, maxLength: _kMaxBio,
          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
          style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14, color: Color(0xFF1F2937)),
          decoration: InputDecoration(border: _inputBorder(), enabledBorder: _inputBorder(),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
              hintText: 'About you…', hintStyle: const TextStyle(fontFamily: 'DM Sans', color: _kMutedLt, fontSize: 14),
              contentPadding: const EdgeInsets.all(14), filled: true, fillColor: _kWhite)),
      ]);
    }),
    const SizedBox(height: 28),
    Wrap(spacing: 12, runSpacing: 12, children: [
      SizedBox(height: 46,
        child: ElevatedButton.icon(
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _kWhite))
              : const Icon(Icons.save_outlined, size: 16),
          label: Text(_saving ? 'Saving…' : 'Save Changes', style: const TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: _kWhite, elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          onPressed: _saving ? null : _saveProfile)),
      SizedBox(height: 46,
        child: OutlinedButton(
          onPressed: _saving ? null : () => Navigator.maybePop(context),
          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1F2937),
              side: const BorderSide(color: _kBorder),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(fontFamily: 'DM Sans')),
          child: const Text('Back'))),
    ]),
  ]));

  // ── Bottom nav ────────────────────────────────────────────────────────────
  Widget _bottomNav() => Container(
        height: 64,
        decoration: BoxDecoration(
          color: _kWhite,
          border: const Border(top: BorderSide(color: _kBorder)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, -4))]),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _NavItem(icon: Icons.home_outlined, label: 'Home',
              onTap: () => Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false)),
          _NavItem(icon: Icons.menu_book_outlined, label: 'Books',
              onTap: () => Navigator.pushNamed(context, '/books')),
          _NavItem(icon: Icons.upload_outlined, label: 'Upload',
              onTap: () => Navigator.pushNamed(context, '/upload')),
          const _NavItem(icon: Icons.admin_panel_settings_outlined, label: 'Admin', active: true),
        ]),
      );

  // ── Shared helpers ────────────────────────────────────────────────────────
  Widget _field(TextEditingController ctrl, String label, {int lines = 1, String? hint, int? maxLen}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _lbl(label), const SizedBox(height: 6),
        TextField(controller: ctrl, maxLines: lines, maxLength: maxLen,
          buildCounter: maxLen == null ? null :
              (_, {required currentLength, required isFocused, maxLength}) => null,
          style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14, color: Color(0xFF1F2937)),
          decoration: InputDecoration(border: _inputBorder(), enabledBorder: _inputBorder(),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
              hintText: hint, hintStyle: const TextStyle(fontFamily: 'DM Sans', color: _kMutedLt, fontSize: 14),
              filled: true, fillColor: _kWhite,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12))),
      ]);

  Widget _row2(List<Widget> kids) => Row(crossAxisAlignment: CrossAxisAlignment.start,
      children: kids.expand((w) => [Expanded(child: w), const SizedBox(width: 14)]).toList()..removeLast());

  Widget _lbl(String t) => Text(t, style: const TextStyle(fontFamily: 'DM Sans', fontSize: 13,
      fontWeight: FontWeight.w600, color: Color(0xFF1F2937)));

  Widget _metaTag(String t) => Text(t, style: const TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: _kMutedLt));

  OutlineInputBorder _inputBorder() => OutlineInputBorder(
      borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kBorder));

  String _date(dynamic raw) {
    if (raw == null) return '';
    try {
      final d = DateTime.parse(raw as String).toLocal();
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) { return ''; }
  }

  static double _dbl(dynamic v) =>
      double.tryParse(v?.toString() ?? '0') ?? 0;

  String _price(dynamic raw) {
    final d = _dbl(raw);
    return d.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  String _formatPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12) return '+${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6, 9)} ${digits.substring(9)}';
    return raw;
  }

  static double _hp(double w) {
    if (w >= 900) return 32;
    if (w >= 600) return 24;
    return 16;
  }

  Color _roleColor(String role) => switch (role) {
    'admin'          => _kRed,
    'author'         => _kBlue,
    'publisher'      => _kPurple,
    'editor'         => _kAmber,
    'moderator'      => _kGreen,
    'corporate_user' => const Color(0xFF4F46E5),
    _                => _kMuted,
  };
}

// ═════════════════════════════════════════════════════════════════════════════
// CONTENT GRID CARD
// ═════════════════════════════════════════════════════════════════════════════
class _ContentGridCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String? publishingId, deletingId;
  final void Function(String) onView, onEdit;
  final void Function(String, bool) onToggleFeatured;
  final void Function(String, String) onPublish;
  final void Function(String, String) onDelete;
  const _ContentGridCard({
    required this.item, required this.publishingId, required this.deletingId,
    required this.onView, required this.onEdit, required this.onToggleFeatured,
    required this.onPublish, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final id          = item['id'] as String;
    final isPublished = item['status'] == 'published';
    final isBusy      = publishingId == id;
    final isDeleting  = deletingId == id;
    final isFeatured  = item['is_featured'] == true;
    final coverUrl    = item['cover_image_url'] as String?;
    final title       = item['title'] as String? ?? '—';
    final author      = item['author'] as String? ?? '—';
    final type        = item['content_type'] as String? ?? '';
    final isFree      = item['is_free'] == true;
    final price       = double.tryParse(item['price']?.toString() ?? '0') ?? 0;
    final views       = item['view_count'] as int? ?? 0;
    final dls         = item['total_downloads'] as int? ?? 0;
    final status      = item['status'] as String? ?? 'draft';

    final statusColors = {
      'published':      const Color(0xFFDCFCE7),
      'draft':          const Color(0xFFF3F4F6),
      'archived':       _kRedBg,
      'pending_review': _kAmberBg,
    };
    final statusTextColors = {
      'published': _kGreen, 'draft': _kMuted,
      'archived':  _kRed,   'pending_review': _kAmber,
    };

    return Container(
      decoration: BoxDecoration(color: _kWhite, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorder),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Stack(children: [
          ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: coverUrl != null
                ? CachedNetworkImage(imageUrl: coverUrl, width: double.infinity, height: double.infinity, fit: BoxFit.cover)
                : Container(color: const Color(0xFFF3F4F6), width: double.infinity, height: double.infinity,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.book_outlined, size: 28, color: _kMutedLt),
                      Text(type, style: const TextStyle(fontFamily: 'DM Sans', fontSize: 9, color: _kMutedLt)),
                    ]))),
          Positioned(top: 6, left: 6,
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(color: statusColors[status] ?? const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(4)),
              child: Text(status.replaceAll('_', ' '), style: TextStyle(
                  fontFamily: 'DM Sans', fontSize: 8, fontWeight: FontWeight.w700,
                  color: statusTextColors[status] ?? _kMuted)))),
          if (isFeatured) Positioned(top: 6, right: 6,
            child: Container(padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(color: _kAmberBg, shape: BoxShape.circle),
              child: const Icon(Icons.star_rounded, size: 10, color: _kAmber))),
          Positioned(bottom: 0, left: 0, right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Colors.transparent])),
              padding: const EdgeInsets.all(6),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _iconBtn(Icons.visibility_outlined, () => onView(id)),
                const SizedBox(width: 4),
                _iconBtn(Icons.edit_outlined, () => onEdit(id)),
                const SizedBox(width: 4),
                _iconBtn(isFeatured ? Icons.star_rounded : Icons.star_border_rounded,
                    () => onToggleFeatured(id, isFeatured), color: isFeatured ? _kAmber : Colors.white),
                const SizedBox(width: 4),
                isBusy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : _iconBtn(isPublished ? Icons.visibility_off_outlined : Icons.public_rounded,
                        () => onPublish(id, isPublished ? 'unpublish' : 'publish'),
                        color: isPublished ? const Color(0xFFFF8C00) : _kGreen),
                const SizedBox(width: 4),
                isDeleting
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : _iconBtn(Icons.delete_outline, () => onDelete(id, title), color: _kRed),
              ]))),
        ])),
        Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w600, fontSize: 11, color: Color(0xFF1F2937)),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(author, style: const TextStyle(fontFamily: 'DM Sans', fontSize: 9, color: _kMutedLt),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: Text(type, style: const TextStyle(fontFamily: 'DM Sans', fontSize: 9, color: _kMutedLt))),
            isFree
                ? const Text('Free', style: TextStyle(fontFamily: 'DM Sans', fontSize: 10, fontWeight: FontWeight.w700, color: _kGreen))
                : Text('KES ${price.toStringAsFixed(0)}',
                    style: const TextStyle(fontFamily: 'DM Sans', fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
          ]),
          if (views > 0 || dls > 0)
            Text('${views > 0 ? '$views views' : ''}${dls > 0 ? ' · $dls dl' : ''}',
                style: const TextStyle(fontFamily: 'DM Sans', fontSize: 8, color: _kMutedLt)),
        ])),
      ]),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, {Color color = Colors.white}) =>
      GestureDetector(onTap: onTap,
        child: Container(width: 22, height: 22,
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(5)),
          child: Icon(icon, size: 12, color: color)));
}

// ═════════════════════════════════════════════════════════════════════════════
// CONTENT LIST ROW
// ═════════════════════════════════════════════════════════════════════════════
class _ContentListRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final String? publishingId, deletingId;
  final void Function(String) onView, onEdit;
  final void Function(String, bool) onToggleFeatured;
  final void Function(String, String) onPublish;
  final void Function(String, String) onDelete;
  const _ContentListRow({
    required this.item, required this.publishingId, required this.deletingId,
    required this.onView, required this.onEdit, required this.onToggleFeatured,
    required this.onPublish, required this.onDelete,
  });

  @override
Widget build(BuildContext context) {
  final id          = item['id'] as String;
  final isPublished = item['status'] == 'published';
  final isBusy      = publishingId == id;
  final isDeleting  = deletingId == id;
  final isFeatured  = item['is_featured'] == true;
  final coverUrl    = item['cover_image_url'] as String?;
  final title       = item['title'] as String? ?? '—';
  final author      = item['author'] as String? ?? '—';
  final type        = item['content_type'] as String? ?? '';
  final isFree      = item['is_free'] == true;
  final price       = double.tryParse(item['price']?.toString() ?? '0') ?? 0;
  final views       = item['view_count'] as int? ?? 0;
  final dls         = item['total_downloads'] as int? ?? 0;
  final status      = item['status'] as String? ?? 'draft';
  final created     = item['created_at'] as String?;

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: Row(children: [
      // Cover thumbnail — fixed, small
      if (coverUrl != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: CachedNetworkImage(
            imageUrl: coverUrl, width: 32, height: 44, fit: BoxFit.cover),
        )
      else
        Container(
          width: 32, height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Icon(Icons.book_outlined, size: 14, color: _kMutedLt),
        ),
      const SizedBox(width: 10),

      // Title + author — flex fills remaining space
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: Color(0xFF1F2937),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isFeatured) ...[
              const SizedBox(width: 4),
              const Icon(Icons.star_rounded, size: 11, color: _kAmber),
            ],
          ]),
          Text(
            author,
            style: const TextStyle(fontFamily: 'DM Sans', fontSize: 10, color: _kMutedLt),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          // On narrow screens wrap the meta pills below the title
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (type.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(type,
                      style: const TextStyle(fontFamily: 'DM Sans', fontSize: 9, color: _kMutedLt)),
                ),
              _StatusPill(status),
              isFree
                  ? const Text('Free',
                      style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _kGreen,
                      ))
                  : Text(
                      'KES ${price.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontFamily: 'DM Sans', fontSize: 11, fontWeight: FontWeight.w700),
                    ),
              Text('${views}v ${dls}dl',
                  style: const TextStyle(
                      fontFamily: 'DM Sans', fontSize: 9, color: _kMutedLt)),
              if (created != null)
                Text(_fmtDate(created),
                    style: const TextStyle(
                        fontFamily: 'DM Sans', fontSize: 9, color: _kMutedLt)),
            ],
          ),
        ]),
      ),
      const SizedBox(width: 8),

      // Action icons — fixed on the right, never shrink
      Row(mainAxisSize: MainAxisSize.min, children: [
        _tinyBtn(Icons.visibility_outlined, () => onView(id)),
        _tinyBtn(Icons.edit_outlined, () => onEdit(id)),
        _tinyBtn(
          isFeatured ? Icons.star_rounded : Icons.star_border_rounded,
          () => onToggleFeatured(id, isFeatured),
          color: isFeatured ? _kAmber : _kMuted,
        ),
        isBusy
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(_kPrimary),
                ))
            : _tinyBtn(
                isPublished
                    ? Icons.visibility_off_outlined
                    : Icons.public_rounded,
                () => onPublish(id, isPublished ? 'unpublish' : 'publish'),
                color: isPublished ? _kOrange : _kGreen,
              ),
        isDeleting
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(_kRed),
                ))
            : _tinyBtn(Icons.delete_outline, () => onDelete(id, title),
                color: _kRed),
      ]),
    ]),
  );
}

  Widget _tinyBtn(IconData icon, VoidCallback onTap, {Color color = _kMuted}) =>
      GestureDetector(onTap: onTap,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Icon(icon, size: 15, color: color)));

  static String _fmtDate(String raw) {
    try {
      final d = DateTime.parse(raw).toLocal();
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) { return ''; }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// CONFIRM DIALOG OVERLAY
// ═════════════════════════════════════════════════════════════════════════════
class _ConfirmDialogOverlay extends StatelessWidget {
  final _ConfirmOpts opts;
  final VoidCallback onDismiss;
  const _ConfirmDialogOverlay({required this.opts, required this.onDismiss});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onDismiss,
        child: Container(
          color: Colors.black.withOpacity(0.45),
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: _kWhite, borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 24)]),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 40, height: 40,
                    decoration: BoxDecoration(
                        color: opts.destructive ? _kRedBg : _kAmberBg, shape: BoxShape.circle),
                    child: Icon(Icons.warning_amber_rounded, size: 20,
                        color: opts.destructive ? _kRed : _kAmber)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(opts.title, style: const TextStyle(fontFamily: 'DM Sans', fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
                    const SizedBox(height: 4),
                    Text(opts.description, style: const TextStyle(fontFamily: 'DM Sans', fontSize: 13, color: _kMuted)),
                  ])),
                ]),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  OutlinedButton(
                    onPressed: onDismiss,
                    style: OutlinedButton.styleFrom(foregroundColor: _kMuted,
                        side: const BorderSide(color: _kBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        textStyle: const TextStyle(fontFamily: 'DM Sans')),
                    child: const Text('Cancel')),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () { opts.onConfirm(); onDismiss(); },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: opts.destructive ? _kRed : _kPrimary,
                        foregroundColor: _kWhite, elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        textStyle: const TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w700)),
                    child: Text(opts.confirmLabel)),
                ]),
              ]),
            ),
          ),
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// REJECT OVERLAY
// ═════════════════════════════════════════════════════════════════════════════
class _RejectOverlay extends StatelessWidget {
  final Map<String, dynamic> pub;
  final TextEditingController ctrl;
  final bool processing;
  final VoidCallback onConfirm, onCancel;
  const _RejectOverlay({required this.pub, required this.ctrl, required this.processing,
      required this.onConfirm, required this.onCancel});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onCancel,
        child: Container(color: Colors.black.withOpacity(0.45), alignment: Alignment.center,
          child: GestureDetector(onTap: () {},
            child: Container(
              margin: const EdgeInsets.all(24), padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: _kWhite, borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 24)]),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Reject Submission', style: TextStyle(fontFamily: 'PlayfairDisplay',
                    fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
                const SizedBox(height: 4),
                Text('"${pub['title']}" by ${pub['author_name'] ?? '—'}',
                    style: const TextStyle(fontFamily: 'DM Sans', fontSize: 13, color: _kMuted)),
                const SizedBox(height: 16),
                TextField(controller: ctrl, maxLines: 4,
                  style: const TextStyle(fontFamily: 'DM Sans', fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Provide feedback to the author (optional but recommended)…',
                    hintStyle: const TextStyle(fontFamily: 'DM Sans', fontSize: 13, color: _kMutedLt),
                    filled: true, fillColor: const Color(0xFFF9FAFB), contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorder)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _kRed, width: 1.5)))),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: onCancel,
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1F2937),
                        side: const BorderSide(color: _kBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        textStyle: const TextStyle(fontFamily: 'DM Sans')),
                    child: const Text('Cancel'))),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton(onPressed: processing ? null : onConfirm,
                    style: ElevatedButton.styleFrom(backgroundColor: _kRed, foregroundColor: _kWhite,
                        elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        textStyle: const TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w700)),
                    child: processing
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _kWhite))
                        : const Text('Confirm Rejection'))),
                ]),
              ]),
            )),
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// SMALL REUSABLE WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

class _StatData {
  final String label, value;
  final IconData icon;
  final Color color, bg;
  const _StatData(this.label, this.value, this.icon, this.color, this.bg);
}

class _StatCard extends StatelessWidget {
  final _StatData d;
  const _StatCard(this.d);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: _kWhite, borderRadius: BorderRadius.circular(_kCard),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2))]),
        child: Row(children: [
          Container(width: 36, height: 36,
              decoration: BoxDecoration(color: d.bg, borderRadius: BorderRadius.circular(8)),
              child: Icon(d.icon, color: d.color, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center, children: [
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                child: Text(d.value, style: const TextStyle(fontFamily: 'DM Sans',
                    fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1F2937)))),
            Text(d.label, style: const TextStyle(fontFamily: 'DM Sans', fontSize: 9, color: _kMutedLt),
                overflow: TextOverflow.ellipsis),
          ])),
        ]),
      );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final int? badge;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.active, required this.onTap, this.badge});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? _kPrimary : _kWhite,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? _kPrimary : _kBorder)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: TextStyle(fontFamily: 'DM Sans', fontSize: 12, fontWeight: FontWeight.w600,
                color: active ? _kWhite : _kMuted)),
            if (badge != null && badge! > 0) ...[
              const SizedBox(width: 5),
              Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: _kAmber, borderRadius: BorderRadius.circular(10)),
                child: Text('$badge', style: const TextStyle(fontFamily: 'DM Sans', fontSize: 9,
                    fontWeight: FontWeight.w800, color: _kWhite))),
            ],
          ]),
        ),
      );
}

class _RolePill extends StatelessWidget {
  final String label; final Color color;
  const _RolePill(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color.withOpacity(0.1),
            border: Border.all(color: color.withOpacity(0.3)), borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: TextStyle(fontFamily: 'DM Sans', fontSize: 9, fontWeight: FontWeight.w800, color: color)));
}

class _RoleDropdown extends StatelessWidget {
  final String value; final bool saving; final ValueChanged<String?> onChanged;
  const _RoleDropdown({required this.value, required this.saving, required this.onChanged});

  Color _color(String r) => switch (r) {
    'admin'          => _kRed,    'author'         => _kBlue,
    'publisher'      => _kPurple, 'editor'         => _kAmber,
    'moderator'      => _kGreen,  'corporate_user' => const Color(0xFF4F46E5),
    _                => _kMuted,
  };

  @override
  Widget build(BuildContext context) {
    final c = _color(value);
    return saving
        ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c))
        : DropdownButton<String>(value: value, isDense: true, underline: const SizedBox.shrink(),
            style: TextStyle(fontFamily: 'DM Sans', fontSize: 11, fontWeight: FontWeight.w700, color: c),
            onChanged: onChanged,
            items: _roles.map((r) => DropdownMenuItem(value: r, child: Text(r,
                style: TextStyle(fontFamily: 'DM Sans', fontSize: 12, fontWeight: FontWeight.w600, color: _color(r))))).toList());
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill(this.status);
  Color get _color => switch (status) {
    'published' || 'approved' || 'completed' || 'paid' => _kGreen,
    'rejected'  || 'cancelled' || 'failed'             => _kRed,
    'under_review' || 'processing'                     => _kBlue,
    'pending'                                          => _kAmber,
    'shipped'                                          => _kPurple,
    'delivered'                                        => _kEmerald,
    _                                                  => _kMuted,
  };
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: _color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
        child: Text(status.replaceAll('_', ' '),
            style: TextStyle(fontFamily: 'DM Sans', fontSize: 10, fontWeight: FontWeight.w700, color: _color)));
}

class _ActionBtn extends StatelessWidget {
  final String label; final IconData icon; final Color color; final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap,
        child: Container(padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: color.withOpacity(0.08),
              border: Border.all(color: color.withOpacity(0.25)), borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 13, color: color), const SizedBox(width: 5),
            Text(label, style: TextStyle(fontFamily: 'DM Sans', fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ])));
}

class _SmallBtn extends StatelessWidget {
  final String label; final IconData icon; final VoidCallback onTap;
  const _SmallBtn({required this.label, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap,
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(border: Border.all(color: _kBorder), borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: _kMuted),
            if (label.isNotEmpty) ...[const SizedBox(width: 5),
              Text(label, style: const TextStyle(fontFamily: 'DM Sans', fontSize: 12, color: _kMuted))],
          ])));
}

class _WCard extends StatelessWidget {
  final Widget child; final EdgeInsetsGeometry? padding;
  const _WCard({required this.child, this.padding});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: _kWhite, borderRadius: BorderRadius.circular(_kCard),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))]),
        padding: padding ?? const EdgeInsets.all(20),
        child: child);
}

class _NavItem extends StatelessWidget {
  final IconData icon; final String label; final bool active; final VoidCallback? onTap;
  const _NavItem({required this.icon, required this.label, this.active = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = active ? _kPrimary : Colors.grey;
    return GestureDetector(onTap: onTap,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: c, size: 22), const SizedBox(height: 3),
          Text(label, style: TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: c,
              fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
        ]));
  }
}