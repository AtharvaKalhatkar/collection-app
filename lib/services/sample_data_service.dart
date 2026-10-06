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
    return [];
  }

  static List<CollectionModel> getInitialCollections() {
    return [];
  }

  static List<PendingBillModel> getInitialPendingBills() {
    return [];
  }
}
