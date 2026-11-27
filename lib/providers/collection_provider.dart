import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../models/route_model.dart';
import '../models/shop_model.dart';
import '../models/collection_model.dart';
import '../models/pending_bill_model.dart';
import '../models/bill_summary.dart';
import '../models/order_model.dart';
import '../models/cash_handover_model.dart';
import '../models/vehicle_collection_model.dart';
import '../models/user_model.dart';
import '../models/location_timeline_entry.dart';
import '../models/attendance_record.dart';
import '../services/order_catalog_service.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';
import '../services/tally_integration_service.dart';
import '../services/backup_service.dart';
import '../services/auth_service.dart';
import '../services/location_tracking_service.dart';
import '../utils/currency_formatter.dart';
import '../utils/marathi_search_helper.dart';

class StaffCollectionSummary {
  final String staffName;
  final double totalAmount;
  final double cashAmount;
  final double upiAmount;
  final double chequeAmount;
  final int collectionsCount;
  final List<CollectionModel> collections;

  const StaffCollectionSummary({
    required this.staffName,
    required this.totalAmount,
    required this.cashAmount,
    required this.upiAmount,
    required this.chequeAmount,
    required this.collectionsCount,
    required this.collections,
  });
}

class CollectionProvider extends ChangeNotifier {
  final StorageService _storage;
  final SupabaseService _supabase;
  final BackupService _backupService = BackupService();

  static const String _keyDirtyRoutes = 'dirty_route_ids_v1';
  static const String _keyDirtyShops = 'dirty_shop_ids_v1';
  static const String _keyDirtyBills = 'dirty_bill_ids_v1';
  static const String _keyDirtyCollections = 'dirty_collection_ids_v1';
  static const String _keyDirtyOrders = 'dirty_order_ids_v1';
  static const String _keyDirtyProducts = 'dirty_product_ids_v1';
  static const String _keyDirtyHandovers = 'dirty_handover_ids_v1';
  static const String _keyDirtyVehicleCollections = 'dirty_vc_ids_v1';
  static const String _keyDirtyRouteOrders = 'dirty_route_order_ids_v1';
  static const String _keyDirtyVehiclesFlag = 'dirty_vehicles_flag_v1';
  static const String _keyDirtyEmployeesFlag = 'dirty_employees_flag_v1';

  static const String _keyDeletedOrders = 'deleted_order_ids_v1';
  static const String _keyCloudDeletedOrders = 'cloud_deleted_order_ids_v1';
  static const String _keyDeletedProducts = 'deleted_product_ids_v1';
  static const String _keyDeletedHandovers = 'deleted_handover_ids_v1';
  static const String _keyDeletedVehicleCollections = 'deleted_vc_ids_v1';

  Set<String> _dirtyRouteIds = {};
  Set<String> _dirtyShopIds = {};
  Set<String> _dirtyBillIds = {};
  Set<String> _dirtyCollectionIds = {};
  Set<String> _dirtyOrderIds = {};
  Set<String> _dirtyProductIds = {};
  Set<String> _dirtyHandoverIds = {};
  Set<String> _dirtyVehicleCollectionIds = {};
  Set<String> _dirtyRouteOrderIds = {};
  bool _dirtyVehiclesFlag = false;
  bool _dirtyEmployeesFlag = false;

  Set<String> _locallyDeletedOrderIds = {};
  Set<String> _cloudDeletedOrderIds = {};
  final Set<String> _sessionDeletedOrderIds = {};
  Set<String> _locallyDeletedProductIds = {};
  Set<String> _locallyDeletedHandoverIds = {};
  Set<String> _locallyDeletedVehicleCollectionIds = {};

  Map<String, List<String>> _routeOutletOrders = {};
  Future<void>? _activeSyncFuture;
  Future<void> Function(List<UserModel>)? onUsersSynced;

  Future<void> _loadSyncOutboxes() async {
    _dirtyRouteIds = await _storage.loadIdSet(_keyDirtyRoutes);
    _dirtyShopIds = await _storage.loadIdSet(_keyDirtyShops);
    _dirtyBillIds = await _storage.loadIdSet(_keyDirtyBills);
    _dirtyCollectionIds = await _storage.loadIdSet(_keyDirtyCollections);
    _dirtyOrderIds = await _storage.loadIdSet(_keyDirtyOrders);
    _dirtyProductIds = await _storage.loadIdSet(_keyDirtyProducts);
    _dirtyHandoverIds = await _storage.loadIdSet(_keyDirtyHandovers);
    _dirtyVehicleCollectionIds =
        await _storage.loadIdSet(_keyDirtyVehicleCollections);
    _dirtyRouteOrderIds = await _storage.loadIdSet(_keyDirtyRouteOrders);
    _dirtyVehiclesFlag = await _storage.loadBoolFlag(_keyDirtyVehiclesFlag);
    _dirtyEmployeesFlag = await _storage.loadBoolFlag(_keyDirtyEmployeesFlag);

    _locallyDeletedOrderIds = await _storage.loadIdSet(_keyDeletedOrders);
    _cloudDeletedOrderIds = await _storage.loadIdSet(_keyCloudDeletedOrders);
    _locallyDeletedProductIds = await _storage.loadIdSet(_keyDeletedProducts);
    _locallyDeletedHandoverIds =
        await _storage.loadIdSet(_keyDeletedHandovers);
    _locallyDeletedVehicleCollectionIds =
        await _storage.loadIdSet(_keyDeletedVehicleCollections);
    _routeOutletOrders = await _storage.loadRouteOutletOrders();
  }

  /// Merges an authoritative cloud list [cloudItems] with [localItems] using
  /// persistent [dirtyIds] and [deletedIds], detecting real content changes.
  List<T>? _mergeCloudEntity<T>({
    required List<T> localItems,
    required List<T> cloudItems,
    required Set<String> dirtyIds,
    required Set<String> deletedIds,
    required String Function(T) idOf,
    required bool Function(T local, T cloud) differs,
    bool pruneMissingSynced = true,
  }) {
    final cloudMap = <String, T>{};
    for (final c in cloudItems) {
      final id = idOf(c);
      if (!deletedIds.contains(id)) {
        cloudMap[id] = c;
      }
    }

    final localMap = <String, T>{for (final l in localItems) idOf(l): l};
    final result = <T>[];
    final seen = <String>{};
    bool changed = false;

    for (final c in cloudMap.values) {
      final id = idOf(c);
      seen.add(id);
      final local = localMap[id];
      if (dirtyIds.contains(id) && local != null) {
        result.add(local);
      } else {
        result.add(c);
        if (local == null || differs(local, c)) {
          changed = true;
        }
      }
    }

    for (final l in localItems) {
      final id = idOf(l);
      if (seen.contains(id)) continue;
      if (dirtyIds.contains(id) || !pruneMissingSynced) {
        result.add(l);
      } else if (!deletedIds.contains(id)) {
        // Deleted on another device
        changed = true;
      }
    }

    if (result.length != localItems.length) {
      changed = true;
    }
    return changed ? result : null;
  }

  void _applyStoredRouteOrdersToShops() {
    if (_routeOutletOrders.isEmpty || _shops.isEmpty) return;
    final rankByRoute = <String, Map<String, int>>{};
    for (final entry in _routeOutletOrders.entries) {
      rankByRoute[entry.key] = {
        for (int i = 0; i < entry.value.length; i++) entry.value[i]: i,
      };
    }
    _shops.sort((a, b) {
      final rA = rankByRoute[a.routeId]?[a.id];
      final rB = rankByRoute[b.routeId]?[b.id];
      if (rA != null && rB != null) return rA.compareTo(rB);
      if (rA != null) return -1;
      if (rB != null) return 1;
      return 0;
    });
  }
  final Uuid _uuid = const Uuid();
  DateTime? _lastBackupTime;

  StreamSubscription<List<PendingBillModel>>? _pendingBillsSubscription;
  StreamSubscription<List<CollectionModel>>? _collectionsSubscription;
  StreamSubscription<List<ShopModel>>? _shopsSubscription;
  StreamSubscription<List<RouteModel>>? _routesSubscription;
  Timer? _autoSyncTimer;
  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;
  List<RouteModel> _routes = [];
  List<ShopModel> _shops = [];
  List<CollectionModel> _collections = [];
  List<PendingBillModel> _pendingBills = [];
  List<CashHandoverModel> _cashHandovers = [];
  List<VehicleCollectionModel> _vehicleCollections = [];
  List<String> _vehicles = [];
  List<String> _employees = [];
  Set<String> _locallyDeletedBillIds = {};
  Set<String> _locallyDeletedCollectionIds = {};
  Set<String> _locallyDeletedShopIds = {};
  Set<String> _locallyDeletedRouteIds = {};
  List<SalesOrderModel> _salesOrders = [];
  List<CatalogProduct> _customProducts = [];
  List<String> _businesses = ['Purva Enterprises', 'Manas Sales'];
  String _salesmanName = 'Akash';
  String _salesmanPhone = '+91 98765 43210';
  String _salesmanRole = 'Field Collection & Sales Officer';
  UserModel? _currentUser;
  String? _selectedStaffFilter; // null or 'All' means all staff. Super Admin can select a specific staff member.
  bool _isLoading = true;

  UserModel? get currentUser => _currentUser;
  String? get selectedStaffFilter => _selectedStaffFilter;

  void setCurrentUser(UserModel? user) {
    _currentUser = user;
    _filteredCollectionsCache = null;
    if (user != null) {
      _salesmanName = user.name;
      _salesmanPhone = user.phone;
      _salesmanRole = user.roleDisplayName;
      if (_shouldFilterByAssignedRoutes &&
          _filterRouteId != null &&
          !user.assignedRouteIds.contains(_filterRouteId)) {
        _filterRouteId = null;
      }
    }
    notifyListeners();
  }

  void setSelectedStaffFilter(String? staffName) {
    if (staffName == null || staffName.trim().isEmpty || staffName == 'All') {
      _selectedStaffFilter = null;
    } else {
      _selectedStaffFilter = staffName.trim();
    }
    notifyListeners();
  }

  // Filters for Dashboard & Collection List
  DateTime _selectedDate = DateTime.now();
  String? _filterBusiness; // null means 'All'
  String? _filterRouteId; // null means 'All'
  String _searchQuery = '';

  bool get _shouldFilterByAssignedRoutes {
    if (_currentUser == null) return false;
    if (_currentUser!.isSuperAdmin) return false;
    if (_currentUser!.isDriver) return true;
    return _currentUser!.assignedRouteIds.isNotEmpty;
  }

  List<RouteModel> get routes {
    final list = List<RouteModel>.from(_routes);
    if (_shouldFilterByAssignedRoutes) {
      final assigned = _currentUser!.assignedRouteIds;
      list.retainWhere((r) => assigned.contains(r.id));
    }
    list.sort((a, b) => a.priority.compareTo(b.priority));
    return list;
  }

  List<RouteModel> get allRoutes {
    final list = List<RouteModel>.from(_routes);
    list.sort((a, b) => a.priority.compareTo(b.priority));
    return list;
  }

  String getRouteName(String routeId) {
    return _routes.firstWhere(
      (r) => r.id == routeId,
      orElse: () => RouteModel(id: routeId, name: 'Unknown Route'),
    ).name;
  }

  List<ShopModel> get shops {
    if (_shouldFilterByAssignedRoutes) {
      final assigned = _currentUser!.assignedRouteIds;
      return _shops.where((s) => assigned.contains(s.routeId)).toList();
    }
    return _shops;
  }

  List<ShopModel> get allShops => _shops;

  List<CollectionModel> get collections => _collections;

  List<PendingBillModel> get pendingBills {
    if (_shouldFilterByAssignedRoutes) {
      final assigned = _currentUser!.assignedRouteIds;
      return _pendingBills.where((b) => assigned.contains(b.routeId)).toList();
    }
    return _pendingBills;
  }

  List<PendingBillModel> get allPendingBills => _pendingBills;
  List<CashHandoverModel> get cashHandovers => _cashHandovers;
  List<VehicleCollectionModel> get vehicleCollections => _vehicleCollections;
  List<String> get vehicles => List.unmodifiable(_vehicles);
  List<String> get employees => List.unmodifiable(_employees);
  List<SalesOrderModel> get salesOrders => _salesOrders;
  List<CatalogProduct> get customProducts => _customProducts;
  List<String> get businesses => _businesses;
  String get salesmanName => _salesmanName;
  String get salesmanPhone => _salesmanPhone;
  String get salesmanRole => _salesmanRole;
  bool get isLoading => _isLoading;
  DateTime get selectedDate => _selectedDate;
  String? get filterBusiness => _filterBusiness;
  String? get filterRouteId => _filterRouteId;
  String get searchQuery => _searchQuery;
  bool get isCloudConnected => _supabase.isInitialized;
  bool get isSupabaseConnected => _supabase.isInitialized;
  bool get isFirebaseConnected => isCloudConnected;
  String? get cloudError => _supabase.lastError;
  String? get firebaseError => cloudError;
  DateTime? get lastBackupTime => _lastBackupTime;

  Future<bool> triggerManualBackup() async {
    final authService = AuthService();
    final users = await authService.loadUsers();
    final success = await _backupService.createBackup(
      routes: _routes,
      shops: _shops,
      collections: _collections,
      pendingBills: _pendingBills,
      users: users,
      trigger: 'manual',
    );
    if (success) {
      _lastBackupTime = DateTime.now();
      notifyListeners();
    }
    return success;
  }

  Future<void>? _initFuture;

  CollectionProvider({
    StorageService? storage,
    SupabaseService? supabase,
    bool autoInitialize = true,
  })  : _storage = storage ?? StorageService(),
        _supabase = supabase ?? SupabaseService() {
    if (autoInitialize) {
      initialize();
    }
  }

  Future<void> initialize() => _initFuture ??= _performInitialize();

