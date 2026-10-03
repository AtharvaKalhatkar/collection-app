import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../models/order_model.dart';
import '../models/pending_bill_model.dart';
import '../models/route_model.dart';
import '../models/shop_model.dart';
import '../providers/collection_provider.dart';
import '../services/godown_billing_pdf_service.dart';
import '../services/order_catalog_service.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';
import '../widgets/add_product_dialog.dart';

class OrdersScreen extends StatefulWidget {
  final String? initialFirm;
  final String? initialRouteId;
  final String? initialShopId;

  const OrdersScreen({
    super.key,
    this.initialFirm,
    this.initialRouteId,
    this.initialShopId,
  });

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Dropdown Selections
  late String _selectedFirm;
  String? _selectedRouteId;
  String? _selectedShopId;
  late String _selectedCompany;
  String? _selectedCategory; // null = all in this company
  String? _quickSelectedProductId;

  // UI state
  bool _isHistoryExpanded = true;
  String _bookedOrdersFirmFilter = 'All';
  DateTime? _selectedOrderDate = DateTime.now();

  // Cart: Map of ProductId -> OrderItem
  final Map<String, OrderItem> _cart = {};

  final TextEditingController _notesController = TextEditingController();
  final Uuid _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedFirm = widget.initialFirm ?? OrderCatalogService.purva;
    _selectedRouteId = widget.initialRouteId;
    _selectedShopId = widget.initialShopId;

