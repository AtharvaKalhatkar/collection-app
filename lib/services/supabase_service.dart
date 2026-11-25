import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/collection_model.dart';
import '../models/shop_model.dart';
import '../models/route_model.dart';
import '../models/pending_bill_model.dart';
import '../models/user_model.dart';
import '../models/location_timeline_entry.dart';
import '../models/attendance_record.dart';
import '../models/order_model.dart';
import '../models/cash_handover_model.dart';
import '../models/vehicle_collection_model.dart';

class CloudFetchResult<T> {
  final bool success;
  final List<T> items;
  const CloudFetchResult({required this.success, required this.items});
}

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  @visibleForTesting
  SupabaseService.forTesting();

  static const String supabaseUrl = 'https://ytetqikoinacavzsxgop.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl0ZXRxaWtvaW5hY2F2enN4Z29wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE4NjIyMzksImV4cCI6MjEwNzQzODIzOX0.jTMxPpzD_llgfLgg1hH4zdJyADCD0BXxcuNwZdggpJU';

  @visibleForTesting
  static bool allowNetworkInTests = false;

  @visibleForTesting
  static bool? forceTestOffline;

  bool _isInitialized = false;
  String? _lastError;

  bool get isInitialized => _isInitialized && !_isTestEnvironment;
  bool get isTestMode => _isTestEnvironment;
  String? get lastError => _lastError;

  bool get _isTestEnvironment {
    if (forceTestOffline != null) return forceTestOffline!;
    if (allowNetworkInTests) return false;
    if (const bool.fromEnvironment('FLUTTER_TEST')) return true;
    try {
      return WidgetsBinding.instance.runtimeType
          .toString()
          .contains('TestWidgetsFlutterBinding');
    } catch (_) {
      return false;
    }
  }

  SupabaseClient get client => Supabase.instance.client;

  Future<void> init() async {
    if (_isTestEnvironment) {
      _isInitialized = false;
      return;
    }
    try {
      if (_isInitialized) return;
      try {
        final _ = Supabase.instance.client;
        _isInitialized = true;
        return;
      } catch (_) {}

      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabaseAnonKey,
      );
      _isInitialized = true;
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Supabase init notice: $e');
      try {
        final _ = Supabase.instance.client;
        _isInitialized = true;
        _lastError = null;
      } catch (_) {}
    }
  }

  Future<bool> _ensureReady() async {
    if (_isTestEnvironment) return false;
    if (!_isInitialized) await init();
    return _isInitialized;
  }

  Future<List<Map<String, dynamic>>> _fetchPaginated(
    String table, {
    String orderColumn = 'createdAt',
    bool ascending = true,
    PostgrestFilterBuilder<PostgrestList> Function(
            PostgrestFilterBuilder<PostgrestList> q)?
        filter,
    int pageSize = 1000,
  }) async {
    final allRows = <Map<String, dynamic>>[];
    int offset = 0;
    while (true) {
      var query = client.from(table).select();
      if (filter != null) {
        query = filter(query);
      }
      final List<dynamic> batch = await query
          .order(orderColumn, ascending: ascending)
          .range(offset, offset + pageSize - 1);
      for (final row in batch) {
        allRows.add(Map<String, dynamic>.from(row as Map));
      }
      if (batch.length < pageSize) break;
      offset += pageSize;
    }
    return allRows;
  }

  Future<bool> _upsertChunked(
    String table,
    List<Map<String, dynamic>> rows, {
    int chunkSize = 200,
    String errorLabel = 'records',
  }) async {
    if (rows.isEmpty) return true;
    if (!await _ensureReady()) return false;

    try {
      for (int i = 0; i < rows.length; i += chunkSize) {
        final end = (i + chunkSize < rows.length) ? i + chunkSize : rows.length;
        await client.from(table).upsert(rows.sublist(i, end));
      }
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error saving $errorLabel to Supabase: $e');
      return false;
    }
  }

  Future<bool> _deleteChunked(
    String table,
    List<String> ids, {
    String column = 'id',
    int chunkSize = 100,
    String errorLabel = 'records',
  }) async {
    if (ids.isEmpty) return true;
    if (!await _ensureReady()) return false;

    try {
      for (int i = 0; i < ids.length; i += chunkSize) {
        final end = (i + chunkSize < ids.length) ? i + chunkSize : ids.length;
        await client.from(table).delete().inFilter(column, ids.sublist(i, end));
      }
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error deleting $errorLabel from Supabase: $e');
      return false;
    }
  }

  // --- Routes ---
  Future<CloudFetchResult<RouteModel>> fetchRoutesWithStatus() async {
    if (!await _ensureReady()) {
      return const CloudFetchResult(success: false, items: []);
    }

    try {
      final data = await _fetchPaginated('routes', orderColumn: 'priority', ascending: true);
      final items = data.map((row) => RouteModel.fromJson(row)).toList();
      return CloudFetchResult(success: true, items: items);
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error fetching routes from Supabase: $e');
      return const CloudFetchResult(success: false, items: []);
    }
  }

  Future<List<RouteModel>> fetchRoutes() async =>
      (await fetchRoutesWithStatus()).items;

  Future<bool> saveRoute(RouteModel route) async {
    if (!await _ensureReady()) return false;

    try {
      await client.from('routes').upsert(route.toJson());
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error saving route to Supabase: $e');
      return false;
    }
  }

  Future<bool> saveRoutesBulk(List<RouteModel> routes) => _upsertChunked(
        'routes',
        routes.map((r) => r.toJson()).toList(),
        errorLabel: 'routes',
      );

  Future<bool> deleteRoute(String id) async {
    if (!await _ensureReady()) return false;

    try {
      await client.from('routes').delete().eq('id', id);
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error deleting route from Supabase: $e');
      return false;
    }
  }

  Future<bool> deleteRoutesBulk(List<String> ids) => _deleteChunked(
        'routes',
        ids,
        errorLabel: 'routes',
      );

  Stream<List<RouteModel>>? streamRoutes() {
    if (!_isInitialized) return null;

    try {
      return client
          .from('routes')
          .stream(primaryKey: ['id'])
          .order('priority', ascending: true)
          .map((rows) => rows
              .map((r) => RouteModel.fromJson(Map<String, dynamic>.from(r)))
              .toList());
    } catch (e) {
      debugPrint('Error streaming routes from Supabase: $e');
      return null;
    }
  }

  // --- Shops ---
  Future<CloudFetchResult<ShopModel>> fetchShopsWithStatus() async {
    if (!await _ensureReady()) {
      return const CloudFetchResult(success: false, items: []);
    }

    try {
      final data = await _fetchPaginated(
        'shops',
        orderColumn: 'name',
        ascending: true,
      );
      return CloudFetchResult(
        success: true,
        items: data.map((row) => ShopModel.fromJson(row)).toList(),
      );
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error fetching shops from Supabase: $e');
      return const CloudFetchResult(success: false, items: []);
    }
  }

  Future<List<ShopModel>> fetchShops() async =>
      (await fetchShopsWithStatus()).items;

  Future<bool> saveShop(ShopModel shop) async {
    if (!await _ensureReady()) return false;

    try {
      await client.from('shops').upsert(shop.toJson());
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error saving shop to Supabase: $e');
      return false;
    }
  }

  Future<bool> saveShopsBulk(List<ShopModel> shops) => _upsertChunked(
        'shops',
        shops.map((s) => s.toJson()).toList(),
        errorLabel: 'shops',
      );

  Future<bool> deleteShop(String id) async {
    if (!await _ensureReady()) return false;

    try {
      await client.from('shops').delete().eq('id', id);
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error deleting shop from Supabase: $e');
      return false;
    }
  }

  Future<bool> deleteShopsBulk(List<String> ids) => _deleteChunked(
        'shops',
        ids,
        errorLabel: 'shops',
      );

  Stream<List<ShopModel>>? streamShops() {
    if (!isInitialized) return null;

    try {
      return client
          .from('shops')
          .stream(primaryKey: ['id'])
          .order('name', ascending: true)
          .map((rows) => rows
              .map((r) => ShopModel.fromJson(Map<String, dynamic>.from(r)))
              .toList());
    } catch (e) {
      debugPrint('Error streaming shops from Supabase: $e');
      return null;
    }
  }

  // --- Pending Bills ---
  Future<CloudFetchResult<PendingBillModel>>
      fetchPendingBillsWithStatus() async {
    if (!await _ensureReady()) {
      return const CloudFetchResult(success: false, items: []);
    }

    try {
      final List<Map<String, dynamic>> data = await _fetchPaginated(
        'pending_bills',
        orderColumn: 'createdAt',
        ascending: false,
      );
      return CloudFetchResult(
        success: true,
        items: data.map((row) => PendingBillModel.fromJson(row)).toList(),
      );
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error fetching pending bills from Supabase: $e');
      return const CloudFetchResult(success: false, items: []);
    }
  }

  Future<List<PendingBillModel>> fetchPendingBills() async =>
      (await fetchPendingBillsWithStatus()).items;

  Future<bool> savePendingBill(PendingBillModel bill) async {
    if (!await _ensureReady()) return false;

    try {
      await client.from('pending_bills').upsert(bill.toJson());
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error saving pending bill to Supabase: $e');
      return false;
    }
  }

  Future<bool> deletePendingBill(String id) async {
    if (!await _ensureReady()) return false;

    try {
      await client.from('pending_bills').delete().eq('id', id);
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error deleting pending bill from Supabase: $e');
      return false;
    }
  }

  Future<bool> deletePendingBillsBulk(List<String> ids) => _deleteChunked(
        'pending_bills',
        ids,
        errorLabel: 'pending bills',
      );

  Stream<List<PendingBillModel>>? streamPendingBills() {
    if (!isInitialized) return null;

    try {
      return client
          .from('pending_bills')
          .stream(primaryKey: ['id'])
          .order('createdAt', ascending: false)
          .map((rows) => rows
              .map((r) => PendingBillModel.fromJson(Map<String, dynamic>.from(r)))
              .toList());
    } catch (e) {
      debugPrint('Error streaming pending bills from Supabase: $e');
      return null;
    }
  }

  // --- Collections ---
  Future<CloudFetchResult<CollectionModel>> fetchCollectionsWithStatus() async {
    if (!await _ensureReady()) {
      return const CloudFetchResult(success: false, items: []);
    }

    try {
      final List<Map<String, dynamic>> data = await _fetchPaginated(
        'collections',
        orderColumn: 'collectedAt',
        ascending: false,
      );
      return CloudFetchResult(
        success: true,
        items: data.map((row) => CollectionModel.fromJson(row)).toList(),
      );
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error fetching collections from Supabase: $e');
      return const CloudFetchResult(success: false, items: []);
    }
  }

  Future<List<CollectionModel>> fetchCollections() async =>
      (await fetchCollectionsWithStatus()).items;

  Future<bool> saveCollection(CollectionModel collection) async {
    if (!await _ensureReady()) return false;

    try {
      await client.from('collections').upsert(collection.toJson());
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error saving collection to Supabase: $e');
      return false;
    }
  }

  Stream<List<CollectionModel>>? streamCollections() {
    if (!isInitialized) return null;

    try {
      return client
          .from('collections')
          .stream(primaryKey: ['id'])
          .order('collectedAt', ascending: false)
          .map((rows) => rows
              .map((r) => CollectionModel.fromJson(Map<String, dynamic>.from(r)))
              .toList());
    } catch (e) {
      debugPrint('Error streaming collections from Supabase: $e');
      return null;
    }
  }

  Future<bool> savePendingBillsBulk(List<PendingBillModel> bills) => _upsertChunked(
        'pending_bills',
        bills.map((b) => b.toJson()).toList(),
        errorLabel: 'pending bills',
      );

  Future<bool> saveCollectionsBulk(List<CollectionModel> collections) =>
      _upsertChunked(
        'collections',
        collections.map((c) => c.toJson()).toList(),
        errorLabel: 'collections',
      );

  Future<bool> deleteCollection(String id) async {
    if (!await _ensureReady()) {
      debugPrint('Supabase not initialized for deleting collection $id');
      return false;
    }

    try {
      final cleanId = id.trim();
      final res = await client.from('collections').delete().eq('id', cleanId).select();
      debugPrint('Supabase deleteCollection successfully removed: $res');
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error deleting collection from Supabase: $e');
      return false;
    }
  }

  Future<bool> deleteCollectionsBulk(List<String> ids) => _deleteChunked(
        'collections',
        ids.map((id) => id.trim()).toList(),
        errorLabel: 'collections',
      );

  Future<bool> clearAllBillsAndCollections() async {
    if (!await _ensureReady()) return false;

    try {
      await client.from('collections').delete().neq('id', '00000000-0000-0000-0000-000000000000');
      await client.from('pending_bills').delete().neq('id', '00000000-0000-0000-0000-000000000000');
      debugPrint('Successfully wiped all collections and pending bills from Supabase');
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error clearing all bills and collections: $e');
      return false;
    }
  }

  bool _isStaffUserRow(Map<String, dynamic> row) {
    final id = row['id'] as String? ?? '';
    final role = (row['role'] as String? ?? '').toLowerCase();
    return id.isNotEmpty &&
        id != 'config_gemini_api' &&
        !id.startsWith('config_') &&
        !id.startsWith('tl_') &&
        !id.startsWith('timeline_') &&
        !id.startsWith('att_') &&
        !id.startsWith('route_order_') &&
        !id.startsWith('so_') &&
        !id.startsWith('cp_') &&
        !id.startsWith('ch_') &&
        !id.startsWith('vc_') &&
        !id.startsWith('cfg_') &&
        role != 'sales_order' &&
        role != 'custom_product' &&
        role != 'route_order' &&
        role != 'cash_handover' &&
        role != 'vehicle_collection' &&
        role != 'app_config' &&
        role != 'advance';
  }

  // --- Users ---
  Future<CloudFetchResult<UserModel>> fetchUsersWithStatus() async {
    if (!await _ensureReady()) {
      return const CloudFetchResult(success: false, items: []);
    }

    try {
      final List<Map<String, dynamic>> data = await _fetchPaginated(
        'app_users',
        orderColumn: 'createdAt',
        ascending: true,
        filter: (q) => q
            .not('id', 'like', 'tl_%')
            .not('id', 'like', 'so_%')
            .not('id', 'like', 'cp_%')
            .not('id', 'like', 'att_%')
            .not('id', 'like', 'route_order_%')
            .not('id', 'like', 'ch_%')
            .not('id', 'like', 'vc_%')
            .not('id', 'like', 'cfg_%')
            .neq('id', 'config_gemini_api'),
      );
      final items = data
          .where(_isStaffUserRow)
          .map((row) => UserModel.fromJson(row))
          .toList();
      return CloudFetchResult(success: true, items: items);
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error fetching users from Supabase: $e');
      return const CloudFetchResult(success: false, items: []);
    }
  }

  Future<List<UserModel>> fetchUsers() async =>
      (await fetchUsersWithStatus()).items;

  Future<UserModel?> fetchUserById(String userId) async {
    if (!await _ensureReady()) return null;
    try {
      final row = await client
          .from('app_users')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (row == null) return null;
      final map = Map<String, dynamic>.from(row);
      if (!_isStaffUserRow(map)) return null;
      return UserModel.fromJson(map);
    } catch (e) {
      debugPrint('Error fetching user $userId from Supabase: $e');
      return null;
    }
  }

  // --- Gemini Cloud API Key Sync ---
  Future<void> syncGeminiApiKey(String apiKey) async {
    if (!await _ensureReady()) return;
    try {
      await client.from('app_users').upsert({
        'id': 'config_gemini_api',
        'phone': 'config_gemini',
        'name': 'Cloud Gemini Key',
        'role': 'office',
        'password': apiKey.trim(),
        'isActive': true,
      });
      debugPrint('Successfully synced Gemini API key to Supabase');
    } catch (e) {
      debugPrint('Error syncing Gemini API key to Supabase: $e');
    }
  }

  Future<String?> fetchGeminiApiKey() async {
    if (!await _ensureReady()) return null;
    try {
      final res = await client
          .from('app_users')
          .select('password')
          .eq('id', 'config_gemini_api')
          .maybeSingle();
      if (res != null && res['password'] != null) {
        final key = (res['password'] as String).trim();
        if (key.isNotEmpty) return key;
      }
    } catch (e) {
      debugPrint('Error fetching Gemini API key from Supabase: $e');
    }
    return null;
  }

  Future<bool> saveUser(UserModel user) async {
    if (!await _ensureReady()) return false;

    try {
      await client.from('app_users').upsert(user.toJson());
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error saving user to Supabase: $e');
      return false;
    }
  }

  Future<bool> deleteUser(String id) async {
    if (!await _ensureReady()) return false;

    try {
      await client.from('app_users').delete().eq('id', id);
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error deleting user from Supabase: $e');
      return false;
    }
  }

  // --- Location Timeline Breadcrumbs & Live Tracking ---
  Future<bool> saveLocationTimelineEntry(LocationTimelineEntry entry) async {
    if (!await _ensureReady()) return false;

    try {
      await client.from('app_users').upsert(entry.toSupabaseUserRow());
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error saving location timeline entry to Supabase: $e');
      return false;
    }
  }

  Future<bool> saveLocationTimelineEntriesBulk(
          List<LocationTimelineEntry> entries) =>
      _upsertChunked(
        'app_users',
        entries.map((e) => e.toSupabaseUserRow()).toList(),
        errorLabel: 'location timeline',
      );

  Future<List<LocationTimelineEntry>> fetchLocationTimeline({
    DateTime? date,
    String? staffName,
  }) async {
    if (!await _ensureReady()) return [];

    try {
      final data = await _fetchPaginated(
        'app_users',
        orderColumn: 'createdAt',
        ascending: true,
        filter: (q) => q.like('id', 'tl_%'),
      );

      final entries = data
          .map((row) => LocationTimelineEntry.fromSupabaseUserRow(row))
          .whereType<LocationTimelineEntry>()
          .toList();

      return entries.where((e) {
        if (date != null) {
          final isSameDay = e.timestamp.year == date.year &&
              e.timestamp.month == date.month &&
              e.timestamp.day == date.day;
          if (!isSameDay) return false;
        }
        if (staffName != null &&
            staffName.isNotEmpty &&
            staffName.toLowerCase() != 'all' &&
            staffName.toLowerCase() != 'all staff') {
          final s = staffName.toLowerCase();
          final matchesStaff = e.staffName.toLowerCase() == s ||
              e.userId.toLowerCase() == s ||
              e.staffName.toLowerCase().contains(s) ||
              s.contains(e.staffName.toLowerCase());
          if (!matchesStaff) return false;
        }
        return true;
      }).toList();
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error fetching location timeline from Supabase: $e');
      return [];
    }
  }

  // --- Attendance Employees Cloud Sync ---
  Future<List<AttendanceEmployee>> fetchAttendanceEmployees() async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return [];

    try {
      final List<dynamic> data = await client
          .from('app_users')
          .select()
          .like('id', 'att_emp_%')
          .order('createdAt', ascending: true);

      final list = <AttendanceEmployee>[];
      for (final row in data) {
        try {
          final pass = row['password'] as String? ?? '';
          if (pass.startsWith('{') && pass.endsWith('}')) {
            final json = jsonDecode(pass) as Map<String, dynamic>;
            list.add(AttendanceEmployee.fromJson(json));
          } else {
            list.add(AttendanceEmployee(
              id: (row['id'] as String).replaceFirst('att_emp_', ''),
              name: row['name'] as String? ?? '',
              role: row['role'] as String? ?? 'Sales & Collection',
              phone: row['phone'] as String? ?? '',
              isActive: row['isActive'] as bool? ?? true,
            ));
          }
        } catch (e) {
          debugPrint('Error parsing attendance employee row: $e');
        }
      }
      return list;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error fetching attendance employees from Supabase: $e');
      return [];
    }
  }

  Future<bool> saveAttendanceEmployee(AttendanceEmployee emp) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return false;

    try {
      await client.from('app_users').upsert({
        'id': 'att_emp_${emp.id}',
        'name': emp.name,
        'role': emp.role,
        'phone': emp.phone,
        'password': jsonEncode(emp.toJson()),
        'isActive': emp.isActive,
        'createdAt': emp.joinedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error saving attendance employee to Supabase: $e');
      return false;
    }
  }

  Future<bool> deleteAttendanceEmployee(String id) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return false;

    try {
      await client.from('app_users').delete().eq('id', 'att_emp_$id');
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error deleting attendance employee from Supabase: $e');
      return false;
    }
  }

  // --- Attendance Records Cloud Sync ---
  Future<List<AttendanceRecord>> fetchAttendanceRecords(int year, int month) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return [];

    try {
      final monthStr = '$year${month.toString().padLeft(2, '0')}';
      final List<dynamic> data = await client
          .from('app_users')
          .select()
          .like('id', 'att_rec_%$monthStr%');

      final list = <AttendanceRecord>[];
      for (final row in data) {
        try {
          final pass = row['password'] as String? ?? '';
          if (pass.startsWith('{') && pass.endsWith('}')) {
            final json = jsonDecode(pass) as Map<String, dynamic>;
            list.add(AttendanceRecord.fromJson(json));
          }
        } catch (_) {}
      }
      return list;
    } catch (e) {
      debugPrint('Error fetching attendance records: $e');
      return [];
    }
  }

  Future<bool> saveAttendanceRecord(AttendanceRecord record) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return false;

    try {
      await client.from('app_users').upsert({
        'id': 'att_rec_${record.id}',
        'name': record.staffName,
        'role': record.staffRole,
        'phone': record.userId,
        'password': jsonEncode(record.toJson()),
        'isActive': true,
        'createdAt': record.date.toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('Error saving attendance record to Supabase: $e');
      return false;
    }
  }

  // --- Attendance Monthly Adjustments / Advances Cloud Sync ---
  Future<List<SalaryMonthlyAdjustment>> fetchAttendanceAdjustments(int year, int month) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return [];

    try {
      final List<dynamic> data = await client
          .from('app_users')
          .select()
          .like('id', 'att_adj_${year}_${month}_%');

      final list = <SalaryMonthlyAdjustment>[];
      for (final row in data) {
        try {
          final pass = row['password'] as String? ?? '';
          if (pass.startsWith('{') && pass.endsWith('}')) {
            final json = jsonDecode(pass) as Map<String, dynamic>;
            list.add(SalaryMonthlyAdjustment.fromJson(json));
          }
        } catch (_) {}
      }
      return list;
    } catch (e) {
      debugPrint('Error fetching attendance adjustments: $e');
      return [];
    }
  }

  Future<bool> saveAttendanceAdjustment(SalaryMonthlyAdjustment adj) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return false;

    try {
      await client.from('app_users').upsert({
        'id': 'att_adj_${adj.year}_${adj.month}_${adj.employeeId}',
        'name': adj.employeeId,
        'role': 'advance',
        'phone': '${adj.year}-${adj.month}',
        'password': jsonEncode(adj.toJson()),
        'isActive': true,
        'createdAt': adj.disbursedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('Error saving attendance adjustment to Supabase: $e');
      return false;
    }
  }

  // --- Route Outlet Order Cloud Sync ---
  Future<List<String>> fetchRouteOutletOrder(String routeId) async {
    if (!await _ensureReady()) return [];

    try {
      final res = await client
          .from('app_users')
          .select('password')
          .eq('id', 'route_order_$routeId')
          .maybeSingle();

      if (res != null && res['password'] != null) {
        final pass = res['password'] as String;
        final decoded = jsonDecode(pass);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
        if (decoded is Map<String, dynamic> && decoded['shopIds'] is List) {
          return (decoded['shopIds'] as List).map((e) => e.toString()).toList();
        }
      }
    } catch (e) {
      debugPrint('Error fetching route outlet order: $e');
    }
    return [];
  }

  Future<CloudFetchResult<MapEntry<String, List<String>>>>
      fetchAllRouteOutletOrdersWithStatus() async {
    if (!await _ensureReady()) {
      return const CloudFetchResult(success: false, items: []);
    }

    try {
      final data = await _fetchPaginated(
        'app_users',
        orderColumn: 'createdAt',
        ascending: true,
        filter: (q) => q.like('id', 'route_order_%'),
      );
      final list = <MapEntry<String, List<String>>>[];
      for (final row in data) {
        try {
          final id = (row['id'] as String? ?? '');
          final routeId = id.startsWith('route_order_')
              ? id.substring('route_order_'.length)
              : (row['phone'] as String? ?? '');
          final pass = row['password'] as String? ?? '';
          if (routeId.isEmpty || pass.isEmpty) continue;
          final decoded = jsonDecode(pass);
          if (decoded is List) {
            list.add(MapEntry(routeId, decoded.map((e) => e.toString()).toList()));
          } else if (decoded is Map<String, dynamic> &&
              decoded['shopIds'] is List) {
            list.add(MapEntry(
              routeId,
              (decoded['shopIds'] as List).map((e) => e.toString()).toList(),
            ));
          }
        } catch (e) {
          debugPrint('Error parsing route outlet order row: $e');
        }
      }
      return CloudFetchResult(success: true, items: list);
    } catch (e) {
      debugPrint('Error fetching route outlet orders from Supabase: $e');
      return const CloudFetchResult(success: false, items: []);
    }
  }

  Future<bool> saveRouteOutletOrder(String routeId, List<String> shopIds) async {
    if (!await _ensureReady()) return false;

    try {
      await client.from('app_users').upsert({
        'id': 'route_order_$routeId',
        'name': 'Route Order $routeId',
        'role': 'route_order',
        'phone': routeId,
        'password': jsonEncode(shopIds),
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('Error saving route outlet order to Supabase: $e');
      return false;
    }
  }

  // --- Sales Orders Cloud Sync (Stored in app_users with prefix so_) ---
  Future<CloudFetchResult<SalesOrderModel>> fetchSalesOrdersWithStatus() async {
    if (!await _ensureReady()) {
      return const CloudFetchResult(success: false, items: []);
    }

    try {
      final data = await _fetchPaginated(
        'app_users',
        orderColumn: 'createdAt',
        ascending: false,
        filter: (q) => q.like('id', 'so_%'),
      );

      final list = <SalesOrderModel>[];
      for (final row in data) {
        try {
          final pass = row['password'] as String? ?? '';
          if (pass.startsWith('{') && pass.endsWith('}')) {
            final json = jsonDecode(pass) as Map<String, dynamic>;
            list.add(SalesOrderModel.fromJson(json));
          }
        } catch (e) {
          debugPrint('Error parsing sales order row: $e');
        }
      }
      return CloudFetchResult(success: true, items: list);
    } catch (e) {
      debugPrint('Error fetching sales orders from Supabase: $e');
      return const CloudFetchResult(success: false, items: []);
    }
  }

  Future<List<SalesOrderModel>> fetchSalesOrders() async =>
      (await fetchSalesOrdersWithStatus()).items;

  Map<String, dynamic> _salesOrderRow(SalesOrderModel order) => {
        'id': 'so_${order.id}',
        'name': order.shopName,
        'role': 'sales_order',
        'phone': order.salesmanName,
        'password': jsonEncode(order.toJson()),
        'isActive': true,
        'createdAt': order.orderDate.toIso8601String(),
      };

  Future<bool> saveSalesOrder(SalesOrderModel order) async {
    if (!await _ensureReady()) return false;

    try {
      await client.from('app_users').upsert(_salesOrderRow(order));
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error saving sales order to Supabase: $e');
      return false;
    }
  }

  Future<bool> saveSalesOrdersBulk(List<SalesOrderModel> orders) => _upsertChunked(
        'app_users',
        orders.map(_salesOrderRow).toList(),
        errorLabel: 'sales orders',
      );

  Future<bool> deleteSalesOrder(String orderId) async {
    if (!await _ensureReady()) return false;

    final cleanId = orderId.trim();
    if (cleanId.isEmpty) return true;
    try {
      await client
          .from('app_users')
          .delete()
          .inFilter('id', ['so_$cleanId', cleanId])
          .select('id');
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error deleting sales order from Supabase: $e');
      return false;
    }
  }

  Future<bool> deleteSalesOrdersBulk(List<String> orderIds) {
    final targetIds = <String>{
      for (final raw in orderIds)
        if (raw.trim().isNotEmpty) ...['so_${raw.trim()}', raw.trim()],
    }.toList();
    return _deleteChunked(
      'app_users',
      targetIds,
      errorLabel: 'sales orders',
    );
  }

  /// Cross-device tombstone list so deleted sales orders cannot be resurrected by
  /// another device or offline cache. Capped to recent 500 IDs.
  Future<CloudFetchResult<String>> fetchDeletedOrderTombstonesWithStatus() =>
      fetchStringListConfigWithStatus('cfg_deleted_orders');

  Future<bool> saveDeletedOrderTombstones(List<String> orderIds) {
    final bounded = orderIds.length > 500
        ? orderIds.sublist(orderIds.length - 500)
        : orderIds;
    return saveStringListConfig(
      'cfg_deleted_orders',
      'Deleted Sales Orders Tombstones',
      bounded,
    );
  }

  // --- Custom Products Master Cloud Sync (Stored in app_users with prefix cp_) ---
  Future<CloudFetchResult<CatalogProduct>> fetchCustomProductsWithStatus() async {
    if (!await _ensureReady()) {
      return const CloudFetchResult(success: false, items: []);
    }

    try {
      final data = await _fetchPaginated(
        'app_users',
        orderColumn: 'createdAt',
        ascending: true,
        filter: (q) => q.like('id', 'cp_%'),
      );

      final list = <CatalogProduct>[];
      for (final row in data) {
        try {
          final pass = row['password'] as String? ?? '';
          if (pass.startsWith('{') && pass.endsWith('}')) {
            final json = jsonDecode(pass) as Map<String, dynamic>;
            list.add(CatalogProduct.fromJson(json));
          }
        } catch (e) {
          debugPrint('Error parsing custom product row: $e');
        }
      }
      return CloudFetchResult(success: true, items: list);
    } catch (e) {
      debugPrint('Error fetching custom products from Supabase: $e');
      return const CloudFetchResult(success: false, items: []);
    }
  }

  Future<List<CatalogProduct>> fetchCustomProducts() async =>
      (await fetchCustomProductsWithStatus()).items;

  Map<String, dynamic> _customProductRow(CatalogProduct product) => {
        'id': 'cp_${product.id}',
        'name': product.name,
        'role': 'custom_product',
        'phone': product.company,
        'password': jsonEncode(product.toJson()),
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      };

  Future<bool> saveCustomProduct(CatalogProduct product) async {
    if (!await _ensureReady()) return false;

    try {
      await client.from('app_users').upsert(_customProductRow(product));
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error saving custom product to Supabase: $e');
      return false;
    }
  }

  Future<bool> saveCustomProductsBulk(List<CatalogProduct> products) =>
      _upsertChunked(
        'app_users',
        products.map(_customProductRow).toList(),
        errorLabel: 'custom products',
      );

  Future<bool> deleteCustomProduct(String productId) async {
    if (!await _ensureReady()) return false;

    try {
      await client.from('app_users').delete().eq('id', 'cp_$productId');
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error deleting custom product from Supabase: $e');
      return false;
    }
  }

  Future<bool> deleteCustomProductsBulk(List<String> productIds) =>
      _deleteChunked(
        'app_users',
        productIds.map((id) => 'cp_$id').toList(),
        errorLabel: 'custom products',
      );

  // --- Cash Handovers Cloud Sync (Stored in app_users with prefix ch_) ---
  Future<CloudFetchResult<CashHandoverModel>> fetchCashHandoversWithStatus() async {
    if (!await _ensureReady()) {
      return const CloudFetchResult(success: false, items: []);
    }

    try {
      final data = await _fetchPaginated(
        'app_users',
        orderColumn: 'createdAt',
        ascending: false,
        filter: (q) => q.like('id', 'ch_%'),
      );
      final list = <CashHandoverModel>[];
      for (final row in data) {
        try {
          final pass = row['password'] as String? ?? '';
          if (pass.startsWith('{') && pass.endsWith('}')) {
            list.add(CashHandoverModel.fromJson(jsonDecode(pass) as Map<String, dynamic>));
          }
        } catch (e) {
          debugPrint('Error parsing cash handover row: $e');
        }
      }
      return CloudFetchResult(success: true, items: list);
    } catch (e) {
      debugPrint('Error fetching cash handovers from Supabase: $e');
      return const CloudFetchResult(success: false, items: []);
    }
  }

  Map<String, dynamic> _cashHandoverRow(CashHandoverModel h) => {
        'id': 'ch_${h.id}',
        'name': '${h.businessName} | ${h.date.toIso8601String().substring(0, 10)}',
        'role': 'cash_handover',
        'phone': 'ch_${h.id}',
        'password': jsonEncode(h.toJson()),
        'isActive': true,
        'createdAt': h.createdAt.toIso8601String(),
      };

  Future<bool> saveCashHandover(CashHandoverModel h) async {
    if (!await _ensureReady()) return false;
    try {
      await client.from('app_users').upsert(_cashHandoverRow(h));
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error saving cash handover to Supabase: $e');
      return false;
    }
  }

  Future<bool> saveCashHandoversBulk(List<CashHandoverModel> list) => _upsertChunked(
        'app_users',
        list.map(_cashHandoverRow).toList(),
        errorLabel: 'cash handovers',
      );

  Future<bool> deleteCashHandover(String id) async {
    if (!await _ensureReady()) return false;
    try {
      await client.from('app_users').delete().eq('id', 'ch_$id');
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error deleting cash handover from Supabase: $e');
      return false;
    }
  }

  Future<bool> deleteCashHandoversBulk(List<String> ids) => _deleteChunked(
        'app_users',
        ids.map((id) => 'ch_$id').toList(),
        errorLabel: 'cash handovers',
      );

  // --- Vehicle Collections Cloud Sync (Stored in app_users with prefix vc_) ---
  Future<CloudFetchResult<VehicleCollectionModel>>
      fetchVehicleCollectionsWithStatus() async {
    if (!await _ensureReady()) {
      return const CloudFetchResult(success: false, items: []);
    }

    try {
      final data = await _fetchPaginated(
        'app_users',
        orderColumn: 'createdAt',
        ascending: false,
        filter: (q) => q.like('id', 'vc_%'),
      );
      final list = <VehicleCollectionModel>[];
      for (final row in data) {
        try {
          final pass = row['password'] as String? ?? '';
          if (pass.startsWith('{') && pass.endsWith('}')) {
            list.add(
                VehicleCollectionModel.fromJson(jsonDecode(pass) as Map<String, dynamic>));
          }
        } catch (e) {
          debugPrint('Error parsing vehicle collection row: $e');
        }
      }
      return CloudFetchResult(success: true, items: list);
    } catch (e) {
      debugPrint('Error fetching vehicle collections from Supabase: $e');
      return const CloudFetchResult(success: false, items: []);
    }
  }

  Map<String, dynamic> _vehicleCollectionRow(VehicleCollectionModel vc) => {
        'id': 'vc_${vc.id}',
        'name': '${vc.vehicleNo} | ${vc.employeeName}',
        'role': 'vehicle_collection',
        'phone': 'vc_${vc.id}',
        'password': jsonEncode(vc.toJson()),
        'isActive': true,
        'createdAt': vc.createdAt.toIso8601String(),
      };

  Future<bool> saveVehicleCollection(VehicleCollectionModel vc) async {
    if (!await _ensureReady()) return false;
    try {
      await client.from('app_users').upsert(_vehicleCollectionRow(vc));
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error saving vehicle collection to Supabase: $e');
      return false;
    }
  }

  Future<bool> saveVehicleCollectionsBulk(List<VehicleCollectionModel> list) =>
      _upsertChunked(
        'app_users',
        list.map(_vehicleCollectionRow).toList(),
        errorLabel: 'vehicle collections',
      );

  Future<bool> deleteVehicleCollection(String id) async {
    if (!await _ensureReady()) return false;
    try {
      await client.from('app_users').delete().eq('id', 'vc_$id');
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error deleting vehicle collection from Supabase: $e');
      return false;
    }
  }

  Future<bool> deleteVehicleCollectionsBulk(List<String> ids) => _deleteChunked(
        'app_users',
        ids.map((id) => 'vc_$id').toList(),
        errorLabel: 'vehicle collections',
      );

  // --- Shared App Fleet Config (Vehicles & Employees) Sync ---
  Future<CloudFetchResult<String>> fetchStringListConfigWithStatus(
      String configId) async {
    if (!await _ensureReady()) {
      return const CloudFetchResult(success: false, items: []);
    }
    try {
      final res = await client
          .from('app_users')
          .select('password')
          .eq('id', configId)
          .maybeSingle();
      if (res == null || res['password'] == null) {
        return const CloudFetchResult(success: true, items: []);
      }
      final pass = res['password'] as String;
      final decoded = jsonDecode(pass);
      if (decoded is List) {
        return CloudFetchResult(
          success: true,
          items: decoded.map((e) => e.toString()).toList(),
        );
      }
      if (decoded is Map<String, dynamic> && decoded['items'] is List) {
        return CloudFetchResult(
          success: true,
          items: (decoded['items'] as List).map((e) => e.toString()).toList(),
        );
      }
      return const CloudFetchResult(success: true, items: []);
    } catch (e) {
      debugPrint('Error fetching config $configId from Supabase: $e');
      return const CloudFetchResult(success: false, items: []);
    }
  }

  Future<bool> saveStringListConfig(
      String configId, String displayName, List<String> items) async {
    if (!await _ensureReady()) return false;
    try {
      await client.from('app_users').upsert({
        'id': configId,
        'name': displayName,
        'role': 'app_config',
        'phone': configId,
        'password': jsonEncode({
          'items': items,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        }),
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('Error saving config $configId to Supabase: $e');
      return false;
    }
  }

  Future<CloudFetchResult<String>> fetchManagedVehiclesWithStatus() =>
      fetchStringListConfigWithStatus('cfg_vehicles');

  Future<bool> saveManagedVehicles(List<String> vehicles) =>
      saveStringListConfig('cfg_vehicles', 'Managed Vehicles', vehicles);

  Future<CloudFetchResult<String>> fetchManagedEmployeesWithStatus() =>
      fetchStringListConfigWithStatus('cfg_employees');

  Future<bool> saveManagedEmployees(List<String> employees) =>
      saveStringListConfig('cfg_employees', 'Managed Employees', employees);
}
