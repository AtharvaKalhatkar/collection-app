import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/collection_model.dart';
import '../models/shop_model.dart';
import '../models/route_model.dart';
import '../models/pending_bill_model.dart';
import '../models/user_model.dart';

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
          .map((row) => UserModel.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Error fetching users from Supabase: $e');
      return [];
    }
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
}
