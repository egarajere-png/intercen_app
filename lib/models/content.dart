/// Content data model matching the Supabase `content` table schema
/// and the TypeScript `Content` interface from content.types.ts.
class Content {
  final String id;
  final String title;
  final String? subtitle;
  final String? description;
  final String contentType;   // book, ebook, document, paper, report, manual, guide
  final String? format;       // pdf, epub, mobi, docx, txt
  final String? author;
  final String? publisher;
  final String? publishedDate;
  final String? categoryId;
  final String? language;
  final String? coverImageUrl;
  final String? backpageImageUrl;   // ← NEW: back cover image
  final String? fileUrl;
  final int? fileSizeBytes;
  final int? pageCount;
  final double price;
  final double? originalPrice;      // ← NEW: original price before discount
  final bool isFree;
  final bool isForSale;
  final int stockQuantity;
  final String? isbn;
  final bool isFeatured;
  final bool isBestseller;
  final bool isNewArrival;
  final double averageRating;
  final int totalReviews;
  final int totalDownloads;
  final int viewCount;
  final String visibility;    // public, private, organization, restricted
  final String? accessLevel;  // free, paid, subscription, organization_only
  final String? documentNumber;
  final String version;
  final String? department;
  final String? confidentiality;
  final String status;        // draft, pending_review, published, archived, discontinued
  final String? uploadedBy;
  final String createdAt;
  final String updatedAt;
  final String? publishedAt;
  final bool? isOwnContent;
  final List<String>? metaKeywords; // ← NEW: tags / meta keywords

  Content({
    required this.id,
    required this.title,
    this.subtitle,
    this.description,
    this.contentType = 'book',
    this.format,
    this.author,
    this.publisher,
    this.publishedDate,
    this.categoryId,
    this.language,
    this.coverImageUrl,
    this.backpageImageUrl,       // ← NEW
    this.fileUrl,
    this.fileSizeBytes,
    this.pageCount,
    this.price = 0,
    this.originalPrice,          // ← NEW
    this.isFree = false,
    this.isForSale = true,
    this.stockQuantity = 0,
    this.isbn,
    this.isFeatured = false,
    this.isBestseller = false,
    this.isNewArrival = false,
    this.averageRating = 0,
    this.totalReviews = 0,
    this.totalDownloads = 0,
    this.viewCount = 0,
    this.visibility = 'public',
    this.accessLevel,
    this.documentNumber,
    this.version = '1.0',
    this.department,
    this.confidentiality,
    this.status = 'published',
    this.uploadedBy,
    this.createdAt = '',
    this.updatedAt = '',
    this.publishedAt,
    this.isOwnContent,
    this.metaKeywords,           // ← NEW
  });

