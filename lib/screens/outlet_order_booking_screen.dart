import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../utils/image_compress_helper.dart';
import '../utils/theme.dart';
import '../widgets/add_product_dialog.dart';
import '../widgets/clean_ui.dart';

const Color _bookingBlue = Color(0xFF15429E);

class OutletOrderBookingScreen extends StatefulWidget {
  final ShopModel shop;
  final DateTime selectedDate;
  final SalesOrderModel? existingOrder;

  const OutletOrderBookingScreen({
    super.key,
    required this.shop,
    required this.selectedDate,
    this.existingOrder,
  });

  @override
  State<OutletOrderBookingScreen> createState() => _OutletOrderBookingScreenState();
}

class _OutletOrderBookingScreenState extends State<OutletOrderBookingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String _selectedFirm = OrderCatalogService.purva;
  String _selectedCompany = 'All Companies';
  String _selectedCategory = 'All Category';
  String _selectedSubcategory = 'All Subcategory';
  String _searchQuery = '';
  bool _showSearchBar = false;

  // ProductId -> OrderItem
  final Map<String, OrderItem> _cart = {};
  final Map<String, TextEditingController> _csControllers = {};
  final Map<String, TextEditingController> _utControllers = {};

  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _selectedFirm = widget.existingOrder?.firm ?? OrderCatalogService.purva;
    _initCatalogHierarchy();

    if (widget.existingOrder != null) {
      for (final item in widget.existingOrder!.items) {
        _cart[item.productId] = OrderItem(
          productId: item.productId,
          productName: item.productName,
          company: item.company,
          category: item.category,
          subcategory: item.subcategory,
          packing: item.packing,
          rate: item.rate,
          quantity: item.quantity,
          unit: item.unit,
          cases: item.cases,
          units: item.units,
          unitsPerCase: item.unitsPerCase,
          weightKg: item.weightKg,
          photoUrl: item.photoUrl,
          photoBase64: item.photoBase64,
        );
      }
      if (widget.existingOrder!.notes != null) {
        _notesController.text = widget.existingOrder!.notes!;
      }
    }
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  void _initCatalogHierarchy() {
    final companies = ['All Companies', ...OrderCatalogService.getCompanies(_selectedFirm)];
    if (!companies.contains(_selectedCompany)) {
      _selectedCompany = 'All Companies';
    }
  }

  TextEditingController _getCsController(String productId, int val) {
    final existing = _csControllers[productId];
    if (existing != null) return existing;
    final ctrl = TextEditingController(text: val > 0 ? '$val' : '');
    _csControllers[productId] = ctrl;
    return ctrl;
  }

  TextEditingController _getUtController(String productId, int val) {
    final existing = _utControllers[productId];
    if (existing != null) return existing;
    final ctrl = TextEditingController(text: val > 0 ? '$val' : '');
    _utControllers[productId] = ctrl;
    return ctrl;
  }

  void _syncControllersForProduct(String productId, int cases, int units) {
    final csCtrl = _csControllers[productId];
    final csStr = cases > 0 ? '$cases' : '';
    if (csCtrl != null && csCtrl.text != csStr) {
      csCtrl.value = TextEditingValue(
        text: csStr,
        selection: TextSelection.collapsed(offset: csStr.length),
      );
    }
    final utCtrl = _utControllers[productId];
    final utStr = units > 0 ? '$units' : '';
    if (utCtrl != null && utCtrl.text != utStr) {
      utCtrl.value = TextEditingValue(
        text: utStr,
        selection: TextSelection.collapsed(offset: utStr.length),
      );
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _notesController.dispose();
    _searchController.dispose();
    for (final c in _csControllers.values) {
      c.dispose();
    }
    for (final c in _utControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get _totalCases => _cart.values.fold(0, (sum, i) => sum + i.cases);
  int get _totalUnits => _cart.values.fold(0, (sum, i) => sum + i.units);
  int get _totalAllUnits => _cart.values.fold(0, (sum, i) => sum + i.totalUnits);
  double get _totalKg => _cart.values.fold(0.0, (sum, i) => sum + i.totalWeightKg);
  double get _totalAmount => _cart.values.fold(0.0, (sum, i) => sum + i.subtotal);

  void _updateCartItem(CatalogProduct product, {int? cases, int? units, bool syncInputs = false}) {
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
      if (syncInputs) {
        _syncControllersForProduct(product.id, currentCases, currentUnits);
      }
    });
  }

  Future<void> _openAddProduct() async {
    final added = await showDialog<CatalogProduct>(
      context: context,
      builder: (_) => AddProductDialog(
        initialFirm: _selectedFirm,
        initialCompany: _selectedCompany != 'All Companies' ? _selectedCompany : null,
        initialCategory: _selectedCategory != 'All Category' ? _selectedCategory : null,
        initialSubcategory: _selectedSubcategory != 'All Subcategory' ? _selectedSubcategory : null,
      ),
    );
    if (added != null) {
      setState(() {
        _selectedFirm = added.firm;
        _selectedCompany = added.company;
        _selectedCategory = added.category;
        _selectedSubcategory = added.subcategory;
      });
    }
  }

  /// Dedicated Product Photo Detail View with Prev/Next Switcher & Live CS/UT Inputs
  /// (Matching Reference Image 2: 8d7e1bfb-2992-4462-b6c2-a07be248da48.jpeg)
  void _showProductDetailSheet(List<CatalogProduct> productList, int initialIndex) {
    int currentIndex = initialIndex;
    final currentProd = productList[currentIndex];
    final csModalCtrl = TextEditingController(
      text: (_cart[currentProd.id]?.cases ?? 0) > 0 ? '${_cart[currentProd.id]!.cases}' : '',
    );
    final utModalCtrl = TextEditingController(
      text: (_cart[currentProd.id]?.units ?? 0) > 0 ? '${_cart[currentProd.id]!.units}' : '',
    );

    void loadProd(CatalogProduct p) {
      final existing = _cart[p.id];
      csModalCtrl.text = (existing?.cases ?? 0) > 0 ? '${existing!.cases}' : '';
      utModalCtrl.text = (existing?.units ?? 0) > 0 ? '${existing!.units}' : '';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (dlgCtx, setModalState) {
          final prod = productList[currentIndex];
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(dlgCtx).viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header with circular prev arrow, product name, and next arrow
                    Row(
                      children: [
                        InkWell(
                          onTap: currentIndex > 0
                              ? () {
                                  setModalState(() {
                                    currentIndex--;
                                    loadProd(productList[currentIndex]);
                                  });
                                }
                              : () => Navigator.pop(ctx),
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: const Icon(Icons.chevron_left_rounded, size: 20, color: Color(0xFF334155)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            prod.name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: Color(0xFF0F172A)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (currentIndex < productList.length - 1)
                          InkWell(
                            onTap: () {
                              setModalState(() {
                                currentIndex++;
                                loadProd(productList[currentIndex]);
                              });
                            },
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFF334155)),
                            ),
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Large Centered Photo Card
                    Container(
                      height: 230,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildProductImage(prod, iconSize: 72, fit: BoxFit.contain),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Unit Price Pill (if > 0), Stock & Active Scheme + Pack Specs
                    Row(
                      children: [
                        if (prod.rate > 0) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFFDBA74)),
                            ),
                            child: Text(
                              'Unit Price ${prod.rate.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFFC2410C)),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Text(
                            '${prod.company} • ${prod.category} (${prod.subcategory}) • 1 CS = ${prod.unitsPerCase} ${prod.defaultUnit}',
                            style: const TextStyle(color: Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    if (prod.scheme.trim().isNotEmpty || prod.stock > 0) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (prod.scheme.trim().isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFFCD34D)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.local_offer_rounded, size: 13, color: Color(0xFFB45309)),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Scheme: ${prod.scheme}',
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                                  ),
                                ],
                              ),
                            ),
                          if (prod.stock > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Stock: ${prod.formattedStock} ${prod.defaultUnit}',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF15803D)),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),

                    // Side-by-side Live CS & UT Inputs (Matching Image 2)
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CS (${prod.unitsPerCase} UT)',
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              TextField(
                                controller: csModalCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: InputDecoration(
                                  hintText: '0',
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onChanged: (val) {
                                  final newCs = (int.tryParse(val.trim()) ?? 0).clamp(0, 99999);
                                  final curUt = int.tryParse(utModalCtrl.text.trim()) ?? 0;
                                  _updateCartItem(prod, cases: newCs, units: curUt, syncInputs: true);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'UT (1 ${prod.defaultUnit})',
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              TextField(
                                controller: utModalCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: InputDecoration(
                                  hintText: '0',
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onChanged: (val) {
                                  final newUt = (int.tryParse(val.trim()) ?? 0).clamp(0, 99999);
                                  final curCs = int.tryParse(csModalCtrl.text.trim()) ?? 0;
                                  _updateCartItem(prod, cases: curCs, units: newUt, syncInputs: true);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _bookingBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).then((_) {
      csModalCtrl.dispose();
      utModalCtrl.dispose();
    });
  }

  Widget _buildProductImage(CatalogProduct product, {double iconSize = 26, BoxFit fit = BoxFit.cover}) {
    final base64Bytes = ImageCompressHelper.safeBase64Decode(product.photoBase64);
    if (base64Bytes != null) {
      return Image.memory(
        base64Bytes,
        fit: fit,
        errorBuilder: (_, _, _) => Icon(Icons.inventory_2_outlined, size: iconSize, color: const Color(0xFF94A3B8)),
      );
    }
    if (product.photoUrl != null && product.photoUrl!.isNotEmpty) {
      return Image.network(
        product.photoUrl!,
        fit: fit,
        errorBuilder: (_, _, _) => Icon(Icons.inventory_2_outlined, size: iconSize, color: const Color(0xFF94A3B8)),
      );
    }
    return Icon(Icons.inventory_2_outlined, size: iconSize, color: const Color(0xFF94A3B8));
  }

  Future<void> _submitOrder() async {
    if (_isSubmitting) return;
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cart is empty. Add at least 1 product.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final auth = context.read<AuthProvider>();
      final provider = context.read<CollectionProvider>();
      final user = auth.currentUser;
      final salesmanName = user != null ? user.plainName : 'Staff';

      final isEditing = widget.existingOrder != null;
      final orderNum = isEditing
          ? widget.existingOrder!.orderNumber
          : 'ORD-${DateFormat('yyMMdd').format(widget.selectedDate)}-${1000 + Random().nextInt(9000)}';
      final orderId = isEditing
          ? widget.existingOrder!.id
          : 'ord-${DateTime.now().millisecondsSinceEpoch}';

      final order = SalesOrderModel(
        id: orderId,
        orderNumber: orderNum,
        firm: _selectedFirm,
        routeId: widget.shop.routeId,
        routeName: widget.shop.routeName,
        shopId: widget.shop.id,
        shopName: widget.shop.name,
        shopMobile: widget.shop.mobileNumber,
        salesmanName: isEditing ? widget.existingOrder!.salesmanName : salesmanName,
        orderDate: isEditing ? widget.existingOrder!.orderDate : widget.selectedDate,
        items: _cart.values.toList(),
        totalAmount: _totalAmount,
        totalQuantity: _totalAllUnits,
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
        status: isEditing ? widget.existingOrder!.status : 'Booked',
      );

      await provider.addSalesOrder(order);

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 28),
              const SizedBox(width: 8),
              Text(isEditing ? 'Order Updated!' : 'Order Booked!', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Order #$orderNum', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 4),
              Text('Outlet: ${widget.shop.name}', style: const TextStyle(fontSize: 13, color: Color(0xFF334155))),
              if (_totalAmount > 0)
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
                backgroundColor: _bookingBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.pop(dialogCtx);
                Navigator.pop(context, true);
              },
              child: const Text('Done / Back to Outlets', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _shareOrderWhatsApp(SalesOrderModel order) async {
    final buffer = StringBuffer();
    buffer.writeln('*NEW SALES ORDER - ${order.firm.toUpperCase()}*');
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
      if (it.rate > 0) {
        buffer.writeln('   CS: ${it.cases} | UT: ${it.units} | Rate: ₹${it.rate.toStringAsFixed(2)} | Subtotal: ₹${it.subtotal.toStringAsFixed(2)}');
      } else {
        buffer.writeln('   CS: ${it.cases} | UT: ${it.units} (${it.totalUnits} ${it.unit})');
      }
    }
    buffer.writeln('--------------------------------');
    buffer.writeln('Total Lines: ${order.items.length}');
    buffer.writeln('Total Cases: ${order.totalCases} CS | Units: ${order.totalLooseUnits} UT');
    if (order.totalAmount > 0) {
      buffer.writeln('*TOTAL AMOUNT: ${CurrencyFormatter.format(order.totalAmount)}*');
    }
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
    final provider = context.watch<CollectionProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: _bookingBlue,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white, size: 22),
        actionsIconTheme: const IconThemeData(color: Colors.white, size: 22),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.shop.name.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${widget.shop.routeName.toUpperCase()} • $_selectedFirm',
              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.85)),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (_tabController.index == 0)
            IconButton(
              icon: Icon(_showSearchBar ? Icons.search_off_rounded : Icons.search_rounded),
              tooltip: 'Search SKU',
              onPressed: () {
                setState(() {
                  _showSearchBar = !_showSearchBar;
                  if (!_showSearchBar) {
                    _searchController.clear();
                    _searchQuery = '';
                  }
                });
              },
            ),
          IconButton(
            icon: const Icon(Icons.add_box_outlined),
            tooltip: 'Add Product to Catalog',
            onPressed: _openAddProduct,
          ),
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Sync Catalog',
            onPressed: () => provider.syncAllWithCloud(notify: true),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              indicatorColor: _bookingBlue,
              indicatorWeight: 2.5,
              labelColor: _bookingBlue,
              unselectedLabelColor: const Color(0xFF64748B),
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              labelPadding: const EdgeInsets.symmetric(horizontal: 6),
              tabs: [
                const Tab(text: 'Order'),
                const Tab(text: 'Outlet Info'),
                Tab(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Submit Order'),
                        if (_cart.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: const BoxDecoration(
                              color: AppTheme.balanceDueColor,
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
                ),
              ],
            ),
          ),
        ),
      ),
      body: ResponsiveContent(
        maxWidth: 860,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildOrderTab(),
            _buildOutletInfoTab(),
            _buildSubmitOrderTab(),
          ],
        ),
      ),
      bottomNavigationBar: _tabController.index == 0
          ? Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _tabController.animateTo(2),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                RichText(
                                  text: TextSpan(
                                    style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                                    children: [
                                      const TextSpan(text: 'CS: '),
                                      TextSpan(
                                        text: '$_totalCases',
                                        style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                RichText(
                                  text: TextSpan(
                                    style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                                    children: [
                                      const TextSpan(text: 'UT: '),
                                      TextSpan(
                                        text: '$_totalUnits',
                                        style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                RichText(
                                  text: TextSpan(
                                    style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                                    children: [
                                      TextSpan(text: _totalAmount > 0 ? 'Total: ' : 'Lines: '),
                                      TextSpan(
                                        text: _totalAmount > 0
                                            ? _totalAmount.toStringAsFixed(0)
                                            : '${_cart.length}',
                                        style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Tooltip(
                      message: 'Review & Submit Order',
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => _tabController.animateTo(2),
                        icon: const Icon(Icons.shopping_cart_outlined, size: 18, color: Colors.white),
                        label: Text(
                          _cart.isEmpty ? 'Cart' : 'Review (${_cart.length})',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white),
                        ),
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
    final rawCompanies = OrderCatalogService.getCompanies(_selectedFirm);
    final companies = ['All Companies', ...rawCompanies];
    final validCompany = companies.contains(_selectedCompany) ? _selectedCompany : 'All Companies';

    final rawCategories = OrderCatalogService.getCategories(
      _selectedFirm,
      validCompany != 'All Companies' ? validCompany : null,
    );
    final categories = ['All Category', ...rawCategories];
    final validCategory = categories.contains(_selectedCategory) ? _selectedCategory : 'All Category';

    final rawSubcategories = OrderCatalogService.getSubcategories(
      _selectedFirm,
      validCompany != 'All Companies' ? validCompany : null,
      validCategory != 'All Category' ? validCategory : null,
    );
    final subcategories = ['All Subcategory', ...rawSubcategories];
    final validSubcategory = subcategories.contains(_selectedSubcategory) ? _selectedSubcategory : 'All Subcategory';

    final products = OrderCatalogService.getProducts(
      firm: _selectedFirm,
      company: validCompany != 'All Companies' ? validCompany : null,
      category: validCategory != 'All Category' ? validCategory : null,
      subcategory: validSubcategory != 'All Subcategory' ? validSubcategory : null,
      query: _searchQuery,
    );

    final provider = context.watch<CollectionProvider>();
    final shopHistory = provider.getPreviousOrdersForShop(widget.shop.id, limit: 10);

    return Column(
      children: [
        if (widget.existingOrder != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            color: const Color(0xFFEFF6FF),
            child: Row(
              children: [
                const Icon(Icons.edit_note_rounded, size: 17, color: _bookingBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Editing Order: ${widget.existingOrder!.orderNumber}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _bookingBlue),
                  ),
                ),
                Text(
                  DateFormat('dd MMM').format(widget.existingOrder!.orderDate),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                ),
              ],
            ),
          ),

        // Slim Compact Filter Header (Matching Images 4, 6, 7)
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Collapsible Search Bar (triggered by AppBar magnifying glass)
              if (_showSearchBar || _searchQuery.isNotEmpty) ...[
                Container(
                  height: 38,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    autofocus: _showSearchBar && _searchQuery.isEmpty,
                    decoration: InputDecoration(
                      hintText: 'Search SKU / Product name...',
                      hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF64748B)),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
              ],

              // Row 1: Firm Pills (Purva | Manas) + Company Dropdown on ONE compact line
              Row(
                children: [
                  Container(
                    height: 36,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildCompactFirmBtn('Purva', OrderCatalogService.purva, _bookingBlue),
                        const SizedBox(width: 2),
                        _buildCompactFirmBtn('Manas', OrderCatalogService.manas, const Color(0xFF0F766E)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: validCompany,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _bookingBlue, size: 18),
                          items: companies.map((c) {
                            return DropdownMenuItem<String>(
                              value: c,
                              child: Text(
                                c,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
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
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Row 2: Labeled Category & Subcategory Side-by-Side (Exact match to Image 4 & 6)
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Category', style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: validCategory,
                              isExpanded: true,
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF475569), size: 18),
                              items: categories.map((cat) {
                                return DropdownMenuItem<String>(
                                  value: cat,
                                  child: Text(
                                    cat,
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedCategory = val;
                                    _selectedSubcategory = 'All Subcategory';
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Subcategory', style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: validSubcategory,
                              isExpanded: true,
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF475569), size: 18),
                              items: subcategories.map((sub) {
                                return DropdownMenuItem<String>(
                                  value: sub,
                                  child: Text(
                                    sub,
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedSubcategory = val);
                                }
                              },
                            ),
                          ),
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
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 56, color: Color(0xFFCBD5E1)),
                        const SizedBox(height: 12),
                        Text(
                          'No products found in $_selectedCompany > $_selectedCategory',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Tap below to add products with category, unit & case details.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _openAddProduct,
                          icon: const Icon(Icons.add, size: 18, color: Colors.white),
                          label: const Text('Add Product to Catalog', style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _bookingBlue,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 20),
                  itemCount: products.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (ctx, index) {
                    final product = products[index];
                    final cartItem = _cart[product.id];
                    final casesVal = cartItem?.cases ?? 0;
                    final unitsVal = cartItem?.units ?? 0;

                    final csCtrl = _getCsController(product.id, casesVal);
                    final utCtrl = _getUtController(product.id, unitsVal);

                    // Check last order for this SKU in shop history
                    int lastOrderCases = 0;
                    int lastOrderUnits = 0;
                    for (final ord in shopHistory) {
                      for (final it in ord.items) {
                        if (it.productId == product.id || it.productName.toLowerCase() == product.name.toLowerCase()) {
                          lastOrderCases = it.cases;
                          lastOrderUnits = it.units;
                          break;
                        }
                      }
                      if (lastOrderCases > 0 || lastOrderUnits > 0) break;
                    }

                    final hasQty = casesVal > 0 || unitsVal > 0;

                    return Container(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: hasQty ? _bookingBlue : const Color(0xFFE2E8F0),
                          width: hasQty ? 1.5 : 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (lastOrderCases > 0 || lastOrderUnits > 0)
                            Align(
                              alignment: Alignment.topRight,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  'LO: ${lastOrderCases > 0 ? "$lastOrderCases CS" : ""}${lastOrderUnits > 0 ? " $lastOrderUnits UT" : ""}',
                                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
                                ),
                              ),
                            ),

                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Left Thumbnail (Tap -> Image 2 Product Detail Modal)
                              InkWell(
                                onTap: () => _showProductDetailSheet(products, index),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 66,
                                  height: 66,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: _buildProductImage(product, iconSize: 28, fit: BoxFit.cover),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Right: Name, Optional Price Pill, Direct CS & UT TextFields (Image 4 & 7)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    InkWell(
                                      onTap: () => _showProductDetailSheet(products, index),
                                      child: Text(
                                        product.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13.5,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 5),

                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        if (product.rate > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFF7ED),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: const Color(0xFFFDBA74)),
                                            ),
                                            child: Text(
                                              'Unit Price ${product.rate.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 11,
                                                color: Color(0xFFC2410C),
                                              ),
                                            ),
                                          ),
                                        Text(
                                          '${product.category} (${product.subcategory}) • 1 CS = ${product.unitsPerCase} ${product.defaultUnit}',
                                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                    if (product.scheme.trim().isNotEmpty || product.stock > 0) ...[
                                      const SizedBox(height: 5),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          if (product.scheme.trim().isNotEmpty)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFEF3C7),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: const Color(0xFFFCD34D)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.local_offer_rounded, size: 10.5, color: Color(0xFFB45309)),
                                                  const SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      'Scheme: ${product.scheme}',
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w700,
                                                        color: Color(0xFFB45309),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (product.stock > 0)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFDCFCE7),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'Stock: ${product.formattedStock}',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF15803D),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 8),

                                    // Direct Numeric Input Boxes (Matching Reference Images 4, 6, 7)
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'CS (${product.unitsPerCase} UT)',
                                                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                                              ),
                                              const SizedBox(height: 3),
                                              SizedBox(
                                                height: 38,
                                                child: TextField(
                                                  controller: csCtrl,
                                                  keyboardType: TextInputType.number,
                                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Color(0xFF0F172A)),
                                                  decoration: InputDecoration(
                                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                    filled: true,
                                                    fillColor: casesVal > 0 ? const Color(0xFFEFF6FF) : Colors.white,
                                                    border: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(8),
                                                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                                    ),
                                                    enabledBorder: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(8),
                                                      borderSide: BorderSide(
                                                        color: casesVal > 0 ? _bookingBlue : const Color(0xFFCBD5E1),
                                                        width: casesVal > 0 ? 1.4 : 1.0,
                                                      ),
                                                    ),
                                                    focusedBorder: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(8),
                                                      borderSide: const BorderSide(color: _bookingBlue, width: 1.6),
                                                    ),
                                                  ),
                                                  onChanged: (val) {
                                                    final parsedCs = (int.tryParse(val.trim()) ?? 0).clamp(0, 99999);
                                                    _updateCartItem(product, cases: parsedCs);
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'UT (1 ${product.defaultUnit})',
                                                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                                              ),
                                              const SizedBox(height: 3),
                                              SizedBox(
                                                height: 38,
                                                child: TextField(
                                                  controller: utCtrl,
                                                  keyboardType: TextInputType.number,
                                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Color(0xFF0F172A)),
                                                  decoration: InputDecoration(
                                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                    filled: true,
                                                    fillColor: unitsVal > 0 ? const Color(0xFFEFF6FF) : Colors.white,
                                                    border: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(8),
                                                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                                    ),
                                                    enabledBorder: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(8),
                                                      borderSide: BorderSide(
                                                        color: unitsVal > 0 ? _bookingBlue : const Color(0xFFCBD5E1),
                                                        width: unitsVal > 0 ? 1.4 : 1.0,
                                                      ),
                                                    ),
                                                    focusedBorder: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(8),
                                                      borderSide: const BorderSide(color: _bookingBlue, width: 1.6),
                                                    ),
                                                  ),
                                                  onChanged: (val) {
                                                    final parsedUt = (int.tryParse(val.trim()) ?? 0).clamp(0, 99999);
                                                    _updateCartItem(product, units: parsedUt);
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
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

  Widget _buildCompactFirmBtn(String label, String firmKey, Color activeColor) {
    final isSelected = _selectedFirm == firmKey;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedFirm = firmKey;
          _selectedCompany = 'All Companies';
          _selectedCategory = 'All Category';
          _selectedSubcategory = 'All Subcategory';
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildOutletInfoTab() {
    final provider = context.watch<CollectionProvider>();
    final history = provider.getPreviousOrdersForShop(widget.shop.id);
    final pendingDue = provider.getTotalBalanceForShop(widget.shop.id);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.shop.name.toUpperCase(),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 4),
                Text('Owner: ${widget.shop.ownerName ?? 'Not set'}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                Text('Address: ${widget.shop.address}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                Text('Mobile: ${widget.shop.mobileNumber}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: pendingDue > 0 ? const Color(0xFFFEF2F2) : AppTheme.manasLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: pendingDue > 0
                          ? AppTheme.balanceDueColor.withValues(alpha: 0.3)
                          : AppTheme.manasBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 15,
                        color: pendingDue > 0 ? AppTheme.balanceDueColor : AppTheme.manasPrimary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Pending Due: ${CurrencyFormatter.format(pendingDue)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: pendingDue > 0 ? AppTheme.balanceDueColor : AppTheme.manasPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
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
                        icon: const Icon(Icons.chat_outlined, size: 16, color: Color(0xFF16A34A)),
                        label: const Text('WhatsApp', style: TextStyle(color: Color(0xFF16A34A))),
                        onPressed: widget.shop.mobileNumber.isNotEmpty
                            ? () {
                                final clean = widget.shop.mobileNumber.replaceAll(RegExp(r'[^0-9]'), '');
                                final phone = clean.length == 10 ? '91$clean' : clean;
                                launchUrl(Uri.parse('https://wa.me/$phone'), mode: LaunchMode.externalApplication);
                              }
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.navigation_rounded, size: 16),
                        label: const Text('Map'),
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
                  subtitle: Text('${DateFormat('dd MMM yyyy').format(ord.orderDate)} • ${ord.items.length} lines • ${ord.firm == 'Purva Enterprises' ? 'Purva' : 'Manas'}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (ord.totalAmount > 0) ...[
                        Text(
                          CurrencyFormatter.format(ord.totalAmount),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedFirm = ord.firm;
                            for (final item in ord.items) {
                              _cart[item.productId] = item.copyWith();
                              _syncControllersForProduct(item.productId, item.cases, item.units);
                            }
                            _tabController.animateTo(2);
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Loaded ${ord.items.length} item(s) from #${ord.orderNumber}'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        child: const Text('Repeat', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  /// Tabular Submit Order Tab (Matching Reference Image 5: cafe1eca-26f4-4b9d-ba4c-28458ea05fb9.jpeg)
  Widget _buildSubmitOrderTab() {
    if (_cart.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shopping_cart_outlined, size: 56, color: Color(0xFFCBD5E1)),
              const SizedBox(height: 12),
              const Text('Your cart is empty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF475569))),
              const SizedBox(height: 6),
              const Text('Add products from the Order tab to submit.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _bookingBlue, foregroundColor: Colors.white),
                onPressed: () => _tabController.animateTo(0),
                child: const Text('Go to Products'),
              ),
            ],
          ),
        ),
      );
    }

    final hasAmount = _totalAmount > 0;
    final hasKg = _totalKg > 0;

    return Column(
      children: [
        // Top Cream/Yellow Summary Strip
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: const Color(0xFFFEFCE8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 14,
            runSpacing: 8,
            children: [
              if (hasAmount) _buildSummaryPill('Amount', _totalAmount.toStringAsFixed(2)),
              _buildSummaryPill('Lines', '${_cart.length}'),
              _buildSummaryPill('Case/Bags', '$_totalCases'),
              _buildSummaryPill('Unit', '$_totalUnits'),
              if (hasKg)
                _buildSummaryPill('Kg', _totalKg.toStringAsFixed(2))
              else
                _buildSummaryPill('Total Pcs', '$_totalAllUnits'),
            ],
          ),
        ),
        const Divider(height: 1),

        // Tabular Items Breakdown Cards + Scrollable Order Notes
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(10),
            itemCount: _cart.values.length + 1,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (ctx, index) {
              if (index == _cart.values.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: TextField(
                    controller: _notesController,
                    decoration: InputDecoration(
                      hintText: 'Order notes / remarks (Optional)...',
                      hintStyle: const TextStyle(fontSize: 12),
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                );
              }
              final item = _cart.values.elementAt(index);
              final itemHasRate = item.rate > 0;

              return InkWell(
                onTap: () => _showOrderItemEditDialog(item),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Bold Product Name + Red Trash Icon
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.productName,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Color(0xFF0F172A)),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18, color: _bookingBlue),
                            tooltip: 'Edit CS / UT',
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            onPressed: () => _showOrderItemEditDialog(item),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFDC2626)),
                            tooltip: 'Remove item',
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              setState(() {
                                _cart.remove(item.productId);
                                _syncControllersForProduct(item.productId, 0, 0);
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Clean Aligned Table Grid (Matching Image 5)
                      Row(
                        children: [
                          if (itemHasRate)
                            Expanded(
                              flex: 3,
                              child: _buildTableCell('UT Price', item.rate.toStringAsFixed(2), align: TextAlign.left),
                            )
                          else
                            Expanded(
                              flex: 3,
                              child: _buildTableCell('Pack / Unit', '1 CS = ${item.unitsPerCase} ${item.unit}', align: TextAlign.left),
                            ),
                          Expanded(
                            flex: 2,
                            child: _buildTableCell('CS', '${item.cases}', align: TextAlign.center, isBoldVal: true),
                          ),
                          Expanded(
                            flex: 2,
                            child: _buildTableCell('UT', '${item.units}', align: TextAlign.center, isBoldVal: true),
                          ),
                          if (item.totalWeightKg > 0)
                            Expanded(
                              flex: 2,
                              child: _buildTableCell('Kg', item.totalWeightKg.toStringAsFixed(2), align: TextAlign.right),
                            )
                          else
                            Expanded(
                              flex: 2,
                              child: _buildTableCell('Total', '${item.totalUnits}', align: TextAlign.right),
                            ),
                          if (item.subtotal > 0)
                            Expanded(
                              flex: 2,
                              child: _buildTableCell('Amount', item.subtotal.toStringAsFixed(2), align: TextAlign.right, isBoldVal: true),
                            ),
                        ],
                      ),

                      if (item.subtotal > 0) ...[
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                            Text(
                              item.subtotal.toStringAsFixed(2),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // Compact Bottom Total & Submit Footer (Zero vertical overflow even on 320px/keyboard screens)
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
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
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _totalAmount > 0 ? 'TOTAL AMOUNT:' : 'TOTAL ORDER:',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF16A34A)),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _totalAmount > 0
                              ? CurrencyFormatter.format(_totalAmount)
                              : '$_totalCases CS, $_totalUnits UT',
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Color(0xFF16A34A)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _bookingBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isSubmitting ? null : _submitOrder,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Submit Order', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTableCell(String header, String value, {TextAlign align = TextAlign.left, bool isBoldVal = false}) {
    final crossAlign = align == TextAlign.right
        ? CrossAxisAlignment.end
        : (align == TextAlign.center ? CrossAxisAlignment.center : CrossAxisAlignment.start);
    return Column(
      crossAxisAlignment: crossAlign,
      children: [
        Text(
          header,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isBoldVal ? FontWeight.w800 : FontWeight.w600,
              color: const Color(0xFF0F172A),
            ),
          ),
        ),
      ],
    );
  }

  void _showOrderItemEditDialog(OrderItem item) {
    final csCtrl = TextEditingController(text: '${item.cases}');
    final utCtrl = TextEditingController(text: '${item.units}');
    showDialog<void>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          item.productName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.rate > 0
                  ? '₹${item.rate.toStringAsFixed(2)}/UT  •  1 CS = ${item.unitsPerCase} UT'
                  : '1 CS = ${item.unitsPerCase} ${item.unit}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: csCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Cases (CS)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: utCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Units (UT)'),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dlgCtx);
              setState(() {
                _cart.remove(item.productId);
                _syncControllersForProduct(item.productId, 0, 0);
              });
            },
            child: const Text('Remove', style: TextStyle(color: AppTheme.balanceDueColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _bookingBlue, foregroundColor: Colors.white),
            onPressed: () {
              final newCs = (int.tryParse(csCtrl.text.trim()) ?? 0).clamp(0, 99999);
              final newUt = (int.tryParse(utCtrl.text.trim()) ?? 0).clamp(0, 99999);
              Navigator.pop(dlgCtx);
              setState(() {
                if (newCs == 0 && newUt == 0) {
                  _cart.remove(item.productId);
                } else {
                  final upc = item.unitsPerCase > 0 ? item.unitsPerCase : 1;
                  _cart[item.productId] = item.copyWith(
                    cases: newCs,
                    units: newUt,
                    quantity: (newCs * upc) + newUt,
                  );
                }
                _syncControllersForProduct(item.productId, newCs, newUt);
              });
            },
            child: const Text('Update'),
          ),
        ],
      ),
    ).then((_) {
      csCtrl.dispose();
      utCtrl.dispose();
    });
  }

  Widget _buildSummaryPill(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Color(0xFF0F172A))),
      ],
    );
  }
}
