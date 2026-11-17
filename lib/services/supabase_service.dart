import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/collection_model.dart';
import '../models/shop_model.dart';
import '../models/route_model.dart';
import '../models/pending_bill_model.dart';
import '../models/user_model.dart';
import '../models/location_timeline_entry.dart';
import '../models/attendance_record.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  static const String supabaseUrl = 'https://ytetqikoinacavzsxgop.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl0ZXRxaWtvaW5hY2F2enN4Z29wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE4NjIyMzksImV4cCI6MjEwNzQzODIzOX0.jTMxPpzD_llgfLgg1hH4zdJyADCD0BXxcuNwZdggpJU';

  bool _isInitialized = false;
  String? _lastError;

  bool get isInitialized => _isInitialized;
  String? get lastError => _lastError;

  SupabaseClient get client => Supabase.instance.client;

  Future<void> init() async {
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

  // --- Routes ---
  Future<List<RouteModel>> fetchRoutes() async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return [];

    try {
      final List<dynamic> data =
          await client.from('routes').select().order('priority', ascending: true);
      return data
          .map((row) => RouteModel.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error fetching routes from Supabase: $e');
      return [];
    }
  }

  Future<bool> saveRoute(RouteModel route) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return false;

    try {
      await client.from('routes').upsert(route.toJson());
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error saving route to Supabase: $e');
      return false;
    }
  }

  Future<bool> deleteRoute(String id) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return false;

    try {
      await client.from('routes').delete().eq('id', id);
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error deleting route from Supabase: $e');
      return false;
    }
  }

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
  Future<List<ShopModel>> fetchShops() async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return [];

    try {
      final List<dynamic> data =
          await client.from('shops').select().order('name', ascending: true);
      return data
          .map((row) => ShopModel.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error fetching shops from Supabase: $e');
      return [];
    }
  }

  Future<bool> saveShop(ShopModel shop) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return false;

    try {
      await client.from('shops').upsert(shop.toJson());
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error saving shop to Supabase: $e');
      return false;
    }
  }

  Future<bool> deleteShop(String id) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return false;

    try {
      await client.from('shops').delete().eq('id', id);
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error deleting shop from Supabase: $e');
      return false;
    }
  }

  Stream<List<ShopModel>>? streamShops() {
    if (!_isInitialized) return null;

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
  Future<List<PendingBillModel>> fetchPendingBills() async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return [];

    try {
      final List<dynamic> data =
          await client.from('pending_bills').select().order('createdAt', ascending: false);
      return data
          .map((row) => PendingBillModel.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error fetching pending bills from Supabase: $e');
      return [];
    }
  }

  Future<bool> savePendingBill(PendingBillModel bill) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return false;

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
    if (!_isInitialized) await init();
    if (!_isInitialized) return false;

    try {
      await client.from('pending_bills').delete().eq('id', id);
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error deleting pending bill from Supabase: $e');
      return false;
    }
  }

  Stream<List<PendingBillModel>>? streamPendingBills() {
    if (!_isInitialized) return null;

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
  Future<List<CollectionModel>> fetchCollections() async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return [];

    try {
      final List<dynamic> data =
          await client.from('collections').select().order('collectedAt', ascending: false);
      return data
          .map((row) => CollectionModel.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error fetching collections from Supabase: $e');
      return [];
    }
  }

  Future<bool> saveCollection(CollectionModel collection) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return false;

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
    if (!_isInitialized) return null;

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

  Future<bool> savePendingBillsBulk(List<PendingBillModel> bills) async {
    if (!_isInitialized) await init();
    if (!_isInitialized || bills.isEmpty) return false;

    try {
      await client.from('pending_bills').upsert(bills.map((b) => b.toJson()).toList());
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error bulk saving pending bills to Supabase: $e');
      return false;
    }
  }

  Future<bool> saveCollectionsBulk(List<CollectionModel> collections) async {
    if (!_isInitialized) await init();
    if (!_isInitialized || collections.isEmpty) return false;

    try {
      await client.from('collections').upsert(collections.map((c) => c.toJson()).toList());
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error bulk saving collections to Supabase: $e');
      return false;
    }
  }

  Future<bool> deleteCollection(String id) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) {
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

  Future<bool> clearAllBillsAndCollections() async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return false;

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

  // --- Users ---
  Future<List<UserModel>> fetchUsers() async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return [];

    try {
      final List<dynamic> data =
          await client.from('app_users').select().order('createdAt', ascending: true);
      return data
          .where((row) {
            final id = row['id'] as String? ?? '';
            return id != 'config_gemini_api' &&
                !id.startsWith('tl_') &&
                !id.startsWith('timeline_') &&
                !id.startsWith('att_') &&
                !id.startsWith('route_order_');
          })
          .map((row) => UserModel.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error fetching users from Supabase: $e');
      return [];
    }
  }

  // --- Gemini Cloud API Key Sync ---
  Future<void> syncGeminiApiKey(String apiKey) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return;
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
    if (!_isInitialized) await init();
    if (!_isInitialized) return null;
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
    if (!_isInitialized) await init();
    if (!_isInitialized) return false;

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
    if (!_isInitialized) await init();
    if (!_isInitialized) return false;

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
    if (!_isInitialized) await init();
    if (!_isInitialized) return false;

    try {
      await client.from('app_users').upsert(entry.toSupabaseUserRow());
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error saving location timeline entry to Supabase: $e');
      return false;
    }
  }

  Future<List<LocationTimelineEntry>> fetchLocationTimeline({
    DateTime? date,
    String? staffName,
  }) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return [];

    try {
      final List<dynamic> data = await client
          .from('app_users')
          .select()
          .like('id', 'tl_%')
          .order('createdAt', ascending: true);

      final entries = data
          .map((row) => LocationTimelineEntry.fromSupabaseUserRow(Map<String, dynamic>.from(row as Map)))
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
    if (!_isInitialized) await init();
    if (!_isInitialized) return [];

    try {
      final res = await client
          .from('app_users')
          .select('password')
          .eq('id', 'route_order_$routeId')
          .maybeSingle();

      if (res != null && res['password'] != null) {
        final pass = res['password'] as String;
        final decoded = jsonDecode(pass) as List<dynamic>;
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (e) {
      debugPrint('Error fetching route outlet order: $e');
    }
    return [];
  }

  Future<bool> saveRouteOutletOrder(String routeId, List<String> shopIds) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return false;

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
}
