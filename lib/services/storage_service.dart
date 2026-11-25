import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/route_model.dart';
import '../models/shop_model.dart';
import '../models/collection_model.dart';
import '../models/pending_bill_model.dart';
import '../models/order_model.dart';
import '../models/cash_handover_model.dart';
import '../models/vehicle_collection_model.dart';
import '../models/location_timeline_entry.dart';

class StorageService {
  static const String _keyRoutes = 'app_routes_v1';
  static const String _keyShops = 'app_shops_v1';
  static const String _keyCollections = 'app_collections_v1';
  static const String _keyPendingBills = 'app_pending_bills_v1';
  static const String _keySalesOrders = 'app_sales_orders_v1';
  static const String _keyCustomProducts = 'app_custom_products_v1';
  static const String _keyBusinesses = 'app_businesses_v1';
  static const String _keySalesman = 'app_salesman_name_v1';
  static const String _keySalesmanPhone = 'app_salesman_phone_v1';
  static const String _keySalesmanRole = 'app_salesman_role_v1';
  static const String _keyInitialized = 'app_sample_data_initialized_v1';
  static const String _keyDeletedBillIds = 'deleted_bill_ids_v1';
  static const String _keyDeletedCollectionIds = 'deleted_collection_ids_v1';
  static const String _keyDeletedShopIds = 'deleted_shop_ids_v1';
  static const String _keyDeletedRouteIds = 'deleted_route_ids_v1';
  static const String _keyCashHandovers = 'app_cash_handovers_v1';
  static const String _keyVehicleCollections = 'app_vehicle_collections_v1';
  static const String _keyVehicles = 'app_managed_vehicles_v1';
  static const String _keyEmployees = 'app_managed_employees_v1';
  static const String _keyLocationTimeline = 'app_location_timeline_v1';

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

