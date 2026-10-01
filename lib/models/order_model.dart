class CatalogProduct {
  final String id;
  final String name;
  final String category;
  final String company;
  final String firm;
  final String packing;
  final double mrp;
  final double rate;
  final String? code;

  const CatalogProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.company,
    required this.firm,
    required this.packing,
    required this.mrp,
    required this.rate,
    this.code,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'company': company,
    'firm': firm,
    'packing': packing,
    'mrp': mrp,
    'rate': rate,
    'code': code,
  };

  factory CatalogProduct.fromJson(Map<String, dynamic> json) => CatalogProduct(
    id: json['id'] as String,
    name: json['name'] as String,
    category: json['category'] as String,
    company: json['company'] as String,
    firm: json['firm'] as String,
    packing: json['packing'] as String? ?? '',
    mrp: (json['mrp'] as num).toDouble(),
    rate: (json['rate'] as num).toDouble(),
    code: json['code'] as String?,
  );
}

class OrderItem {
  final String productId;
  final String productName;
  final String company;
  final String category;
  final String packing;
  final double rate;
  int quantity;

  OrderItem({
    required this.productId,
    required this.productName,
    required this.company,
    required this.category,
    required this.packing,
    required this.rate,
    required this.quantity,
  });

  double get subtotal => rate * quantity;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'productName': productName,
    'company': company,
    'category': category,
    'packing': packing,
    'rate': rate,
    'quantity': quantity,
    'subtotal': subtotal,
  };

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    productId: json['productId'] as String,
    productName: json['productName'] as String,
    company: json['company'] as String? ?? '',
    category: json['category'] as String? ?? '',
    packing: json['packing'] as String? ?? '',
    rate: (json['rate'] as num).toDouble(),
    quantity: (json['quantity'] as num).toInt(),
  );

  OrderItem copyWith({int? quantity}) => OrderItem(
    productId: productId,
    productName: productName,
    company: company,
    category: category,
    packing: packing,
    rate: rate,
    quantity: quantity ?? this.quantity,
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
