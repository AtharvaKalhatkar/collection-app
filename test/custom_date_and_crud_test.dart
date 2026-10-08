import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_collection_app/models/collection_model.dart';
import 'package:daily_collection_app/providers/collection_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Custom Bill Date vs Collection Date', () {
    test('Stores separate billDate and collectedAt accurately', () {
      final billDate = DateTime(2026, 9, 17);
      final collectionDate = DateTime(2026, 9, 20, 14, 30);

      final collection = CollectionModel(
        id: 'coll-1',
        businessName: 'Purva Enterprises',
        shopId: 'shop-1',
        shopName: 'ATA Kirana Store',
        routeId: 'route-1',
        routeName: 'Chakan Beat',
        billNumber: 'PE-9021',
        billAmount: 40000.0,
        collectedAmount: 25000.0,
        balanceRemaining: 15000.0,
        paymentMode: PaymentMode.cash,
        salesmanName: 'Akash Gite',
        billDate: billDate,
        collectedAt: collectionDate,
      );

      expect(collection.billDate, billDate);
      expect(collection.collectedAt, collectionDate);
      expect(collection.billDate.day, 17);
      expect(collection.collectedAt.day, 20);

      // JSON serialization & deserialization verification
      final json = collection.toJson();
      expect(json['billDate'], billDate.toIso8601String());
      expect(json['collectedAt'], collectionDate.toIso8601String());

      final restored = CollectionModel.fromJson(json);
      expect(restored.billDate, billDate);
      expect(restored.collectedAt, collectionDate);
    });

    test('CollectionModel defaults billDate to collectedAt when not provided', () {
      final now = DateTime(2026, 9, 20);
      final collection = CollectionModel(
        id: 'coll-2',
        businessName: 'Manas Sales',
        shopId: 'shop-2',
        shopName: 'Balaji Provisions',
        routeId: 'route-1',
        routeName: 'Chakan Beat',
        billNumber: 'MS-104',
        billAmount: 15000.0,
        collectedAmount: 15000.0,
        balanceRemaining: 0.0,
        paymentMode: PaymentMode.upi,
        salesmanName: 'Akash Gite',
        collectedAt: now,
      );

      expect(collection.billDate, now);
    });
  });

  group('Route & Store Edit & Delete Operations', () {
    test('Updating route cascades updated route name to existing shops', () async {
      final provider = CollectionProvider();
      await provider.initialize();

      final route = await provider.addRoute(name: 'Alandi Beat', description: 'Near Temple');
      final shop = await provider.addShop(
        name: 'Mahesh Traders',
        routeId: route.id,
        routeName: route.name,
        mobileNumber: '9876543210',
        address: 'Main Road',
      );

      expect(shop.routeName, 'Alandi Beat');

      // Update Route Name
      final updatedRoute = route.copyWith(name: 'Alandi - Markal Beat');
      await provider.updateRoute(updatedRoute);

      final updatedShop = provider.getShopById(shop.id);
      expect(updatedShop?.routeName, 'Alandi - Markal Beat');
    });

    test('Deleting route removes it from provider', () async {
      final provider = CollectionProvider();
      await provider.initialize();

      final route = await provider.addRoute(name: 'Temporary Beat');
      expect(provider.routes.any((r) => r.id == route.id), isTrue);

      await provider.deleteRoute(route.id);
      expect(provider.routes.any((r) => r.id == route.id), isFalse);
    });

    test('Updating shop cascades updated shop name to collections', () async {
      final provider = CollectionProvider();
      await provider.initialize();

      final shop = await provider.addShop(
        name: 'Om Supermarket',
        routeId: 'r-1',
        routeName: 'General Beat',
        mobileNumber: '9988776655',
        address: 'Chowk',
      );

      final coll = CollectionModel(
        id: 'c-100',
        businessName: 'Purva Enterprises',
        shopId: shop.id,
        shopName: shop.name,
        routeId: 'r-1',
        routeName: 'General Beat',
        billNumber: 'PE-555',
        billAmount: 5000,
        collectedAmount: 5000,
        balanceRemaining: 0,
        paymentMode: PaymentMode.cash,
        salesmanName: 'Akash Gite',
        collectedAt: DateTime.now(),
      );
      await provider.addCollection(coll);

      // Update shop name
      final updatedShop = shop.copyWith(name: 'Om Supermarket & General Store');
      await provider.updateShop(updatedShop);

      final updatedColl = provider.collections.firstWhere((c) => c.id == 'c-100');
      expect(updatedColl.shopName, 'Om Supermarket & General Store');
    });

    test('Deleting shop removes it from provider', () async {
      final provider = CollectionProvider();
      await provider.initialize();

      final shop = await provider.addShop(
        name: 'Temporary Store',
        routeId: 'r-1',
        routeName: 'General Beat',
        mobileNumber: '9000000000',
        address: 'Area',
      );
      expect(provider.shops.any((s) => s.id == shop.id), isTrue);

      await provider.deleteShop(shop.id);
      expect(provider.shops.any((s) => s.id == shop.id), isFalse);
    });

    test('Route priority ordering is strictly maintained everywhere', () async {
      final provider = CollectionProvider();
      await provider.initialize();

      // Ensure routes are returned in strict priority sequence
      final initialRoutes = provider.routes;
      for (int i = 0; i < initialRoutes.length - 1; i++) {
        expect(initialRoutes[i].priority <= initialRoutes[i + 1].priority, isTrue);
      }

      // Add 2 new routes
      final rA = await provider.addRoute(name: 'Route Alpha');
      final rB = await provider.addRoute(name: 'Route Beta');

      // Move Route Beta up
      await provider.moveRouteUp(rB.id);

      final current = provider.routes;
      final betaIndex = current.indexWhere((r) => r.id == rB.id);
      final alphaIndex = current.indexWhere((r) => r.id == rA.id);

      expect(betaIndex < alphaIndex, isTrue);
      expect(current[betaIndex].priority < current[alphaIndex].priority, isTrue);

      // Verify priorities are sequential 1..N
      for (int i = 0; i < current.length; i++) {
        expect(current[i].priority, i + 1);
      }
    });
  });
}