  Future<void> _performInitialize() async {
    _isLoading = true;
    notifyListeners();

    // 1. Initialize local cache first for instant UI availability
    final isFirst = await _storage.isFirstLaunch();
    if (isFirst) {
      _routes = [];
      _shops = [];
      _collections = [];
      _pendingBills = [];
      _businesses = ['Purva Enterprises', 'Manas Sales'];
      _salesmanName = 'Akash';
      _vehicles = ['MH 14 HG 2426', 'MH 14 GD 6212', 'MH 14 KA 2059'];
      _employees = ['Akash', 'Sahil', 'Office / Owner'];

      await _storage.saveBusinesses(_businesses);
      await _storage.saveSalesmanName(_salesmanName);
      await _storage.saveVehicles(_vehicles);
      await _storage.saveEmployees(_employees);
      await _storage.markInitialized();
    } else {
      _routes = await _storage.loadRoutes();
      _shops = await _storage.loadShops();
      _collections = await _storage.loadCollections();
      _pendingBills = await _storage.loadPendingBills();
      _cashHandovers = await _storage.loadCashHandovers();
      _vehicleCollections = await _storage.loadVehicleCollections();
      _vehicles = await _storage.loadVehicles();
      _employees = await _storage.loadEmployees();
      _locallyDeletedBillIds = await _storage.loadDeletedBillIds();
      _locallyDeletedCollectionIds = await _storage.loadDeletedCollectionIds();
      _locallyDeletedShopIds = await _storage.loadDeletedShopIds();
      _locallyDeletedRouteIds = await _storage.loadDeletedRouteIds();

      if (_locallyDeletedCollectionIds.isNotEmpty) {
        _collections.removeWhere((c) => _locallyDeletedCollectionIds.contains(c.id));
      }
      if (_locallyDeletedBillIds.isNotEmpty) {
        _pendingBills.removeWhere((b) => _locallyDeletedBillIds.contains(b.id));
      }
      if (_locallyDeletedShopIds.isNotEmpty) {
        _shops.removeWhere((s) => _locallyDeletedShopIds.contains(s.id));
      }
      if (_locallyDeletedRouteIds.isNotEmpty) {
        _routes.removeWhere((r) => _locallyDeletedRouteIds.contains(r.id));
      }

      // Auto-purge only exact legacy sample dummy IDs (col-1..col-6, pb-1..pb-4, shop-*)
      const legacyDummyCollectionIds = {'col-1', 'col-2', 'col-3', 'col-4', 'col-5', 'col-6'};
      const legacyDummyBillIds = {'pb-1', 'pb-2', 'pb-3', 'pb-4'};
      final hadDummyCol = _collections.any((c) => legacyDummyCollectionIds.contains(c.id));
      final hadDummyPb = _pendingBills.any((b) => legacyDummyBillIds.contains(b.id));
      final hadDummyShop = _shops.any(_isDummyShop);
      if (hadDummyCol || hadDummyPb || hadDummyShop) {
        _collections.removeWhere((c) => legacyDummyCollectionIds.contains(c.id));
        _pendingBills.removeWhere((b) => legacyDummyBillIds.contains(b.id));
        _shops.removeWhere(_isDummyShop);
        await _storage.saveCollections(_collections);
        await _storage.savePendingBills(_pendingBills);
        await _storage.saveShops(_shops);
      }

      // Auto-sanitize any legacy bloated test photos (>600KB base64) so they don't freeze localStorage
      bool hadBloatedPhotos = false;
      for (int i = 0; i < _pendingBills.length; i++) {
        final b = _pendingBills[i];
        if (b.photoBase64 != null && b.photoBase64!.length > 600000) {
          _pendingBills[i] = b.copyWith(photoBase64: null, clearPhoto: true);
          hadBloatedPhotos = true;
        }
      }
      if (hadBloatedPhotos) {
        await _storage.savePendingBills(_pendingBills);
      }

      final deduped = _deduplicateShops(_shops);
      if (deduped.length != _shops.length) {
        _shops = deduped;
        await _storage.saveShops(_shops);
      }
      _businesses = await _storage.loadBusinesses();
      _salesmanName = await _storage.loadSalesmanName();
      _salesmanPhone = await _storage.loadSalesmanPhone();
      _salesmanRole = await _storage.loadSalesmanRole();
      _salesOrders = await _storage.loadSalesOrders();

      // One-time cleanup of legacy dummy mock records only (never wipe real production data).
      final prefs = await SharedPreferences.getInstance();
      final legacyCleaned = prefs.getBool('legacy_dummy_cleaned_v6') ?? false;
      if (!legacyCleaned) {
        _collections.removeWhere((c) => _isDummyShopIdName(c.shopId, c.shopName));
        _pendingBills.removeWhere((b) => _isDummyShopIdName(b.shopId, b.shopName));
        await _storage.saveCollections(_collections);
        await _storage.savePendingBills(_pendingBills);
        await prefs.setBool('legacy_dummy_cleaned_v6', true);
      }
    }

    // Load persistent dirty outbox queues & custom route orders for ALL setups
    await _loadSyncOutboxes();
    if (_locallyDeletedOrderIds.isNotEmpty || _cloudDeletedOrderIds.isNotEmpty) {
      final tombstoned = {..._locallyDeletedOrderIds, ..._cloudDeletedOrderIds};
      _salesOrders.removeWhere((o) => tombstoned.contains(o.id));
      _dirtyOrderIds.removeAll(tombstoned);
    }

    // Load custom products for both fresh and existing setups
    _customProducts = await _storage.loadCustomProducts();
    OrderCatalogService.setCustomProducts(_customProducts);

    _routes.sort((a, b) => a.priority.compareTo(b.priority));
    bool routesResave = false;
    for (int i = 0; i < _routes.length; i++) {
      if (_routes[i].priority != i + 1) {
        _routes[i] = _routes[i].copyWith(priority: i + 1);
        routesResave = true;
      }
    }
    if (routesResave) {
      await _storage.saveRoutes(_routes);
    }

    // Fast check: if local storage has no routes or shops yet (e.g. fresh launch or new device),
    // pre-fetch routes and shops from Supabase before unlocking UI
    try {
      await _supabase.init();
      await LocationTrackingService().flushPendingTimelineToCloud();
      if (_supabase.isInitialized && (_routes.isEmpty || _shops.isEmpty)) {
        final routesRes = await _supabase.fetchRoutesWithStatus();
        if (routesRes.success && routesRes.items.isNotEmpty) {
          _routes = routesRes.items
              .where((r) => !_locallyDeletedRouteIds.contains(r.id))
              .toList()
            ..sort((a, b) => a.priority.compareTo(b.priority));
          await _storage.saveRoutes(_routes);
        }
        final shopsRes = await _supabase.fetchShopsWithStatus();
        if (shopsRes.success && shopsRes.items.isNotEmpty) {
          final clean = shopsRes.items
              .where((s) => !_isDummyShop(s) && !_locallyDeletedShopIds.contains(s.id))
              .toList();
          _shops = _deduplicateShops(clean);
          _applyStoredRouteOrdersToShops();
          await _storage.saveShops(_shops);
        }
      }
    } catch (e) {
      debugPrint('Supabase initial fetch notice: $e');
    }

    // Instant UI load from local cache / prefetch
    _isLoading = false;
    notifyListeners();

    // 2. Initialize Supabase in background, perform 2-way sync, and start real-time sync timer
    syncAllWithCloud(notify: false, syncShopsAndRoutes: true);
    _startAutoSyncTimer();
  }

  bool _isDummyShopIdName(String shopId, String shopName) {
    if (shopId.startsWith('shop-') || shopId.startsWith('sample-')) return true;
    const dummyNames = {
      'ata kirana',
      'shree ganesh traders',
      'mahesh provision store',
      'sai krupa supermarket',
      'om traders',
    };
    return dummyNames.contains(shopName.trim().toLowerCase());
  }

  bool _isDummyShop(ShopModel s) => _isDummyShopIdName(s.id, s.name);

  bool _billsDiffer(PendingBillModel a, PendingBillModel b) {
    if (a.businessName != b.businessName ||
        a.shopId != b.shopId ||
        a.shopName != b.shopName ||
        a.routeId != b.routeId ||
        a.routeName != b.routeName ||
        a.billNumber != b.billNumber ||
        a.invoiceDate != b.invoiceDate ||
        a.deliveryDate != b.deliveryDate ||
        a.totalAmount != b.totalAmount ||
        a.collectedAmount != b.collectedAmount ||
        a.status != b.status ||
        a.photosBase64.length != b.photosBase64.length) {
      return true;
    }
    for (int i = 0; i < a.photosBase64.length; i++) {
      if (a.photosBase64[i] != b.photosBase64[i]) return true;
    }
    return false;
  }

  bool _collectionsDiffer(CollectionModel a, CollectionModel b) =>
      a.businessName != b.businessName ||
      a.shopId != b.shopId ||
      a.shopName != b.shopName ||
      a.routeId != b.routeId ||
      a.routeName != b.routeName ||
      a.billNumber != b.billNumber ||
      a.billAmount != b.billAmount ||
      a.collectedAmount != b.collectedAmount ||
      a.balanceRemaining != b.balanceRemaining ||
      a.paymentMode != b.paymentMode ||
      a.chequeNumber != b.chequeNumber ||
      a.referenceNumber != b.referenceNumber ||
      a.bankName != b.bankName ||
      a.remarks != b.remarks ||
      a.salesmanName != b.salesmanName ||
      a.billDate != b.billDate ||
      a.collectedAt != b.collectedAt;

  bool _shopsDiffer(ShopModel a, ShopModel b) =>
      a.name != b.name ||
      a.routeId != b.routeId ||
      a.routeName != b.routeName ||
      a.mobileNumber != b.mobileNumber ||
      a.address != b.address ||
      a.ownerName != b.ownerName ||
      a.locationUrl != b.locationUrl ||
      a.latitude != b.latitude ||
      a.longitude != b.longitude;

  bool _routesDiffer(RouteModel a, RouteModel b) =>
      a.name != b.name ||
      a.priority != b.priority ||
      a.description != b.description;

  bool _ordersDiffer(SalesOrderModel a, SalesOrderModel b) =>
      a.status != b.status ||
      a.notes != b.notes ||
      a.totalAmount != b.totalAmount ||
      a.totalQuantity != b.totalQuantity ||
      a.items.length != b.items.length ||
      a.updatedAt != b.updatedAt ||
      a.shopName != b.shopName ||
      a.routeName != b.routeName;

  bool _productsDiffer(CatalogProduct a, CatalogProduct b) =>
      jsonEncode(a.toJson()) != jsonEncode(b.toJson());

  bool _handoversDiffer(CashHandoverModel a, CashHandoverModel b) =>
      jsonEncode(a.toJson()) != jsonEncode(b.toJson());

  bool _vehicleCollectionsDiffer(
          VehicleCollectionModel a, VehicleCollectionModel b) =>
      jsonEncode(a.toJson()) != jsonEncode(b.toJson());

  void _cascadeShopUpdates() {
    bool colChanged = false;
    bool billChanged = false;
    final shopMap = {for (final s in _shops) s.id: s};
    for (int i = 0; i < _collections.length; i++) {
      final s = shopMap[_collections[i].shopId];
      if (s != null &&
          (_collections[i].shopName != s.name ||
              _collections[i].routeName != s.routeName)) {
        _collections[i] =
            _collections[i].copyWith(shopName: s.name, routeName: s.routeName);
        colChanged = true;
      }
    }
    for (int i = 0; i < _pendingBills.length; i++) {
      final s = shopMap[_pendingBills[i].shopId];
      if (s != null &&
          (_pendingBills[i].shopName != s.name ||
              _pendingBills[i].routeName != s.routeName)) {
        _pendingBills[i] =
            _pendingBills[i].copyWith(shopName: s.name, routeName: s.routeName);
        billChanged = true;
      }
    }
    if (colChanged) _storage.saveCollections(_collections);
    if (billChanged) _storage.savePendingBills(_pendingBills);
  }

  List<ShopModel> _deduplicateShops(List<ShopModel> list) {
    final seenIds = <String>{};
    final seenKeys = <String>{};
    final result = <ShopModel>[];
    for (final s in list) {
      final key = '${s.name.trim().toLowerCase()}_${s.routeId}';
      if (seenIds.add(s.id) && seenKeys.add(key)) {
        result.add(s);
      }
    }
    return result;
  }

  // --- Performance Caches ---
  List<CollectionModel>? _filteredCollectionsCache;
  DateTime? _cachedForDate;
  String? _cachedStaffOverride;
  String? _cachedFilterBusiness;
  String? _cachedFilterRouteId;
  String? _cachedSelectedStaffFilter;
  String? _cachedSearchQuery;
  Map<String, double>? _shopBalanceCache;
  List<BillSummary>? _allBillSummariesCache;
  Map<String, BillSummary>? _billSummaryMapCache;

  void _invalidateCaches() {
    _filteredCollectionsCache = null;
    _shopBalanceCache = null;
    _allBillSummariesCache = null;
    _billSummaryMapCache = null;
  }

  @override
  void notifyListeners() {
    _invalidateCaches();
    super.notifyListeners();
  }

