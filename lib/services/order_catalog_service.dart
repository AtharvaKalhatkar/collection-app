import '../models/order_model.dart';

class OrderCatalogService {
  static const String purva = 'Purva Enterprises';
  static const String manas = 'Manas Sales';

  // Default companies if user has not entered any products yet
  static const Map<String, List<String>> companiesByFirm = {
    purva: ['Wipro', 'Fena', 'Funfood', 'Imami'],
    manas: ['Racket', 'Imami', 'Dabar', 'Cadbury', 'Gowardhan'],
  };

  static const List<String> defaultCompanies = ['Fena', 'Wipro', 'Purva Enterprises', 'Manas Sales'];
  static const List<String> defaultCategories = ['HC', 'PC', 'FC'];
  static const List<String> defaultSubcategories = ['NSB', 'NSP'];

  static const List<String> availableUnits = ['Pcs', 'Outer', 'Box', 'Nodes'];

  // Dynamic custom products added by user (stored locally & synced to Supabase)
  static final List<CatalogProduct> _customProducts = [];

  // NO mock sample products - catalog starts empty as requested by user
  static const List<CatalogProduct> catalog = <CatalogProduct>[];

  static void setCustomProducts(List<CatalogProduct> products) {
    _customProducts.clear();
    _customProducts.addAll(products);
  }

  static void addCustomProduct(CatalogProduct product) {
    _customProducts.removeWhere((p) => p.id == product.id);
    _customProducts.add(product);
  }

  static void deleteCustomProduct(String productId) {
    _customProducts.removeWhere((p) => p.id == productId);
  }

  static List<CatalogProduct> get customProducts => List.unmodifiable(_customProducts);

  static List<CatalogProduct> get allProducts => [...catalog, ..._customProducts];

  static List<String> getCompanies([String? firm]) {
    final base = List<String>.from(companiesByFirm[firm] ?? defaultCompanies);
    for (final p in _customProducts) {
      if (firm == null || p.firm.toLowerCase() == firm.toLowerCase()) {
        if (!base.any((c) => c.toLowerCase() == p.company.toLowerCase())) {
          base.add(p.company);
        }
      }
    }
    return base;
  }

  static List<String> getCategories([String? firm, String? company]) {
    final Set<String> categories = {};
    for (final p in allProducts) {
      final firmMatch = firm == null || firm.isEmpty || firm == 'All' || p.firm.toLowerCase() == firm.toLowerCase();
      final compMatch = company == null || company.isEmpty || company == 'All' || company == 'All Companies' || p.company.toLowerCase() == company.toLowerCase();
      if (firmMatch && compMatch && p.category.trim().isNotEmpty) {
        categories.add(p.category.trim());
      }
    }
    if (categories.isEmpty) {
      return List.from(defaultCategories);
    }
    final list = categories.toList()..sort();
    return list;
  }

  static List<String> getSubcategories([String? firm, String? company, String? category]) {
    final Set<String> subcategories = {};
    for (final p in allProducts) {
      final firmMatch = firm == null || firm.isEmpty || firm == 'All' || p.firm.toLowerCase() == firm.toLowerCase();
      final compMatch = company == null || company.isEmpty || company == 'All' || company == 'All Companies' || p.company.toLowerCase() == company.toLowerCase();
      final catMatch = category == null || category.isEmpty || category == 'All' || category == 'All Category' || p.category.toLowerCase() == category.toLowerCase();
      if (firmMatch && compMatch && catMatch && p.subcategory.trim().isNotEmpty) {
        subcategories.add(p.subcategory.trim());
      }
    }
    if (subcategories.isEmpty) {
      return List.from(defaultSubcategories);
    }
    final list = subcategories.toList()..sort();
    return list;
  }

  static List<CatalogProduct> getProducts({
    String? firm,
    String? company,
    String? category,
    String? subcategory,
    String? query,
  }) {
    return allProducts.where((p) {
      if (firm != null && firm.isNotEmpty && firm != 'All' && p.firm.toLowerCase() != firm.toLowerCase()) {
        return false;
      }
      if (company != null && company.isNotEmpty && company != 'All' && company != 'All Companies' && p.company.toLowerCase() != company.toLowerCase()) {
        return false;
      }
      if (category != null && category.isNotEmpty && category != 'All' && category != 'All Category' && category != 'All (Category)' && p.category.toLowerCase() != category.toLowerCase()) {
        return false;
      }
      if (subcategory != null && subcategory.isNotEmpty && subcategory != 'All' && subcategory != 'All Subcategory' && p.subcategory.toLowerCase() != subcategory.toLowerCase()) {
        return false;
      }
      if (query != null && query.trim().isNotEmpty) {
        final q = query.toLowerCase().trim();
        final match = p.name.toLowerCase().contains(q) ||
            p.company.toLowerCase().contains(q) ||
            p.category.toLowerCase().contains(q) ||
            p.subcategory.toLowerCase().contains(q) ||
            (p.code != null && p.code!.toLowerCase().contains(q));
        if (!match) return false;
      }
      return true;
    }).toList();
  }
}