  Future<String> loadSalesmanPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySalesmanPhone) ?? '+91 98765 43210';
  }

  Future<void> saveSalesmanPhone(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySalesmanPhone, phone);
  }

  Future<String> loadSalesmanRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySalesmanRole) ?? 'Field Collection & Sales Officer';
  }

  Future<void> saveSalesmanRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySalesmanRole, role);
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
        // Keep photos for recent 15 records, only trim older ones if storage limit hit
        final trimmed = <CollectionModel>[];
        for (int i = 0; i < collections.length; i++) {
          if (i < 15) {
            trimmed.add(collections[i]);
          } else {
            trimmed.add(collections[i].copyWith(photoBase64: null));
          }
        }
        final rawList = trimmed.map((c) => jsonEncode(c.toJson())).toList();
        await prefs.setStringList(_keyCollections, rawList);
      } catch (inner) {
        // Safe failover: in-memory state is preserved even if localStorage is completely locked
        // ignore: avoid_print
        debugPrint('LocalStorage write fallback note: $inner');
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
        // Fallback 1: Keep photos for recent 5 bills, strip older photos to stay within localStorage quota
        final trimmed = <PendingBillModel>[];
        for (int i = 0; i < bills.length; i++) {
          if (i < 5) {
            trimmed.add(bills[i]);
          } else {
            trimmed.add(bills[i].copyWith(photoBase64: null));
          }
        }
        final rawList = trimmed.map((b) => jsonEncode(b.toJson())).toList();
        await prefs.setStringList(_keyPendingBills, rawList);
      } catch (inner) {
        try {
          // Fallback 2: Strip ALL photos so bill records, bill numbers, amounts are NEVER lost
          final noPhotos = bills
              .map((b) => b.copyWith(photoBase64: null))
              .map((b) => jsonEncode(b.toJson()))
              .toList();
          await prefs.setStringList(_keyPendingBills, noPhotos);
        } catch (inner2) {
          // ignore: avoid_print
          debugPrint('LocalStorage pending bills save notice: $inner2');
        }
      }
    }
  }

  // --- Deleted Bill IDs Tracking ---
  Future<Set<String>> loadDeletedBillIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyDeletedBillIds) ?? [];
    return list.toSet();
  }

  Future<void> saveDeletedBillIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyDeletedBillIds, ids.toList());
  }

  // --- Deleted Collection IDs Tracking ---
  Future<Set<String>> loadDeletedCollectionIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyDeletedCollectionIds) ?? [];
    return list.toSet();
  }

  Future<void> saveDeletedCollectionIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyDeletedCollectionIds, ids.toList());
  }

  // --- Deleted Shop IDs Tracking ---
  Future<Set<String>> loadDeletedShopIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyDeletedShopIds) ?? [];
    return list.toSet();
  }

  Future<void> saveDeletedShopIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyDeletedShopIds, ids.toList());
  }

  // --- Deleted Route IDs Tracking ---
  Future<Set<String>> loadDeletedRouteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyDeletedRouteIds) ?? [];
    return list.toSet();
  }

  Future<void> saveDeletedRouteIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyDeletedRouteIds, ids.toList());
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
      debugPrint('LocalStorage sales orders save notice: $e');
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
      debugPrint('LocalStorage custom products save notice: $e');
    }
  }

  // --- Cash Handovers ---
  Future<List<CashHandoverModel>> loadCashHandovers() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_keyCashHandovers) ?? [];
    return rawList
        .map((s) => CashHandoverModel.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveCashHandovers(List<CashHandoverModel> handovers) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final rawList = handovers.map((h) => jsonEncode(h.toJson())).toList();
      await prefs.setStringList(_keyCashHandovers, rawList);
    } catch (e) {
      // ignore: avoid_print
      debugPrint('LocalStorage cash handovers save notice: $e');
    }
  }

  // --- Vehicle Collections ---
  Future<List<VehicleCollectionModel>> loadVehicleCollections() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_keyVehicleCollections) ?? [];
    return rawList
        .map((s) => VehicleCollectionModel.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveVehicleCollections(List<VehicleCollectionModel> list) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final rawList = list.map((v) => jsonEncode(v.toJson())).toList();
      await prefs.setStringList(_keyVehicleCollections, rawList);
    } catch (e) {
      // ignore: avoid_print
      debugPrint('LocalStorage vehicle collections save notice: $e');
    }
  }

  // --- Managed Vehicles ---
  Future<List<String>> loadVehicles() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyVehicles);
    if (list != null && list.isNotEmpty) {
      return list;
    }
    return ['MH 14 HG 2426', 'MH 14 GD 6212', 'MH 14 KA 2059'];
  }

  Future<void> saveVehicles(List<String> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyVehicles, list);
  }

  // --- Managed Employees ---
  Future<List<String>> loadEmployees() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyEmployees);
    if (list != null && list.isNotEmpty) {
      return list;
    }
    return ['Akash', 'Sahil', 'Office / Owner'];
  }

  Future<void> saveEmployees(List<String> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyEmployees, list);
  }

  // --- Location Timeline ---
  Future<List<LocationTimelineEntry>> loadLocationTimeline() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_keyLocationTimeline) ?? [];
    return rawList
        .map((s) => LocationTimelineEntry.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveLocationTimeline(List<LocationTimelineEntry> timeline) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      // Keep most recent 500 entries locally to prevent excessive memory usage
      final boundedList = timeline.length > 500 ? timeline.sublist(0, 500) : timeline;
      final rawList = boundedList.map((e) => jsonEncode(e.toJson())).toList();
      await prefs.setStringList(_keyLocationTimeline, rawList);
    } catch (e) {
      // ignore: avoid_print
      debugPrint('LocalStorage location timeline save notice: $e');
    }
  }

  /// Returns `true` if a new entry was inserted, or `false` if deduplicated.
  Future<bool> addLocationTimelineEntry(LocationTimelineEntry entry,
      {int minDuplicateSeconds = 60, double minMovedDegrees = 0.0001}) async {
    final existing = await loadLocationTimeline();
    // Prevent redundant stationary entries within threshold
    if (existing.isNotEmpty) {
      final last = existing.firstWhere(
        (e) => e.userId == entry.userId,
        orElse: () => entry,
      );
      if (last != entry &&
          last.eventType == entry.eventType &&
          entry.timestamp.difference(last.timestamp).inSeconds.abs() <
              minDuplicateSeconds &&
          (last.latitude - entry.latitude).abs() < minMovedDegrees &&
          (last.longitude - entry.longitude).abs() < minMovedDegrees) {
        return false;
      }
    }
    existing.insert(0, entry);
    await saveLocationTimeline(existing);
    return true;
  }

  // --- Persistent Sync Outbox Queues & Route Orders ---
  static const String _keyRouteOutletOrders = 'route_outlet_orders_v1';
  static const String keyPendingTimelineIds = 'pending_timeline_sync_ids_v1';

  Future<Set<String>> loadIdSet(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(key) ?? []).toSet();
    } catch (e) {
      debugPrint('LocalStorage loadIdSet($key) notice: $e');
      return <String>{};
    }
  }

  Future<void> saveIdSet(String key, Set<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, ids.toList());
    } catch (e) {
      debugPrint('LocalStorage saveIdSet($key) notice: $e');
    }
  }

  Future<bool> loadBoolFlag(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> saveBoolFlag(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      debugPrint('LocalStorage saveBoolFlag($key) notice: $e');
    }
  }

  Future<Map<String, List<String>>> loadRouteOutletOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_keyRouteOutletOrders);
      if (jsonStr == null) return {};
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      return decoded.map(
        (k, v) => MapEntry(k, (v as List).map((e) => e.toString()).toList()),
      );
    } catch (e) {
      debugPrint('LocalStorage route orders load notice: $e');
      return {};
    }
  }

  Future<void> saveRouteOutletOrders(Map<String, List<String>> orders) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyRouteOutletOrders, jsonEncode(orders));
    } catch (e) {
      debugPrint('LocalStorage route orders save notice: $e');
    }
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