  void _startAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    if (_supabase.isTestMode) return;
    // Optimized 3-minute background fallback poll; Realtime WebSockets deliver immediate updates with zero polling bandwidth
    _autoSyncTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      syncAllWithCloud(notify: false, syncShopsAndRoutes: false);
    });
  }

  void _setupRealtimeListeners() {
    if (!_supabase.isInitialized) return;

    if (_pendingBillsSubscription == null) {
      final billStream = _supabase.streamPendingBills();
      if (billStream != null) {
        _pendingBillsSubscription = billStream.listen((cloudBills) async {
          final merged = _mergeCloudEntity<PendingBillModel>(
            localItems: _pendingBills,
            cloudItems: cloudBills,
            dirtyIds: _dirtyBillIds,
            deletedIds: _locallyDeletedBillIds,
            idOf: (b) => b.id,
            differs: _billsDiffer,
            pruneMissingSynced: true,
          );
          if (merged != null) {
            merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            _pendingBills = merged;
            _invalidateCaches();
            notifyListeners();
            await _storage.savePendingBills(_pendingBills);
          }
        }, onError: (e) {
          debugPrint('Realtime pending_bills error: $e');
        });
      }
    }

    if (_collectionsSubscription == null) {
      final collStream = _supabase.streamCollections();
      if (collStream != null) {
        _collectionsSubscription = collStream.listen((cloudColls) async {
          final merged = _mergeCloudEntity<CollectionModel>(
            localItems: _collections,
            cloudItems: cloudColls,
            dirtyIds: _dirtyCollectionIds,
            deletedIds: _locallyDeletedCollectionIds,
            idOf: (c) => c.id,
            differs: _collectionsDiffer,
            pruneMissingSynced: true,
          );
          if (merged != null) {
            merged.sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
            _collections = merged;
            _invalidateCaches();
            notifyListeners();
            await _storage.saveCollections(_collections);
          }
        }, onError: (e) {
          debugPrint('Realtime collections error: $e');
        });
      }
    }

    if (_shopsSubscription == null) {
      final shopStream = _supabase.streamShops();
      if (shopStream != null) {
        _shopsSubscription = shopStream.listen((cloudShops) async {
          final cleanCloudShops = <ShopModel>[];
          for (final s in cloudShops) {
            if (_isDummyShop(s)) {
              _supabase.deleteShop(s.id);
            } else if (!_locallyDeletedShopIds.contains(s.id)) {
              cleanCloudShops.add(s);
            }
          }
          final merged = _mergeCloudEntity<ShopModel>(
            localItems: _shops,
            cloudItems: _deduplicateShops(cleanCloudShops),
            dirtyIds: _dirtyShopIds,
            deletedIds: _locallyDeletedShopIds,
            idOf: (s) => s.id,
            differs: _shopsDiffer,
            pruneMissingSynced: cleanCloudShops.isNotEmpty,
          );
          if (merged != null) {
            _shops = _deduplicateShops(merged);
            _applyStoredRouteOrdersToShops();
            _cascadeShopUpdates();
            _invalidateCaches();
            notifyListeners();
            await _storage.saveShops(_shops);
          }
        }, onError: (e) {
          debugPrint('Realtime shops error: $e');
        });
      }
    }

    if (_routesSubscription == null) {
      final routeStream = _supabase.streamRoutes();
      if (routeStream != null) {
        _routesSubscription = routeStream.listen((cloudRoutes) async {
          final merged = _mergeCloudEntity<RouteModel>(
            localItems: _routes,
            cloudItems: cloudRoutes,
            dirtyIds: _dirtyRouteIds,
            deletedIds: _locallyDeletedRouteIds,
            idOf: (r) => r.id,
            differs: _routesDiffer,
            pruneMissingSynced: cloudRoutes.isNotEmpty,
          );
          if (merged != null) {
            merged.sort((a, b) => a.priority.compareTo(b.priority));
            _routes = merged;
            _invalidateCaches();
            notifyListeners();
            await _storage.saveRoutes(_routes);
          }
        }, onError: (e) {
          debugPrint('Realtime routes error: $e');
        });
      }
    }
  }

  Future<bool> syncAllWithCloud({bool notify = true, bool? syncShopsAndRoutes}) async {
    if (_activeSyncFuture != null) {
      await _activeSyncFuture;
      return true;
    }
    final completer = Completer<void>();
    _activeSyncFuture = completer.future;
    try {
      return await _runSyncAllWithCloud(
        notify: notify,
        syncShopsAndRoutes: syncShopsAndRoutes,
      );
    } finally {
      _activeSyncFuture = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<bool> _runSyncAllWithCloud({bool notify = true, bool? syncShopsAndRoutes}) async {
    if (_isSyncing) return true;
    _isSyncing = true;
    if (notify) notifyListeners();

    final shouldSyncShops = syncShopsAndRoutes ?? (notify || _shops.isEmpty || _routes.isEmpty);

    try {
      if (!_supabase.isInitialized) {
        await _supabase.init();
      }
      if (!_supabase.isInitialized) {
        _isSyncing = false;
        if (notify) notifyListeners();
        return false;
      }

      bool hasDataChanged = false;

      // 0. Flush any pending offline GPS/action timeline events first
      await LocationTrackingService().flushPendingTimelineToCloud();

      // 1. Synchronize Routes & Route Outlet Ordering (Flush deletes -> Push dirty -> Pull)
      if (_locallyDeletedRouteIds.isNotEmpty) {
        final ids = _locallyDeletedRouteIds.toList();
        if (await _supabase.deleteRoutesBulk(ids)) {
          _locallyDeletedRouteIds.clear();
          await _storage.saveDeletedRouteIds(_locallyDeletedRouteIds);
        }
      }
      if (_dirtyRouteIds.isNotEmpty) {
        final dirty = _routes.where((r) => _dirtyRouteIds.contains(r.id)).toList();
        if (dirty.isEmpty || await _supabase.saveRoutesBulk(dirty)) {
          _dirtyRouteIds.clear();
          await _storage.saveIdSet(_keyDirtyRoutes, _dirtyRouteIds);
        }
      }
      if (shouldSyncShops || _routes.isEmpty) {
        final routesRes = await _supabase.fetchRoutesWithStatus();
        if (routesRes.success && (routesRes.items.isNotEmpty || _dirtyRouteIds.isEmpty)) {
          final merged = _mergeCloudEntity<RouteModel>(
            localItems: _routes,
            cloudItems: routesRes.items,
            dirtyIds: _dirtyRouteIds,
            deletedIds: _locallyDeletedRouteIds,
            idOf: (r) => r.id,
            differs: _routesDiffer,
            pruneMissingSynced: routesRes.items.isNotEmpty,
          );
          if (merged != null) {
            merged.sort((a, b) => a.priority.compareTo(b.priority));
            _routes = merged;
            await _storage.saveRoutes(_routes);
            hasDataChanged = true;
          }
        }
      }
      if (_dirtyRouteOrderIds.isNotEmpty) {
        final remainingOrders = <String>{};
        for (final rId in _dirtyRouteOrderIds) {
          final orderedIds = _routeOutletOrders[rId] ??
              _shops.where((s) => s.routeId == rId).map((s) => s.id).toList();
          final ok = await _supabase.saveRouteOutletOrder(rId, orderedIds);
          if (!ok) remainingOrders.add(rId);
        }
        _dirtyRouteOrderIds = remainingOrders;
        await _storage.saveIdSet(_keyDirtyRouteOrders, _dirtyRouteOrderIds);
      }
      if (shouldSyncShops) {
        final orderRes = await _supabase.fetchAllRouteOutletOrdersWithStatus();
        if (orderRes.success && orderRes.items.isNotEmpty) {
          bool ordersChanged = false;
          for (final entry in orderRes.items) {
            if (_dirtyRouteOrderIds.contains(entry.key)) continue;
            final existing = _routeOutletOrders[entry.key];
            if (existing == null || existing.join(',') != entry.value.join(',')) {
              _routeOutletOrders[entry.key] = entry.value;
              ordersChanged = true;
            }
          }
          if (ordersChanged) {
            await _storage.saveRouteOutletOrders(_routeOutletOrders);
            _applyStoredRouteOrdersToShops();
            hasDataChanged = true;
          }
        }
      }

      // 2. Synchronize Shops (Flush deletes -> Push dirty -> Pull)
      if (_locallyDeletedShopIds.isNotEmpty) {
        final ids = _locallyDeletedShopIds.toList();
        if (await _supabase.deleteShopsBulk(ids)) {
          _locallyDeletedShopIds.clear();
          await _storage.saveDeletedShopIds(_locallyDeletedShopIds);
        }
      }
      if (_dirtyShopIds.isNotEmpty) {
        final dirty = _shops.where((s) => _dirtyShopIds.contains(s.id)).toList();
        if (dirty.isEmpty || await _supabase.saveShopsBulk(dirty)) {
          _dirtyShopIds.clear();
          await _storage.saveIdSet(_keyDirtyShops, _dirtyShopIds);
        }
      }
      if (shouldSyncShops || _shops.isEmpty) {
        final shopsRes = await _supabase.fetchShopsWithStatus();
        if (shopsRes.success) {
          final cleanCloudShops = <ShopModel>[];
          for (final s in shopsRes.items) {
            if (_isDummyShop(s)) {
              _supabase.deleteShop(s.id);
            } else if (!_locallyDeletedShopIds.contains(s.id)) {
              cleanCloudShops.add(s);
            }
          }
          final merged = _mergeCloudEntity<ShopModel>(
            localItems: _shops,
            cloudItems: _deduplicateShops(cleanCloudShops),
            dirtyIds: _dirtyShopIds,
            deletedIds: _locallyDeletedShopIds,
            idOf: (s) => s.id,
            differs: _shopsDiffer,
            pruneMissingSynced: cleanCloudShops.isNotEmpty,
          );
          if (merged != null) {
            _shops = _deduplicateShops(merged);
            _applyStoredRouteOrdersToShops();
            _cascadeShopUpdates();
            await _storage.saveShops(_shops);
            hasDataChanged = true;
          }
        }
      }

      // 3. Synchronize Collections (Flush deletes -> Push dirty -> Pull)
      if (_locallyDeletedCollectionIds.isNotEmpty) {
        final ids = _locallyDeletedCollectionIds.toList();
        if (await _supabase.deleteCollectionsBulk(ids)) {
          _locallyDeletedCollectionIds.clear();
          await _storage.saveDeletedCollectionIds(_locallyDeletedCollectionIds);
        }
      }
      if (_dirtyCollectionIds.isNotEmpty) {
        final dirty =
            _collections.where((c) => _dirtyCollectionIds.contains(c.id)).toList();
        if (dirty.isEmpty || await _supabase.saveCollectionsBulk(dirty)) {
          _dirtyCollectionIds.clear();
          await _storage.saveIdSet(_keyDirtyCollections, _dirtyCollectionIds);
        }
      }
      final collsRes = await _supabase.fetchCollectionsWithStatus();
      if (collsRes.success) {
        final merged = _mergeCloudEntity<CollectionModel>(
          localItems: _collections,
          cloudItems: collsRes.items,
          dirtyIds: _dirtyCollectionIds,
          deletedIds: _locallyDeletedCollectionIds,
          idOf: (c) => c.id,
          differs: _collectionsDiffer,
          pruneMissingSynced: true,
        );
        if (merged != null) {
          merged.sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
          _collections = merged;
          await _storage.saveCollections(_collections);
          hasDataChanged = true;
        }
      }

      // 4. Synchronize Pending Bills (Flush deletes -> Push dirty -> Pull)
      if (_locallyDeletedBillIds.isNotEmpty) {
        final ids = _locallyDeletedBillIds.toList();
        if (await _supabase.deletePendingBillsBulk(ids)) {
          _locallyDeletedBillIds.clear();
          await _storage.saveDeletedBillIds(_locallyDeletedBillIds);
        }
      }
      if (_dirtyBillIds.isNotEmpty) {
        final dirty =
            _pendingBills.where((b) => _dirtyBillIds.contains(b.id)).toList();
        if (dirty.isEmpty || await _supabase.savePendingBillsBulk(dirty)) {
          _dirtyBillIds.clear();
          await _storage.saveIdSet(_keyDirtyBills, _dirtyBillIds);
        }
      }
      final billsRes = await _supabase.fetchPendingBillsWithStatus();
      if (billsRes.success) {
        final merged = _mergeCloudEntity<PendingBillModel>(
          localItems: _pendingBills,
          cloudItems: billsRes.items,
          dirtyIds: _dirtyBillIds,
          deletedIds: _locallyDeletedBillIds,
          idOf: (b) => b.id,
          differs: _billsDiffer,
          pruneMissingSynced: true,
        );
        if (merged != null) {
          merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          _pendingBills = merged;
          await _storage.savePendingBills(_pendingBills);
          hasDataChanged = true;
        }
      }

      // 5. Synchronize Sales Orders (Sync tombstones -> Flush deletes -> Push dirty -> Pull & Update)
      final tombstoneRes = await _supabase.fetchDeletedOrderTombstonesWithStatus();
      bool tombstonesDirty = false;
      if (tombstoneRes.success) {
        final mergedTombstones = {
          ..._cloudDeletedOrderIds,
          ...tombstoneRes.items,
          ..._locallyDeletedOrderIds,
          ..._sessionDeletedOrderIds,
        };
        if (mergedTombstones.length != _cloudDeletedOrderIds.length ||
            !_cloudDeletedOrderIds.containsAll(mergedTombstones)) {
          _cloudDeletedOrderIds = mergedTombstones;
          await _storage.saveIdSet(_keyCloudDeletedOrders, _cloudDeletedOrderIds);
        }
        if (tombstoneRes.items.length != _cloudDeletedOrderIds.length ||
            !tombstoneRes.items.toSet().containsAll(_cloudDeletedOrderIds)) {
          tombstonesDirty = true;
        }
      } else {
        _cloudDeletedOrderIds = {
          ..._cloudDeletedOrderIds,
          ..._locallyDeletedOrderIds,
          ..._sessionDeletedOrderIds,
        };
      }

      final allOrderTombstones = {
        ..._locallyDeletedOrderIds,
        ..._cloudDeletedOrderIds,
        ..._sessionDeletedOrderIds,
      };
      if (allOrderTombstones.isNotEmpty) {
        final removedLocal = _salesOrders.any((o) => allOrderTombstones.contains(o.id));
        _salesOrders.removeWhere((o) => allOrderTombstones.contains(o.id));
        if (_dirtyOrderIds.any(allOrderTombstones.contains)) {
          _dirtyOrderIds.removeAll(allOrderTombstones);
          await _storage.saveIdSet(_keyDirtyOrders, _dirtyOrderIds);
        }
        if (removedLocal) {
          await _storage.saveSalesOrders(_salesOrders);
          hasDataChanged = true;
        }
      }

      if (_locallyDeletedOrderIds.isNotEmpty) {
        final ids = _locallyDeletedOrderIds.toList();
        if (await _supabase.deleteSalesOrdersBulk(ids)) {
          _locallyDeletedOrderIds.clear();
          await _storage.saveIdSet(_keyDeletedOrders, _locallyDeletedOrderIds);
          tombstonesDirty = true;
        }
      }
      if (tombstonesDirty && _cloudDeletedOrderIds.isNotEmpty) {
        await _supabase.saveDeletedOrderTombstones(_cloudDeletedOrderIds.toList());
      }
      if (_dirtyOrderIds.isNotEmpty) {
        final dirty =
            _salesOrders.where((o) => _dirtyOrderIds.contains(o.id)).toList();
        if (dirty.isEmpty || await _supabase.saveSalesOrdersBulk(dirty)) {
          _dirtyOrderIds.clear();
          await _storage.saveIdSet(_keyDirtyOrders, _dirtyOrderIds);
        }
      }
      final ordersRes = await _supabase.fetchSalesOrdersWithStatus();
      if (ordersRes.success) {
        final effectiveTombstones = {
          ..._locallyDeletedOrderIds,
          ..._cloudDeletedOrderIds,
          ..._sessionDeletedOrderIds,
        };
        final zombieCloudIds = ordersRes.items
            .where((o) => effectiveTombstones.contains(o.id))
            .map((o) => o.id)
            .toList();
        if (zombieCloudIds.isNotEmpty) {
          await _supabase.deleteSalesOrdersBulk(zombieCloudIds);
        }
        final merged = _mergeCloudEntity<SalesOrderModel>(
          localItems: _salesOrders,
          cloudItems: ordersRes.items,
          dirtyIds: _dirtyOrderIds,
          deletedIds: effectiveTombstones,
          idOf: (o) => o.id,
          differs: _ordersDiffer,
          pruneMissingSynced: true,
        );
        if (merged != null) {
          merged.sort((a, b) => b.orderDate.compareTo(a.orderDate));
          _salesOrders = merged;
          await _storage.saveSalesOrders(_salesOrders);
          hasDataChanged = true;
        }
      }

      // 6. Synchronize Custom Products
      if (_locallyDeletedProductIds.isNotEmpty) {
        final ids = _locallyDeletedProductIds.toList();
        if (await _supabase.deleteCustomProductsBulk(ids)) {
          _locallyDeletedProductIds.clear();
          await _storage.saveIdSet(_keyDeletedProducts, _locallyDeletedProductIds);
        }
      }
      if (_dirtyProductIds.isNotEmpty) {
        final dirty =
            _customProducts.where((p) => _dirtyProductIds.contains(p.id)).toList();
        if (dirty.isEmpty || await _supabase.saveCustomProductsBulk(dirty)) {
          _dirtyProductIds.clear();
          await _storage.saveIdSet(_keyDirtyProducts, _dirtyProductIds);
        }
      }
      final productsRes = await _supabase.fetchCustomProductsWithStatus();
      if (productsRes.success) {
        final merged = _mergeCloudEntity<CatalogProduct>(
          localItems: _customProducts,
          cloudItems: productsRes.items,
          dirtyIds: _dirtyProductIds,
          deletedIds: _locallyDeletedProductIds,
          idOf: (p) => p.id,
          differs: _productsDiffer,
          pruneMissingSynced: true,
        );
        if (merged != null) {
          _customProducts = merged;
          OrderCatalogService.setCustomProducts(_customProducts);
          await _storage.saveCustomProducts(_customProducts);
          hasDataChanged = true;
        }
      }

      // 7. Synchronize Cash Handovers
      if (_locallyDeletedHandoverIds.isNotEmpty) {
        final ids = _locallyDeletedHandoverIds.toList();
        if (await _supabase.deleteCashHandoversBulk(ids)) {
          _locallyDeletedHandoverIds.clear();
          await _storage.saveIdSet(
              _keyDeletedHandovers, _locallyDeletedHandoverIds);
        }
      }
      if (_dirtyHandoverIds.isNotEmpty) {
        final dirty =
            _cashHandovers.where((h) => _dirtyHandoverIds.contains(h.id)).toList();
        if (dirty.isEmpty || await _supabase.saveCashHandoversBulk(dirty)) {
          _dirtyHandoverIds.clear();
          await _storage.saveIdSet(_keyDirtyHandovers, _dirtyHandoverIds);
        }
      }
      final handoversRes = await _supabase.fetchCashHandoversWithStatus();
      if (handoversRes.success) {
        final merged = _mergeCloudEntity<CashHandoverModel>(
          localItems: _cashHandovers,
          cloudItems: handoversRes.items,
          dirtyIds: _dirtyHandoverIds,
          deletedIds: _locallyDeletedHandoverIds,
          idOf: (h) => h.id,
          differs: _handoversDiffer,
          pruneMissingSynced: true,
        );
        if (merged != null) {
          merged.sort((a, b) => b.date.compareTo(a.date));
          _cashHandovers = merged;
          await _storage.saveCashHandovers(_cashHandovers);
          hasDataChanged = true;
        }
      }

      // 8. Synchronize Vehicle Collections
      if (_locallyDeletedVehicleCollectionIds.isNotEmpty) {
        final ids = _locallyDeletedVehicleCollectionIds.toList();
        if (await _supabase.deleteVehicleCollectionsBulk(ids)) {
          _locallyDeletedVehicleCollectionIds.clear();
          await _storage.saveIdSet(
            _keyDeletedVehicleCollections,
            _locallyDeletedVehicleCollectionIds,
          );
        }
      }
      if (_dirtyVehicleCollectionIds.isNotEmpty) {
        final dirty = _vehicleCollections
            .where((v) => _dirtyVehicleCollectionIds.contains(v.id))
            .toList();
        if (dirty.isEmpty || await _supabase.saveVehicleCollectionsBulk(dirty)) {
          _dirtyVehicleCollectionIds.clear();
          await _storage.saveIdSet(
            _keyDirtyVehicleCollections,
            _dirtyVehicleCollectionIds,
          );
        }
      }
      final vcRes = await _supabase.fetchVehicleCollectionsWithStatus();
      if (vcRes.success) {
        final merged = _mergeCloudEntity<VehicleCollectionModel>(
          localItems: _vehicleCollections,
          cloudItems: vcRes.items,
          dirtyIds: _dirtyVehicleCollectionIds,
          deletedIds: _locallyDeletedVehicleCollectionIds,
          idOf: (v) => v.id,
          differs: _vehicleCollectionsDiffer,
          pruneMissingSynced: true,
        );
        if (merged != null) {
          merged.sort((a, b) => b.date.compareTo(a.date));
          _vehicleCollections = merged;
          await _storage.saveVehicleCollections(_vehicleCollections);
          hasDataChanged = true;
        }
      }

      // 9. Synchronize Managed Vehicles & Employees Lists
      if (_dirtyVehiclesFlag) {
        if (await _supabase.saveManagedVehicles(_vehicles)) {
          _dirtyVehiclesFlag = false;
          await _storage.saveBoolFlag(_keyDirtyVehiclesFlag, false);
        }
      } else {
        final vRes = await _supabase.fetchManagedVehiclesWithStatus();
        if (vRes.success &&
            vRes.items.isNotEmpty &&
            vRes.items.join('|') != _vehicles.join('|')) {
          _vehicles = vRes.items;
          await _storage.saveVehicles(_vehicles);
          hasDataChanged = true;
        }
      }

      if (_dirtyEmployeesFlag) {
        if (await _supabase.saveManagedEmployees(_employees)) {
          _dirtyEmployeesFlag = false;
          await _storage.saveBoolFlag(_keyDirtyEmployeesFlag, false);
        }
      } else {
        final eRes = await _supabase.fetchManagedEmployeesWithStatus();
        if (eRes.success &&
            eRes.items.isNotEmpty &&
            eRes.items.join('|') != _employees.join('|')) {
          _employees = eRes.items;
          await _storage.saveEmployees(_employees);
          hasDataChanged = true;
        }
      }

      // 10. Ensure Realtime subscriptions are active
      _setupRealtimeListeners();

      // 11. Synchronize Users (once), Attendance & Auto-Backup
      List<UserModel> latestUsers = const [];
      try {
        latestUsers = await AuthService().loadUsers();
        if (onUsersSynced != null) {
          await onUsersSynced!(latestUsers);
        }
        await AttendanceService.flushPending();
        await AttendanceService.loadEmployees();
      } catch (e) {
        debugPrint('Auto background sync users/attendance notice: $e');
      }

      try {
        final lastBackup = await _backupService.getLatestBackupTimeShared();
        final now = DateTime.now();
        if (lastBackup == null || now.difference(lastBackup).inDays >= 4) {
          final usersForBackup =
              latestUsers.isNotEmpty ? latestUsers : await AuthService().loadUsers();
          _lastBackupTime = await _backupService.getLatestBackupTimeShared();
          await _backupService.checkAndRunAutoBackup(
            routes: _routes,
            shops: _shops,
            collections: _collections,
            pendingBills: _pendingBills,
            users: usersForBackup,
          );
          _lastBackupTime = await _backupService.getLatestBackupTimeShared();
        }
      } catch (e) {
        debugPrint('Auto backup notice: $e');
      }

      if (hasDataChanged) {
        _invalidateCaches();
      }

      _isSyncing = false;
      if (hasDataChanged || notify) {
        notifyListeners();
      }
      return true;
    } catch (e) {
      debugPrint('syncAllWithCloud notice: $e');
      _isSyncing = false;
      if (notify) notifyListeners();
      return false;
    }
  }

  Future<bool> syncAllToCloud() => syncAllWithCloud();

  Future<bool> connectCloud([dynamic config]) async {
    if (!_supabase.isInitialized) {
      await _supabase.init();
    }
    notifyListeners();
    return true;
  }

  Future<bool> connectFirebase([dynamic config]) => connectCloud(config);

  Future<void> disconnectCloud() async {
    notifyListeners();
  }

  Future<void> disconnectFirebase() => disconnectCloud();

  void setSelectedDate(DateTime date) {
    _selectedDate = date;
    notifyListeners();
  }

  void setFilterBusiness(String? business) {
    _filterBusiness = business;
    notifyListeners();
  }

  void setFilterRouteId(String? routeId) {
    _filterRouteId = routeId;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  // --- Filtered Collections for selected date and active filters ---
  List<CollectionModel> getFilteredCollections({DateTime? forDate, String? staffOverride}) {
    final date = forDate ?? _selectedDate;

    // Return cached filtered collections if parameters match to avoid O(N) re-filtering in tight build loops
    if (_filteredCollectionsCache != null &&
        _cachedForDate == date &&
        _cachedStaffOverride == staffOverride &&
        _cachedFilterBusiness == _filterBusiness &&
        _cachedFilterRouteId == _filterRouteId &&
        _cachedSelectedStaffFilter == _selectedStaffFilter &&
        _cachedSearchQuery == _searchQuery) {
      return _filteredCollectionsCache!;
    }

    final filtered = _collections.where((c) {
      // Date filter (matches day, month, year)
      final sameDay = c.collectedAt.year == date.year &&
          c.collectedAt.month == date.month &&
          c.collectedAt.day == date.day;
      if (!sameDay) return false;

      // Staff filter & user isolation scoping
      if (staffOverride != null && staffOverride.isNotEmpty && staffOverride != 'All') {
        if (!_matchesStaff(c.salesmanName, staffOverride)) return false;
      } else if (_currentUser != null &&
          (_currentUser!.isSalesman || _currentUser!.isCollection || _currentUser!.isDriver)) {
        // Field staff (Salesman, Collection, Driver) only sees their own collections
        final isOwn = _matchesStaff(c.salesmanName, _currentUser!.name) ||
            _matchesStaff(c.salesmanName, _currentUser!.phone);
        if (!isOwn) return false;
      } else if (_selectedStaffFilter != null && _selectedStaffFilter != 'All') {
        // Super Admin or Office selected a specific staff filter
        if (!_matchesStaff(c.salesmanName, _selectedStaffFilter!)) return false;
      }

      // Business filter
      if (_filterBusiness != null && _filterBusiness!.isNotEmpty && _filterBusiness != 'All') {
        if (c.businessName != _filterBusiness) return false;
      }

      // Route filter
      if (_filterRouteId != null && _filterRouteId!.isNotEmpty && _filterRouteId != 'All') {
        if (c.routeId != _filterRouteId) return false;
      }

      // If user has assigned routes, only show collections for assigned routes
      if (_shouldFilterByAssignedRoutes) {
        if (!_currentUser!.assignedRouteIds.contains(c.routeId)) return false;
      }

      // Search query
      if (_searchQuery.trim().isNotEmpty) {
        final query = _searchQuery.toLowerCase().trim();
        final matchShop = MarathiSearchHelper.matches(c.shopName, query);
        final matchBill = c.billNumber.toLowerCase().contains(query);
        final matchRoute = MarathiSearchHelper.matches(c.routeName, query);
        if (!matchShop && !matchBill && !matchRoute) return false;
      }

      return true;
    }).toList()
      ..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));

    _filteredCollectionsCache = filtered;
    _cachedForDate = date;
    _cachedStaffOverride = staffOverride;
    _cachedFilterBusiness = _filterBusiness;
    _cachedFilterRouteId = _filterRouteId;
    _cachedSelectedStaffFilter = _selectedStaffFilter;
    _cachedSearchQuery = _searchQuery;

    return filtered;
  }

  bool _matchesStaff(String recordedSalesman, String targetStaff) {
    final r = recordedSalesman.trim().toLowerCase();
    final t = targetStaff.trim().toLowerCase();
    if (r == t) return true;
    if (r.contains(t) || t.contains(r)) return true;
    if ((t.contains('user1') || t.contains('driver')) && (r.contains('user1') || r.contains('driver'))) {
      return true;
    }
    return false;
  }

  /// Returns collection breakdown for a specific staff member on a specific date
  StaffCollectionSummary getStaffSummary(String staffName, {DateTime? forDate}) {
    final date = forDate ?? _selectedDate;
    final staffCollections = _collections.where((c) {
      final sameDay = c.collectedAt.year == date.year &&
          c.collectedAt.month == date.month &&
          c.collectedAt.day == date.day;
      if (!sameDay) return false;
      return _matchesStaff(c.salesmanName, staffName);
    }).toList();

    double cashTotal = 0;
    double upiTotal = 0;
    double chequeTotal = 0;
    double otherTotal = 0;
    for (final c in staffCollections) {
      switch (c.paymentMode) {
        case PaymentMode.cash:
          cashTotal += c.collectedAmount;
          break;
        case PaymentMode.upi:
          upiTotal += c.collectedAmount;
          break;
        case PaymentMode.cheque:
          chequeTotal += c.collectedAmount;
          break;
        case PaymentMode.netBanking:
          otherTotal += c.collectedAmount;
          break;
      }
    }

    final total = cashTotal + upiTotal + chequeTotal + otherTotal;
    return StaffCollectionSummary(
      staffName: staffName,
      totalAmount: total,
      cashAmount: cashTotal,
      upiAmount: upiTotal,
      chequeAmount: chequeTotal,
      collectionsCount: staffCollections.length,
      collections: staffCollections,
    );
  }

  // --- Bill Aggregation & Status Tracking (Pending vs Paid) ---
  List<BillSummary> getAllBillSummaries({String? forShopId, String? forBusiness}) {
    if (_allBillSummariesCache == null) {
      final Map<String, List<CollectionModel>> grouped = {};
      final shopRouteMap = <String, String>{};
      for (final s in _shops) {
        shopRouteMap[s.id] = s.routeId;
      }
      final routeNameMap = <String, String>{};
      for (final r in _routes) {
        routeNameMap[r.id] = r.name;
      }

      for (final c in _collections) {
        final key = '${c.shopId}_${c.billNumber.trim().toLowerCase()}';
        grouped.putIfAbsent(key, () => []).add(c);
      }

      final List<BillSummary> list = [];
      final Map<String, BillSummary> summaryMap = {};

      grouped.forEach((key, collList) {
        collList.sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
        final first = collList.first;

        // Bill total is taken from max recorded billAmount for this invoice
        double maxBill = 0.0;
        double totalCollected = 0.0;
        for (final c in collList) {
          if (c.billAmount > maxBill) maxBill = c.billAmount;
          totalCollected += c.collectedAmount;
        }

        final effectiveRouteId = (first.routeId.isNotEmpty)
            ? first.routeId
            : (shopRouteMap[first.shopId] ?? '');

        final rName = first.routeName.isNotEmpty
            ? first.routeName
            : (routeNameMap[effectiveRouteId] ?? 'Unknown Route');

        final summary = BillSummary(
          billNumber: first.billNumber,
          shopId: first.shopId,
          shopName: first.shopName,
          routeId: effectiveRouteId,
          routeName: rName,
          businessName: first.businessName,
          billTotal: maxBill,
          totalCollected: totalCollected,
          collections: collList,
          lastPaymentDate: first.collectedAt,
        );
        list.add(summary);
        summaryMap[key] = summary;
      });

      // Also include any standalone pending bills from _pendingBills that haven't had collections yet
      for (final pb in _pendingBills) {
        final key = '${pb.shopId}_${pb.billNumber.trim().toLowerCase()}';
        if (!summaryMap.containsKey(key)) {
          final effectiveRouteId = (pb.routeId.isNotEmpty)
              ? pb.routeId
              : (shopRouteMap[pb.shopId] ?? '');

          final rName = pb.routeName.isNotEmpty
              ? pb.routeName
              : (routeNameMap[effectiveRouteId] ?? 'Unknown Route');

          final summary = BillSummary(
            billNumber: pb.billNumber,
            shopId: pb.shopId,
            shopName: pb.shopName,
            routeId: effectiveRouteId,
            routeName: rName,
            businessName: pb.businessName,
            billTotal: pb.totalAmount,
            totalCollected: pb.collectedAmount,
            collections: const [],
            lastPaymentDate: pb.invoiceDate,
          );
          list.add(summary);
          summaryMap[key] = summary;
        }
      }

      list.sort((a, b) => b.lastPaymentDate.compareTo(a.lastPaymentDate));
      _allBillSummariesCache = list;
      _billSummaryMapCache = summaryMap;
    }

    if (forShopId == null && (forBusiness == null || forBusiness == 'All')) {
      return _allBillSummariesCache!;
    }

    return _allBillSummariesCache!.where((b) {
      if (forShopId != null && b.shopId != forShopId) return false;
      if (forBusiness != null && forBusiness != 'All' && b.businessName != forBusiness) return false;
      return true;
    }).toList();
  }

  List<BillSummary> getPendingBills({String? forShopId, String? forBusiness}) {
    return getAllBillSummaries(forShopId: forShopId, forBusiness: forBusiness)
        .where((b) => b.isPending)
        .toList();
  }

  List<BillSummary> getPaidBills({String? forShopId, String? forBusiness}) {
    return getAllBillSummaries(forShopId: forShopId, forBusiness: forBusiness)
        .where((b) => b.isPaid)
        .toList();
  }

  BillSummary? getBillSummary(String shopId, String billNumber) {
    if (_billSummaryMapCache == null) {
      getAllBillSummaries();
    }
    final cleanBill = billNumber.trim().toLowerCase();
    final exactKey = '${shopId}_$cleanBill';
    if (_billSummaryMapCache!.containsKey(exactKey)) {
      return _billSummaryMapCache![exactKey];
    }
    // Fallback: If shopId was empty or not matched, search by bill number
    if (shopId.isEmpty) {
      for (final summary in _allBillSummariesCache!) {
        if (summary.billNumber.trim().toLowerCase() == cleanBill) {
          return summary;
        }
      }
    }
    return null;
  }

  // --- Calculation Helpers for Accurate Multi-Installment Accounting ---
  /// Calculates the sum of unique invoice bill amounts from a collection list,
  /// avoiding duplication when an invoice has multiple partial payments.
  double calculateTotalBilled(Iterable<CollectionModel> records) {
    final Map<String, double> uniqueBillTotals = {};
    for (final c in records) {
      final key = '${c.shopId}_${c.billNumber.trim().toLowerCase()}';
      if (!uniqueBillTotals.containsKey(key) || c.billAmount > uniqueBillTotals[key]!) {
        uniqueBillTotals[key] = c.billAmount;
      }
    }
    return uniqueBillTotals.values.fold(0.0, (sum, amt) => sum + amt);
  }

  /// Calculates the current remaining balance due across unique bills in a collection list.
  /// If an invoice is fully settled, its balance due is 0.
  double calculateTotalBalanceDue(Iterable<CollectionModel> records) {
    final Map<String, double> uniqueBillBalances = {};
    for (final c in records) {
      final key = '${c.shopId}_${c.billNumber.trim().toLowerCase()}';
      if (!uniqueBillBalances.containsKey(key)) {
        final bSum = getBillSummary(c.shopId, c.billNumber);
        uniqueBillBalances[key] = bSum != null ? bSum.balanceDue : (c.balanceRemaining ?? 0.0);
      }
    }
    return uniqueBillBalances.values.fold(0.0, (sum, bal) => sum + bal);
  }

  /// Returns the count of unique bills/invoices in a collection list.
  int countUniqueBills(Iterable<CollectionModel> records) {
    final Set<String> uniqueKeys = {};
    for (final c in records) {
      uniqueKeys.add('${c.shopId}_${c.billNumber.trim().toLowerCase()}');
    }
    return uniqueKeys.length;
  }

  // --- Breakdown Calculations for Selected Date & Filters ---
  double get totalCollection {
    return getFilteredCollections().fold(0.0, (sum, c) => sum + c.collectedAmount);
  }

  double get totalBillAmount {
    return calculateTotalBilled(getFilteredCollections());
  }

  double get totalBalanceDue {
    return calculateTotalBalanceDue(getFilteredCollections());
  }

  double get totalCash {
    return getFilteredCollections()
        .where((c) => c.paymentMode == PaymentMode.cash)
        .fold(0.0, (sum, c) => sum + c.collectedAmount);
  }

  double get totalUpi {
    return getFilteredCollections()
        .where((c) => c.paymentMode == PaymentMode.upi)
        .fold(0.0, (sum, c) => sum + c.collectedAmount);
  }

  double get totalCheque {
    return getFilteredCollections()
        .where((c) => c.paymentMode == PaymentMode.cheque)
        .fold(0.0, (sum, c) => sum + c.collectedAmount);
  }

  double get totalNetBanking {
    return getFilteredCollections()
        .where((c) => c.paymentMode == PaymentMode.netBanking)
        .fold(0.0, (sum, c) => sum + c.collectedAmount);
  }

  int get totalBillsCount {
    return countUniqueBills(getFilteredCollections());
  }

  int get partialBillsCount {
    final filtered = getFilteredCollections();
    final uniquePartialBills = <String>{};
    for (final c in filtered) {
      final bill = getBillSummary(c.shopId, c.billNumber);
      final isPending = bill != null ? bill.isPending : ((c.balanceRemaining ?? 0.0) > 0.001);
      if (isPending) {
        uniquePartialBills.add('${c.shopId}_${c.billNumber.trim().toLowerCase()}');
      }
    }
    return uniquePartialBills.length;
  }

  int get uniqueShopsCount {
    final list = getFilteredCollections();
    final ids = list.map((c) => c.shopId).toSet();
    return ids.length;
  }

  // --- Per-Business Performance & Collection Metrics ---
  double getTotalCollectionForBusiness(String business, {DateTime? forDate}) {
    return getFilteredCollections(forDate: forDate)
        .where((c) => c.businessName == business)
        .fold(0.0, (s, c) => s + c.collectedAmount);
  }

  int getBillsCountForBusiness(String business, {DateTime? forDate}) {
    final matching = getFilteredCollections(forDate: forDate)
        .where((c) => c.businessName == business);
    final uniqueBills = <String>{};
    for (final c in matching) {
      uniqueBills.add('${c.shopId}_${c.billNumber.trim().toLowerCase()}');
    }
    return uniqueBills.length;
  }

  double getPendingBalanceForBusiness(String business) {
    return _pendingBills
        .where((b) => (business == 'All' || b.businessName == business) && !b.isPaid)
        .fold(0.0, (s, b) => s + b.balanceDue);
  }

  double getCashForBusiness(String business, {DateTime? forDate}) {
    return getFilteredCollections(forDate: forDate)
        .where((c) => c.businessName == business && c.paymentMode == PaymentMode.cash)
        .fold(0.0, (s, c) => s + c.collectedAmount);
  }

  double getDigitalForBusiness(String business, {DateTime? forDate}) {
    return getFilteredCollections(forDate: forDate)
        .where((c) => c.businessName == business && c.paymentMode != PaymentMode.cash)
        .fold(0.0, (s, c) => s + c.collectedAmount);
  }

  Future<void> _markDirty(Set<String> set, String key, Iterable<String> ids) async {
    set.addAll(ids);
    await _storage.saveIdSet(key, set);
  }

  Future<void> _clearDirty(Set<String> set, String key, Iterable<String> ids) async {
    set.removeAll(ids);
    await _storage.saveIdSet(key, set);
  }

  // --- Route Operations ---
  Future<RouteModel> addRoute({required String name, String? description, int? priority}) async {
    final newPriority = priority ?? (_routes.isEmpty ? 1 : (_routes.map((r) => r.priority).reduce((a, b) => a > b ? a : b) + 1));
    final newRoute = RouteModel(
      id: _uuid.v4(),
      name: name.trim(),
      description: description?.trim(),
      priority: newPriority,
      createdAt: DateTime.now(),
    );
    _routes.add(newRoute);
    _routes.sort((a, b) => a.priority.compareTo(b.priority));
    _locallyDeletedRouteIds.remove(newRoute.id);
    await _storage.saveRoutes(_routes);
    await _storage.saveDeletedRouteIds(_locallyDeletedRouteIds);
    await _markDirty(_dirtyRouteIds, _keyDirtyRoutes, [newRoute.id]);
    notifyListeners();

    if (await _supabase.saveRoute(newRoute)) {
      await _clearDirty(_dirtyRouteIds, _keyDirtyRoutes, [newRoute.id]);
    }
    return newRoute;
  }

  Future<RouteModel> updateRoute(RouteModel updatedRoute) async {
    final idx = _routes.indexWhere((r) => r.id == updatedRoute.id);
    if (idx != -1) {
      _routes[idx] = updatedRoute;
      final affectedShopIds = <String>[];
      for (int i = 0; i < _shops.length; i++) {
        if (_shops[i].routeId == updatedRoute.id) {
          _shops[i] = _shops[i].copyWith(routeName: updatedRoute.name);
          affectedShopIds.add(_shops[i].id);
        }
      }
      final affectedColIds = <String>[];
      for (int i = 0; i < _collections.length; i++) {
        if (_collections[i].routeId == updatedRoute.id &&
            _collections[i].routeName != updatedRoute.name) {
          _collections[i] = _collections[i].copyWith(routeName: updatedRoute.name);
          affectedColIds.add(_collections[i].id);
        }
      }
      final affectedBillIds = <String>[];
      for (int i = 0; i < _pendingBills.length; i++) {
        if (_pendingBills[i].routeId == updatedRoute.id &&
            _pendingBills[i].routeName != updatedRoute.name) {
          _pendingBills[i] = _pendingBills[i].copyWith(routeName: updatedRoute.name);
          affectedBillIds.add(_pendingBills[i].id);
        }
      }

      _routes.sort((a, b) => a.priority.compareTo(b.priority));
      await _storage.saveRoutes(_routes);
      await _markDirty(_dirtyRouteIds, _keyDirtyRoutes, [updatedRoute.id]);
      if (affectedShopIds.isNotEmpty) {
        await _storage.saveShops(_shops);
        await _markDirty(_dirtyShopIds, _keyDirtyShops, affectedShopIds);
      }
      if (affectedColIds.isNotEmpty) {
        await _storage.saveCollections(_collections);
        await _markDirty(_dirtyCollectionIds, _keyDirtyCollections, affectedColIds);
      }
      if (affectedBillIds.isNotEmpty) {
        await _storage.savePendingBills(_pendingBills);
        await _markDirty(_dirtyBillIds, _keyDirtyBills, affectedBillIds);
      }
      notifyListeners();

      if (await _supabase.saveRoute(updatedRoute)) {
        await _clearDirty(_dirtyRouteIds, _keyDirtyRoutes, [updatedRoute.id]);
      }
      if (affectedShopIds.isNotEmpty) {
        final affectedShops = _shops.where((s) => affectedShopIds.contains(s.id)).toList();
        if (await _supabase.saveShopsBulk(affectedShops)) {
          await _clearDirty(_dirtyShopIds, _keyDirtyShops, affectedShopIds);
        }
      }
      if (affectedColIds.isNotEmpty) {
        final affectedCols = _collections.where((c) => affectedColIds.contains(c.id)).toList();
        if (await _supabase.saveCollectionsBulk(affectedCols)) {
          await _clearDirty(_dirtyCollectionIds, _keyDirtyCollections, affectedColIds);
        }
      }
      if (affectedBillIds.isNotEmpty) {
        final affectedBills = _pendingBills.where((b) => affectedBillIds.contains(b.id)).toList();
        if (await _supabase.savePendingBillsBulk(affectedBills)) {
          await _clearDirty(_dirtyBillIds, _keyDirtyBills, affectedBillIds);
        }
      }
    }
    return updatedRoute;
  }

  Future<void> _persistAndSyncRouteOrder() async {
    final ids = _routes.map((r) => r.id).toList();
    await _storage.saveRoutes(_routes);
    await _markDirty(_dirtyRouteIds, _keyDirtyRoutes, ids);
    notifyListeners();

    if (await _supabase.saveRoutesBulk(_routes)) {
      await _clearDirty(_dirtyRouteIds, _keyDirtyRoutes, ids);
    }
  }

  Future<void> updateRoutePriority(String routeId, int newPriority) async {
    final idx = _routes.indexWhere((r) => r.id == routeId);
    if (idx != -1) {
      _routes[idx] = _routes[idx].copyWith(priority: newPriority);
      _routes.sort((a, b) => a.priority.compareTo(b.priority));
      for (int i = 0; i < _routes.length; i++) {
        _routes[i] = _routes[i].copyWith(priority: i + 1);
      }
      await _persistAndSyncRouteOrder();
    }
  }

  Future<void> setRouteOrder(List<String> orderedRouteIds) async {
    for (int i = 0; i < orderedRouteIds.length; i++) {
      final id = orderedRouteIds[i];
      final idx = _routes.indexWhere((r) => r.id == id);
      if (idx != -1) {
        _routes[idx] = _routes[idx].copyWith(priority: i + 1);
      }
    }
    _routes.sort((a, b) => a.priority.compareTo(b.priority));
    await _persistAndSyncRouteOrder();
  }

  Future<void> moveRouteUp(String routeId) async {
    final currentRoutes = routes;
    final idx = currentRoutes.indexWhere((r) => r.id == routeId);
    if (idx > 0) {
      final temp = currentRoutes[idx];
      currentRoutes[idx] = currentRoutes[idx - 1];
      currentRoutes[idx - 1] = temp;
      await setRouteOrder(currentRoutes.map((r) => r.id).toList());
    }
  }

  Future<void> moveRouteDown(String routeId) async {
    final currentRoutes = routes;
    final idx = currentRoutes.indexWhere((r) => r.id == routeId);
    if (idx != -1 && idx < currentRoutes.length - 1) {
      final temp = currentRoutes[idx];
      currentRoutes[idx] = currentRoutes[idx + 1];
      currentRoutes[idx + 1] = temp;
      await setRouteOrder(currentRoutes.map((r) => r.id).toList());
    }
  }

  Future<void> reorderRoutes(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _routes.removeAt(oldIndex);
    _routes.insert(newIndex, item);
    for (int i = 0; i < _routes.length; i++) {
      _routes[i] = _routes[i].copyWith(priority: i + 1);
    }
    await _persistAndSyncRouteOrder();
  }

  Future<void> deleteRoute(String routeId) async {
    _routes.removeWhere((r) => r.id == routeId);
    _dirtyRouteIds.remove(routeId);
    _dirtyRouteOrderIds.remove(routeId);
    _routeOutletOrders.remove(routeId);
    _locallyDeletedRouteIds.add(routeId);
    await _storage.saveIdSet(_keyDirtyRoutes, _dirtyRouteIds);
    await _storage.saveIdSet(_keyDirtyRouteOrders, _dirtyRouteOrderIds);
    await _storage.saveRouteOutletOrders(_routeOutletOrders);
    await _storage.saveDeletedRouteIds(_locallyDeletedRouteIds);
    await _storage.saveRoutes(_routes);
    notifyListeners();

    if (await _supabase.deleteRoute(routeId)) {
      _locallyDeletedRouteIds.remove(routeId);
      await _storage.saveDeletedRouteIds(_locallyDeletedRouteIds);
    }
  }

  // --- Shop Operations ---
  Future<ShopModel> addShop({
    required String name,
    required String routeId,
    required String routeName,
    required String mobileNumber,
    required String address,
    String? ownerName,
    String? locationUrl,
    double? latitude,
    double? longitude,
  }) async {
    final newShop = ShopModel(
      id: _uuid.v4(),
      name: name.trim(),
      routeId: routeId,
      routeName: routeName,
      mobileNumber: mobileNumber.trim(),
      address: address.trim(),
      ownerName: ownerName?.trim(),
      locationUrl: locationUrl?.trim(),
      latitude: latitude,
      longitude: longitude,
      createdAt: DateTime.now(),
    );
    _shops.insert(0, newShop);
    _locallyDeletedShopIds.remove(newShop.id);
    await _storage.saveShops(_shops);
    await _storage.saveDeletedShopIds(_locallyDeletedShopIds);
    await _markDirty(_dirtyShopIds, _keyDirtyShops, [newShop.id]);
    notifyListeners();

    if (await _supabase.saveShop(newShop)) {
      await _clearDirty(_dirtyShopIds, _keyDirtyShops, [newShop.id]);
    }
    return newShop;
  }

  Future<int> addShopsBulk(List<ShopModel> newShops) async {
    if (newShops.isEmpty) return 0;
    final toAdd = <ShopModel>[];
    for (final s in newShops) {
      final exists = _shops.any((existing) =>
          existing.name.trim().toLowerCase() == s.name.trim().toLowerCase() &&
          existing.routeId == s.routeId);
      if (!exists) {
        toAdd.add(s);
      }
    }
    if (toAdd.isEmpty) return 0;

    final addedIds = toAdd.map((s) => s.id).toSet();
    _shops.addAll(toAdd);
    _locallyDeletedShopIds.removeAll(addedIds);
    await _storage.saveDeletedShopIds(_locallyDeletedShopIds);
    await _storage.saveShops(_shops);
    await _markDirty(_dirtyShopIds, _keyDirtyShops, addedIds);
    notifyListeners();

    if (await _supabase.saveShopsBulk(toAdd)) {
      await _clearDirty(_dirtyShopIds, _keyDirtyShops, addedIds);
    }
    return toAdd.length;
  }

  Future<ShopModel?> updateShopLocation(
    String shopId, {
    String? locationUrl,
    double? latitude,
    double? longitude,
  }) async {
    final idx = _shops.indexWhere((s) => s.id == shopId);
    if (idx != -1) {
      final updated = _shops[idx].copyWith(
        locationUrl: locationUrl?.trim(),
        latitude: latitude,
        longitude: longitude,
      );
      _shops[idx] = updated;
      await _storage.saveShops(_shops);
      await _markDirty(_dirtyShopIds, _keyDirtyShops, [shopId]);
      notifyListeners();

      if (await _supabase.saveShop(updated)) {
        await _clearDirty(_dirtyShopIds, _keyDirtyShops, [shopId]);
      }
      return updated;
    }
    return null;
  }

  Future<ShopModel?> deleteShopLocation(String shopId) async {
    final idx = _shops.indexWhere((s) => s.id == shopId);
    if (idx != -1) {
      final updated = _shops[idx].copyWith(clearLocation: true);
      _shops[idx] = updated;
      await _storage.saveShops(_shops);
      await _markDirty(_dirtyShopIds, _keyDirtyShops, [shopId]);
      notifyListeners();

      if (await _supabase.saveShop(updated)) {
        await _clearDirty(_dirtyShopIds, _keyDirtyShops, [shopId]);
      }
      return updated;
    }
    return null;
  }

  Future<ShopModel> updateShop(ShopModel updatedShop) async {
    final idx = _shops.indexWhere((s) => s.id == updatedShop.id);
    if (idx != -1) {
      _shops[idx] = updatedShop;
      final affectedColIds = <String>[];
      for (int i = 0; i < _collections.length; i++) {
        if (_collections[i].shopId == updatedShop.id) {
          _collections[i] = _collections[i].copyWith(
            shopName: updatedShop.name,
            routeId: updatedShop.routeId,
            routeName: updatedShop.routeName,
          );
          affectedColIds.add(_collections[i].id);
        }
      }
      final affectedBillIds = <String>[];
      for (int i = 0; i < _pendingBills.length; i++) {
        if (_pendingBills[i].shopId == updatedShop.id) {
          _pendingBills[i] = _pendingBills[i].copyWith(
            shopName: updatedShop.name,
            routeId: updatedShop.routeId,
            routeName: updatedShop.routeName,
          );
          affectedBillIds.add(_pendingBills[i].id);
        }
      }
      await _storage.saveShops(_shops);
      await _markDirty(_dirtyShopIds, _keyDirtyShops, [updatedShop.id]);
      if (affectedColIds.isNotEmpty) {
        await _storage.saveCollections(_collections);
        await _markDirty(_dirtyCollectionIds, _keyDirtyCollections, affectedColIds);
      }
      if (affectedBillIds.isNotEmpty) {
        await _storage.savePendingBills(_pendingBills);
        await _markDirty(_dirtyBillIds, _keyDirtyBills, affectedBillIds);
      }
      notifyListeners();

      if (await _supabase.saveShop(updatedShop)) {
        await _clearDirty(_dirtyShopIds, _keyDirtyShops, [updatedShop.id]);
      }
      if (affectedColIds.isNotEmpty) {
        final cols = _collections.where((c) => affectedColIds.contains(c.id)).toList();
        if (await _supabase.saveCollectionsBulk(cols)) {
          await _clearDirty(_dirtyCollectionIds, _keyDirtyCollections, affectedColIds);
        }
      }
      if (affectedBillIds.isNotEmpty) {
        final bills = _pendingBills.where((b) => affectedBillIds.contains(b.id)).toList();
        if (await _supabase.savePendingBillsBulk(bills)) {
          await _clearDirty(_dirtyBillIds, _keyDirtyBills, affectedBillIds);
        }
      }
    }
    return updatedShop;
  }

  Future<void> deleteShop(String shopId) async {
    _shops.removeWhere((s) => s.id == shopId);
    _dirtyShopIds.remove(shopId);
    _locallyDeletedShopIds.add(shopId);
    await _storage.saveIdSet(_keyDirtyShops, _dirtyShopIds);
    await _storage.saveDeletedShopIds(_locallyDeletedShopIds);
    await _storage.saveShops(_shops);
    notifyListeners();

    if (await _supabase.deleteShop(shopId)) {
      _locallyDeletedShopIds.remove(shopId);
      await _storage.saveDeletedShopIds(_locallyDeletedShopIds);
    }
  }

  List<ShopModel> getShopsForRoute(String routeId) {
    return _shops.where((s) => s.routeId == routeId).toList();
  }

  Future<void> reorderShopsForRoute(String routeId, List<String> orderedShopIds) async {
    _routeOutletOrders[routeId] = List<String>.from(orderedShopIds);
    final routeShops = _shops.where((s) => s.routeId == routeId).toList();
    routeShops.sort((a, b) {
      final idxA = orderedShopIds.indexOf(a.id);
      final idxB = orderedShopIds.indexOf(b.id);
      if (idxA == -1 && idxB == -1) return 0;
      if (idxA == -1) return 1;
      if (idxB == -1) return -1;
      return idxA.compareTo(idxB);
    });

    final otherShops = _shops.where((s) => s.routeId != routeId).toList();
    _shops = [...otherShops, ...routeShops];
    await _storage.saveRouteOutletOrders(_routeOutletOrders);
    await _markDirty(_dirtyRouteOrderIds, _keyDirtyRouteOrders, [routeId]);
    await _storage.saveShops(_shops);
    notifyListeners();

    if (await _supabase.saveRouteOutletOrder(routeId, orderedShopIds)) {
      await _clearDirty(_dirtyRouteOrderIds, _keyDirtyRouteOrders, [routeId]);
    }
  }

  ShopModel? getShopById(String id) {
    try {
      return _shops.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  // --- Collection Operations ---
  Future<void> addCollection(CollectionModel collection) async {
    if (_locallyDeletedCollectionIds.contains(collection.id)) {
      _locallyDeletedCollectionIds.remove(collection.id);
      await _storage.saveDeletedCollectionIds(_locallyDeletedCollectionIds);
    }

    final isSettled = (collection.balanceRemaining ?? 0.0) <= 0.001;
    final finalCollection = isSettled && collection.photoBase64 != null
        ? collection.copyWith(clearPhoto: true)
        : collection;

    _collections.removeWhere((c) => c.id == finalCollection.id);
    _collections.insert(0, finalCollection);
    _dirtyCollectionIds.add(finalCollection.id);
    try {
      await _storage.saveCollections(_collections);
      await _storage.saveIdSet(_keyDirtyCollections, _dirtyCollectionIds);
    } catch (e) {
      debugPrint('Storage save notice: $e');
    }
    notifyListeners();

    if (await _supabase.saveCollection(finalCollection)) {
      await _clearDirty(_dirtyCollectionIds, _keyDirtyCollections, [finalCollection.id]);
    }

    // Record chronological visit & collection checkpoint cleanly with offline queue fallback
    try {
      final shop = getShopById(finalCollection.shopId);
      final lat = shop?.latitude ?? (_currentUser?.latitude ?? 18.5204);
      final lng = shop?.longitude ?? (_currentUser?.longitude ?? 73.8567);
      final landmark = shop != null
          ? '${shop.name} (${shop.routeName})'
          : finalCollection.shopName;

      final tlEntry = LocationTimelineEntry(
        id: 'tl_${_currentUser?.id ?? "staff"}_${DateTime.now().millisecondsSinceEpoch}',
        userId: _currentUser?.id ?? 'staff',
        staffName: finalCollection.salesmanName.isNotEmpty
            ? finalCollection.salesmanName
            : (_currentUser?.name ?? 'Akash'),
        staffRole: _currentUser?.role.name ?? 'salesman',
        timestamp: finalCollection.collectedAt,
        latitude: lat,
        longitude: lng,
        landmark: landmark,
        eventType: 'collection',
        details:
            'Collected ₹${finalCollection.collectedAmount.toStringAsFixed(0)} (${finalCollection.paymentMode.displayName}) for Bill #${finalCollection.billNumber}',
        amount: finalCollection.collectedAmount,
        shopName: finalCollection.shopName,
        routeName: finalCollection.routeName,
        billNumber: finalCollection.billNumber,
      );
      final inserted = await _storage.addLocationTimelineEntry(
        tlEntry,
        minDuplicateSeconds: 5,
        minMovedDegrees: 0.00001,
      );
      if (inserted) {
        final pendingTl = await _storage.loadIdSet(StorageService.keyPendingTimelineIds);
        pendingTl.add(tlEntry.id);
        await _storage.saveIdSet(StorageService.keyPendingTimelineIds, pendingTl);
        if (await _supabase.saveLocationTimelineEntry(tlEntry)) {
          pendingTl.remove(tlEntry.id);
          await _storage.saveIdSet(StorageService.keyPendingTimelineIds, pendingTl);
        }
      }
    } catch (e) {
      debugPrint('Timeline collection log notice: $e');
    }

    // Auto-delete bill photos when collection completes to keep storage free forever
    if (isSettled) {
      await _syncPendingBillSettlement(finalCollection);
      await _purgePhotoForSettledBill(finalCollection.billNumber, finalCollection.shopId);
    }
  }

  /// Automatically updates matching pending bill to 'paid' and deletes its photo proof
  Future<void> _syncPendingBillSettlement(CollectionModel coll) async {
    final cleanBill = coll.billNumber.trim().toLowerCase();
    final cleanShop = coll.shopId.trim().toLowerCase();
    final updatedBills = <PendingBillModel>[];

    for (int i = 0; i < _pendingBills.length; i++) {
      final b = _pendingBills[i];
      if (b.billNumber.trim().toLowerCase() == cleanBill &&
          (cleanShop.isEmpty || b.shopId.trim().toLowerCase() == cleanShop)) {
        if (!b.isPaid || b.hasPhoto) {
          final updated = b.copyWith(
            collectedAmount: b.totalAmount,
            status: 'paid',
            clearPhoto: true, // Delete photo, all metadata remains permanently!
          );
          _pendingBills[i] = updated;
          updatedBills.add(updated);
        }
      }
    }

    if (updatedBills.isNotEmpty) {
      final ids = updatedBills.map((b) => b.id).toList();
      await _storage.savePendingBills(_pendingBills);
      await _markDirty(_dirtyBillIds, _keyDirtyBills, ids);
      notifyListeners();

      if (await _supabase.savePendingBillsBulk(updatedBills)) {
        await _clearDirty(_dirtyBillIds, _keyDirtyBills, ids);
      }
    }
  }

  /// Removes photos from any existing collections for a settled bill to reclaim storage
  Future<void> _purgePhotoForSettledBill(String billNumber, String? shopId) async {
    final cleanBill = billNumber.trim().toLowerCase();
    final cleanShopId = shopId?.trim().toLowerCase();
    final updatedColls = <CollectionModel>[];

    for (int i = 0; i < _collections.length; i++) {
      final c = _collections[i];
      if (c.billNumber.trim().toLowerCase() == cleanBill) {
        if (cleanShopId == null || cleanShopId.isEmpty || c.shopId.trim().toLowerCase() == cleanShopId) {
          if (c.hasPhoto) {
            final updated = c.copyWith(clearPhoto: true);
            _collections[i] = updated;
            updatedColls.add(updated);
          }
        }
      }
    }

    if (updatedColls.isNotEmpty) {
      final ids = updatedColls.map((c) => c.id).toList();
      await _storage.saveCollections(_collections);
      await _markDirty(_dirtyCollectionIds, _keyDirtyCollections, ids);
      notifyListeners();

      if (await _supabase.saveCollectionsBulk(updatedColls)) {
        await _clearDirty(_dirtyCollectionIds, _keyDirtyCollections, ids);
      }
    }
  }

  Future<void> deleteCollection(String id) async {
    final idx = _collections.indexWhere((c) => c.id == id);
    if (idx == -1) return;
    final coll = _collections[idx];

    // 1. Mark as locally deleted so background sync/realtime won't resurrect it
    _dirtyCollectionIds.remove(id);
    _locallyDeletedCollectionIds.add(id);
    _collections.removeAt(idx);

    // 2. Recalculate remaining collected sum for this invoice and update matching pending bill
    final cleanBill = coll.billNumber.trim().toLowerCase();
    final cleanShop = coll.shopId.trim().toLowerCase();
    final remainingSum = _collections.where((c) =>
        c.billNumber.trim().toLowerCase() == cleanBill &&
        (cleanShop.isEmpty || c.shopId.trim().toLowerCase() == cleanShop)
    ).fold(0.0, (s, c) => s + c.collectedAmount);

    final updatedBills = <PendingBillModel>[];
    for (int i = 0; i < _pendingBills.length; i++) {
      final pb = _pendingBills[i];
      if (pb.billNumber.trim().toLowerCase() == cleanBill &&
          (cleanShop.isEmpty || pb.shopId.trim().toLowerCase() == cleanShop)) {
        final newCollected = remainingSum.clamp(0.0, pb.totalAmount);
        final isPaid = (pb.totalAmount - newCollected) <= 0.001;
        final newStatus = isPaid ? 'paid' : (newCollected > 0 ? 'partial' : 'pending');
        final updatedPb = pb.copyWith(
          collectedAmount: newCollected,
          status: newStatus,
        );
        _pendingBills[i] = updatedPb;
        updatedBills.add(updatedPb);
      }
    }

    notifyListeners();

    // 3. Persist collections, pending bills, dirty & deleted IDs
    try {
      await _storage.saveCollections(_collections);
      await _storage.saveIdSet(_keyDirtyCollections, _dirtyCollectionIds);
      await _storage.saveDeletedCollectionIds(_locallyDeletedCollectionIds);
      if (updatedBills.isNotEmpty) {
        await _storage.savePendingBills(_pendingBills);
        await _markDirty(_dirtyBillIds, _keyDirtyBills, updatedBills.map((b) => b.id));
      }
    } catch (e) {
      debugPrint('Storage deleteCollection error: $e');
    }

    // 4. Push updated bills & delete from Supabase, clearing tombstones only on success
    if (updatedBills.isNotEmpty) {
      if (await _supabase.savePendingBillsBulk(updatedBills)) {
        await _clearDirty(_dirtyBillIds, _keyDirtyBills, updatedBills.map((b) => b.id));
      }
    }
    if (await _supabase.deleteCollection(id)) {
      _locallyDeletedCollectionIds.remove(id);
      await _storage.saveDeletedCollectionIds(_locallyDeletedCollectionIds);
    }
  }

  Future<void> deleteBillSummary(BillSummary bill) async {
    final targetBillNum = bill.billNumber.trim().toLowerCase();

    final matchingCollections = _collections.where((c) =>
        c.shopId == bill.shopId && c.billNumber.trim().toLowerCase() == targetBillNum).toList();

    final collIdsToDelete = <String>{
      for (final c in matchingCollections) c.id,
      for (final c in bill.collections) c.id,
    };

    final matchingPendingBills = _pendingBills.where((pb) =>
        pb.shopId == bill.shopId && pb.billNumber.trim().toLowerCase() == targetBillNum).toList();

    final pendingBillIdsToDelete = <String>{
      for (final pb in matchingPendingBills) pb.id,
    };

    for (final id in collIdsToDelete) {
      _dirtyCollectionIds.remove(id);
      _locallyDeletedCollectionIds.add(id);
      _collections.removeWhere((c) => c.id == id);
    }

    for (final id in pendingBillIdsToDelete) {
      _dirtyBillIds.remove(id);
      _locallyDeletedBillIds.add(id);
      _pendingBills.removeWhere((b) => b.id == id);
    }

    notifyListeners();

    try {
      await _storage.saveCollections(_collections);
      await _storage.saveIdSet(_keyDirtyCollections, _dirtyCollectionIds);
      await _storage.saveDeletedCollectionIds(_locallyDeletedCollectionIds);
      await _storage.savePendingBills(_pendingBills);
      await _storage.saveIdSet(_keyDirtyBills, _dirtyBillIds);
      await _storage.saveDeletedBillIds(_locallyDeletedBillIds);
    } catch (e) {
      debugPrint('Storage deleteBillSummary error: $e');
    }

    if (collIdsToDelete.isNotEmpty &&
        await _supabase.deleteCollectionsBulk(collIdsToDelete.toList())) {
      _locallyDeletedCollectionIds.removeAll(collIdsToDelete);
      await _storage.saveDeletedCollectionIds(_locallyDeletedCollectionIds);
    }
    if (pendingBillIdsToDelete.isNotEmpty &&
        await _supabase.deletePendingBillsBulk(pendingBillIdsToDelete.toList())) {
      _locallyDeletedBillIds.removeAll(pendingBillIdsToDelete);
      await _storage.saveDeletedBillIds(_locallyDeletedBillIds);
    }
  }

  List<CollectionModel> getCollectionsForShop(String shopId) {
    return _collections.where((c) => c.shopId == shopId).toList()
      ..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
  }

  double getTotalBalanceForShop(String shopId) {
    if (_shopBalanceCache == null) {
      final map = <String, double>{};
      for (final b in _pendingBills) {
        if (!b.isPaid && b.balanceDue > 0) {
          map[b.shopId] = (map[b.shopId] ?? 0.0) + b.balanceDue;
        }
      }
      _shopBalanceCache = map;
    }
    return _shopBalanceCache![shopId] ?? 0.0;
  }

  List<CollectionModel> getCollectionsForBill(String billNumber, {String? shopId, String? shopName}) {
    final cleanBill = billNumber.trim().toLowerCase();
    final cleanShopId = shopId?.trim().toLowerCase();
    final cleanShopName = shopName?.trim().toLowerCase();

    final matches = _collections.where((c) {
      if (c.billNumber.trim().toLowerCase() != cleanBill) return false;
      if (cleanShopId != null && c.shopId.trim().toLowerCase() == cleanShopId) return true;
      if (cleanShopName != null && c.shopName.trim().toLowerCase() == cleanShopName) return true;
      return true;
    }).toList()
      ..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));

    return matches;
  }

  List<String> getPhotosForBill(String billNumber, {String? shopId, String? shopName}) {
    final cleanBill = billNumber.trim().toLowerCase();
    final cleanShopId = shopId?.trim().toLowerCase();
    final cleanShopName = shopName?.trim().toLowerCase();

    // 1. Direct match in pending bills with shop match preferred
    for (final b in _pendingBills) {
      if (b.billNumber.trim().toLowerCase() == cleanBill && b.hasPhoto) {
        if (cleanShopId != null && b.shopId.trim().toLowerCase() == cleanShopId) {
          return b.allPhotos;
        }
        if (cleanShopName != null && b.shopName.trim().toLowerCase() == cleanShopName) {
          return b.allPhotos;
        }
      }
    }
    // Any pending bill with same billNumber
    for (final b in _pendingBills) {
      if (b.billNumber.trim().toLowerCase() == cleanBill && b.hasPhoto) {
        return b.allPhotos;
      }
    }

    // 2. Direct match in collections
    for (final c in _collections) {
      if (c.billNumber.trim().toLowerCase() == cleanBill && c.hasPhoto) {
        if (cleanShopId != null && c.shopId.trim().toLowerCase() == cleanShopId) {
          return c.allPhotos;
        }
        if (cleanShopName != null && c.shopName.trim().toLowerCase() == cleanShopName) {
          return c.allPhotos;
        }
      }
    }
    for (final c in _collections) {
      if (c.billNumber.trim().toLowerCase() == cleanBill && c.hasPhoto) {
        return c.allPhotos;
      }
    }

    // 3. Digit-based fuzzy match
    final digits = cleanBill.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isNotEmpty && digits.length >= 3) {
      for (final b in _pendingBills) {
        final bDigits = b.billNumber.replaceAll(RegExp(r'[^0-9]'), '');
        if (bDigits == digits && b.hasPhoto) {
          return b.allPhotos;
        }
      }
      for (final c in _collections) {
        final cDigits = c.billNumber.replaceAll(RegExp(r'[^0-9]'), '');
        if (cDigits == digits && c.hasPhoto) {
          return c.allPhotos;
        }
      }
    }

    return const [];
  }

  String? getPhotoForBill(String billNumber, {String? shopId, String? shopName}) {
    final photos = getPhotosForBill(billNumber, shopId: shopId, shopName: shopName);
    return photos.isNotEmpty ? photos.first : null;
  }

  // --- Pending Bill Operations ---
  Future<PendingBillModel> addPendingBill(PendingBillModel bill) async {
    if (_locallyDeletedBillIds.contains(bill.id)) {
      _locallyDeletedBillIds.remove(bill.id);
      await _storage.saveDeletedBillIds(_locallyDeletedBillIds);
    }

    _pendingBills.removeWhere((b) => b.id == bill.id);
    _pendingBills.insert(0, bill);
    _dirtyBillIds.add(bill.id);
    notifyListeners();

    try {
      await _storage.savePendingBills(_pendingBills);
      await _storage.saveIdSet(_keyDirtyBills, _dirtyBillIds);
    } catch (e) {
      debugPrint('Storage savePendingBills error: $e');
    }

    final ok = await _supabase.savePendingBill(bill);
    if (ok) {
      _dirtyBillIds.remove(bill.id);
      await _storage.saveIdSet(_keyDirtyBills, _dirtyBillIds);
    }

    return bill;
  }

  Future<int> addPendingBillsBulk(List<PendingBillModel> newBills) async {
    if (newBills.isEmpty) return 0;

    // Filter duplicates by billNumber + shopName + businessName
    final toAdd = <PendingBillModel>[];
    for (final bill in newBills) {
      final exists = _pendingBills.any((b) =>
          b.billNumber.trim().toLowerCase() == bill.billNumber.trim().toLowerCase() &&
          b.shopName.trim().toLowerCase() == bill.shopName.trim().toLowerCase() &&
          b.businessName.trim().toLowerCase() == bill.businessName.trim().toLowerCase());
      if (!exists) {
        toAdd.add(bill);
      }
    }

    if (toAdd.isEmpty) return 0;

    final addedIds = toAdd.map((b) => b.id).toSet();
    _pendingBills.insertAll(0, toAdd);
    _locallyDeletedBillIds.removeAll(addedIds);
    _dirtyBillIds.addAll(addedIds);
    notifyListeners();

    try {
      await _storage.savePendingBills(_pendingBills);
      await _storage.saveDeletedBillIds(_locallyDeletedBillIds);
      await _storage.saveIdSet(_keyDirtyBills, _dirtyBillIds);
    } catch (e) {
      debugPrint('Storage savePendingBills bulk error: $e');
    }

    final ok = await _supabase.savePendingBillsBulk(toAdd);
    if (ok) {
      _dirtyBillIds.removeAll(addedIds);
      await _storage.saveIdSet(_keyDirtyBills, _dirtyBillIds);
    }

    return toAdd.length;
  }

  Future<void> updatePendingBill(PendingBillModel updatedBill) async {
    final idx = _pendingBills.indexWhere((b) => b.id == updatedBill.id);
    if (idx != -1) {
      _pendingBills[idx] = updatedBill;
      _dirtyBillIds.add(updatedBill.id);
      notifyListeners();
      try {
        await _storage.savePendingBills(_pendingBills);
        await _storage.saveIdSet(_keyDirtyBills, _dirtyBillIds);
      } catch (e) {
        debugPrint('Storage updatePendingBill error: $e');
      }
      final ok = await _supabase.savePendingBill(updatedBill);
      if (ok) {
        _dirtyBillIds.remove(updatedBill.id);
        await _storage.saveIdSet(_keyDirtyBills, _dirtyBillIds);
      }
    }
  }

  Future<void> deletePendingBill(String id) async {
    final idx = _pendingBills.indexWhere((b) => b.id == id);
    if (idx == -1) return;
    final pb = _pendingBills[idx];
    final cleanBill = pb.billNumber.trim().toLowerCase();
    final cleanShop = pb.shopId.trim().toLowerCase();

    // 1. Mark pending bill as locally deleted so background cloud sync won't resurrect it
    _dirtyBillIds.remove(id);
    _locallyDeletedBillIds.add(id);
    _pendingBills.removeAt(idx);

    // 2. Also remove and tombstone any collections associated with this bill
    final collsToDelete = _collections.where((c) =>
        c.billNumber.trim().toLowerCase() == cleanBill &&
        (cleanShop.isEmpty || c.shopId.trim().toLowerCase() == cleanShop)
    ).toList();
    final deletedCollIds = collsToDelete.map((c) => c.id).toList();

    for (final cid in deletedCollIds) {
      _dirtyCollectionIds.remove(cid);
      _locallyDeletedCollectionIds.add(cid);
      _collections.removeWhere((col) => col.id == cid);
    }

    notifyListeners();

    // 3. Save pending bills, collections, dirty & deleted ID sets to local storage
    try {
      await _storage.savePendingBills(_pendingBills);
      await _storage.saveIdSet(_keyDirtyBills, _dirtyBillIds);
      await _storage.saveDeletedBillIds(_locallyDeletedBillIds);
      if (collsToDelete.isNotEmpty) {
        await _storage.saveCollections(_collections);
        await _storage.saveIdSet(_keyDirtyCollections, _dirtyCollectionIds);
        await _storage.saveDeletedCollectionIds(_locallyDeletedCollectionIds);
      }
    } catch (e) {
      debugPrint('Storage deletePendingBill error: $e');
    }

    // 4. Delete from Supabase and ONLY clear tombstones if cloud delete succeeded
    if (deletedCollIds.isNotEmpty) {
      if (await _supabase.deleteCollectionsBulk(deletedCollIds)) {
        _locallyDeletedCollectionIds.removeAll(deletedCollIds);
        await _storage.saveDeletedCollectionIds(_locallyDeletedCollectionIds);
      }
    }
    if (await _supabase.deletePendingBill(id)) {
      _locallyDeletedBillIds.remove(id);
      await _storage.saveDeletedBillIds(_locallyDeletedBillIds);
    }
  }

  Future<void> syncPendingBillsFromCloud() async {
    await syncAllWithCloud(notify: true);
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _pendingBillsSubscription?.cancel();
    _collectionsSubscription?.cancel();
    _shopsSubscription?.cancel();
    _routesSubscription?.cancel();
    super.dispose();
  }

  List<PendingBillModel> getPendingBillsForRoute(String routeId, {String? businessName}) {
    return _pendingBills.where((b) {
      if (b.routeId != routeId) return false;
      if (businessName != null && businessName.isNotEmpty && businessName != 'All') {
        if (b.businessName != businessName) return false;
      }
      return !b.isPaid;
    }).toList()
      ..sort((a, b) => b.invoiceDate.compareTo(a.invoiceDate));
  }

  PendingBillModel? getPendingBillById(String id) {
    try {
      return _pendingBills.firstWhere((b) => b.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> recordCollectionForPendingBill({
    required PendingBillModel pendingBill,
    required double collectedAmount,
    required PaymentMode paymentMode,
    required DateTime collectionDate,
    String? chequeNumber,
    String? bankName,
    String? referenceNumber,
  }) async {
    final remainingAfter = pendingBill.balanceDue - collectedAmount;
    final newCollectedTotal = pendingBill.collectedAmount + collectedAmount;
    final isFullyPaid = (pendingBill.totalAmount - newCollectedTotal) <= 0.001;
    final newStatus = isFullyPaid ? 'paid' : 'partial';

    final newCollection = CollectionModel(
      id: _uuid.v4(),
      businessName: pendingBill.businessName,
      shopId: pendingBill.shopId,
      shopName: pendingBill.shopName,
      routeId: pendingBill.routeId,
      routeName: pendingBill.routeName,
      billNumber: pendingBill.billNumber,
      billAmount: pendingBill.totalAmount,
      collectedAmount: collectedAmount,
      balanceRemaining: remainingAfter > 0 ? remainingAfter : 0.0,
      paymentMode: paymentMode,
      chequeNumber: chequeNumber,
      bankName: bankName,
      referenceNumber: referenceNumber,
      salesmanName: _salesmanName,
      collectedAt: collectionDate,
      billDate: pendingBill.invoiceDate,
      photoBase64: isFullyPaid ? null : (pendingBill.allPhotos.isNotEmpty ? pendingBill.allPhotos.first : null),
      photosBase64: isFullyPaid ? const [] : pendingBill.allPhotos,
    );
    await addCollection(newCollection);

    final updatedBill = pendingBill.copyWith(
      collectedAmount: newCollectedTotal,
      status: newStatus,
      clearPhoto: isFullyPaid, // Auto-delete photo when collection is done! Bill details remain permanently.
    );
    await updatePendingBill(updatedBill);

    if (isFullyPaid) {
      await _purgePhotoForSettledBill(pendingBill.billNumber, pendingBill.shopId);
    }
  }

  List<CollectionModel> getCollectionsForMode(PaymentMode mode, {DateTime? forDate, String? business}) {
    return getFilteredCollections(forDate: forDate).where((c) {
      if (business != null && business.isNotEmpty && business != 'All') {
        if (c.businessName != business) return false;
      }
      return c.paymentMode == mode;
    }).toList()
      ..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
  }

  // --- Professional Report Formatter ---
  String generateWhatsAppReportText({DateTime? forDate}) {
    final date = forDate ?? _selectedDate;
    final dateStr = DateFormat('dd MMM yyyy').format(date);
    final list = getFilteredCollections(forDate: date);

    final cash = list.where((c) => c.paymentMode == PaymentMode.cash).fold(0.0, (s, c) => s + c.collectedAmount);
    final upi = list.where((c) => c.paymentMode == PaymentMode.upi).fold(0.0, (s, c) => s + c.collectedAmount);
    final cheque = list.where((c) => c.paymentMode == PaymentMode.cheque).fold(0.0, (s, c) => s + c.collectedAmount);
    final netBanking = list.where((c) => c.paymentMode == PaymentMode.netBanking).fold(0.0, (s, c) => s + c.collectedAmount);

    final totalBilled = calculateTotalBilled(list);
    final totalCollected = list.fold(0.0, (s, c) => s + c.collectedAmount);
    final totalBalance = calculateTotalBalanceDue(list);

    final cashBills = list.where((c) => c.paymentMode == PaymentMode.cash).length;
    final upiBills = list.where((c) => c.paymentMode == PaymentMode.upi).length;
    final chequeBills = list.where((c) => c.paymentMode == PaymentMode.cheque).length;
    final netBills = list.where((c) => c.paymentMode == PaymentMode.netBanking).length;
    
    final uniqueBillCount = countUniqueBills(list);
    final uniquePartialCount = list.where((c) {
      final bSum = getBillSummary(c.shopId, c.billNumber);
      return bSum != null ? bSum.isPending : ((c.balanceRemaining ?? 0.0) > 0.001);
    }).map((c) => '${c.shopId}_${c.billNumber.trim().toLowerCase()}').toSet().length;

    final firmHeader = (_filterBusiness != null && _filterBusiness != 'All')
        ? 'Business: $_filterBusiness\n'
        : 'Business: Purva Enterprises & Manas Sales\n';

    final routeHeader = (_filterRouteId != null && _filterRouteId != 'All')
        ? 'Route: ${_routes.firstWhere((r) => r.id == _filterRouteId, orElse: () => RouteModel(id: '', name: 'Selected')).name}\n'
        : '';

    return '''
*DAILY COLLECTION REPORT*
Date: $dateStr
Salesman: $_salesmanName
$firmHeader$routeHeader--------------------------------------------------
*FINANCIAL SUMMARY*
Total Invoiced:    ${CurrencyFormatter.format(totalBilled)} ($uniqueBillCount ${uniqueBillCount == 1 ? 'bill' : 'bills'})
Total Collected:   ${CurrencyFormatter.format(totalCollected)}
Pending Balance:   ${CurrencyFormatter.format(totalBalance)}
Receipts Count:    ${list.length} ($uniquePartialCount pending/partial)
--------------------------------------------------
*PAYMENT BREAKDOWN*
Cash:              ${CurrencyFormatter.format(cash)} ($cashBills receipts)
UPI / QR:          ${CurrencyFormatter.format(upi)} ($upiBills receipts)
Cheque:            ${CurrencyFormatter.format(cheque)} ($chequeBills receipts)
Net Banking:       ${CurrencyFormatter.format(netBanking)} ($netBills receipts)
--------------------------------------------------
*NET COLLECTED:*   ${CurrencyFormatter.format(totalCollected)}
--------------------------------------------------
_Generated via Daily Collection Pro_
'''.trim();
  }

  // --- Cash Handover & Denominations Operations ---
  Future<void> saveCashHandover(CashHandoverModel handover) async {
    _cashHandovers.removeWhere((h) => h.id == handover.id);
    _cashHandovers.insert(0, handover);
    _locallyDeletedHandoverIds.remove(handover.id);
    _dirtyHandoverIds.add(handover.id);
    await _storage.saveCashHandovers(_cashHandovers);
    await _storage.saveIdSet(_keyDeletedHandovers, _locallyDeletedHandoverIds);
    await _storage.saveIdSet(_keyDirtyHandovers, _dirtyHandoverIds);
    notifyListeners();

    final ok = await _supabase.saveCashHandover(handover);
    if (ok) {
      _dirtyHandoverIds.remove(handover.id);
      await _storage.saveIdSet(_keyDirtyHandovers, _dirtyHandoverIds);
    }
  }

  Future<void> deleteCashHandover(String id) async {
    _cashHandovers.removeWhere((h) => h.id == id);
    _dirtyHandoverIds.remove(id);
    _locallyDeletedHandoverIds.add(id);
    await _storage.saveCashHandovers(_cashHandovers);
    await _storage.saveIdSet(_keyDirtyHandovers, _dirtyHandoverIds);
    await _storage.saveIdSet(_keyDeletedHandovers, _locallyDeletedHandoverIds);
    notifyListeners();

    final ok = await _supabase.deleteCashHandover(id);
    if (ok) {
      _locallyDeletedHandoverIds.remove(id);
      await _storage.saveIdSet(_keyDeletedHandovers, _locallyDeletedHandoverIds);
    }
  }

  CashHandoverModel? getLatestHandoverForDate(DateTime date, {String? business}) {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    try {
      return _cashHandovers.firstWhere((h) {
        final hDateStr = DateFormat('yyyy-MM-dd').format(h.date);
        final sameDate = hDateStr == dateStr;
        if (!sameDate) return false;
        if (business != null && business.isNotEmpty && business != 'All') {
          return h.businessName == business || h.businessName == 'All';
        }
        return true;
      });
    } catch (_) {
      return null;
    }
  }

  String generateCashHandoverWhatsAppText(CashHandoverModel h) {
    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(h.createdAt);
    final statusStr = h.isMatched
        ? '✅ PERFECT MATCH (₹0 difference)'
        : (h.hasShortage
            ? '⚠️ SHORTAGE: -${CurrencyFormatter.format(h.variance.abs())}'
            : 'ℹ️ SURPLUS: +${CurrencyFormatter.format(h.variance)}');

    final lines = <String>[];
    if (h.count500 > 0) lines.add('₹500 × ${h.count500} = ₹${h.count500 * 500}');
    if (h.count200 > 0) lines.add('₹200 × ${h.count200} = ₹${h.count200 * 200}');
    if (h.count100 > 0) lines.add('₹100 × ${h.count100} = ₹${h.count100 * 100}');
    if (h.count50 > 0) lines.add('₹50 × ${h.count50} = ₹${h.count50 * 50}');
    if (h.count20 > 0) lines.add('₹20 × ${h.count20} = ₹${h.count20 * 20}');
    if (h.count10 > 0) lines.add('₹10 × ${h.count10} = ₹${h.count10 * 10}');
    if (h.coinsAmount > 0) lines.add('Coins = ${CurrencyFormatter.format(h.coinsAmount)}');

    final denomSection = lines.isNotEmpty ? lines.join('\n') : 'No physical notes entered';

    return '''
*CASH HANDOVER REPORT*
Date: $dateStr
Firm: ${h.businessName}
Salesman: ${h.salesmanName}
Handed Over To: ${h.receivedByName}
--------------------------------------------------
*PHYSICAL CASH DENOMINATIONS:*
$denomSection
--------------------------------------------------
*CASH RECONCILIATION:*
Total Counted Cash:  ${CurrencyFormatter.format(h.totalCounted)}
System Cash Target:  ${CurrencyFormatter.format(h.totalExpected)}
Verification:        $statusStr
${h.remarks != null && h.remarks!.trim().isNotEmpty ? 'Note: ${h.remarks!.trim()}\n' : ''}--------------------------------------------------
_Daily Collection Pro Cash Verification_
'''.trim();
  }

  // --- Vehicle Collection Operations ---
  Future<void> saveVehicleCollection(VehicleCollectionModel entry) async {
    _vehicleCollections.removeWhere((v) => v.id == entry.id);
    _vehicleCollections.insert(0, entry);
    _locallyDeletedVehicleCollectionIds.remove(entry.id);
    _dirtyVehicleCollectionIds.add(entry.id);
    await _storage.saveVehicleCollections(_vehicleCollections);
    await _storage.saveIdSet(
      _keyDeletedVehicleCollections,
      _locallyDeletedVehicleCollectionIds,
    );
    await _storage.saveIdSet(
      _keyDirtyVehicleCollections,
      _dirtyVehicleCollectionIds,
    );
    notifyListeners();

    final ok = await _supabase.saveVehicleCollection(entry);
    if (ok) {
      _dirtyVehicleCollectionIds.remove(entry.id);
      await _storage.saveIdSet(
        _keyDirtyVehicleCollections,
        _dirtyVehicleCollectionIds,
      );
    }
  }

  Future<void> deleteVehicleCollection(String id) async {
    _vehicleCollections.removeWhere((v) => v.id == id);
    _dirtyVehicleCollectionIds.remove(id);
    _locallyDeletedVehicleCollectionIds.add(id);
    await _storage.saveVehicleCollections(_vehicleCollections);
    await _storage.saveIdSet(
      _keyDirtyVehicleCollections,
      _dirtyVehicleCollectionIds,
    );
    await _storage.saveIdSet(
      _keyDeletedVehicleCollections,
      _locallyDeletedVehicleCollectionIds,
    );
    notifyListeners();

    final ok = await _supabase.deleteVehicleCollection(id);
    if (ok) {
      _locallyDeletedVehicleCollectionIds.remove(id);
      await _storage.saveIdSet(
        _keyDeletedVehicleCollections,
        _locallyDeletedVehicleCollectionIds,
      );
    }
  }

  VehicleCollectionModel? getLatestVehicleCollectionForDate(DateTime date, {String? vehicleNo}) {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    try {
      return _vehicleCollections.firstWhere((v) {
        final vDateStr = DateFormat('yyyy-MM-dd').format(v.date);
        final sameDate = vDateStr == dateStr;
        if (!sameDate) return false;
        if (vehicleNo != null && vehicleNo.isNotEmpty && vehicleNo != 'All') {
          return v.vehicleNo == vehicleNo;
        }
        return true;
      });
    } catch (_) {
      return null;
    }
  }

  String generateVehicleCollectionWhatsAppText(VehicleCollectionModel v) {
    return v.generateWhatsAppText();
  }

  // --- Vehicle & Employee Management Operations ---
  Future<void> addVehicle(String vehicleNo) async {
    final v = vehicleNo.trim().toUpperCase();
    if (v.isEmpty || _vehicles.any((x) => x.toUpperCase() == v)) return;
    _vehicles.add(v);
    _dirtyVehiclesFlag = true;
    await _storage.saveVehicles(_vehicles);
    await _storage.saveBoolFlag(_keyDirtyVehiclesFlag, true);
    notifyListeners();

    if (await _supabase.saveManagedVehicles(_vehicles)) {
      _dirtyVehiclesFlag = false;
      await _storage.saveBoolFlag(_keyDirtyVehiclesFlag, false);
    }
  }

  Future<void> deleteVehicle(String vehicleNo) async {
    _vehicles.removeWhere((v) => v.toUpperCase() == vehicleNo.trim().toUpperCase());
    _dirtyVehiclesFlag = true;
    await _storage.saveVehicles(_vehicles);
    await _storage.saveBoolFlag(_keyDirtyVehiclesFlag, true);
    notifyListeners();

    if (await _supabase.saveManagedVehicles(_vehicles)) {
      _dirtyVehiclesFlag = false;
      await _storage.saveBoolFlag(_keyDirtyVehiclesFlag, false);
    }
  }

  Future<void> addEmployee(String employeeName) async {
    final name = employeeName.trim();
    if (name.isEmpty || _employees.any((x) => x.toLowerCase() == name.toLowerCase())) return;
    _employees.add(name);
    _dirtyEmployeesFlag = true;
    await _storage.saveEmployees(_employees);
    await _storage.saveBoolFlag(_keyDirtyEmployeesFlag, true);
    notifyListeners();

    if (await _supabase.saveManagedEmployees(_employees)) {
      _dirtyEmployeesFlag = false;
      await _storage.saveBoolFlag(_keyDirtyEmployeesFlag, false);
    }
  }

  Future<void> deleteEmployee(String employeeName) async {
    _employees.removeWhere((e) => e.trim().toLowerCase() == employeeName.trim().toLowerCase());
    _dirtyEmployeesFlag = true;
    await _storage.saveEmployees(_employees);
    await _storage.saveBoolFlag(_keyDirtyEmployeesFlag, true);
    notifyListeners();

    if (await _supabase.saveManagedEmployees(_employees)) {
      _dirtyEmployeesFlag = false;
      await _storage.saveBoolFlag(_keyDirtyEmployeesFlag, false);
    }
  }

  // --- Sales Order Operations ---
  List<SalesOrderModel> getAccessibleSalesOrders(UserModel? user) {
    if (user == null || user.isSuperAdmin || user.isOffice) {
      return _salesOrders;
    }
    if (user.assignedRouteIds.isEmpty) {
      return _salesOrders;
    }
    final assigned = user.assignedRouteIds.toSet();
    final plain = user.plainName.toLowerCase().trim();
    final full = user.name.toLowerCase().trim();
    return _salesOrders.where((o) {
      final orderStaff = o.salesmanName.toLowerCase().trim();
      final isOwn = orderStaff == plain || orderStaff == full;
      return isOwn || assigned.contains(o.routeId);
    }).toList();
  }

  Future<void> addSalesOrder(SalesOrderModel order) async {
    final isEdit = _salesOrders.any((o) => o.id == order.id);
    final savedOrder = isEdit ? order.copyWith(updatedAt: DateTime.now()) : order;
    _salesOrders.removeWhere((o) => o.id == savedOrder.id);
    _salesOrders.insert(0, savedOrder);
    _locallyDeletedOrderIds.remove(savedOrder.id);
    _cloudDeletedOrderIds.remove(savedOrder.id);
    _sessionDeletedOrderIds.remove(savedOrder.id);
    _dirtyOrderIds.add(savedOrder.id);
    await _storage.saveSalesOrders(_salesOrders);
    await _storage.saveIdSet(_keyDeletedOrders, _locallyDeletedOrderIds);
    await _storage.saveIdSet(_keyCloudDeletedOrders, _cloudDeletedOrderIds);
    await _storage.saveIdSet(_keyDirtyOrders, _dirtyOrderIds);
    notifyListeners();

    if (await _supabase.saveSalesOrder(savedOrder)) {
      _dirtyOrderIds.remove(savedOrder.id);
      await _storage.saveIdSet(_keyDirtyOrders, _dirtyOrderIds);
    }
  }

  Future<void> updateSalesOrderStatus(String orderId, String status) async {
    final idx = _salesOrders.indexWhere((o) => o.id == orderId);
    if (idx == -1) return;
    final updated = _salesOrders[idx].copyWith(
      status: status,
      updatedAt: DateTime.now(),
    );
    await addSalesOrder(updated);
  }

  Future<bool> deleteSalesOrder(String orderId) async {
    _salesOrders.removeWhere((o) => o.id == orderId);
    _dirtyOrderIds.remove(orderId);
    _locallyDeletedOrderIds.add(orderId);
    _cloudDeletedOrderIds.add(orderId);
    _sessionDeletedOrderIds.add(orderId);
    await _storage.saveSalesOrders(_salesOrders);
    await _storage.saveIdSet(_keyDirtyOrders, _dirtyOrderIds);
    await _storage.saveIdSet(_keyDeletedOrders, _locallyDeletedOrderIds);
    await _storage.saveIdSet(_keyCloudDeletedOrders, _cloudDeletedOrderIds);
    notifyListeners();

    final deletedInCloud = await _supabase.deleteSalesOrder(orderId);
    if (deletedInCloud) {
      _locallyDeletedOrderIds.remove(orderId);
      await _storage.saveIdSet(_keyDeletedOrders, _locallyDeletedOrderIds);
      await _supabase.saveDeletedOrderTombstones(_cloudDeletedOrderIds.toList());
    }
    return deletedInCloud;
  }

  // --- Customer History for Order Screen ---
  List<SalesOrderModel> getPreviousOrdersForShop(String shopId, {int limit = 3}) {
    final matches = _salesOrders.where((o) => o.shopId == shopId).toList();
    matches.sort((a, b) => b.orderDate.compareTo(a.orderDate));
    return matches.take(limit).toList();
  }

  List<PendingBillModel> getPreviousBillsForShop(String shopId, {int limit = 3}) {
    final matches = _pendingBills.where((b) => b.shopId == shopId).toList();
    matches.sort((a, b) => b.billDate.compareTo(a.billDate));
    return matches.take(limit).toList();
  }

  // --- Custom Product Master Management ---
  Future<void> addCustomProduct(CatalogProduct product) async {
    final key = OrderCatalogService.skuKey(product);
    final duplicateIds = _customProducts
        .where((p) => p.id != product.id && OrderCatalogService.skuKey(p) == key)
        .map((p) => p.id)
        .toList();

    _customProducts.removeWhere(
      (p) => p.id == product.id || OrderCatalogService.skuKey(p) == key,
    );
    _customProducts.add(product);
    OrderCatalogService.addCustomProduct(product);

    _locallyDeletedProductIds.remove(product.id);
    _dirtyProductIds.add(product.id);
    for (final dupId in duplicateIds) {
      _dirtyProductIds.remove(dupId);
      _locallyDeletedProductIds.add(dupId);
    }

    await _storage.saveCustomProducts(_customProducts);
    await _storage.saveIdSet(_keyDeletedProducts, _locallyDeletedProductIds);
    await _storage.saveIdSet(_keyDirtyProducts, _dirtyProductIds);
    notifyListeners();

    if (duplicateIds.isNotEmpty) {
      if (await _supabase.deleteCustomProductsBulk(duplicateIds)) {
        _locallyDeletedProductIds.removeAll(duplicateIds);
        await _storage.saveIdSet(_keyDeletedProducts, _locallyDeletedProductIds);
      }
    }

    if (await _supabase.saveCustomProduct(product)) {
      _dirtyProductIds.remove(product.id);
      await _storage.saveIdSet(_keyDirtyProducts, _dirtyProductIds);
    }
  }

  Future<void> deleteCustomProduct(String productId) async {
    _customProducts.removeWhere((p) => p.id == productId);
    OrderCatalogService.deleteCustomProduct(productId);
    _dirtyProductIds.remove(productId);
    _locallyDeletedProductIds.add(productId);
    await _storage.saveCustomProducts(_customProducts);
    await _storage.saveIdSet(_keyDirtyProducts, _dirtyProductIds);
    await _storage.saveIdSet(_keyDeletedProducts, _locallyDeletedProductIds);
    notifyListeners();

    if (await _supabase.deleteCustomProduct(productId)) {
      _locallyDeletedProductIds.remove(productId);
      await _storage.saveIdSet(_keyDeletedProducts, _locallyDeletedProductIds);
    }
  }

  String _normProductToken(String input) =>
      input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<({int updatedCount, int addedCount})> importTallyStock(
    List<TallyStockItemRow> rows, {
    required String defaultFirm,
    bool createUnmatched = true,
  }) async {
    final touched = <CatalogProduct>[];
    int updatedCount = 0;
    int addedCount = 0;
    final stamp = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      final normName = _normProductToken(row.name);
      if (normName.isEmpty) continue;

      final targetFirm = row.firm.trim().isNotEmpty ? row.firm.trim() : defaultFirm;
      final normTargetFirm = _normProductToken(targetFirm);

      // Prefer same-firm match, then fallback to any firm with exact name
      int idx = _customProducts.indexWhere(
        (p) => _normProductToken(p.name) == normName && _normProductToken(p.firm) == normTargetFirm,
      );
      if (idx == -1) {
        idx = _customProducts.indexWhere((p) => _normProductToken(p.name) == normName);
      }

      if (idx != -1) {
        final existing = _customProducts[idx];
        final updated = existing.copyWith(
          stock: row.closingQty,
          scheme: row.scheme.trim().isNotEmpty ? row.scheme.trim() : existing.scheme,
          availability: row.closingQty > 0 ? 'In Stock' : existing.availability,
        );
        _customProducts[idx] = updated;
        OrderCatalogService.addCustomProduct(updated);
        _locallyDeletedProductIds.remove(updated.id);
        _dirtyProductIds.add(updated.id);
        touched.add(updated);
        updatedCount++;
      } else if (createUnmatched) {
        final created = CatalogProduct(
          id: 'cust-tally-$stamp-$i',
          name: row.name.trim(),
          category: row.category.trim().isNotEmpty ? row.category.trim() : 'General',
          subcategory: row.subcategory.trim().isNotEmpty ? row.subcategory.trim() : 'General',
          company: row.company.trim().isNotEmpty ? row.company.trim() : 'General',
          firm: targetFirm,
          packing: row.unit,
          rate: 0.0,
          mrp: 0.0,
          defaultUnit: row.unit,
          unitsPerCase: row.unitsPerCase,
          stock: row.closingQty,
          scheme: row.scheme.trim(),
          availability: row.closingQty > 0 ? 'In Stock' : 'Out of Stock',
        );
        _customProducts.add(created);
        OrderCatalogService.addCustomProduct(created);
        _locallyDeletedProductIds.remove(created.id);
        _dirtyProductIds.add(created.id);
        touched.add(created);
        addedCount++;
      }
    }

    if (touched.isNotEmpty) {
      await _storage.saveCustomProducts(_customProducts);
      await _storage.saveIdSet(_keyDeletedProducts, _locallyDeletedProductIds);
      await _storage.saveIdSet(_keyDirtyProducts, _dirtyProductIds);
      notifyListeners();

      if (await _supabase.saveCustomProductsBulk(touched)) {
        for (final p in touched) {
          _dirtyProductIds.remove(p.id);
        }
        await _storage.saveIdSet(_keyDirtyProducts, _dirtyProductIds);
      }
    }

    return (updatedCount: updatedCount, addedCount: addedCount);
  }

  // --- Salesman Profile Management ---
  Future<void> updateProfile({required String name, String? phone, String? role}) async {
    if (name.trim().isNotEmpty) {
      _salesmanName = name.trim();
      await _storage.saveSalesmanName(_salesmanName);
    }
    if (phone != null && phone.trim().isNotEmpty) {
      _salesmanPhone = phone.trim();
      await _storage.saveSalesmanPhone(_salesmanPhone);
    }
    if (role != null && role.trim().isNotEmpty) {
      _salesmanRole = role.trim();
      await _storage.saveSalesmanRole(_salesmanRole);
    }
    notifyListeners();
  }

  // Clear all transaction data (collections, pending bills, orders) but KEEP all routes & shops
  Future<void> resetTransactions() async {
    final oldCollectionIds = _collections.map((c) => c.id).toSet();
    final oldBillIds = _pendingBills.map((b) => b.id).toSet();
    final oldOrderIds = _salesOrders.map((o) => o.id).toList();

    _collections.clear();
    _pendingBills.clear();
    _salesOrders.clear();
    _dirtyCollectionIds.clear();
    _dirtyBillIds.clear();
    _dirtyOrderIds.clear();

    _locallyDeletedCollectionIds.addAll(oldCollectionIds);
    _locallyDeletedBillIds.addAll(oldBillIds);
    _locallyDeletedOrderIds.addAll(oldOrderIds);

    await _storage.saveCollections(_collections);
    await _storage.savePendingBills(_pendingBills);
    await _storage.saveSalesOrders(_salesOrders);
    await _storage.saveIdSet(_keyDirtyCollections, _dirtyCollectionIds);
    await _storage.saveIdSet(_keyDirtyBills, _dirtyBillIds);
    await _storage.saveIdSet(_keyDirtyOrders, _dirtyOrderIds);
    await _storage.saveDeletedCollectionIds(_locallyDeletedCollectionIds);
    await _storage.saveDeletedBillIds(_locallyDeletedBillIds);
    await _storage.saveIdSet(_keyDeletedOrders, _locallyDeletedOrderIds);
    notifyListeners();

    if (await _supabase.clearAllBillsAndCollections()) {
      _locallyDeletedCollectionIds.removeAll(oldCollectionIds);
      _locallyDeletedBillIds.removeAll(oldBillIds);
      await _storage.saveDeletedCollectionIds(_locallyDeletedCollectionIds);
      await _storage.saveDeletedBillIds(_locallyDeletedBillIds);
    }
    if (oldOrderIds.isNotEmpty &&
        await _supabase.deleteSalesOrdersBulk(oldOrderIds)) {
      _locallyDeletedOrderIds.removeAll(oldOrderIds);
      await _storage.saveIdSet(_keyDeletedOrders, _locallyDeletedOrderIds);
    }
  }

  // Reset to initial sample data
  Future<void> resetToSample() async {
    _initFuture = null;
    await _storage.clearAll();
    await initialize();
  }
}
