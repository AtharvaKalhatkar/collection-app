class CatalogProduct {
  final String id;
  final String name;
  final String category;
  final String subcategory;
  final String company;
  final String firm;
  final String packing;
  final double mrp;
  final double rate;
  final String defaultUnit; // 'Pcs', 'Outer', 'Box', 'Nodes'
  final String? code;
  final int unitsPerCase;
  final double weightKg;
  final String? photoUrl;
  final String? photoBase64;
  final String availability;

  const CatalogProduct({
    required this.id,
    required this.name,
    required this.category,
    this.subcategory = 'General',
    required this.company,
    this.firm = 'Purva Enterprises',
    this.packing = '',
    this.mrp = 0.0,
    required this.rate,
    this.defaultUnit = 'Pcs',
    this.code,
    this.unitsPerCase = 24,
    this.weightKg = 0.0,
    this.photoUrl,
    this.photoBase64,
    this.availability = 'In Stock',
  });

  double get unitPrice => rate;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'subcategory': subcategory,
    'company': company,
    'firm': firm,
    'packing': packing,
    'mrp': mrp,
    'rate': rate,
    'defaultUnit': defaultUnit,
    'code': code,
    'unitsPerCase': unitsPerCase,
    'weightKg': weightKg,
    'photoUrl': photoUrl,
    'photoBase64': photoBase64,
    'availability': availability,
  };

  factory CatalogProduct.fromJson(Map<String, dynamic> json) => CatalogProduct(
    id: json['id'] as String,
    name: json['name'] as String,
    category: json['category'] as String? ?? 'General',
    subcategory: json['subcategory'] as String? ?? 'General',
    company: json['company'] as String? ?? '',
    firm: json['firm'] as String? ?? 'Purva Enterprises',
    packing: json['packing'] as String? ?? '',
    mrp: (json['mrp'] as num?)?.toDouble() ?? 0.0,
    rate: (json['rate'] as num?)?.toDouble() ?? 0.0,
    defaultUnit: json['defaultUnit'] as String? ?? 'Pcs',
    code: json['code'] as String?,
    unitsPerCase: (json['unitsPerCase'] as num?)?.toInt() ?? 24,
    weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0.0,
    photoUrl: json['photoUrl'] as String?,
    photoBase64: json['photoBase64'] as String?,
    availability: json['availability'] as String? ?? 'In Stock',
  );
}

class OrderItem {
  final String productId;
  final String productName;
  final String company;
  final String category;
  final String subcategory;
  final String packing;
  final double rate;
  int quantity;
  String unit; // 'Pcs', 'Outer', 'Box', 'Nodes'
  int cases;
  int units;
  int unitsPerCase;
  double weightKg;
  String? photoUrl;
  String? photoBase64;

  OrderItem({
    required this.productId,
    required this.productName,
    required this.company,
    required this.category,
    this.subcategory = 'General',
    required this.packing,
    required this.rate,
    required this.quantity,
    this.unit = 'Pcs',
    this.cases = 0,
    this.units = 0,
    this.unitsPerCase = 24,
    this.weightKg = 0.0,
    this.photoUrl,
    this.photoBase64,
  });

  double get unitPrice => rate;

  int get totalUnits {
    if (cases > 0 || units > 0) {
      return (cases * (unitsPerCase > 0 ? unitsPerCase : 1)) + units;
    }
    return quantity;
  }

  double get totalWeightKg => (weightKg > 0 ? weightKg * (cases > 0 ? cases : 1) : 0.0);

  double get subtotal {
    final effectiveUnits = totalUnits;
    return rate * (effectiveUnits > 0 ? effectiveUnits : quantity);
  }

