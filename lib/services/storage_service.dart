import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/route_model.dart';
import '../models/shop_model.dart';
import '../models/collection_model.dart';
import '../models/pending_bill_model.dart';
import '../models/order_model.dart';

class StorageService {
  static const String _keyRoutes = 'app_routes_v1';
  static const String _keyShops = 'app_shops_v1';
  static const String _keyCollections = 'app_collections_v1';
  static const String _keyPendingBills = 'app_pending_bills_v1';
  static const String _keySalesOrders = 'app_sales_orders_v1';
  static const String _keyCustomProducts = 'app_custom_products_v1';
  static const String _keyBusinesses = 'app_businesses_v1';
  static const String _keySalesman = 'app_salesman_name_v1';
  static const String _keyInitialized = 'app_sample_data_initialized_v1';

  Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_keyInitialized) ?? false);
  }

  Future<void> markInitialized() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyInitialized, true);
  }

  // --- Businesses ---
  Future<List<String>> loadBusinesses() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyBusinesses);
    if (list != null && list.isNotEmpty) {
      return list;
    }
    return ['Purva Enterprises', 'Manas Sales'];
  }

  Future<void> saveBusinesses(List<String> businesses) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyBusinesses, businesses);
  }

  // --- Salesman ---
  Future<String> loadSalesmanName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySalesman) ?? 'Akash';
  }

  Future<void> saveSalesmanName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySalesman, name);
  }

  // --- Routes ---
  Future<List<RouteModel>> loadRoutes() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_keyRoutes) ?? [];
    return rawList
        .map((s) => RouteModel.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveRoutes(List<RouteModel> routes) async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = routes.map((r) => jsonEncode(r.toJson())).toList();
    await prefs.setStringList(_keyRoutes, rawList);
  }

  // --- Shops ---
  Future<List<ShopModel>> loadShops() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_keyShops) ?? [];
    return rawList
        .map((s) => ShopModel.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveShops(List<ShopModel> shops) async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = shops.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_keyShops, rawList);
  }

  // --- Collections ---
  Future<List<CollectionModel>> loadCollections() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_keyCollections) ?? [];
    return rawList
        .map((s) => CollectionModel.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveCollections(List<CollectionModel> collections) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final rawList = collections.map((c) => jsonEncode(c.toJson())).toList();
      await prefs.setStringList(_keyCollections, rawList);
    } catch (e) {
      try {
        await prefs.remove(_keyCollections);
        final noPhotos = collections.map((c) => c.copyWith(photoBase64: null)).toList();
        final rawList = noPhotos.map((c) => jsonEncode(c.toJson())).toList();
        await prefs.setStringList(_keyCollections, rawList);
      } catch (inner) {
        // Safe failover: in-memory state is preserved even if localStorage is completely locked
        // ignore: avoid_print
        print('LocalStorage write fallback note: $inner');
      }
    }
  }

  // --- Pending Bills ---
  Future<List<PendingBillModel>> loadPendingBills() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_keyPendingBills) ?? [];
    return rawList
        .map((s) => PendingBillModel.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> savePendingBills(List<PendingBillModel> bills) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final rawList = bills.map((b) => jsonEncode(b.toJson())).toList();
      await prefs.setStringList(_keyPendingBills, rawList);
    } catch (e) {
      try {
        await prefs.remove(_keyPendingBills);
        final noPhotos = bills.map((b) => b.copyWith(photoBase64: null)).toList();
        final rawList = noPhotos.map((b) => jsonEncode(b.toJson())).toList();
        await prefs.setStringList(_keyPendingBills, rawList);
      } catch (inner) {
        // ignore: avoid_print
        print('LocalStorage pending bills save notice: $inner');
      }
    }
  }

  // --- Sales Orders ---
  Future<List<SalesOrderModel>> loadSalesOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_keySalesOrders) ?? [];
    return rawList
        .map((s) => SalesOrderModel.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveSalesOrders(List<SalesOrderModel> orders) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final rawList = orders.map((o) => jsonEncode(o.toJson())).toList();
      await prefs.setStringList(_keySalesOrders, rawList);
    } catch (e) {
      // ignore: avoid_print
      print('LocalStorage sales orders save notice: $e');
    }
  }

  // --- Custom Products Master ---
  Future<List<CatalogProduct>> loadCustomProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_keyCustomProducts) ?? [];
    return rawList
        .map((s) => CatalogProduct.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveCustomProducts(List<CatalogProduct> products) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final rawList = products.map((p) => jsonEncode(p.toJson())).toList();
      await prefs.setStringList(_keyCustomProducts, rawList);
    } catch (e) {
      // ignore: avoid_print
      print('LocalStorage custom products save notice: $e');
    }
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
