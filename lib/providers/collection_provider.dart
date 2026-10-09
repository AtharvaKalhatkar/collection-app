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
import '../services/order_catalog_service.dart';
import '../services/storage_service.dart';
import '../services/sample_data_service.dart';
import '../services/firebase_service.dart';
import '../services/backup_service.dart';
import '../services/auth_service.dart';
import '../utils/currency_formatter.dart';
import '../utils/marathi_search_helper.dart';

class CollectionProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final FirebaseService _firebase = FirebaseService();
  final BackupService _backupService = BackupService();
  final Uuid _uuid = const Uuid();
  DateTime? _lastBackupTime;

  List<RouteModel> _routes = [];
  List<ShopModel> _shops = [];
  List<CollectionModel> _collections = [];
  List<PendingBillModel> _pendingBills = [];
  List<SalesOrderModel> _salesOrders = [];
  List<CatalogProduct> _customProducts = [];
  List<String> _businesses = ['Purva Enterprises', 'Manas Sales'];
  String _salesmanName = 'Akash';
  String _salesmanPhone = '+91 98765 43210';
  String _salesmanRole = 'Field Collection & Sales Officer';
  bool _isLoading = true;

  // Filters for Dashboard & Collection List
  DateTime _selectedDate = DateTime.now();
  String? _filterBusiness; // null means 'All'
  String? _filterRouteId; // null means 'All'
  String _searchQuery = '';

  List<RouteModel> get routes {
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
  List<ShopModel> get shops => _shops;
  List<CollectionModel> get collections => _collections;
  List<PendingBillModel> get pendingBills => _pendingBills;
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
  bool get isFirebaseConnected => _firebase.isInitialized;
  String? get firebaseError => _firebase.lastError;
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

  CollectionProvider() {
    initialize();
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    // 1. Initialize local cache first for instant UI availability
    final isFirst = await _storage.isFirstLaunch();
    if (isFirst) {
      _routes = SampleDataService.getInitialRoutes();
      _shops = SampleDataService.getInitialShops();
      _collections = SampleDataService.getInitialCollections();
      _pendingBills = SampleDataService.getInitialPendingBills();
      _businesses = ['Purva Enterprises', 'Manas Sales'];
      _salesmanName = 'Akash';

      await _storage.saveRoutes(_routes);
      await _storage.saveShops(_shops);
      await _storage.saveCollections(_collections);
      await _storage.savePendingBills(_pendingBills);
      await _storage.saveBusinesses(_businesses);
      await _storage.saveSalesmanName(_salesmanName);
      await _storage.markInitialized();
    } else {
      _routes = await _storage.loadRoutes();
      _shops = await _storage.loadShops();
      _collections = await _storage.loadCollections();
      _pendingBills = await _storage.loadPendingBills();

      // Auto-purge any legacy sample dummy records (col-1..col-6, pb-1..pb-4, shop-*)
      final hadDummyCol = _collections.any((c) => c.id.startsWith('col-'));
      final hadDummyPb = _pendingBills.any((b) => b.id.startsWith('pb-'));
      final hadDummyShop = _shops.any(_isDummyShop);
      if (hadDummyCol || hadDummyPb || hadDummyShop) {
        _collections.removeWhere((c) => c.id.startsWith('col-'));
        _pendingBills.removeWhere((b) => b.id.startsWith('pb-'));
        _shops.removeWhere(_isDummyShop);
        await _storage.saveCollections(_collections);
        await _storage.savePendingBills(_pendingBills);
        await _storage.saveShops(_shops);
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

      // Forced wipe of legacy cached test collections, bills and orders
      final prefs = await SharedPreferences.getInstance();
      final forcedClean = prefs.getBool('forced_clean_transactions_v4') ?? false;
      if (!forcedClean) {
        _collections.clear();
        _pendingBills.clear();
        _salesOrders.clear();
        await _storage.saveCollections(_collections);
        await _storage.savePendingBills(_pendingBills);
        await _storage.saveSalesOrders(_salesOrders);
        await prefs.setBool('forced_clean_transactions_v4', true);
      }
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

    // Instant UI load from local cache
    _isLoading = false;
    notifyListeners();

    // 2. Initialize Firebase in background if configured (non-blocking)
    () async {
      try {
        await _firebase.init();
        if (_firebase.isInitialized) {
          final cloudCollections = await _firebase.fetchCollections();
          // Always synchronize local with cloud.
          // If cloud collections are empty (e.g. wiped), ensure local is also empty!
          _collections = cloudCollections;
          await _storage.saveCollections(_collections);
          final cloudShops = await _firebase.fetchShops();
          if (cloudShops.isNotEmpty) {
            final cleanCloudShops = <ShopModel>[];
            for (final s in cloudShops) {
              if (_isDummyShop(s)) {
                await _firebase.deleteShop(s.id);
              } else {
                cleanCloudShops.add(s);
              }
            }
            _shops = _deduplicateShops(cleanCloudShops);
            await _storage.saveShops(_shops);
          } else {
            for (final s in _shops) {
              if (!_isDummyShop(s)) {
                await _firebase.saveShop(s);
              }
            }
          }
          final cloudRoutes = await _firebase.fetchRoutes();
          if (cloudRoutes.isNotEmpty) {
            _routes = cloudRoutes;
            await _storage.saveRoutes(_routes);
          } else {
            for (final r in _routes) {
              await _firebase.saveRoute(r);
            }
          }

          // Synchronize Pending Bills across all devices & logins safely
          final cloudBills = await _firebase.fetchPendingBills();
          final billMap = <String, PendingBillModel>{};
          for (final b in cloudBills) {
            billMap[b.id] = b;
          }
          // Merge local bills so newly added bills on this device are NEVER overwritten/lost
          for (final b in _pendingBills) {
            if (!billMap.containsKey(b.id)) {
              billMap[b.id] = b;
              if (_firebase.isInitialized) {
                _firebase.savePendingBill(b);
              }
            }
          }
          _pendingBills = billMap.values.toList();
          _pendingBills.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          await _storage.savePendingBills(_pendingBills);

          // Auto-clean: ensure any already paid/settled bills auto-delete heavy photos to save cloud storage
          bool hasPurgedCloud = false;
          for (int i = 0; i < _pendingBills.length; i++) {
            if (_pendingBills[i].isPaid && _pendingBills[i].photoBase64 != null) {
              _pendingBills[i] = _pendingBills[i].copyWith(clearPhoto: true);
              hasPurgedCloud = true;
              if (_firebase.isInitialized) {
                _firebase.savePendingBill(_pendingBills[i]);
              }
            }
          }
          if (hasPurgedCloud) {
            await _storage.savePendingBills(_pendingBills);
          }

          // Check and perform auto-backup if 4 days have passed
          final authService = AuthService();
          final users = await authService.loadUsers();
          _lastBackupTime = await _backupService.getLatestBackupTimeShared();
          await _backupService.checkAndRunAutoBackup(
            routes: _routes,
            shops: _shops,
            collections: _collections,
            pendingBills: _pendingBills,
            users: users,
          );
          _lastBackupTime = await _backupService.getLatestBackupTimeShared();

          notifyListeners();
        }
      } catch (e) {
        debugPrint('Firebase load error: $e');
      }
    }();
  }

  bool _isDummyShop(ShopModel s) {
    if (s.id.startsWith('shop-') || s.id.startsWith('sample-')) return true;
    const dummyNames = {
      'ata kirana',
      'shree ganesh traders',
      'mahesh provision store',
      'sai krupa supermarket',
      'om traders',
    };
    return dummyNames.contains(s.name.trim().toLowerCase());
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

  Future<bool> syncAllToCloud() async {
    try {
      if (!_firebase.isInitialized) {
        await _firebase.init();
      }
      for (final r in _routes) {
        await _firebase.saveRoute(r);
      }
      for (final s in _shops) {
        await _firebase.saveShop(s);
      }
      for (final c in _collections) {
        await _firebase.saveCollection(c);
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Sync all error: $e');
      return false;
    }
  }

  Future<bool> connectFirebase(FirebaseConfig config) async {
    final success = await _firebase.connectWithConfig(config);
    if (success) {
      for (final r in _routes) {
        await _firebase.saveRoute(r);
      }
      for (final s in _shops) {
        await _firebase.saveShop(s);
      }
      for (final c in _collections) {
        await _firebase.saveCollection(c);
      }
    }
    notifyListeners();
    return success;
  }

  Future<void> disconnectFirebase() async {
    await _firebase.disconnect();
    notifyListeners();
  }

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
  List<CollectionModel> getFilteredCollections({DateTime? forDate}) {
    final date = forDate ?? _selectedDate;
    return _collections.where((c) {
      // Date filter (matches day, month, year)
      final sameDay = c.collectedAt.year == date.year &&
          c.collectedAt.month == date.month &&
          c.collectedAt.day == date.day;
      if (!sameDay) return false;

      // Business filter
      if (_filterBusiness != null && _filterBusiness!.isNotEmpty && _filterBusiness != 'All') {
        if (c.businessName != _filterBusiness) return false;
      }

      // Route filter
      if (_filterRouteId != null && _filterRouteId!.isNotEmpty && _filterRouteId != 'All') {
        if (c.routeId != _filterRouteId) return false;
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
  }

  // --- Bill Aggregation & Status Tracking (Pending vs Paid) ---
  List<BillSummary> getAllBillSummaries({String? forShopId, String? forBusiness}) {
    final Map<String, List<CollectionModel>> grouped = {};

    for (final c in _collections) {
      if (forShopId != null && c.shopId != forShopId) continue;
      if (forBusiness != null && forBusiness != 'All' && c.businessName != forBusiness) continue;

      final key = '${c.shopId}_${c.billNumber.trim().toLowerCase()}';
      grouped.putIfAbsent(key, () => []).add(c);
    }

    final List<BillSummary> list = [];
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
          : (_shops.any((s) => s.id == first.shopId)
              ? _shops.firstWhere((s) => s.id == first.shopId).routeId
              : '');

      list.add(BillSummary(
        billNumber: first.billNumber,
        shopId: first.shopId,
        shopName: first.shopName,
        routeId: effectiveRouteId,
        routeName: first.routeName.isNotEmpty ? first.routeName : getRouteName(effectiveRouteId),
        businessName: first.businessName,
        billTotal: maxBill,
        totalCollected: totalCollected,
        collections: collList,
        lastPaymentDate: first.collectedAt,
      ));
    });

    // Also include any standalone pending bills from _pendingBills that haven't had collections yet
    final Set<String> processedKeys = Set<String>.from(grouped.keys);
    for (final pb in _pendingBills) {
      if (forShopId != null && pb.shopId != forShopId) continue;
      if (forBusiness != null && forBusiness != 'All' && pb.businessName != forBusiness) continue;

      final key = '${pb.shopId}_${pb.billNumber.trim().toLowerCase()}';
      if (!processedKeys.contains(key)) {
        final effectiveRouteId = (pb.routeId.isNotEmpty)
            ? pb.routeId
            : (_shops.any((s) => s.id == pb.shopId)
                ? _shops.firstWhere((s) => s.id == pb.shopId).routeId
                : '');

        list.add(BillSummary(
          billNumber: pb.billNumber,
          shopId: pb.shopId,
          shopName: pb.shopName,
          routeId: effectiveRouteId,
          routeName: pb.routeName.isNotEmpty ? pb.routeName : getRouteName(effectiveRouteId),
          businessName: pb.businessName,
          billTotal: pb.totalAmount,
          totalCollected: pb.collectedAmount,
          collections: const [],
          lastPaymentDate: pb.invoiceDate,
        ));
        processedKeys.add(key);
      }
    }

    list.sort((a, b) => b.lastPaymentDate.compareTo(a.lastPaymentDate));
    return list;
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
    try {
      final key = billNumber.trim().toLowerCase();
      final list = getAllBillSummaries(forShopId: shopId);
      return list.firstWhere((b) => b.billNumber.trim().toLowerCase() == key);
    } catch (_) {
      return null;
    }
  }

  // --- Breakdown Calculations for Selected Date & Filters ---
  double get totalCollection {
    return getFilteredCollections().fold(0.0, (sum, c) => sum + c.collectedAmount);
  }

  double get totalBillAmount {
    return getFilteredCollections().fold(0.0, (sum, c) => sum + c.billAmount);
  }

  double get totalBalanceDue {
    return getFilteredCollections().fold(0.0, (sum, c) => sum + c.balanceAmount);
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
    return getFilteredCollections().length;
  }

  int get partialBillsCount {
    return getFilteredCollections().where((c) => c.isPartial).length;
  }

  int get uniqueShopsCount {
    final list = getFilteredCollections();
    final ids = list.map((c) => c.shopId).toSet();
    return ids.length;
  }

  // --- Per-Business Performance & Collection Metrics ---
  double getTotalCollectionForBusiness(String business, {DateTime? forDate}) {
    final date = forDate ?? _selectedDate;
    return _collections.where((c) {
      final sameDay = c.collectedAt.year == date.year &&
          c.collectedAt.month == date.month &&
          c.collectedAt.day == date.day;
      return sameDay && c.businessName == business;
    }).fold(0.0, (s, c) => s + c.collectedAmount);
  }

  int getBillsCountForBusiness(String business, {DateTime? forDate}) {
    final date = forDate ?? _selectedDate;
    return _collections.where((c) {
      final sameDay = c.collectedAt.year == date.year &&
          c.collectedAt.month == date.month &&
          c.collectedAt.day == date.day;
      return sameDay && c.businessName == business;
    }).length;
  }

  double getPendingBalanceForBusiness(String business) {
    return getPendingBills(forBusiness: business).fold(0.0, (s, b) => s + b.balanceDue);
  }

  double getCashForBusiness(String business, {DateTime? forDate}) {
    final date = forDate ?? _selectedDate;
    return _collections.where((c) {
      final sameDay = c.collectedAt.year == date.year &&
          c.collectedAt.month == date.month &&
          c.collectedAt.day == date.day;
      return sameDay && c.businessName == business && c.paymentMode == PaymentMode.cash;
    }).fold(0.0, (s, c) => s + c.collectedAmount);
  }

  double getDigitalForBusiness(String business, {DateTime? forDate}) {
    final date = forDate ?? _selectedDate;
    return _collections.where((c) {
      final sameDay = c.collectedAt.year == date.year &&
          c.collectedAt.month == date.month &&
          c.collectedAt.day == date.day;
      return sameDay && c.businessName == business && c.paymentMode != PaymentMode.cash;
    }).fold(0.0, (s, c) => s + c.collectedAmount);
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
    await _storage.saveRoutes(_routes);
    notifyListeners();
    if (_firebase.isInitialized) {
      _firebase.saveRoute(newRoute);
    }
    return newRoute;
  }

  Future<RouteModel> updateRoute(RouteModel updatedRoute) async {
    final idx = _routes.indexWhere((r) => r.id == updatedRoute.id);
    if (idx != -1) {
      _routes[idx] = updatedRoute;
      // Also update routeName for any shops assigned to this route
      for (int i = 0; i < _shops.length; i++) {
        if (_shops[i].routeId == updatedRoute.id) {
          _shops[i] = _shops[i].copyWith(routeName: updatedRoute.name);
          if (_firebase.isInitialized) {
            _firebase.saveShop(_shops[i]);
          }
        }
      }
      _routes.sort((a, b) => a.priority.compareTo(b.priority));
      await _storage.saveRoutes(_routes);
      await _storage.saveShops(_shops);
      notifyListeners();
      if (_firebase.isInitialized) {
        _firebase.saveRoute(updatedRoute);
      }
    }
    return updatedRoute;
  }

  Future<void> updateRoutePriority(String routeId, int newPriority) async {
    final idx = _routes.indexWhere((r) => r.id == routeId);
    if (idx != -1) {
      _routes[idx] = _routes[idx].copyWith(priority: newPriority);
      _routes.sort((a, b) => a.priority.compareTo(b.priority));
      for (int i = 0; i < _routes.length; i++) {
        _routes[i] = _routes[i].copyWith(priority: i + 1);
        if (_firebase.isInitialized) {
          _firebase.saveRoute(_routes[i]);
        }
      }
      await _storage.saveRoutes(_routes);
      notifyListeners();
    }
  }

  Future<void> setRouteOrder(List<String> orderedRouteIds) async {
    for (int i = 0; i < orderedRouteIds.length; i++) {
      final id = orderedRouteIds[i];
      final idx = _routes.indexWhere((r) => r.id == id);
      if (idx != -1) {
        _routes[idx] = _routes[idx].copyWith(priority: i + 1);
        if (_firebase.isInitialized) {
          _firebase.saveRoute(_routes[idx]);
        }
      }
    }
    _routes.sort((a, b) => a.priority.compareTo(b.priority));
    await _storage.saveRoutes(_routes);
    notifyListeners();
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
      if (_firebase.isInitialized) {
        _firebase.saveRoute(_routes[i]);
      }
    }
    await _storage.saveRoutes(_routes);
    notifyListeners();
  }

  Future<void> deleteRoute(String routeId) async {
    _routes.removeWhere((r) => r.id == routeId);
    await _storage.saveRoutes(_routes);
    notifyListeners();
    if (_firebase.isInitialized) {
      _firebase.deleteRoute(routeId);
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
    await _storage.saveShops(_shops);
    notifyListeners();
    if (_firebase.isInitialized) {
      _firebase.saveShop(newShop);
    }
    return newShop;
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
      notifyListeners();
      if (_firebase.isInitialized) {
        _firebase.saveShop(updated);
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
      notifyListeners();
      if (_firebase.isInitialized) {
        _firebase.saveShop(updated);
      }
      return updated;
    }
    return null;
  }

  Future<ShopModel> updateShop(ShopModel updatedShop) async {
    final idx = _shops.indexWhere((s) => s.id == updatedShop.id);
    if (idx != -1) {
      _shops[idx] = updatedShop;
      // Also update shopName in collections for this shop
      for (int i = 0; i < _collections.length; i++) {
        if (_collections[i].shopId == updatedShop.id) {
          _collections[i] = _collections[i].copyWith(
            shopName: updatedShop.name,
            routeId: updatedShop.routeId,
            routeName: updatedShop.routeName,
          );
        }
      }
      await _storage.saveShops(_shops);
      try {
        await _storage.saveCollections(_collections);
      } catch (_) {}
      notifyListeners();
      if (_firebase.isInitialized) {
        _firebase.saveShop(updatedShop);
      }
    }
    return updatedShop;
  }

  Future<void> deleteShop(String shopId) async {
    _shops.removeWhere((s) => s.id == shopId);
    await _storage.saveShops(_shops);
    notifyListeners();
    if (_firebase.isInitialized) {
      _firebase.deleteShop(shopId);
    }
  }

  List<ShopModel> getShopsForRoute(String routeId) {
    return _shops.where((s) => s.routeId == routeId).toList();
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
    final isSettled = (collection.balanceRemaining ?? 0.0) <= 0.001;
    final finalCollection = isSettled && collection.photoBase64 != null
        ? collection.copyWith(clearPhoto: true)
        : collection;

    _collections.insert(0, finalCollection);
    try {
      await _storage.saveCollections(_collections);
    } catch (e) {
      debugPrint('Storage save notice: $e');
    }
    notifyListeners();

    // Background Firebase Sync (instant write directly to Cloud Firestore)
    if (_firebase.isInitialized) {
      () async {
        try {
          await _firebase.saveCollection(finalCollection);
        } catch (e) {
          debugPrint('Firebase direct sync error: $e');
        }
      }();
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
    bool changed = false;

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
          changed = true;
          if (_firebase.isInitialized) {
            await _firebase.savePendingBill(updated);
          }
        }
      }
    }

    if (changed) {
      await _storage.savePendingBills(_pendingBills);
      notifyListeners();
    }
  }

  /// Removes photos from any existing collections for a settled bill to reclaim storage
  Future<void> _purgePhotoForSettledBill(String billNumber, String? shopId) async {
    final cleanBill = billNumber.trim().toLowerCase();
    final cleanShopId = shopId?.trim().toLowerCase();
    bool changed = false;

    for (int i = 0; i < _collections.length; i++) {
      final c = _collections[i];
      if (c.billNumber.trim().toLowerCase() == cleanBill) {
        if (cleanShopId == null || cleanShopId.isEmpty || c.shopId.trim().toLowerCase() == cleanShopId) {
          if (c.hasPhoto) {
            _collections[i] = c.copyWith(clearPhoto: true);
            changed = true;
            if (_firebase.isInitialized) {
              _firebase.saveCollection(_collections[i]);
            }
          }
        }
      }
    }

    if (changed) {
      await _storage.saveCollections(_collections);
      notifyListeners();
    }
  }

  Future<void> deleteCollection(String id) async {
    _collections.removeWhere((c) => c.id == id);
    await _storage.saveCollections(_collections);
    notifyListeners();
    if (_firebase.isInitialized) {
      _firebase.deleteCollection(id);
    }
  }

  List<CollectionModel> getCollectionsForShop(String shopId) {
    return _collections.where((c) => c.shopId == shopId).toList()
      ..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
  }

  double getTotalBalanceForShop(String shopId) {
    final pending = getPendingBills(forShopId: shopId);
    return pending.fold(0.0, (sum, b) => sum + b.balanceDue);
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
    _pendingBills.insert(0, bill);
    await _storage.savePendingBills(_pendingBills);
    if (_firebase.isInitialized) {
      await _firebase.savePendingBill(bill);
    }
    notifyListeners();
    return bill;
  }

  Future<void> updatePendingBill(PendingBillModel updatedBill) async {
    final idx = _pendingBills.indexWhere((b) => b.id == updatedBill.id);
    if (idx != -1) {
      _pendingBills[idx] = updatedBill;
      await _storage.savePendingBills(_pendingBills);
      if (_firebase.isInitialized) {
        await _firebase.savePendingBill(updatedBill);
      }
      notifyListeners();
    }
  }

  Future<void> deletePendingBill(String id) async {
    _pendingBills.removeWhere((b) => b.id == id);
    await _storage.savePendingBills(_pendingBills);
    if (_firebase.isInitialized) {
      await _firebase.deletePendingBill(id);
    }
    notifyListeners();
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
    final date = forDate ?? _selectedDate;
    return _collections.where((c) {
      final sameDay = c.collectedAt.year == date.year &&
          c.collectedAt.month == date.month &&
          c.collectedAt.day == date.day;
      if (!sameDay) return false;
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

    final totalBilled = list.fold(0.0, (s, c) => s + c.billAmount);
    final totalCollected = list.fold(0.0, (s, c) => s + c.collectedAmount);
    final totalBalance = list.fold(0.0, (s, c) => s + c.balanceAmount);

    final cashBills = list.where((c) => c.paymentMode == PaymentMode.cash).length;
    final upiBills = list.where((c) => c.paymentMode == PaymentMode.upi).length;
    final chequeBills = list.where((c) => c.paymentMode == PaymentMode.cheque).length;
    final netBills = list.where((c) => c.paymentMode == PaymentMode.netBanking).length;
    final partialCount = list.where((c) => c.isPartial).length;

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
Total Billed:      ${CurrencyFormatter.format(totalBilled)}
Total Collected:   ${CurrencyFormatter.format(totalCollected)}
Pending Balance:   ${CurrencyFormatter.format(totalBalance)}
Receipts Count:    ${list.length} ($partialCount pending/partial)
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

  // --- Sales Order Operations ---
  Future<void> addSalesOrder(SalesOrderModel order) async {
    _salesOrders.insert(0, order);
    await _storage.saveSalesOrders(_salesOrders);
    notifyListeners();
  }

  Future<void> deleteSalesOrder(String orderId) async {
    _salesOrders.removeWhere((o) => o.id == orderId);
    await _storage.saveSalesOrders(_salesOrders);
    notifyListeners();
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
    _customProducts.removeWhere((p) => p.id == product.id);
    _customProducts.add(product);
    OrderCatalogService.addCustomProduct(product);
    await _storage.saveCustomProducts(_customProducts);
    notifyListeners();
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
    final oldCollections = List<CollectionModel>.from(_collections);
    _collections.clear();
    _pendingBills.clear();
    _salesOrders.clear();
    await _storage.saveCollections(_collections);
    await _storage.savePendingBills(_pendingBills);
    await _storage.saveSalesOrders(_salesOrders);
    if (_firebase.isInitialized) {
      for (final c in oldCollections) {
        try {
          await _firebase.deleteCollection(c.id);
        } catch (_) {}
      }
      try {
        final cloudCols = await _firebase.fetchCollections();
        for (final c in cloudCols) {
          await _firebase.deleteCollection(c.id);
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  // Reset to initial sample data
  Future<void> resetToSample() async {
    await _storage.clearAll();
    await initialize();
  }
}
