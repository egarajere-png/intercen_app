// lib/pages/notifications_page.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

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
const _kPurple   = Color(0xFF7C3AED);
const _kPurpleBg = Color(0xFFF5F3FF);
const _kRed      = Color(0xFFDC2626);
const _kRedBg    = Color(0xFFFEF2F2);

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;
  String _filter = 'all'; // all | unread

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) return;

      var query = _sb
          .from('notifications')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(100);

      final data = await query;
      if (!mounted) return;
      setState(() => _notifications =
          List<Map<String, dynamic>>.from(data ?? []));
    } catch (e) {
      _toast('Failed to load notifications: $e', err: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(String id) async {
    await _sb.from('notifications').update({
      'read': true,
      'read_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
    setState(() {
      _notifications = _notifications
          .map((n) => n['id'] == id ? {...n, 'read': true} : n)
          .toList();
    });
  }

  Future<void> _markAllRead() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    await _sb.from('notifications').update({
      'read': true,
      'read_at': DateTime.now().toIso8601String(),
    }).eq('user_id', uid).eq('read', false);
    setState(() {
      _notifications =
          _notifications.map((n) => {...n, 'read': true}).toList();
    });
    _toast('All notifications marked as read');
  }

  Future<void> _deleteNotification(String id) async {
    await _sb.from('notifications').delete().eq('id', id);
    setState(() =>
        _notifications.removeWhere((n) => n['id'] == id));
    _toast('Notification deleted');
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

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'unread') {
      return _notifications.where((n) => n['read'] != true).toList();
    }
    return _notifications;
  }

  int get _unreadCount =>
      _notifications.where((n) => n['read'] != true).length;

  // ── Icon + colour per notification type ──────────────────────────────────
  _NotifMeta _meta(String type) {
    switch (type) {
      case 'content_approved':
      case 'submission_approved':
        return _NotifMeta(
            icon: Icons.check_circle_outline_rounded,
            color: _kGreen,
            bg: _kGreenBg);
      case 'content_rejected':
      case 'submission_rejected':
        return _NotifMeta(
            icon: Icons.cancel_outlined, color: _kRed, bg: _kRedBg);
      case 'submission_received':
        return _NotifMeta(
            icon: Icons.inbox_outlined, color: _kBlue, bg: _kBlueBg);
      case 'content_published':
      case 'org_content_published':
        return _NotifMeta(
            icon: Icons.auto_stories_rounded,
            color: _kPurple,
            bg: _kPurpleBg);
      case 'purchase_confirmed':
      case 'order_completed':
        return _NotifMeta(
            icon: Icons.shopping_bag_outlined,
            color: _kGreen,
            bg: _kGreenBg);
      case 'new_review':
        return _NotifMeta(
            icon: Icons.star_outline_rounded,
            color: _kAmber,
            bg: _kAmberBg);
      case 'role_changed':
        return _NotifMeta(
            icon: Icons.manage_accounts_outlined,
            color: _kPurple,
            bg: _kPurpleBg);
      case 'system_announcement':
        return _NotifMeta(
            icon: Icons.campaign_outlined,
            color: _kAmber,
            bg: _kAmberBg);
      case 'new_follower':
        return _NotifMeta(
            icon: Icons.person_add_outlined,
            color: _kBlue,
            bg: _kBlueBg);
      default:
        return _NotifMeta(
            icon: Icons.notifications_outlined,
            color: _kMuted,
            bg: const Color(0xFFF3F4F6));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: _kBg,
      bottomNavigationBar: _bottomNav(),
      body: CustomScrollView(slivers: [
        // ── App bar ──────────────────────────────────────────────────────
        SliverAppBar(
          pinned: true,
          backgroundColor: _kWhite,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 20, color: Color(0xFF1A1A2E)),
            onPressed: () => Navigator.pop(context),
          ),
          title: Row(children: [
            const Text(
              'Notifications',
              style: TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: Color(0xFF111827),
              ),
            ),
            if (_unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _kPrimary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$_unreadCount',
                  style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _kWhite,
                  ),
                ),
              ),
            ],
          ]),
          actions: [
            if (_unreadCount > 0)
              TextButton(
                onPressed: _markAllRead,
                child: const Text(
                  'Mark all read',
                  style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _kPrimary,
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  color: _kMuted, size: 20),
              onPressed: _load,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: _kBorder),
          ),
        ),

        // ── Filter pills ─────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              _pill('All', 'all'),
              const SizedBox(width: 8),
              _pill(
                  'Unread${_unreadCount > 0 ? ' ($_unreadCount)' : ''}',
                  'unread'),
            ]),
          ),
        ),

        // ── Content ──────────────────────────────────────────────────────
        if (_loading)
          const SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(_kPrimary),
                strokeWidth: 3,
              ),
            ),
          )
        else if (filtered.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: const Icon(
                        Icons.notifications_none_rounded,
                        size: 40,
                        color: _kMutedLt),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _filter == 'unread'
                        ? 'No unread notifications'
                        : 'No notifications yet',
                    style: const TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _filter == 'unread'
                        ? "You're all caught up!"
                        : "We'll notify you when something happens.",
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 13,
                        color: _kMutedLt),
                  ),
                ],
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                if (i < filtered.length) {
                  return _notifCard(filtered[i]);
                }
                // bottom padding
                return SizedBox(
                    height: 32 + MediaQuery.of(context).padding.bottom);
              },
              childCount: filtered.length + 1,
            ),
          ),
      ]),
    );
  }

  Widget _pill(String label, String value) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          label,
          style: TextStyle(
            fontFamily: 'DM Sans',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? _kWhite : _kMuted,
          ),
        ),
      ),
    );
  }

  Widget _notifCard(Map<String, dynamic> n) {
    final isRead    = n['read'] == true;
    final type      = n['type'] as String? ?? 'general';
    final title     = n['title'] as String? ?? '';
    final message   = n['message'] as String? ?? '';
    final createdAt = n['created_at'] as String?;
    final meta      = _meta(type);

    DateTime? dt;
    if (createdAt != null) {
      try { dt = DateTime.parse(createdAt).toLocal(); } catch (_) {}
    }
    final timeStr = dt != null ? timeago.format(dt) : '';

    return Dismissible(
      key: ValueKey(n['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: _kRed,
        child: const Icon(Icons.delete_outline_rounded,
            color: _kWhite, size: 24),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text('Delete Notification',
                style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontWeight: FontWeight.w800)),
            content: const Text(
                'Remove this notification?',
                style: TextStyle(
                    fontFamily: 'DM Sans', color: _kMuted)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _kRed,
                    foregroundColor: _kWhite,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => _deleteNotification(n['id'] as String),
      child: GestureDetector(
        onTap: () {
          if (!isRead) _markRead(n['id'] as String);
        },
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          decoration: BoxDecoration(
            color: isRead ? _kWhite : const Color(0xFFFFF8F8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isRead
                  ? _kBorder
                  : _kPrimary.withOpacity(0.15),
            ),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: meta.bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(meta.icon, color: meta.color, size: 20),
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 14,
                              fontWeight: isRead
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                              color: const Color(0xFF111827),
                            ),
                          ),
                        ),
                        if (!isRead)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 6),
                            decoration: const BoxDecoration(
                              color: _kPrimary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ]),
                      const SizedBox(height: 3),
                      Text(
                        message,
                        style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 13,
                          color: _kMuted,
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(children: [
                        _typeBadge(type),
                        const Spacer(),
                        Text(
                          timeStr,
                          style: const TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 11,
                              color: _kMutedLt),
                        ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _typeBadge(String type) {
    final label = type
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty
            ? w[0].toUpperCase() + w.substring(1)
            : w)
        .join(' ');
    final m = _meta(type);
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: m.bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'DM Sans',
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: m.color,
        ),
      ),
    );
  }

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
            _navItem(Icons.shopping_cart_outlined, 'Cart', false,
                () => Navigator.pushNamed(context, '/cart')),
            _navItem(Icons.person, 'Profile', true,
                () => Navigator.pushNamed(context, '/settings')),
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

class _NotifMeta {
  final IconData icon;
  final Color color, bg;
  const _NotifMeta(
      {required this.icon, required this.color, required this.bg});
}