    _initCompanyAndCategory();
  }

  void _initCompanyAndCategory() {
    final companies = OrderCatalogService.getCompanies(_selectedFirm);
    _selectedCompany = companies.isNotEmpty ? companies.first : 'Wipro';
    _selectedCategory = null; // show all categories by default
    _quickSelectedProductId = null;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onFirmChanged(String firm) {
    if (_selectedFirm == firm) return;
    setState(() {
      _selectedFirm = firm;
      _initCompanyAndCategory();
    });
  }

  void _onCompanyChanged(String company) {
    if (_selectedCompany == company) return;
    setState(() {
      _selectedCompany = company;
      _selectedCategory = null;
      _quickSelectedProductId = null;
    });
  }

  void _onCategoryChanged(String? category) {
    setState(() {
      _selectedCategory = category;
      _quickSelectedProductId = null;
    });
  }

  // Cart Operations
  void _addProduct(CatalogProduct product, {int qtyToAdd = 1, String? unit}) {
    final chosenUnit = unit ?? product.defaultUnit;
    setState(() {
      if (_cart.containsKey(product.id)) {
        _cart[product.id]!.quantity += qtyToAdd;
      } else {
        _cart[product.id] = OrderItem(
          productId: product.id,
          productName: product.name,
          company: product.company,
          category: product.category,
          packing: product.packing,
          rate: product.rate,
          quantity: qtyToAdd,
          unit: chosenUnit,
        );
      }
    });
  }

  void _removeProduct(CatalogProduct product) {
    setState(() {
      if (_cart.containsKey(product.id)) {
        if (_cart[product.id]!.quantity > 1) {
          _cart[product.id]!.quantity -= 1;
        } else {
          _cart.remove(product.id);
        }
      }
    });
  }

  void _setQuantity(CatalogProduct product, int qty, {String? unit}) {
    setState(() {
      if (qty <= 0) {
        _cart.remove(product.id);
      } else {
        final chosenUnit = unit ?? (_cart[product.id]?.unit ?? product.defaultUnit);
        if (_cart.containsKey(product.id)) {
          _cart[product.id]!.quantity = qty;
          _cart[product.id] = _cart[product.id]!.copyWith(unit: chosenUnit);
        } else {
          _cart[product.id] = OrderItem(
            productId: product.id,
            productName: product.name,
            company: product.company,
            category: product.category,
            packing: product.packing,
            rate: product.rate,
            quantity: qty,
            unit: chosenUnit,
          );
        }
      }
    });
  }

  void _setProductUnit(String productId, String unit) {
    setState(() {
      if (_cart.containsKey(productId)) {
        _cart[productId] = _cart[productId]!.copyWith(unit: unit);
      }
    });
  }

  int _getItemQuantity(String productId) {
    return _cart[productId]?.quantity ?? 0;
  }

  String _getItemUnit(CatalogProduct product) {
    return _cart[product.id]?.unit ?? product.defaultUnit;
  }

  int get _totalCartQuantity {
    return _cart.values.fold(0, (sum, item) => sum + item.quantity);
  }

  double get _totalCartAmount {
    return _cart.values.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  void _clearCart() {
    setState(() {
      _cart.clear();
      _notesController.clear();
    });
  }

  // Quick repeat previous order items
  void _reorderPreviousOrder(SalesOrderModel pastOrder) {
    setState(() {
      for (final it in pastOrder.items) {
        if (_cart.containsKey(it.productId)) {
          _cart[it.productId]!.quantity += it.quantity;
        } else {
          _cart[it.productId] = it.copyWith();
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('Added ${pastOrder.items.length} items from previous order to cart!')),
          ],
        ),
        backgroundColor: AppTheme.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Open Add Product Dialog
  Future<void> _openAddProductDialog() async {
    final newProduct = await showDialog<CatalogProduct>(
      context: context,
      builder: (ctx) => AddProductDialog(
        initialFirm: _selectedFirm,
        initialCompany: _selectedCompany,
        initialCategory: _selectedCategory,
      ),
    );

    if (newProduct != null && mounted) {
      setState(() {
        _selectedFirm = newProduct.firm;
        _selectedCompany = newProduct.company;
        _selectedCategory = newProduct.category;
        _quickSelectedProductId = newProduct.id;
        _addProduct(newProduct, qtyToAdd: 1);
      });
    }
  }

  // Searchable Shop Picker Dialog (Alternative to Dropdown)
  void _openShopPicker(List<ShopModel> shops) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = shops.where((s) {
              if (query.isEmpty) return true;
              final q = query.toLowerCase();
              return s.name.toLowerCase().contains(q) ||
                  (s.ownerName?.toLowerCase().contains(q) ?? false) ||
                  s.mobileNumber.contains(q);
            }).toList();

            return Padding(
              padding: EdgeInsets.only(
                top: 16,
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Select Outlet / Shop',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search shop name, owner, or mobile...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onChanged: (val) => setModalState(() => query = val),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('No matching shops found.'))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (context, idx) {
                                final s = filtered[idx];
                                final isSelected = s.id == _selectedShopId;
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    s.name,
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                      color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${s.ownerName != null && s.ownerName!.isNotEmpty ? "${s.ownerName} • " : ""}${s.mobileNumber}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: isSelected ? const Icon(Icons.check_circle, color: AppTheme.primary) : null,
                                  onTap: () {
                                    setState(() => _selectedShopId = s.id);
                                    Navigator.pop(ctx);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Quantity Manual Input Dialog with Unit Selection
  void _showQtyInputDialog(CatalogProduct product, int currentQty) {
    final controller = TextEditingController(text: currentQty > 0 ? '$currentQty' : '1');
    String unit = _getItemUnit(product);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text('Quantity & Unit: ${product.name}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${product.packing} • Rate: ${CurrencyFormatter.format(product.rate)}',
                  style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 13)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Quantity',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: unit,
                      decoration: InputDecoration(
                        labelText: 'Unit',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      ),
                      items: OrderCatalogService.availableUnits
                          .map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontWeight: FontWeight.bold))))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setDlgState(() => unit = val);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              onPressed: () {
                final val = int.tryParse(controller.text.trim()) ?? 0;
                _setQuantity(product, val, unit: unit);
                Navigator.pop(ctx);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  // Review & Book Order Bottom Sheet
  void _openReviewOrderSheet(CollectionProvider provider) {
    if (_selectedRouteId == null || _selectedRouteId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a route first'), backgroundColor: AppTheme.error),
      );
      return;
    }
    if (_selectedShopId == null || _selectedShopId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an outlet / shop first'), backgroundColor: AppTheme.error),
      );
      return;
    }
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cart is empty. Please add products first.'), backgroundColor: AppTheme.error),
      );
      return;
    }

    final route = provider.routes.firstWhere(
      (r) => r.id == _selectedRouteId,
      orElse: () => RouteModel(id: '', name: 'Route'),
    );
    final shop = provider.shops.firstWhere(
      (s) => s.id == _selectedShopId,
      orElse: () => ShopModel(id: '', name: 'Shop', routeId: '', routeName: '', mobileNumber: '', address: ''),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  top: 16,
                  left: 16,
                  right: 16,
                  bottom: bottomInset > 0 ? bottomInset + 8 : 12,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Review Sales Order',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                              ),
                              Text(
                                'Salesman: ${provider.salesmanName} • ${DateFormat("dd MMM yyyy").format(DateTime.now())}',
                                style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Outlet & Firm Banner
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _selectedFirm == OrderCatalogService.purva
                              ? AppTheme.purvaPrimary.withValues(alpha: 0.08)
                              : AppTheme.manasPrimary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _selectedFirm == OrderCatalogService.purva
                                ? AppTheme.purvaPrimary.withValues(alpha: 0.25)
                                : AppTheme.manasPrimary.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.storefront,
                              size: 26,
                              color: _selectedFirm == OrderCatalogService.purva
                                  ? AppTheme.purvaPrimary
                                  : AppTheme.manasPrimary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    shop.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Route: ${route.name} • Firm: $_selectedFirm',
                                    style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade700),
                                  ),
                                  if (shop.mobileNumber.isNotEmpty)
                                    Text(
                                      'Mobile: ${shop.mobileNumber}${shop.ownerName != null ? " (${shop.ownerName})" : ""}',
                                      style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Items List Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'ORDER ITEMS (${_cart.length})',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.blueGrey),
                          ),
                          Text(
                            '$_totalCartQuantity units total',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.blueGrey.shade600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Items ListView
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _cart.values.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final item = _cart.values.elementAt(idx);
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.productName,
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                        ),
                                        Text(
                                          '${item.company} • ${item.packing} • ${CurrencyFormatter.format(item.rate)} / ${item.unit}',
                                          style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.blueGrey),
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                        padding: EdgeInsets.zero,
                                        onPressed: () {
                                          setSheetState(() {
                                            if (item.quantity > 1) {
                                              item.quantity--;
                                            } else {
                                              _cart.remove(item.productId);
                                            }
                                          });
                                          setState(() {});
                                        },
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        child: Text(
                                          '${item.quantity} ${item.unit}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline, size: 20, color: AppTheme.primary),
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                        padding: EdgeInsets.zero,
                                        onPressed: () {
                                          setSheetState(() {
                                            item.quantity++;
                                          });
                                          setState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      CurrencyFormatter.format(item.subtotal),
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 8),
                      // Remarks / Notes
                      TextField(
                        controller: _notesController,
                        decoration: InputDecoration(
                          hintText: 'Order notes / delivery instructions...',
                          prefixIcon: const Icon(Icons.note_alt_outlined, size: 18),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Total & Book Button
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$_totalCartQuantity UNITS TOTAL',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade600),
                                  ),
                                  Text(
                                    CurrencyFormatter.format(_totalCartAmount),
                                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.check_circle, size: 18),
                              label: const Text('Confirm & Book', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                              onPressed: () async {
                                final order = SalesOrderModel(
                                  id: _uuid.v4(),
                                  orderNumber: 'ORD-${DateFormat("yyMMdd").format(DateTime.now())}-${(1000 + provider.salesOrders.length + 1)}',
                                  firm: _selectedFirm,
                                  routeId: route.id,
                                  routeName: route.name,
                                  shopId: shop.id,
                                  shopName: shop.name,
                                  shopMobile: shop.mobileNumber,
                                  salesmanName: provider.salesmanName,
                                  orderDate: DateTime.now(),
                                  items: _cart.values.map((i) => i.copyWith()).toList(),
                                  totalAmount: _totalCartAmount,
                                  totalQuantity: _totalCartQuantity,
                                  notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
                                );

                                await provider.addSalesOrder(order);

                                if (ctx.mounted) {
                                  Navigator.pop(ctx);
                                }
                                if (mounted) {
                                  _clearCart();
                                  _showOrderSuccessDialog(order, provider);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Order Placed Success Dialog - Share to Godown/Billing
  void _showOrderSuccessDialog(SalesOrderModel order, CollectionProvider provider) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          children: [
            const CircleAvatar(
              radius: 28,
              backgroundColor: Color(0xFF10B981),
              child: Icon(Icons.check, size: 32, color: Colors.white),
            ),
            const SizedBox(height: 12),
            const Text('Order Booked!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              order.orderNumber,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blueGrey.shade600),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDialogRow('Outlet:', order.shopName),
            _buildDialogRow('Route:', order.routeName),
            _buildDialogRow('Firm:', order.firm),
            _buildDialogRow('Items:', '${order.items.length} items (${order.totalQuantity} units)'),
            _buildDialogRow('Total Value:', CurrencyFormatter.format(order.totalAmount), isBold: true),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warehouse_rounded, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ready for Godown Picking & Billing staff dispatch.',
                      style: TextStyle(fontSize: 11.5, color: Colors.blue, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          OutlinedButton.icon(
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 16, color: AppTheme.primary),
            label: const Text('Godown Slip (PDF)'),
            onPressed: () {
              GodownBillingPdfService.previewOrSharePdf(
                context,
                orders: [order],
                salesmanName: provider.salesmanName,
                firmFilter: order.firm,
                reportDate: order.orderDate,
              );
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.chat, size: 16, color: Color(0xFF25D366)),
            label: const Text('WhatsApp to Staff'),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF25D366)),
              foregroundColor: const Color(0xFF25D366),
            ),
            onPressed: () {
              _shareGodownOrderOnWhatsApp(order);
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () {
              Navigator.pop(ctx);
              _tabController.animateTo(1);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12.5, color: Colors.blueGrey.shade600)),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: isBold ? const Color(0xFF0F172A) : Colors.blueGrey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  // Format message tailored for Godown and Billing staff with date first
  String _formatGodownWhatsAppMessage(SalesOrderModel order) {
    final buffer = StringBuffer();
    buffer.writeln('📅 *DATE: ${DateFormat("dd-MMM-yyyy, hh:mm a").format(order.orderDate)}*');
    buffer.writeln('📦 *ORDER: ${order.orderNumber}* (${order.firm})');
    buffer.writeln('🏪 *OUTLET: ${order.shopName}*');
    buffer.writeln('📍 *ROUTE: ${order.routeName}*');
    buffer.writeln('👤 *Salesman:* ${order.salesmanName}');
    buffer.writeln('----------------------------------------');
    buffer.writeln('📋 *ITEMS TO BILL & DISPATCH:*');
    for (int i = 0; i < order.items.length; i++) {
      final it = order.items[i];
      buffer.writeln('${i + 1}. *${it.productName}* (${it.packing})');
      buffer.writeln('   👉 Qty: *${it.quantity} ${it.unit}* @ ${CurrencyFormatter.format(it.rate)} = ${CurrencyFormatter.format(it.subtotal)}');
    }
    buffer.writeln('----------------------------------------');
    buffer.writeln('*TOTAL UNITS:* ${order.totalQuantity}');
    buffer.writeln('*EST. INVOICE AMOUNT:* ${CurrencyFormatter.format(order.totalAmount)}');
    if (order.notes != null && order.notes!.isNotEmpty) {
      buffer.writeln('📝 Special Instructions: *${order.notes}*');
    }
    buffer.writeln('----------------------------------------');
    buffer.writeln('_Generated via Daily Collection Pro - Orders Dispatch_');
    return buffer.toString().trim();
  }

  Future<void> _shareGodownOrderOnWhatsApp(SalesOrderModel order) async {
    final text = _formatGodownWhatsAppMessage(order);
    final whatsappUrl = Uri.parse(
      'https://api.whatsapp.com/send?text=${Uri.encodeComponent(text)}',
    );

    try {
      final launched = await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
      if (!launched) {
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order dispatch details copied to clipboard! Paste in WhatsApp.')),
          );
        }
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order dispatch details copied to clipboard! Paste in WhatsApp.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<CollectionProvider>(context);
    final routes = provider.routes;

    // Default route selection if not set
    if (_selectedRouteId == null && routes.isNotEmpty) {
      _selectedRouteId = routes.first.id;
    }

    final shopsOnRoute = _selectedRouteId != null
        ? provider.shops.where((s) => s.routeId == _selectedRouteId).toList()
        : <ShopModel>[];

    // Default shop selection if not set or invalid for route
    if (_selectedShopId == null && shopsOnRoute.isNotEmpty) {
      _selectedShopId = shopsOnRoute.first.id;
    } else if (_selectedShopId != null && !shopsOnRoute.any((s) => s.id == _selectedShopId)) {
      _selectedShopId = shopsOnRoute.isNotEmpty ? shopsOnRoute.first.id : null;
    }

    final companies = OrderCatalogService.getCompanies(_selectedFirm);
    if (!companies.contains(_selectedCompany) && companies.isNotEmpty) {
      _selectedCompany = companies.first;
    }

    final categories = OrderCatalogService.getCategories(_selectedFirm, _selectedCompany);
    if (_selectedCategory != null && !categories.contains(_selectedCategory)) {
      _selectedCategory = null;
    }

    final products = OrderCatalogService.getProducts(
      firm: _selectedFirm,
      company: _selectedCompany,
      category: _selectedCategory,
    );

    // Customer previous 3 orders history
    final previousOrders = _selectedShopId != null
        ? provider.getPreviousOrdersForShop(_selectedShopId!, limit: 3)
        : <SalesOrderModel>[];

    final previousBills = _selectedShopId != null
        ? provider.getPreviousBillsForShop(_selectedShopId!, limit: 3)
        : <PendingBillModel>[];

    return PopScope(
      canPop: _tabController.index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _tabController.index != 0) {
          _tabController.animateTo(0);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text('Orders & Billing'),
          leading: Navigator.canPop(context)
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    if (_tabController.index != 0) {
                      _tabController.animateTo(0);
                    } else {
                      Navigator.pop(context);
                    }
                  },
                )
              : null,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 18),
            label: const Text('Add SKU', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            onPressed: _openAddProductDialog,
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            const Tab(
              icon: Icon(Icons.edit_note_outlined, size: 20),
              text: 'Take Order',
            ),
            Tab(
              icon: Badge(
                label: Text('${provider.salesOrders.length}'),
                isLabelVisible: provider.salesOrders.isNotEmpty,
                child: const Icon(Icons.receipt_long_outlined, size: 20),
              ),
              text: 'Booked Orders',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: TAKE ORDER
          Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    // MASTER DROPDOWN CONTROLS CARD
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. FIRM DROPDOWN
                          const Text('1. Distributing Firm', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppTheme.textSecondary)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: _selectedFirm,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.business_rounded, color: AppTheme.primary, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            items: const [
                              DropdownMenuItem(value: OrderCatalogService.purva, child: Text('Purva Enterprises')),
                              DropdownMenuItem(value: OrderCatalogService.manas, child: Text('Manas Sales')),
                            ],
                            onChanged: (val) {
                              if (val != null) _onFirmChanged(val);
                            },
                          ),
                          const SizedBox(height: 12),

                          // 2. ROUTE DROPDOWN
                          const Text('2. Route Beat', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppTheme.textSecondary)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: routes.any((r) => r.id == _selectedRouteId) ? _selectedRouteId : null,
                            hint: const Text('Select Route Beat'),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.alt_route_rounded, color: AppTheme.primary, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            items: routes.map((r) {
                              final count = provider.getShopsForRoute(r.id).length;
                              return DropdownMenuItem<String>(
                                value: r.id,
                                child: Text('${r.priority}. ${r.name} ($count shops)', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() {
                                _selectedRouteId = val;
                                _selectedShopId = null;
                              });
                            },
                          ),
                          const SizedBox(height: 12),

                          // 3. OUTLET / SHOP DROPDOWN
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('3. Customer / Outlet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppTheme.textSecondary)),
                              if (shopsOnRoute.isNotEmpty)
                                InkWell(
                                  onTap: () => _openShopPicker(shopsOnRoute),
                                  child: const Text('🔍 Search Shop', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: shopsOnRoute.any((s) => s.id == _selectedShopId) ? _selectedShopId : null,
                            hint: Text(shopsOnRoute.isEmpty ? 'No shops on this route' : 'Select Customer / Outlet'),
                            isExpanded: true,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.storefront_rounded, color: Color(0xFF10B981), size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            items: shopsOnRoute.map((s) {
                              return DropdownMenuItem<String>(
                                value: s.id,
                                child: Text(
                                  '${s.name}${s.ownerName != null && s.ownerName!.isNotEmpty ? " (${s.ownerName})" : ""}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() => _selectedShopId = val);
                            },
                          ),

                          // CUSTOMER'S PREVIOUS 3 ORDERS / BILLS HISTORY CARD
                          if (_selectedShopId != null && (previousOrders.isNotEmpty || previousBills.isNotEmpty)) ...[
                            const SizedBox(height: 12),
                            _buildCustomerHistoryCard(previousOrders, previousBills),
                          ],

                          const Divider(height: 24),

                          // 4. COMPANY DROPDOWN
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('4. Company / Brand', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppTheme.textSecondary)),
                              Text('${companies.length} Companies', style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade600)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: companies.contains(_selectedCompany) ? _selectedCompany : null,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.apartment_rounded, color: AppTheme.primary, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            items: companies.map((c) {
                              final count = _cart.values.where((i) => i.company.toLowerCase() == c.toLowerCase()).fold(0, (s, i) => s + i.quantity);
                              return DropdownMenuItem(
                                value: c,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(c, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                    if (count > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primary,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text('$count in cart', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) _onCompanyChanged(val);
                            },
                          ),
                          const SizedBox(height: 12),

                          // 5. CATEGORY DROPDOWN
                          if (categories.isNotEmpty) ...[
                            const Text('5. Category', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppTheme.textSecondary)),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String?>(
                              value: _selectedCategory,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.category_rounded, color: AppTheme.primary, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('All Categories (सर्व कॅटेगरीज)', style: TextStyle(fontWeight: FontWeight.w600)),
                                ),
                                ...categories.map(
                                  (cat) => DropdownMenuItem<String?>(
                                    value: cat,
                                    child: Text(cat, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  ),
                                ),
                              ],
                              onChanged: (val) => _onCategoryChanged(val),
                            ),
                            const SizedBox(height: 12),
                          ],

                          // 6. QUICK PRODUCT DROPDOWN SELECTOR
                          if (products.isNotEmpty) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('6. Quick SKU Select (उत्पादन निवडा)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppTheme.textSecondary)),
                                Text('${products.length} Products', style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade600)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              value: products.any((p) => p.id == _quickSelectedProductId) ? _quickSelectedProductId : null,
                              hint: const Text('Pick a product to add directly...'),
                              isExpanded: true,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.shopping_bag_outlined, color: AppTheme.primary, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              items: products.map((p) {
                                return DropdownMenuItem<String>(
                                  value: p.id,
                                  child: Text(
                                    '${p.name} (${p.packing}) - ${CurrencyFormatter.format(p.rate)}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                );
                              }).toList(),
                              onChanged: (prodId) {
                                if (prodId != null) {
                                  final p = products.firstWhere((item) => item.id == prodId);
                                  setState(() => _quickSelectedProductId = prodId);
                                  _addProduct(p, qtyToAdd: 1);
                                }
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // PRODUCTS LIST HEADER
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'PRODUCTS CATALOG (${products.length})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Colors.blueGrey),
                        ),
                        Row(
                          children: [
                            InkWell(
                              onTap: _openAddProductDialog,
                              child: const Text(
                                '+ Add SKU',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                              ),
                            ),
                            if (_cart.isNotEmpty) ...[
                              const SizedBox(width: 12),
                              InkWell(
                                onTap: _clearCart,
                                child: const Text(
                                  'Clear Cart',
                                  style: TextStyle(fontSize: 12, color: AppTheme.error, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // PRODUCTS LIST
                    if (products.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          children: [
                            const Icon(Icons.inventory_2_outlined, size: 36, color: Colors.blueGrey),
                            const SizedBox(height: 8),
                            Text('No products found under this category.', style: TextStyle(color: Colors.blueGrey.shade700)),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _openAddProductDialog,
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add New Product to Catalog'),
                            ),
                          ],
                        ),
                      )
                    else
                      ...products.map((prod) {
                        final qty = _getItemQuantity(prod.id);
                        final unit = _getItemUnit(prod);
                        return _buildProductCard(prod, qty, unit);
                      }),

                    const SizedBox(height: 90), // Bottom padding for sticky cart bar
                  ],
                ),
              ),

              // STICKY BOTTOM CART BAR
              if (_totalCartQuantity > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        offset: const Offset(0, -3),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${_cart.length} SKUs • $_totalCartQuantity units',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blueGrey.shade600),
                            ),
                            Text(
                              CurrencyFormatter.format(_totalCartAmount),
                              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                          label: const Text('Review Order', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          onPressed: () => _openReviewOrderSheet(provider),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          // TAB 2: BOOKED ORDERS HISTORY
          _buildBookedOrdersTab(provider),
        ],
      ),
    ),
  );
}

  // Customer Previous 3 Orders & Bills History Card
  Widget _buildCustomerHistoryCard(List<SalesOrderModel> orders, List<PendingBillModel> bills) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _isHistoryExpanded = !_isHistoryExpanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.history_rounded, size: 18, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Customer Previous Purchases (मागील ऑर्डर्स व बिले)',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${orders.isNotEmpty ? orders.length : bills.length} past records',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.primary),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(_isHistoryExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 20, color: Colors.blueGrey),
                ],
              ),
            ),
          ),
          if (_isHistoryExpanded) ...[
            const Divider(height: 1),
            if (orders.isNotEmpty)
              ...orders.map((past) {
                return Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${past.orderNumber} • ${DateFormat("dd MMM yyyy").format(past.orderDate)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F172A)),
                          ),
                          Row(
                            children: [
                              Text(
                                CurrencyFormatter.format(past.totalAmount),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Color(0xFF10B981)),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => _reorderPreviousOrder(past),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('Re-order', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        past.items.map((i) => '${i.productName} (${i.quantity} ${i.unit})').join(', '),
                        style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade700),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Divider(height: 12),
                    ],
                  ),
                );
              })
            else if (bills.isNotEmpty)
              ...bills.map((bill) {
                return Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Bill: ${bill.billNumber}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          Text(DateFormat("dd MMM yyyy").format(bill.billDate), style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600)),
                        ],
                      ),
                      Text(CurrencyFormatter.format(bill.billAmount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF10B981))),
                    ],
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }

  // Individual Product Card with Unit and Stepper
  Widget _buildProductCard(CatalogProduct product, int qty, String currentUnit) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: qty > 0 ? AppTheme.primary.withValues(alpha: 0.5) : AppTheme.border,
          width: qty > 0 ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Product Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${product.company} • ${product.category} • ${product.packing}',
                      style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          CurrencyFormatter.format(product.rate),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: Color(0xFF10B981)),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'MRP ${CurrencyFormatter.format(product.mrp)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.blueGrey.shade400,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Unit Selector Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: currentUnit,
                    isDense: true,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    items: OrderCatalogService.availableUnits
                        .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        _setProductUnit(product.id, val);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Stepper / Quick Add
              if (qty == 0)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('ADD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () => _addProduct(product, unit: currentUnit),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove, size: 18, color: AppTheme.primary),
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            padding: EdgeInsets.zero,
                            onPressed: () => _removeProduct(product),
                          ),
                          InkWell(
                            onTap: () => _showQtyInputDialog(product, qty),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                '$qty $currentUnit',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primary),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add, size: 18, color: AppTheme.primary),
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            padding: EdgeInsets.zero,
                            onPressed: () => _addProduct(product, unit: currentUnit),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Quick +6 / +12 box buttons
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () => _addProduct(product, qtyToAdd: 6, unit: currentUnit),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: const Text('+6', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        InkWell(
                          onTap: () => _addProduct(product, qtyToAdd: 12, unit: currentUnit),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: const Text('+12', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  // TAB 2: Booked Orders Tab with Consolidated Godown Billing PDF Sharing
  Widget _buildBookedOrdersTab(CollectionProvider provider) {
    final allOrders = provider.salesOrders;
    final orders = allOrders.where((o) {
      if (_bookedOrdersFirmFilter != 'All' && o.firm != _bookedOrdersFirmFilter) {
        return false;
      }
      if (_selectedOrderDate != null) {
        final sameDay = o.orderDate.year == _selectedOrderDate!.year &&
            o.orderDate.month == _selectedOrderDate!.month &&
            o.orderDate.day == _selectedOrderDate!.day;
        if (!sameDay) return false;
      }
      return true;
    }).toList();

    final totalAmount = orders.fold<double>(0.0, (s, o) => s + o.totalAmount);
    final totalUnits = orders.fold<int>(0, (s, o) => s + o.totalQuantity);

    if (allOrders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.receipt_long_outlined, size: 36, color: AppTheme.primary),
              ),
              const SizedBox(height: 16),
              const Text(
                'No Orders Booked Yet',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 6),
              Text(
                'Switch to "Take Order" tab to book orders from your outlets.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade600),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Start Taking Orders'),
                onPressed: () => _tabController.animateTo(0),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // ORDERS DISPATCH ACTION BANNER
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1E3A8A).withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ORDERS DISPATCH',
                        style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${orders.length} Orders • $totalUnits Units',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Text(
                    CurrencyFormatter.format(totalAmount),
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1E3A8A),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 2,
                ),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 20, color: Color(0xFFDC2626)),
                label: const Text(
                  'Share Orders PDF',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                ),
                onPressed: () {
                  GodownBillingPdfService.previewOrSharePdf(
                    context,
                    orders: orders,
                    salesmanName: provider.salesmanName,
                    firmFilter: _bookedOrdersFirmFilter,
                    reportDate: _selectedOrderDate ?? DateTime.now(),
                  );
                },
              ),
            ],
          ),
        ),

        // FIRM & DATE FILTER CARD
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: [
              // Row 1: Firm Filter
              Row(
                children: [
                  const Text('Firm: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _bookedOrdersFirmFilter,
                          isExpanded: true,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                          items: const [
                            DropdownMenuItem(value: 'All', child: Text('All Businesses (Purva & Manas)')),
                            DropdownMenuItem(value: OrderCatalogService.purva, child: Text('Purva Enterprises')),
                            DropdownMenuItem(value: OrderCatalogService.manas, child: Text('Manas Sales')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _bookedOrdersFirmFilter = val);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Row 2: Date Filter
              Row(
                children: [
                  const Text('Date: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedOrderDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                          helpText: 'SELECT ORDER DATE',
                        );
                        if (picked != null) {
                          setState(() => _selectedOrderDate = picked);
                        }
                      },
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.calendar_month_outlined, size: 16, color: AppTheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  _selectedOrderDate != null
                                      ? DateFormat('dd MMM yyyy').format(_selectedOrderDate!)
                                      : 'All Dates (सर्व तारखा)',
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const Icon(Icons.arrow_drop_down, color: Colors.blueGrey, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (_selectedOrderDate != null)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        minimumSize: const Size(0, 36),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => setState(() => _selectedOrderDate = null),
                      child: const Text('All', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    )
                  else
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        minimumSize: const Size(0, 36),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => setState(() => _selectedOrderDate = DateTime.now()),
                      child: const Text('Today', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ORDERS LIST
        Expanded(
          child: orders.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.search_off_rounded, size: 44, color: Colors.blueGrey),
                        const SizedBox(height: 10),
                        const Text(
                          'No orders match this date / firm filter',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Try selecting a different date or showing all dates.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _selectedOrderDate = null;
                              _bookedOrdersFirmFilter = 'All';
                            });
                          },
                          child: const Text('Clear Filters (सर्व दाखवा)'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  itemCount: orders.length,
                  itemBuilder: (context, idx) {
              final order = orders[idx];
              final isPurva = order.firm == OrderCatalogService.purva;

              return Card(
                elevation: 1.5,
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Row: Order # and Firm Badge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            order.orderNumber,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isPurva ? AppTheme.purvaPrimary.withValues(alpha: 0.12) : AppTheme.manasPrimary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isPurva ? 'Purva' : 'Manas',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isPurva ? AppTheme.purvaPrimary : AppTheme.manasPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Shop & Route
                      Text(
                        order.shopName,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                      ),
                      Text(
                        'Route: ${order.routeName} • ${DateFormat("dd MMM yyyy, hh:mm a").format(order.orderDate)}',
                        style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade600),
                      ),
                      const Divider(height: 14),

                      // Items preview
                      Text(
                        '${order.items.map((i) => "${i.productName} (${i.quantity} ${i.unit})").take(3).join(', ')}${order.items.length > 3 ? " +${order.items.length - 3} more" : ""}',
                        style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade800),
                      ),
                      const SizedBox(height: 8),

                      // Bottom row: Total amount & Actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${order.totalQuantity} units • ${CurrencyFormatter.format(order.totalAmount)}',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: Color(0xFF10B981)),
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf_rounded, size: 20, color: Color(0xFFDC2626)),
                                tooltip: 'Godown Slip PDF',
                                onPressed: () {
                                  GodownBillingPdfService.previewOrSharePdf(
                                    context,
                                    orders: [order],
                                    salesmanName: provider.salesmanName,
                                    firmFilter: order.firm,
                                    reportDate: order.orderDate,
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.chat, size: 20, color: Color(0xFF25D366)),
                                tooltip: 'WhatsApp to Staff',
                                onPressed: () => _shareGodownOrderOnWhatsApp(order),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.blueGrey),
                                tooltip: 'Delete Order',
                                onPressed: () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Delete Order?'),
                                      content: Text('Are you sure you want to delete order ${order.orderNumber}?'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok == true) {
                                    await provider.deleteSalesOrder(order.id);
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
