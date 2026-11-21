import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/order_model.dart';
import '../models/shop_model.dart';
import '../providers/auth_provider.dart';
import '../providers/collection_provider.dart';
import '../services/godown_billing_pdf_service.dart';
import '../services/order_catalog_service.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';
import '../widgets/add_product_dialog.dart';

class OutletOrderBookingScreen extends StatefulWidget {
  final ShopModel shop;
  final DateTime selectedDate;

  const OutletOrderBookingScreen({
    super.key,
    required this.shop,
    required this.selectedDate,
  });

  @override
  State<OutletOrderBookingScreen> createState() => _OutletOrderBookingScreenState();
}

class _OutletOrderBookingScreenState extends State<OutletOrderBookingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final String _selectedFirm = OrderCatalogService.purva;
  String _selectedCompany = 'Fena';
  String _selectedCategory = 'All Category';
  String _selectedSubcategory = 'All Subcategory';
  String _searchQuery = '';

  // ProductId -> OrderItem
  final Map<String, OrderItem> _cart = {};

  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initCatalogHierarchy();
  }

  void _initCatalogHierarchy() {
    final companies = OrderCatalogService.getCompanies(_selectedFirm);
    if (companies.isNotEmpty) {
      if (!companies.contains(_selectedCompany)) {
        _selectedCompany = companies.first;
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _notesController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  int get _totalCases => _cart.values.fold(0, (sum, i) => sum + i.cases);
  int get _totalUnits => _cart.values.fold(0, (sum, i) => sum + i.units);
  int get _totalAllUnits => _cart.values.fold(0, (sum, i) => sum + i.totalUnits);
  double get _totalKg => _cart.values.fold(0.0, (sum, i) => sum + i.totalWeightKg);
  double get _totalAmount => _cart.values.fold(0.0, (sum, i) => sum + i.subtotal);

  void _updateCartItem(CatalogProduct product, {int? cases, int? units}) {
    setState(() {
      final existing = _cart[product.id];
      final currentCases = cases ?? existing?.cases ?? 0;
      final currentUnits = units ?? existing?.units ?? 0;

      if (currentCases <= 0 && currentUnits <= 0) {
        _cart.remove(product.id);
      } else {
        _cart[product.id] = OrderItem(
          productId: product.id,
          productName: product.name,
          company: product.company,
          category: product.category,
          subcategory: product.subcategory,
          packing: product.packing,
          rate: product.rate,
          quantity: (currentCases * product.unitsPerCase) + currentUnits,
          unit: product.defaultUnit,
          cases: currentCases,
          units: currentUnits,
          unitsPerCase: product.unitsPerCase,
          weightKg: product.weightKg,
          photoUrl: product.photoUrl,
          photoBase64: product.photoBase64,
        );
      }
    });
  }

  Future<void> _openAddProduct() async {
    final added = await showDialog<CatalogProduct>(
      context: context,
      builder: (_) => AddProductDialog(
        initialFirm: _selectedFirm,
        initialCompany: _selectedCompany,
        initialCategory: _selectedCategory != 'All Category' ? _selectedCategory : null,
      ),
    );
    if (added != null) {
      setState(() {
        _selectedCompany = added.company;
        _selectedCategory = added.category;
        _selectedSubcategory = added.subcategory;
      });
    }
  }

  void _showImageZoom(CatalogProduct product) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 250,
                  width: double.infinity,
                  color: const Color(0xFFF1F5F9),
                  child: product.photoUrl != null && product.photoUrl!.isNotEmpty
                      ? Image.network(
                          product.photoUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => const Icon(
                            Icons.inventory_2_outlined,
                            size: 80,
                            color: Color(0xFF94A3B8),
                          ),
                        )
                      : const Icon(
                          Icons.inventory_2_outlined,
                          size: 80,
                          color: Color(0xFF94A3B8),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Unit Price: ₹${product.rate.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFEA580C))),
                  Text('1 CS = ${product.unitsPerCase} UT',
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitOrder() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cart is empty. Add at least 1 product.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final provider = context.read<CollectionProvider>();
    final user = auth.currentUser;
    final salesmanName = user != null ? user.plainName : 'Staff';

    final orderNum = 'ORD-${DateFormat('yyMMdd').format(widget.selectedDate)}-${1000 + Random().nextInt(9000)}';

    final order = SalesOrderModel(
      id: 'ord-${DateTime.now().millisecondsSinceEpoch}',
      orderNumber: orderNum,
      firm: _selectedFirm,
      routeId: widget.shop.routeId,
      routeName: widget.shop.routeName,
      shopId: widget.shop.id,
      shopName: widget.shop.name,
      shopMobile: widget.shop.mobileNumber,
      salesmanName: salesmanName,
      orderDate: widget.selectedDate,
      items: _cart.values.toList(),
      totalAmount: _totalAmount,
      totalQuantity: _totalAllUnits,
      notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
      status: 'Booked',
    );

    await provider.addSalesOrder(order);

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 28),
            SizedBox(width: 8),
            Text('Order Booked!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Order #$orderNum', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text('Outlet: ${widget.shop.name}', style: const TextStyle(fontSize: 13, color: Color(0xFF334155))),
            Text('Total Amount: ${CurrencyFormatter.format(_totalAmount)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            Text('Items: ${_cart.length} lines • $_totalCases CS, $_totalUnits UT',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 16, color: Color(0xFFDC2626)),
                    label: const Text('Godown Slip'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      side: const BorderSide(color: Color(0xFFDC2626)),
                      foregroundColor: const Color(0xFFDC2626),
                    ),
                    onPressed: () {
                      GodownBillingPdfService.previewOrSharePdf(
                        context,
                        orders: [order],
                        salesmanName: order.salesmanName,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                    label: const Text('WhatsApp'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () => _shareOrderWhatsApp(order),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(dialogCtx);
              Navigator.pop(context, true); // return to retailer list
            },
            child: const Text('Done / Back to Outlets', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _shareOrderWhatsApp(SalesOrderModel order) async {
    final buffer = StringBuffer();
    buffer.writeln('📦 *NEW SALES ORDER - PURVA ENTERPRISES*');
    buffer.writeln('--------------------------------');
    buffer.writeln('Order #: ${order.orderNumber}');
    buffer.writeln('Date: ${DateFormat('dd MMM yyyy').format(order.orderDate)}');
    buffer.writeln('Store: *${order.shopName}*');
    buffer.writeln('Route: ${order.routeName}');
    buffer.writeln('Booked By: ${order.salesmanName}');
    buffer.writeln('--------------------------------');
    buffer.writeln('*ORDER ITEMS:*');
    for (int i = 0; i < order.items.length; i++) {
      final it = order.items[i];
      buffer.writeln('${i + 1}. *${it.productName}*');
      buffer.writeln('   CS: ${it.cases} | UT: ${it.units} | Rate: ₹${it.rate.toStringAsFixed(2)} | Subtotal: ₹${it.subtotal.toStringAsFixed(2)}');
    }
    buffer.writeln('--------------------------------');
    buffer.writeln('Total Lines: ${order.items.length}');
    buffer.writeln('Total Cases: ${order.totalCases} CS');
    buffer.writeln('*TOTAL AMOUNT: ${CurrencyFormatter.format(order.totalAmount)}*');
    if (order.notes != null && order.notes!.isNotEmpty) {
      buffer.writeln('Notes: ${order.notes}');
    }

    final url = Uri.parse('https://api.whatsapp.com/send?text=${Uri.encodeComponent(buffer.toString())}');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.shop.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              '${widget.shop.routeName} • ${DateFormat('dd MMM').format(widget.selectedDate)}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box_rounded),
            tooltip: 'Add Product to Catalog',
            onPressed: _openAddProduct,
          ),
          IconButton(
            icon: const Icon(Icons.shopping_cart_rounded),
            tooltip: 'View Cart',
            onPressed: () => _tabController.animateTo(2),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF38BDF8),
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFF94A3B8),
          tabs: [
            const Tab(text: 'Order'),
            const Tab(text: 'Outlet Info'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Submit Order'),
                  if (_cart.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${_cart.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOrderTab(),
          _buildOutletInfoTab(),
          _buildSubmitOrderTab(),
        ],
      ),
      floatingActionButton: _tabController.index == 0 && _cart.isNotEmpty
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
              onPressed: () => _tabController.animateTo(2),
              icon: const Icon(Icons.shopping_cart_checkout_rounded),
              label: Text('${_cart.length} in Cart • ₹${_totalAmount.toStringAsFixed(0)}'),
            )
          : null,
      bottomNavigationBar: _tabController.index == 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'CS: $_totalCases',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155)),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'UT: $_totalUnits',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Total: ${CurrencyFormatter.format(_totalAmount)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1D4ED8),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _tabController.animateTo(2),
                      child: const Row(
                        children: [
                          Text('Next / Review', style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_forward_rounded, size: 16),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildOrderTab() {
    final companies = OrderCatalogService.getCompanies(_selectedFirm);
    final categories = ['All Category', ...OrderCatalogService.getCategories(_selectedFirm, _selectedCompany)];
    final subcategories = [
      'All Subcategory',
      ...OrderCatalogService.getSubcategories(
        _selectedFirm,
        _selectedCompany,
        _selectedCategory != 'All Category' ? _selectedCategory : null,
      ),
    ];

    final products = OrderCatalogService.getProducts(
      firm: _selectedFirm,
      company: _selectedCompany,
      category: _selectedCategory != 'All Category' ? _selectedCategory : null,
      subcategory: _selectedSubcategory != 'All Subcategory' ? _selectedSubcategory : null,
      query: _searchQuery,
    );

    return Column(
      children: [
        // Top Filter Bar matching Bizom UI
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            children: [
              // Search Input
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search SKU / Product name...',
                    hintStyle: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                    prefixIcon: Icon(Icons.search, size: 18, color: Color(0xFF64748B)),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
              const SizedBox(height: 10),

              // Dropdowns Row: Company, Category, Subcategory
              Row(
                children: [
                  // 1. Company
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Company', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                        const SizedBox(height: 2),
                        DropdownButtonFormField<String>(
                          initialValue: companies.contains(_selectedCompany) ? _selectedCompany : (companies.isNotEmpty ? companies.first : null),
                          isExpanded: true,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                          ),
                          items: companies.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)))).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedCompany = val;
                                _selectedCategory = 'All Category';
                                _selectedSubcategory = 'All Subcategory';
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),

                  // 2. Category
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Category', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                        const SizedBox(height: 2),
                        DropdownButtonFormField<String>(
                          initialValue: categories.contains(_selectedCategory) ? _selectedCategory : categories.first,
                          isExpanded: true,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                          ),
                          items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)))).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedCategory = val;
                                _selectedSubcategory = 'All Subcategory';
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),

                  // 3. Subcategory
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Subcategory', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                        const SizedBox(height: 2),
                        DropdownButtonFormField<String>(
                          initialValue: subcategories.contains(_selectedSubcategory) ? _selectedSubcategory : subcategories.first,
                          isExpanded: true,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                          ),
                          items: subcategories.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)))).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedSubcategory = val);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Product List
        Expanded(
          child: products.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 64, color: Color(0xFFCBD5E1)),
                        const SizedBox(height: 12),
                        Text(
                          'No products found in $_selectedCompany > $_selectedCategory',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Tap below to add products with Unit Price & Case conversion.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _openAddProduct,
                          icon: const Icon(Icons.add, size: 18, color: Colors.white),
                          label: const Text('Add Product to Catalog', style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: products.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (ctx, index) {
                    final product = products[index];
                    final cartItem = _cart[product.id];
                    final casesVal = cartItem?.cases ?? 0;
                    final unitsVal = cartItem?.units ?? 0;

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: (casesVal > 0 || unitsVal > 0)
                              ? const Color(0xFF38BDF8)
                              : Colors.grey.shade200,
                          width: (casesVal > 0 || unitsVal > 0) ? 1.5 : 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left: Product Photo Thumbnail
                          InkWell(
                            onTap: () => _showImageZoom(product),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: product.photoUrl != null && product.photoUrl!.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        product.photoUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) => const Icon(
                                          Icons.inventory_2_outlined,
                                          color: Color(0xFF94A3B8),
                                        ),
                                      ),
                                    )
                                  : const Icon(Icons.inventory_2_outlined, color: Color(0xFF94A3B8)),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Right: Details & CS/UT Inputs
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      'Unit Price ${product.rate.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: Color(0xFFEA580C),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Availability: ${product.availability}',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),

                                // Quantity Input row: CS (Case) and UT (Unit)
                                Row(
                                  children: [
                                    // CS Input
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF8FAFC),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.grey.shade300),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'CS (${product.unitsPerCase} UT)',
                                              style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                                            ),
                                            Row(
                                              children: [
                                                InkWell(
                                                  onTap: casesVal > 0 ? () => _updateCartItem(product, cases: casesVal - 1) : null,
                                                  child: const Icon(Icons.remove_circle_outline, size: 18, color: Color(0xFF64748B)),
                                                ),
                                                Expanded(
                                                  child: Text(
                                                    '$casesVal',
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                  ),
                                                ),
                                                InkWell(
                                                  onTap: () => _updateCartItem(product, cases: casesVal + 1),
                                                  child: const Icon(Icons.add_circle_outline, size: 18, color: Color(0xFF2563EB)),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // UT Input
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF8FAFC),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.grey.shade300),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'UT (1 PC)',
                                              style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                                            ),
                                            Row(
                                              children: [
                                                InkWell(
                                                  onTap: unitsVal > 0 ? () => _updateCartItem(product, units: unitsVal - 1) : null,
                                                  child: const Icon(Icons.remove_circle_outline, size: 18, color: Color(0xFF64748B)),
                                                ),
                                                Expanded(
                                                  child: Text(
                                                    '$unitsVal',
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                  ),
                                                ),
                                                InkWell(
                                                  onTap: () => _updateCartItem(product, units: unitsVal + 1),
                                                  child: const Icon(Icons.add_circle_outline, size: 18, color: Color(0xFF2563EB)),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildOutletInfoTab() {
    final provider = context.watch<CollectionProvider>();
    final history = provider.getPreviousOrdersForShop(widget.shop.id);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.shop.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 4),
                Text('Owner: ${widget.shop.ownerName ?? 'Not set'}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                Text('Address: ${widget.shop.address}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                Text('Mobile: ${widget.shop.mobileNumber}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.phone_rounded, size: 16),
                        label: const Text('Call'),
                        onPressed: widget.shop.mobileNumber.isNotEmpty
                            ? () => launchUrl(Uri.parse('tel:${widget.shop.mobileNumber}'))
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.navigation_rounded, size: 16),
                        label: const Text('Navigate'),
                        onPressed: widget.shop.mapsUrl != null
                            ? () => launchUrl(Uri.parse(widget.shop.mapsUrl!), mode: LaunchMode.externalApplication)
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text('Previous Booked Orders', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
          const SizedBox(height: 8),

          if (history.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Center(
                child: Text('No previous orders for this store.', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ),
            )
          else
            ...history.map((ord) {
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
                child: ListTile(
                  title: Text(ord.orderNumber, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text('${DateFormat('dd MMM yyyy').format(ord.orderDate)} • ${ord.items.length} lines'),
                  trailing: Text(CurrencyFormatter.format(ord.totalAmount), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildSubmitOrderTab() {
    if (_cart.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shopping_cart_outlined, size: 64, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 12),
            const Text('Your cart is empty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF475569))),
            const SizedBox(height: 6),
            const Text('Add products from the Order tab to submit.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _tabController.animateTo(0),
              child: const Text('Go to Products'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Top Summary Strip matching screenshot 4f53b724-87f9-4617-a5b2-83ae87fc3630.jpeg
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          color: const Color(0xFFFEF9C3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSummaryPill('Amount', '₹${_totalAmount.toStringAsFixed(2)}'),
              _buildSummaryPill('Lines', '${_cart.length}'),
              _buildSummaryPill('Case/Bags', '$_totalCases'),
              _buildSummaryPill('Unit', '$_totalUnits'),
              _buildSummaryPill('Kg', _totalKg.toStringAsFixed(1)),
            ],
          ),
        ),

        // Items Breakdown
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _cart.values.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (ctx, index) {
              final item = _cart.values.elementAt(index);
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.productName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          onPressed: () {
                            setState(() {
                              _cart.remove(item.productId);
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('UT Price: ₹${item.rate.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                        Text('CS: ${item.cases}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        Text('UT: ${item.units}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        Text('Subtotal: ₹${item.subtotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        // Bottom Notes & Submit button
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _notesController,
                  decoration: InputDecoration(
                    hintText: 'Order notes / remarks (Optional)...',
                    hintStyle: const TextStyle(fontSize: 12),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('TOTAL AMOUNT:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                          Text(
                            '₹${_totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1D4ED8),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _submitOrder,
                      child: const Text('Submit Order', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryPill(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF713F12))),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF713F12))),
      ],
    );
  }
}
