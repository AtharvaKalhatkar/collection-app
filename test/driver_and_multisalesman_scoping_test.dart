import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_collection_app/models/user_model.dart';
import 'package:daily_collection_app/models/collection_model.dart';
import 'package:daily_collection_app/models/pending_bill_model.dart';
import 'package:daily_collection_app/models/shop_model.dart';
import 'package:daily_collection_app/models/route_model.dart';
import 'package:daily_collection_app/providers/collection_provider.dart';
import 'package:daily_collection_app/utils/firm_details.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  group('UserModel Driver & Route Encoding Tests', () {
    test('normalizes alphanumeric username like user1 without stripping letters', () {
      expect(UserModel.normalizePhone('user1'), 'user1');
      expect(UserModel.normalizePhone('USER1'), 'user1');
      expect(UserModel.normalizePhone('driver_1'), 'driver_1');
      // Standard mobile numbers
      expect(UserModel.normalizePhone('+91 99219 77636'), '9921977636');
      expect(UserModel.normalizePhone('08605131764'), '8605131764');
    });

    test('parses Driver role and route assignment correctly from json', () {
      final json = {
        'id': 'user_driver_user1',
        'phone': 'user1',
        'name': 'Driver (user1)',
        'role': 'driver',
        'password': 'pass123:::routes=route_pune,route_satara',
        'isActive': true,
      };

      final user = UserModel.fromJson(json);
      expect(user.isDriver, isTrue);
      expect(user.role, UserRole.driver);
      expect(user.actualPassword, 'pass123');
      expect(user.assignedRouteIds, ['route_pune', 'route_satara']);
    });

    test('serializes assignedRouteIds into password for database compatibility', () {
      final user = UserModel(
        id: 'user_driver_user1',
        phone: 'user1',
        name: 'Driver (user1)',
        role: UserRole.driver,
        password: 'pass123',
        assignedRouteIds: ['route_pune', 'route_mumbai'],
      );

      final json = user.toJson();
      expect(json['role'], 'driver');
      expect(json['phone'], 'user1');
      expect(json['password'], 'pass123:::routes=route_pune,route_mumbai');
      expect(user.actualPassword, 'pass123');
    });
  });

  group('Multi-Salesman Isolation & Scoping Tests', () {
    late CollectionProvider provider;
    final testDate = DateTime(2026, 10, 22, 10, 0);

    setUp(() async {
      provider = CollectionProvider();
      await provider.initialize();
      provider.setSelectedDate(testDate);
    });

    test('Akash and Atharva only see their own collections and totals', () async {
      final akashCollection = CollectionModel(
        id: 'c1',
        businessName: 'Purva Enterprises',
        shopId: 's1',
        shopName: 'Ganesh Kirana',
        routeId: 'r1',
        routeName: 'Pune Road',
        billNumber: '101',
        billAmount: 5000,
        collectedAmount: 5000,
        paymentMode: PaymentMode.cash,
        salesmanName: 'Akash',
        collectedAt: testDate,
      );

      final atharvaCollection = CollectionModel(
        id: 'c2',
        businessName: 'Purva Enterprises',
        shopId: 's2',
        shopName: 'Sai Super Market',
        routeId: 'r1',
        routeName: 'Pune Road',
        billNumber: '102',
        billAmount: 3000,
        collectedAmount: 3000,
        paymentMode: PaymentMode.upi,
        salesmanName: 'Atharva',
        collectedAt: testDate,
      );

      await provider.addCollection(akashCollection);
      await provider.addCollection(atharvaCollection);

      // 1. Akash logged in
      final akashUser = UserModel(
        id: 'user_sales_akash',
        phone: '9309862465',
        name: 'Akash',
        role: UserRole.salesman,
        password: 'pass123',
      );
      provider.setCurrentUser(akashUser);

      final akashFiltered = provider.getFilteredCollections();
      expect(akashFiltered.length, 1);
      expect(akashFiltered.first.salesmanName, 'Akash');
      expect(provider.totalCollection, 5000.0);
      expect(provider.totalCash, 5000.0);
      expect(provider.totalUpi, 0.0);

      // 2. Atharva logged in
      final atharvaUser = UserModel(
        id: 'user_sales_atharva',
        phone: '8390768833',
        name: 'Atharva',
        role: UserRole.salesman,
        password: 'pass123',
      );
      provider.setCurrentUser(atharvaUser);

      final atharvaFiltered = provider.getFilteredCollections();
      expect(atharvaFiltered.length, 1);
      expect(atharvaFiltered.first.salesmanName, 'Atharva');
      expect(provider.totalCollection, 3000.0);
      expect(provider.totalCash, 0.0);
      expect(provider.totalUpi, 3000.0);

      // 3. Super Admin logged in (sees grand total + can filter individual staff)
      final adminUser = UserModel(
        id: 'user_super_admin',
        phone: '9921977636',
        name: 'Super Admin',
        role: UserRole.superAdmin,
        password: 'pass123',
      );
      provider.setCurrentUser(adminUser);
      provider.setSelectedStaffFilter(null); // All

      expect(provider.getFilteredCollections().length, 2);
      expect(provider.totalCollection, 8000.0);

      // Super admin filters by Akash
      provider.setSelectedStaffFilter('Akash');
      expect(provider.getFilteredCollections().length, 1);
      expect(provider.totalCollection, 5000.0);

      // Staff breakdown summaries
      final akashSummary = provider.getStaffSummary('Akash');
      expect(akashSummary.totalAmount, 5000.0);
      expect(akashSummary.cashAmount, 5000.0);

      final atharvaSummary = provider.getStaffSummary('Atharva');
      expect(atharvaSummary.totalAmount, 3000.0);
      expect(atharvaSummary.upiAmount, 3000.0);
    });
  });

  group('Driver Route Scoping Tests', () {
    late CollectionProvider provider;

    setUp(() async {
      provider = CollectionProvider();
      await provider.initialize();
    });

    test('driver is restricted only to pending bills and outlets of assigned routes', () async {
      // Create test routes
      final r1 = await provider.addRoute(name: 'Route 1 - Pune');
      final r2 = await provider.addRoute(name: 'Route 2 - Satara');

      // Create test shops
      final s1 = await provider.addShop(
        name: 'Shop on Route 1',
        routeId: r1.id,
        routeName: r1.name,
        mobileNumber: '9822000001',
        address: 'Pune Highway',
      );
      final s2 = await provider.addShop(
        name: 'Shop on Route 2',
        routeId: r2.id,
        routeName: r2.name,
        mobileNumber: '9822000002',
        address: 'Satara Bypass',
      );

      // Add pending bills
      final b1 = PendingBillModel(
        id: 'bill_r1',
        businessName: 'Purva Enterprises',
        shopId: s1.id,
        shopName: s1.name,
        routeId: r1.id,
        routeName: r1.name,
        billNumber: 'B-101',
        totalAmount: 4000,
        collectedAmount: 0,
        status: 'pending',
        invoiceDate: DateTime.now(),
        deliveryDate: DateTime.now(),
        createdAt: DateTime.now(),
      );
      final b2 = PendingBillModel(
        id: 'bill_r2',
        businessName: 'Purva Enterprises',
        shopId: s2.id,
        shopName: s2.name,
        routeId: r2.id,
        routeName: r2.name,
        billNumber: 'B-102',
        totalAmount: 6000,
        collectedAmount: 0,
        status: 'pending',
        invoiceDate: DateTime.now(),
        deliveryDate: DateTime.now(),
        createdAt: DateTime.now(),
      );
      await provider.addPendingBill(b1);
      await provider.addPendingBill(b2);

      // 1. Salesman login sees all pending bills
      final salesman = UserModel(
        id: 'user_sales_akash',
        phone: '9309862465',
        name: 'Akash',
        role: UserRole.salesman,
        password: 'pass123',
      );
      provider.setCurrentUser(salesman);
      expect(provider.pendingBills.length, 2);
      expect(provider.shops.length, 2);

      // 2. Driver assigned ONLY to Route 1
      final driver = UserModel(
        id: 'user_driver_user1',
        phone: 'user1',
        name: 'Driver (user1)',
        role: UserRole.driver,
        password: 'pass123',
        assignedRouteIds: [r1.id],
      );
      provider.setCurrentUser(driver);

      expect(provider.routes.length, 1);
      expect(provider.routes.first.id, r1.id);

      expect(provider.shops.length, 1);
      expect(provider.shops.first.id, s1.id);

      expect(provider.pendingBills.length, 1);
      expect(provider.pendingBills.first.id, b1.id);
    });
  });

  group('Bank Details & Payment Options Tests', () {
    test('FirmDetailsHelper provides correct NEFT / Bank details and formatted share text', () {
      final purva = FirmDetailsHelper.getInfo('Purva Enterprises');
      expect(purva.firmName, 'PURVA ENTERPRISES');
      expect(purva.bankName, 'Union Bank of India');
      expect(purva.accountNumber, '115925080000004');
      expect(purva.ifscCode, 'UBIN0570575');
      expect(purva.formattedShareText.contains('115925080000004'), isTrue);
      expect(purva.formattedShareText.contains('UBIN0570575'), isTrue);
      expect(purva.formattedShareText.contains('8459671694@okbizaxis'), isTrue);

      final manas = FirmDetailsHelper.getInfo('Manas Sales');
      expect(manas.firmName, 'MANAS SALES');
      expect(manas.bankName, 'Central Bank of India');
      expect(manas.accountNumber, '5251719817');
      expect(manas.ifscCode, 'CBIN0284624');
      expect(manas.formattedShareText.contains('5251719817'), isTrue);
      expect(manas.formattedShareText.contains('CBIN0284624'), isTrue);
      expect(manas.formattedShareText.contains('9309862465@okbizaxis'), isTrue);
    });
  });
}
