import '../models/route_model.dart';
import '../models/shop_model.dart';
import '../models/collection_model.dart';
import '../models/payment_mode.dart';
import '../models/pending_bill_model.dart';

class SampleDataService {
  static List<RouteModel> getInitialRoutes() {
    return [
      RouteModel(
        id: 'route-chakan',
        name: 'Chakan',
        description: 'Main Bazaar, Market Yard & Talegaon Chowk',
        priority: 1,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      RouteModel(
        id: 'route-bhosari',
        name: 'Bhosari',
        description: 'MIDC, Dighi Road & Gaonthan',
        priority: 2,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
      RouteModel(
        id: 'route-hadapsar',
        name: 'Hadapsar',
        description: 'Gadital, Pune-Solapur Highway',
        priority: 3,
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
      ),
    ];
  }

  static List<ShopModel> getInitialShops() {
    return [
      ShopModel(
        id: 'shop-ata-kirana',
        name: 'ATA Kirana',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        mobileNumber: '9822012345',
        address: 'Shop No. 12, Main Bazaar, Chakan',
        ownerName: 'Altaf Bhai',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      ShopModel(
        id: 'shop-ganesh-traders',
        name: 'Shree Ganesh Traders',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        mobileNumber: '9823054321',
        address: 'Near ST Bus Stand, Chakan',
        ownerName: 'Ganesh Shinde',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      ShopModel(
        id: 'shop-mahesh-provision',
        name: 'Mahesh Provision Store',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        mobileNumber: '9850123987',
        address: 'Talegaon Road, Chakan',
        ownerName: 'Mahesh Patil',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      ShopModel(
        id: 'shop-sai-krupa',
        name: 'Sai Krupa Supermarket',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        mobileNumber: '9766543210',
        address: 'Opp. Market Yard Gate 2, Chakan',
        ownerName: 'Suresh Pawar',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      ShopModel(
        id: 'shop-om-traders',
        name: 'Om Traders',
        routeId: 'route-bhosari',
        routeName: 'Bhosari',
        mobileNumber: '9422334455',
        address: 'Bhosari Gaonthan, Pune',
        ownerName: 'Kiran Deshmukh',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
    ];
  }

  static List<CollectionModel> getInitialCollections() {
    final now = DateTime.now();
    return [
      // ATA Kirana has a full bill of 40,000 but only gives 30,000 today -> PENDING (10,000 balance!)
      CollectionModel(
        id: 'col-1',
        businessName: 'Purva Enterprises',
        shopId: 'shop-ata-kirana',
        shopName: 'ATA Kirana',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        billNumber: 'PE-4081',
        billAmount: 40000.0,
        collectedAmount: 30000.0,
        paymentMode: PaymentMode.cash,
        remarks: 'Partial payment received. ₹10,000 pending.',
        salesmanName: 'Akash',
        collectedAt: DateTime(now.year, now.month, now.day, 10, 30),
      ),
      // 100% complete settlement -> PAID
      CollectionModel(
        id: 'col-2',
        businessName: 'Manas Sales',
        shopId: 'shop-ganesh-traders',
        shopName: 'Shree Ganesh Traders',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        billNumber: 'MS-2015',
        billAmount: 40000.0,
        collectedAmount: 40000.0,
        paymentMode: PaymentMode.cash,
        remarks: 'Full cash payment settled',
        salesmanName: 'Akash',
        collectedAt: DateTime(now.year, now.month, now.day, 12, 15),
      ),
      // 100% complete settlement -> PAID
      CollectionModel(
        id: 'col-3',
        businessName: 'Purva Enterprises',
        shopId: 'shop-mahesh-provision',
        shopName: 'Mahesh Provision Store',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        billNumber: 'PE-4085',
        billAmount: 30000.0,
        collectedAmount: 30000.0,
        paymentMode: PaymentMode.cash,
        remarks: 'Full cash settlement',
        salesmanName: 'Akash',
        collectedAt: DateTime(now.year, now.month, now.day, 14, 45),
      ),
      // 4,000 UPI -> PAID
      CollectionModel(
        id: 'col-4',
        businessName: 'Manas Sales',
        shopId: 'shop-sai-krupa',
        shopName: 'Sai Krupa Supermarket',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        billNumber: 'MS-2018',
        billAmount: 4000.0,
        collectedAmount: 4000.0,
        paymentMode: PaymentMode.upi,
        referenceNumber: 'UPI/629104821/GPAY',
        remarks: 'Google Pay to Manas Sales QR',
        salesmanName: 'Akash',
        collectedAt: DateTime(now.year, now.month, now.day, 16, 20),
      ),
      // 5,000 Cheque -> PAID
      CollectionModel(
        id: 'col-5',
        businessName: 'Purva Enterprises',
        shopId: 'shop-om-traders',
        shopName: 'Om Traders',
        routeId: 'route-bhosari',
        routeName: 'Bhosari',
        billNumber: 'PE-4090',
        billAmount: 5000.0,
        collectedAmount: 5000.0,
        paymentMode: PaymentMode.cheque,
        chequeNumber: '402911',
        bankName: 'HDFC Bank',
        remarks: 'Cheque dated today in favour of Purva Enterprises',
        salesmanName: 'Akash',
        collectedAt: DateTime(now.year, now.month, now.day, 17, 10),
      ),
      // 3,000 Net Banking -> PAID
      CollectionModel(
        id: 'col-6',
        businessName: 'Manas Sales',
        shopId: 'shop-ata-kirana',
        shopName: 'ATA Kirana',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        billNumber: 'MS-2022',
        billAmount: 3000.0,
        collectedAmount: 3000.0,
        paymentMode: PaymentMode.netBanking,
        referenceNumber: 'NEFT/SBIN91823091',
        bankName: 'State Bank of India',
        remarks: 'NEFT transfer verified',
        salesmanName: 'Akash',
        collectedAt: DateTime(now.year, now.month, now.day, 18, 05),
      ),
    ];
  }

  static List<PendingBillModel> getInitialPendingBills() {
    final now = DateTime.now();
    return [
      PendingBillModel(
        id: 'pb-1',
        businessName: 'Purva Enterprises',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        shopId: 'shop-ata-kirana',
        shopName: 'ATA Kirana',
        invoiceDate: DateTime(now.year, now.month, 12),
        deliveryDate: DateTime(now.year, now.month, 12),
        billNumber: 'PE-5012',
        totalAmount: 18500.0,
        collectedAmount: 0.0,
        status: 'pending',
        createdAt: DateTime(now.year, now.month, 13, 9, 30),
      ),
      PendingBillModel(
        id: 'pb-2',
        businessName: 'Manas Sales',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        shopId: 'shop-ganesh-traders',
        shopName: 'Shree Ganesh Traders',
        invoiceDate: DateTime(now.year, now.month, 14),
        deliveryDate: DateTime(now.year, now.month, 15),
        billNumber: 'MS-3104',
        totalAmount: 24000.0,
        collectedAmount: 0.0,
        status: 'pending',
        createdAt: DateTime(now.year, now.month, 15, 11, 00),
      ),
      PendingBillModel(
        id: 'pb-3',
        businessName: 'Purva Enterprises',
        routeId: 'route-bhosari',
        routeName: 'Bhosari',
        shopId: 'shop-om-traders',
        shopName: 'Om Traders',
        invoiceDate: DateTime(now.year, now.month, 16),
        deliveryDate: DateTime(now.year, now.month, 16),
        billNumber: 'PE-5020',
        totalAmount: 12000.0,
        collectedAmount: 0.0,
        status: 'pending',
        createdAt: DateTime(now.year, now.month, 17, 10, 15),
      ),
      PendingBillModel(
        id: 'pb-4',
        businessName: 'Manas Sales',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        shopId: 'shop-mahesh-provision',
        shopName: 'Mahesh Provision Store',
        invoiceDate: DateTime(now.year, now.month, 17),
        deliveryDate: DateTime(now.year, now.month, 18),
        billNumber: 'MS-3110',
        totalAmount: 9500.0,
        collectedAmount: 0.0,
        status: 'pending',
        createdAt: DateTime(now.year, now.month, 18, 14, 00),
      ),
    ];
  }
}