  factory Content.fromJson(Map<String, dynamic> json) {
    return Content(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled',
      subtitle: json['subtitle'] as String?,
      description: json['description'] as String?,
      contentType: json['content_type'] as String? ?? 'book',
      format: json['format'] as String?,
      author: json['author'] as String?,
      publisher: json['publisher'] as String?,
      publishedDate: json['published_date'] as String?,
      categoryId: json['category_id'] as String?,
      language: json['language'] as String?,
      coverImageUrl: json['cover_image_url'] as String?,
      backpageImageUrl: json['backpage_image_url'] as String?,       // ← NEW
      fileUrl: json['file_url'] as String?,
      fileSizeBytes: json['file_size_bytes'] as int?,
      pageCount: json['page_count'] as int?,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      originalPrice: (json['original_price'] as num?)?.toDouble(),  // ← NEW
      isFree: json['is_free'] as bool? ?? false,
      isForSale: json['is_for_sale'] as bool? ?? true,
      stockQuantity: json['stock_quantity'] as int? ?? 0,
      isbn: json['isbn'] as String?,
      isFeatured: json['is_featured'] as bool? ?? false,
      isBestseller: json['is_bestseller'] as bool? ?? false,
      isNewArrival: json['is_new_arrival'] as bool? ?? false,
      averageRating: (json['average_rating'] as num?)?.toDouble() ?? 0,
      totalReviews: json['total_reviews'] as int? ?? 0,
      totalDownloads: json['total_downloads'] as int? ?? 0,
      viewCount: json['view_count'] as int? ?? 0,
      visibility: json['visibility'] as String? ?? 'public',
      accessLevel: json['access_level'] as String?,
      documentNumber: json['document_number'] as String?,
      version: json['version'] as String? ?? '1.0',
      department: json['department'] as String?,
      confidentiality: json['confidentiality'] as String?,
      status: json['status'] as String? ?? 'published',
      uploadedBy: json['uploaded_by'] as String?,
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
      publishedAt: json['published_at'] as String?,
      isOwnContent: json['is_own_content'] as bool?,
      metaKeywords: (json['meta_keywords'] as List<dynamic>?)        // ← NEW
          ?.map((e) => e as String)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'description': description,
        'content_type': contentType,
        'format': format,
        'author': author,
        'publisher': publisher,
        'published_date': publishedDate,
        'category_id': categoryId,
        'language': language,
        'cover_image_url': coverImageUrl,
        'backpage_image_url': backpageImageUrl,  // ← NEW
        'file_url': fileUrl,
        'file_size_bytes': fileSizeBytes,
        'page_count': pageCount,
        'price': price,
        'original_price': originalPrice,         // ← NEW
        'is_free': isFree,
        'is_for_sale': isForSale,
        'stock_quantity': stockQuantity,
        'isbn': isbn,
        'is_featured': isFeatured,
        'is_bestseller': isBestseller,
        'is_new_arrival': isNewArrival,
        'average_rating': averageRating,
        'total_reviews': totalReviews,
        'total_downloads': totalDownloads,
        'view_count': viewCount,
        'visibility': visibility,
        'access_level': accessLevel,
        'document_number': documentNumber,
        'version': version,
        'department': department,
        'confidentiality': confidentiality,
        'status': status,
        'uploaded_by': uploadedBy,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'published_at': publishedAt,
        'meta_keywords': metaKeywords,           // ← NEW
      };

  Content copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? description,
    String? contentType,
    String? format,
    String? author,
    String? publisher,
    String? publishedDate,
    String? categoryId,
    String? language,
    String? coverImageUrl,
    String? backpageImageUrl,
    String? fileUrl,
    int? fileSizeBytes,
    int? pageCount,
    double? price,
    double? originalPrice,
    bool? isFree,
    bool? isForSale,
    int? stockQuantity,
    String? isbn,
    bool? isFeatured,
    bool? isBestseller,
    bool? isNewArrival,
    double? averageRating,
    int? totalReviews,
    int? totalDownloads,
    int? viewCount,
    String? visibility,
    String? accessLevel,
    String? documentNumber,
    String? version,
    String? department,
    String? confidentiality,
    String? status,
    String? uploadedBy,
    String? createdAt,
    String? updatedAt,
    String? publishedAt,
    bool? isOwnContent,
    List<String>? metaKeywords,
  }) =>
      Content(
        id: id ?? this.id,
        title: title ?? this.title,
        subtitle: subtitle ?? this.subtitle,
        description: description ?? this.description,
        contentType: contentType ?? this.contentType,
        format: format ?? this.format,
        author: author ?? this.author,
        publisher: publisher ?? this.publisher,
        publishedDate: publishedDate ?? this.publishedDate,
        categoryId: categoryId ?? this.categoryId,
        language: language ?? this.language,
        coverImageUrl: coverImageUrl ?? this.coverImageUrl,
        backpageImageUrl: backpageImageUrl ?? this.backpageImageUrl,
        fileUrl: fileUrl ?? this.fileUrl,
        fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
        pageCount: pageCount ?? this.pageCount,
        price: price ?? this.price,
        originalPrice: originalPrice ?? this.originalPrice,
        isFree: isFree ?? this.isFree,
        isForSale: isForSale ?? this.isForSale,
        stockQuantity: stockQuantity ?? this.stockQuantity,
        isbn: isbn ?? this.isbn,
        isFeatured: isFeatured ?? this.isFeatured,
        isBestseller: isBestseller ?? this.isBestseller,
        isNewArrival: isNewArrival ?? this.isNewArrival,
        averageRating: averageRating ?? this.averageRating,
        totalReviews: totalReviews ?? this.totalReviews,
        totalDownloads: totalDownloads ?? this.totalDownloads,
        viewCount: viewCount ?? this.viewCount,
        visibility: visibility ?? this.visibility,
        accessLevel: accessLevel ?? this.accessLevel,
        documentNumber: documentNumber ?? this.documentNumber,
        version: version ?? this.version,
        department: department ?? this.department,
        confidentiality: confidentiality ?? this.confidentiality,
        status: status ?? this.status,
        uploadedBy: uploadedBy ?? this.uploadedBy,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        publishedAt: publishedAt ?? this.publishedAt,
        isOwnContent: isOwnContent ?? this.isOwnContent,
        metaKeywords: metaKeywords ?? this.metaKeywords,
      );
}