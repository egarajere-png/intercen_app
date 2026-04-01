import 'package:supabase_flutter/supabase_flutter.dart';

// This gives us access to Supabase anywhere in the app
final supabase = Supabase.instance.client;

class SupabaseService {
  // ─────────────────────────────────────────────────────
  // PRIVATE HELPER
  // ─────────────────────────────────────────────────────
  //
  // BUG FIX: supabase.functions.invoke() on some Flutter
  // SDK versions does NOT auto-attach the Authorization
  // header. The edge function receives a 401, returns null,
  // and res.data comes back null → silently returned as {}.
  //
  // Every authenticated call now goes through _invoke(),
  // which:
  //   1. Refreshes the session to ensure the token is fresh.
  //   2. Passes "Authorization: Bearer <token>" explicitly.
  //   3. Throws a clear error if the user is not logged in.

  Future<String> _accessToken() async {
    try {
      final r = await supabase.auth.refreshSession();
      final t = r.session?.accessToken;
      if (t != null && t.isNotEmpty) return t;
    } catch (_) {
      // No session to refresh — fall through
    }
    final t = supabase.auth.currentSession?.accessToken;
    if (t != null && t.isNotEmpty) return t;
    throw Exception('Not authenticated. Please log in again.');
  }

  Future<Map<String, dynamic>> _invoke(
    String function, {
    Map<String, dynamic>? body,
  }) async {
    final token = await _accessToken();
    final res = await supabase.functions.invoke(
      function,
      body: body,
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = res.data;
    if (data == null) return {};
    if (data is Map) return Map<String, dynamic>.from(data);
    return {'result': data};
  }

  // ─────────────────────────────────────────
  // AUTH
  // ─────────────────────────────────────────

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return {'user': response.user, 'session': response.session};
  }

  Future<Map<String, dynamic>> signup(String email, String password) async {
    final response = await supabase.auth.signUp(
      email: email,
      password: password,
    );
    return {'user': response.user, 'session': response.session};
  }

  Future<void> logout() async {
    await supabase.auth.signOut();
  }

  dynamic get currentUser => supabase.auth.currentUser;

  // Reset password — no session needed, called without auth header
  Future<void> resetPassword(String email) async {
    await supabase.functions.invoke(
      'auth-reset-password',
      body: {'email': email},
    );
  }

  // ─────────────────────────────────────────
  // CART
  // ─────────────────────────────────────────

  Future<Map<String, dynamic>> getCart() async {
    return _invoke('cart-get');
  }

  Future<Map<String, dynamic>> addToCart(String bookId, int quantity) async {
    return _invoke(
      'cart-add-item',
      body: {'content_id': bookId, 'quantity': quantity},
    );
  }

  Future<Map<String, dynamic>> removeFromCart(String cartItemId) async {
    return _invoke(
      'cart-remove-item',
      body: {'cart_item_id': cartItemId},
    );
  }

  Future<Map<String, dynamic>> updateCartQuantity(
      String cartItemId, int quantity) async {
    return _invoke(
      'cart-update-quantity',
      body: {'cart_item_id': cartItemId, 'quantity': quantity},
    );
  }

  Future<Map<String, dynamic>> clearCart() async {
    return _invoke('cart-clear');
  }

  Future<Map<String, dynamic>> validateCart() async {
    return _invoke('cart-validate');
  }

  // ─────────────────────────────────────────
  // CHECKOUT
  // ─────────────────────────────────────────

  Future<Map<String, dynamic>> initiateCheckout(
      Map<String, dynamic> body) async {
    return _invoke('checkout-initiate', body: body);
  }

  Future<Map<String, dynamic>> processPayment(
      Map<String, dynamic> body) async {
    return _invoke('checkout-process-payment', body: body);
  }

  Future<Map<String, dynamic>> mpesaStkPush(
      String phone, double amount) async {
    return _invoke(
      'checkout-mpesa-stk-push',
      body: {'phone': phone, 'amount': amount},
    );
  }

  // ─────────────────────────────────────────
  // CONTENT / BOOKS
  // ─────────────────────────────────────────

  Future<Map<String, dynamic>> searchContent({
    String query = '',
    String? categorySlug,
    List<String>? contentTypes,
    String priceRange = 'all',
    String visibility = 'public',
    String sortBy = 'relevance',
    int page = 1,
    int pageSize = 40,
  }) async {
    final Map<String, dynamic> filters = {};

    if (categorySlug != null && categorySlug.isNotEmpty) {
      filters['category_slug'] = categorySlug;
    }
    if (contentTypes != null && contentTypes.isNotEmpty) {
      filters['content_types'] = contentTypes;
    }
    if (priceRange != 'all') {
      if (priceRange == 'free') {
        filters['is_free'] = true;
      } else if (priceRange == 'under-15') {
        filters['price_max'] = 2000;
      } else if (priceRange == '15-25') {
        filters['price_min'] = 2000;
        filters['price_max'] = 3500;
      } else if (priceRange == '25-50') {
        filters['price_min'] = 3500;
        filters['price_max'] = 7000;
      } else if (priceRange == 'over-50') {
        filters['price_min'] = 7000;
      }
    }
    if (visibility != 'any') {
      filters['visibility'] = visibility;
    }

    String apiSortBy = 'relevance';
    switch (sortBy) {
      case 'price-low':
      case 'price-high':
        apiSortBy = 'price';
        break;
      case 'rating':
        apiSortBy = 'rating';
        break;
      case 'newest':
        apiSortBy = 'newest';
        break;
    }

    return _invoke(
      'content-search',
      body: {
        'query': query,
        'filters': filters,
        'sort_by': apiSortBy,
        'page': page,
        'page_size': pageSize,
      },
    );
  }

  Future<Map<String, dynamic>> publishContent(
      Map<String, dynamic> body) async {
    return _invoke('content-publish', body: body);
  }

  Future<Map<String, dynamic>> deleteContent(String contentId) async {
    return _invoke('content-delete', body: {'content_id': contentId});
  }

  // ─────────────────────────────────────────
  // REVIEWS
  // ─────────────────────────────────────────

  Future<Map<String, dynamic>> getReviews(String bookId) async {
    return _invoke('reviews-get', body: {'book_id': bookId});
  }

  Future<Map<String, dynamic>> submitReview(
      String bookId, String review, int rating) async {
    return _invoke(
      'reviews-submit',
      body: {'book_id': bookId, 'review': review, 'rating': rating},
    );
  }

  Future<Map<String, dynamic>> voteReviewHelpful(String reviewId) async {
    return _invoke(
      'reviews-vote-helpful',
      body: {'review_id': reviewId},
    );
  }

  // ─────────────────────────────────────────
  // PROFILE
  // ─────────────────────────────────────────

  Future<Map<String, dynamic>> updateProfile(
      Map<String, dynamic> body) async {
    return _invoke('profile-update', body: body);
  }

  Future<Map<String, dynamic>> editProfileInfo(
      Map<String, dynamic> body) async {
    return _invoke('profile-info-edit', body: body);
  }
}