  double get total => subtotal;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'productName': productName,
    'company': company,
    'category': category,
    'subcategory': subcategory,
    'packing': packing,
    'rate': rate,
    'quantity': totalUnits,
    'unit': unit,
    'cases': cases,
    'units': units,
    'unitsPerCase': unitsPerCase,
    'weightKg': weightKg,
    'photoUrl': photoUrl,
    'photoBase64': photoBase64,
    'subtotal': subtotal,
  };

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    productId: json['productId'] as String,
    productName: json['productName'] as String,
    company: json['company'] as String? ?? '',
    category: json['category'] as String? ?? '',
    subcategory: json['subcategory'] as String? ?? 'General',
    packing: json['packing'] as String? ?? '',
    rate: (json['rate'] as num?)?.toDouble() ?? 0.0,
    quantity: (json['quantity'] as num?)?.toInt() ?? 0,
    unit: json['unit'] as String? ?? 'Pcs',
    cases: (json['cases'] as num?)?.toInt() ?? 0,
    units: (json['units'] as num?)?.toInt() ?? 0,
    unitsPerCase: (json['unitsPerCase'] as num?)?.toInt() ?? 24,
    weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0.0,
    photoUrl: json['photoUrl'] as String?,
    photoBase64: json['photoBase64'] as String?,
  );

  OrderItem copyWith({
    int? quantity,
    String? unit,
    int? cases,
    int? units,
    int? unitsPerCase,
    double? weightKg,
    String? photoUrl,
    String? photoBase64,
  }) => OrderItem(
    productId: productId,
    productName: productName,
    company: company,
    category: category,
    subcategory: subcategory,
    packing: packing,
    rate: rate,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    cases: cases ?? this.cases,
    units: units ?? this.units,
    unitsPerCase: unitsPerCase ?? this.unitsPerCase,
    weightKg: weightKg ?? this.weightKg,
    photoUrl: photoUrl ?? this.photoUrl,
    photoBase64: photoBase64 ?? this.photoBase64,
  );
}

class SalesOrderModel {
  final String id;
  final String orderNumber;
  final String firm; // 'Purva Enterprises' or 'Manas Sales'
  final String routeId;
  final String routeName;
  final String shopId;
  final String shopName;
  final String shopMobile;
  final String salesmanName;
  final DateTime orderDate;
  final List<OrderItem> items;
  final double totalAmount;
  final int totalQuantity;
  final String status; // 'Booked', 'Dispatched', 'Delivered'
  final String? notes;

  SalesOrderModel({
    required this.id,
    required this.orderNumber,
    required this.firm,
    required this.routeId,
    required this.routeName,
    required this.shopId,
    required this.shopName,
    required this.shopMobile,
    required this.salesmanName,
    required this.orderDate,
    required this.items,
    required this.totalAmount,
    required this.totalQuantity,
    this.status = 'Booked',
    this.notes,
  });

  String get businessName => firm;

  int get totalCases => items.fold(0, (sum, i) => sum + i.cases);
  int get totalLooseUnits => items.fold(0, (sum, i) => sum + i.units);
  double get totalWeightKg => items.fold(0.0, (sum, i) => sum + i.totalWeightKg);
  int get linesCount => items.length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'orderNumber': orderNumber,
    'firm': firm,
    'routeId': routeId,
    'routeName': routeName,
    'shopId': shopId,
    'shopName': shopName,
    'shopMobile': shopMobile,
    'salesmanName': salesmanName,
    'orderDate': orderDate.toIso8601String(),
    'items': items.map((i) => i.toJson()).toList(),
    'totalAmount': totalAmount,
    'totalQuantity': totalQuantity,
    'status': status,
    'notes': notes,
  };

  factory SalesOrderModel.fromJson(Map<String, dynamic> json) => SalesOrderModel(
    id: json['id'] as String,
    orderNumber: json['orderNumber'] as String,
    firm: json['firm'] as String,
    routeId: json['routeId'] as String,
    routeName: json['routeName'] as String? ?? 'General Route',
    shopId: json['shopId'] as String,
    shopName: json['shopName'] as String,
    shopMobile: json['shopMobile'] as String? ?? '',
    salesmanName: json['salesmanName'] as String? ?? 'Akash',
    orderDate: json['orderDate'] != null
        ? DateTime.tryParse(json['orderDate'] as String) ?? DateTime.now()
        : DateTime.now(),
    items: (json['items'] as List<dynamic>? ?? [])
        .map((i) => OrderItem.fromJson(i as Map<String, dynamic>))
        .toList(),
    totalAmount: (json['totalAmount'] as num).toDouble(),
    totalQuantity: (json['totalQuantity'] as num).toInt(),
    status: json['status'] as String? ?? 'Booked',
    notes: json['notes'] as String?,
  );
}
