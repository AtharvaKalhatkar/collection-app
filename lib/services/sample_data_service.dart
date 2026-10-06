import '../models/route_model.dart';
import '../models/shop_model.dart';
import '../models/collection_model.dart';
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
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      ShopModel(
        id: 'shop-ganesh-traders',
        name: 'Shree Ganesh Traders',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        mobileNumber: '9823054321',
        address: 'Near ST Bus Stand, Chakan',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      ShopModel(
        id: 'shop-mahesh-provision',
        name: 'Mahesh Provision Store',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        mobileNumber: '9850123987',
        address: 'Talegaon Road, Chakan',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      ShopModel(
        id: 'shop-sai-krupa',
        name: 'Sai Krupa Supermarket',
        routeId: 'route-chakan',
        routeName: 'Chakan',
        mobileNumber: '9766543210',
        address: 'Opp. Market Yard Gate 2, Chakan',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      ShopModel(
        id: 'shop-om-traders',
        name: 'Om Traders',
        routeId: 'route-bhosari',
        routeName: 'Bhosari',
        mobileNumber: '9422334455',
        address: 'Bhosari Gaonthan, Pune',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
    ];
  }

  static List<CollectionModel> getInitialCollections() {
    return [];
  }

  static List<PendingBillModel> getInitialPendingBills() {
    return [];
  }
}
