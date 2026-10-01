import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../models/order_model.dart';
import '../models/route_model.dart';
import '../models/shop_model.dart';
import '../providers/collection_provider.dart';
import '../services/order_catalog_service.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';

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

  // Order Header Selection
  late String _selectedFirm;
  String? _selectedRouteId;
  String? _selectedShopId;

  // Catalog Navigation
  late String _selectedCompany;
  String? _selectedCategory; // null = all in this company

  // Cart / In-Progress Order: Map of ProductId -> OrderItem
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

    final initialCompanies = OrderCatalogService.getCompanies(_selectedFirm);
    _selectedCompany = initialCompanies.isNotEmpty ? initialCompanies.first : 'Wipro';

    final categories = OrderCatalogService.getCategories(_selectedFirm, _selectedCompany);
    _selectedCategory = categories.isNotEmpty ? categories.first : null;
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
      final companies = OrderCatalogService.getCompanies(firm);
      _selectedCompany = companies.isNotEmpty ? companies.first : '';
      final categories = OrderCatalogService.getCategories(_selectedFirm, _selectedCompany);
      _selectedCategory = categories.isNotEmpty ? categories.first : null;
    });
  }

  void _onCompanyChanged(String company) {
    if (_selectedCompany == company) return;
    setState(() {
      _selectedCompany = company;
      final categories = OrderCatalogService.getCategories(_selectedFirm, _selectedCompany);
      _selectedCategory = categories.isNotEmpty ? categories.first : null;
    });
  }

  void _onCategoryChanged(String? category) {
    setState(() {
      _selectedCategory = category;
    });
  }

  // Cart Operations
  void _addProduct(CatalogProduct product, {int qtyToAdd = 1}) {
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

  void _setQuantity(CatalogProduct product, int qty) {
    setState(() {
      if (qty <= 0) {
        _cart.remove(product.id);
      } else {
        if (_cart.containsKey(product.id)) {
          _cart[product.id]!.quantity = qty;
        } else {
          _cart[product.id] = OrderItem(
            productId: product.id,
            productName: product.name,
            company: product.company,
            category: product.category,
            packing: product.packing,
            rate: product.rate,
            quantity: qty,
          );
        }
      }
    });
  }

  int _getItemQuantity(String productId) {
    return _cart[productId]?.quantity ?? 0;
  }

  int get _totalCartQuantity {
    return _cart.values.fold(0, (sum, item) => sum + item.quantity);
  }

  double get _totalCartAmount {
    return _cart.values.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  int _getCartCountForCompany(String company) {
    return _cart.values.where((i) => i.company.toLowerCase() == company.toLowerCase()).fold(0, (s, i) => s + i.quantity);
  }

  void _clearCart() {
    setState(() {
      _cart.clear();
      _notesController.clear();
    });
  }

  // Searchable Shop Picker Bottom Sheet
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Select Outlet / Store',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Search by shop name, owner or mobile...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onChanged: (val) {
                        setModalState(() => query = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                query.isEmpty ? 'No outlets found on this route' : 'No matches for "$query"',
                                style: TextStyle(color: Colors.blueGrey.shade600),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (context, idx) {
                                final s = filtered[idx];
                                final isSelected = s.id == _selectedShopId;
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  leading: CircleAvatar(
                                    backgroundColor: isSelected ? AppTheme.primary : Colors.grey.shade200,
                                    foregroundColor: isSelected ? Colors.white : Colors.blueGrey.shade800,
                                    child: Text(s.name.isNotEmpty ? s.name[0].toUpperCase() : 'S'),
                                  ),
                                  title: Text(
                                    s.name,
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                      color: isSelected ? AppTheme.primary : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${s.ownerName != null && s.ownerName!.isNotEmpty ? "${s.ownerName} • " : ""}${s.mobileNumber} • ${s.address}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                                  ),
                                  trailing: isSelected
                                      ? const Icon(Icons.check_circle, color: AppTheme.primary)
                                      : null,
                                  onTap: () {
                                    setState(() {
                                      _selectedShopId = s.id;
                                    });
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

  // Quantity Manual Input Dialog
  void _showQtyInputDialog(CatalogProduct product, int currentQty) {
    final controller = TextEditingController(text: currentQty > 0 ? '$currentQty' : '1');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Quantity for ${product.name}', style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${product.packing} • Rate: ${CurrencyFormatter.format(product.rate)}',
                style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Quantity (Pieces)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
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
              _setQuantity(product, val);
              Navigator.pop(ctx);
            },
            child: const Text('Apply'),
          ),
        ],
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
            return Padding(
              padding: EdgeInsets.only(
                top: 18,
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.85,
                child: Column(
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
                    const SizedBox(height: 12),

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
                            size: 28,
                            color: _selectedFirm == OrderCatalogService.purva
                                ? AppTheme.purvaPrimary
                                : AppTheme.manasPrimary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  shop.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Route: ${route.name} • Firm: $_selectedFirm',
                                  style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700),
                                ),
                                if (shop.mobileNumber.isNotEmpty)
                                  Text(
                                    'Mobile: ${shop.mobileNumber}${shop.ownerName != null ? " (${shop.ownerName})" : ""}',
                                    style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade600),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Items List Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'ITEMS (${_cart.length})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.blueGrey),
                        ),
                        Text(
                          '$_totalCartQuantity pcs total',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blueGrey.shade600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Items ListView
                    Expanded(
                      child: ListView.separated(
                        itemCount: _cart.values.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final item = _cart.values.elementAt(idx);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.productName,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                                      ),
                                      Text(
                                        '${item.company} • ${item.packing} • ${CurrencyFormatter.format(item.rate)} / pc',
                                        style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.blueGrey),
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
                                    Text(
                                      '${item.quantity}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline, size: 20, color: AppTheme.primary),
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
                                  width: 75,
                                  child: Text(
                                    CurrencyFormatter.format(item.subtotal),
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 10),
                    // Remarks / Notes
                    TextField(
                      controller: _notesController,
                      decoration: InputDecoration(
                        hintText: 'Order notes / delivery instructions (optional)...',
                        prefixIcon: const Icon(Icons.note_alt_outlined, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Total & Book Button
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TOTAL ORDER AMOUNT',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade600),
                              ),
                              Text(
                                CurrencyFormatter.format(_totalCartAmount),
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                              ),
                            ],
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.check_circle, size: 18),
                            label: const Text('Confirm & Book Order', style: TextStyle(fontWeight: FontWeight.bold)),
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
                                _showOrderSuccessDialog(order);
                              }
                            },
                          ),
                        ],
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

  // Order Placed Success Dialog
  void _showOrderSuccessDialog(SalesOrderModel order) {
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
            _buildDialogRow('Items:', '${order.items.length} items (${order.totalQuantity} pcs)'),
            _buildDialogRow('Total Value:', CurrencyFormatter.format(order.totalAmount), isBold: true),
          ],
        ),
        actions: [
          OutlinedButton.icon(
            icon: const Icon(Icons.chat, size: 16, color: Color(0xFF25D366)),
            label: const Text('Share on WhatsApp'),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF25D366)),
              foregroundColor: const Color(0xFF25D366),
            ),
            onPressed: () {
              _shareOrderOnWhatsApp(order);
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () {
              Navigator.pop(ctx);
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

  String _formatWhatsAppMessage(SalesOrderModel order) {
    final buffer = StringBuffer();
    buffer.writeln('*SALES ORDER: ${order.orderNumber}*');
    buffer.writeln('Firm: ${order.firm}');
    buffer.writeln('Outlet: ${order.shopName}');
    buffer.writeln('Route: ${order.routeName}');
    buffer.writeln('Date: ${DateFormat("dd-MMM-yyyy hh:mm a").format(order.orderDate)}');
    buffer.writeln('Salesman: ${order.salesmanName}');
    buffer.writeln('----------------------------------------');
    for (int i = 0; i < order.items.length; i++) {
      final it = order.items[i];
      buffer.writeln('${i + 1}. ${it.productName} (${it.packing})');
      buffer.writeln('   Qty: ${it.quantity} x ${CurrencyFormatter.format(it.rate)} = ${CurrencyFormatter.format(it.subtotal)}');
    }
    buffer.writeln('----------------------------------------');
    buffer.writeln('*TOTAL PCS:* ${order.totalQuantity}');
    buffer.writeln('*TOTAL VALUE:* ${CurrencyFormatter.format(order.totalAmount)}');
    if (order.notes != null && order.notes!.isNotEmpty) {
      buffer.writeln('Note: ${order.notes}');
    }
    buffer.writeln('----------------------------------------');
    buffer.writeln('_Order booked via Daily Collection & Orders App_');
    return buffer.toString().trim();
  }

  Future<void> _shareOrderOnWhatsApp(SalesOrderModel order) async {
    final text = _formatWhatsAppMessage(order);
    final cleanPhone = order.shopMobile.replaceAll(RegExp(r'[^0-9]'), '');
    final formattedPhone = cleanPhone.length == 10 ? '91$cleanPhone' : cleanPhone;

    final whatsappUrl = Uri.parse(
      'https://api.whatsapp.com/send?phone=$formattedPhone&text=${Uri.encodeComponent(text)}',
    );

    try {
      final launched = await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
      if (!launched) {
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order copied to clipboard! Paste in WhatsApp.')),
          );
        }
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order copied to clipboard! Paste in WhatsApp.')),
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

    final selectedShop = shopsOnRoute.firstWhere(
      (s) => s.id == _selectedShopId,
      orElse: () => ShopModel(id: '', name: 'Select Outlet', routeId: '', routeName: '', mobileNumber: '', address: ''),
    );

    final companies = OrderCatalogService.getCompanies(_selectedFirm);
    final categories = OrderCatalogService.getCategories(_selectedFirm, _selectedCompany);
    final products = OrderCatalogService.getProducts(
      firm: _selectedFirm,
      company: _selectedCompany,
      category: _selectedCategory,
    );

    final isPurva = _selectedFirm == OrderCatalogService.purva;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Sales Orders'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
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
                    // 1. FIRM SELECTION (Purva Enterprises vs Manas Sales)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _onFirmChanged(OrderCatalogService.purva),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 9),
                                decoration: BoxDecoration(
                                  color: isPurva ? AppTheme.purvaPrimary : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    'Purva Enterprises',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isPurva ? Colors.white : AppTheme.purvaText,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: InkWell(
                              onTap: () => _onFirmChanged(OrderCatalogService.manas),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 9),
                                decoration: BoxDecoration(
                                  color: !isPurva ? AppTheme.manasPrimary : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    'Manas Sales',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: !isPurva ? Colors.white : AppTheme.manasText,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 2. ROUTE & OUTLET SELECTOR CARD
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Route Selector
                          Row(
                            children: [
                              const Icon(Icons.alt_route, size: 18, color: AppTheme.primary),
                              const SizedBox(width: 8),
                              const Text(
                                'Route Beat:',
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    isExpanded: true,
                                    value: _selectedRouteId,
                                    hint: const Text('Choose Route'),
                                    items: routes.map((r) {
                                      final count = provider.getShopsForRoute(r.id).length;
                                      return DropdownMenuItem<String>(
                                        value: r.id,
                                        child: Text(
                                          '${r.name} ($count shops)',
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      setState(() {
                                        _selectedRouteId = val;
                                        _selectedShopId = null;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 14),

                          // Outlet Selector
                          InkWell(
                            onTap: () => _openShopPicker(shopsOnRoute),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  const Icon(Icons.storefront, size: 18, color: Color(0xFF10B981)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          selectedShop.name.isNotEmpty ? selectedShop.name : 'Select Outlet / Shop',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                        ),
                                        if (selectedShop.mobileNumber.isNotEmpty)
                                          Text(
                                            '${selectedShop.ownerName != null ? "${selectedShop.ownerName} • " : ""}${selectedShop.mobileNumber}',
                                            style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade600),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.arrow_drop_down, color: Colors.blueGrey),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 3. COMPANY SELECTOR
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'SELECT COMPANY',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Colors.blueGrey),
                        ),
                        Text(
                          '${companies.length} Companies',
                          style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 42,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: companies.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, idx) {
                          final comp = companies[idx];
                          final isSelected = comp.toLowerCase() == _selectedCompany.toLowerCase();
                          final inCartCount = _getCartCountForCompany(comp);

                          return ChoiceChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(comp, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, fontSize: 13)),
                                if (inCartCount > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.white : AppTheme.primary,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$inCartCount',
                                      style: TextStyle(
                                        color: isSelected ? AppTheme.primary : Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            selected: isSelected,
                            selectedColor: isPurva ? AppTheme.purvaPrimary : AppTheme.manasPrimary,
                            labelStyle: TextStyle(color: isSelected ? Colors.white : const Color(0xFF0F172A)),
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: isSelected
                                  ? (isPurva ? AppTheme.purvaPrimary : AppTheme.manasPrimary)
                                  : AppTheme.border,
                            ),
                            onSelected: (_) => _onCompanyChanged(comp),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 4. CATEGORY SELECTOR
                    if (categories.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'CATEGORIES IN $_selectedCompany'.toUpperCase(),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Colors.blueGrey),
                          ),
                          InkWell(
                            onTap: () => _onCategoryChanged(null),
                            child: Text(
                              'View All',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _selectedCategory == null ? AppTheme.primary : Colors.blueGrey,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilterChip(
                                label: const Text('All'),
                                selected: _selectedCategory == null,
                                selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  fontWeight: _selectedCategory == null ? FontWeight.bold : FontWeight.normal,
                                  color: _selectedCategory == null ? AppTheme.primary : Colors.blueGrey.shade800,
                                ),
                                onSelected: (_) => _onCategoryChanged(null),
                              ),
                            ),
                            ...categories.map((cat) {
                              final isCatSelected = _selectedCategory == cat;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: FilterChip(
                                  label: Text(cat),
                                  selected: isCatSelected,
                                  selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                                  labelStyle: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isCatSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isCatSelected ? AppTheme.primary : Colors.blueGrey.shade800,
                                  ),
                                  onSelected: (_) => _onCategoryChanged(cat),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // 5. PRODUCTS LIST HEADER
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'PRODUCTS (${products.length})',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Colors.blueGrey),
                        ),
                        if (_cart.isNotEmpty)
                          InkWell(
                            onTap: _clearCart,
                            child: const Text(
                              'Clear Cart',
                              style: TextStyle(fontSize: 11.5, color: AppTheme.error, fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // PRODUCTS LIST
                    if (products.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        alignment: Alignment.center,
                        child: Text(
                          'No products found in this category.',
                          style: TextStyle(color: Colors.blueGrey.shade600),
                        ),
                      )
                    else
                      ...products.map((prod) {
                        final qty = _getItemQuantity(prod.id);
                        return _buildProductCard(prod, qty);
                      }),

                    const SizedBox(height: 80), // Padding for sticky bottom cart
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
                              '${_cart.length} items • $_totalCartQuantity pcs',
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
    );
  }

  // Individual Product Card
  Widget _buildProductCard(CatalogProduct product, int qty) {
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
      child: Row(
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
              onPressed: () => _addProduct(product),
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
                            '$qty',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primary),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 18, color: AppTheme.primary),
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                        onPressed: () => _addProduct(product),
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
                      onTap: () => _addProduct(product, qtyToAdd: 6),
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
                      onTap: () => _addProduct(product, qtyToAdd: 12),
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
    );
  }

  // TAB 2: Booked Orders Tab
  Widget _buildBookedOrdersTab(CollectionProvider provider) {
    final orders = provider.salesOrders;

    if (orders.isEmpty) {
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
                'Switch to the "Take Order" tab to book orders from your outlets.',
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

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: orders.length,
      itemBuilder: (context, idx) {
        final order = orders[idx];
        final isPurva = order.firm == OrderCatalogService.purva;

        return Card(
          elevation: 1.5,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Order # and Firm Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      order.orderNumber,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                const SizedBox(height: 6),

                // Shop & Route
                Text(
                  order.shopName,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                ),
                Text(
                  'Route: ${order.routeName} • ${DateFormat("dd MMM yyyy, hh:mm a").format(order.orderDate)}',
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                ),
                const Divider(height: 16),

                // Items preview
                Text(
                  '${order.items.map((i) => "${i.productName} (${i.quantity})").take(3).join(', ')}${order.items.length > 3 ? " +${order.items.length - 3} more" : ""}',
                  style: TextStyle(fontSize: 12.5, color: Colors.blueGrey.shade800),
                ),
                const SizedBox(height: 8),

                // Bottom row: Total amount & WhatsApp Share Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${order.totalQuantity} pcs • ${CurrencyFormatter.format(order.totalAmount)}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF10B981)),
                    ),
                    Row(
                      children: [
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
                        IconButton(
                          icon: const Icon(Icons.chat, size: 20, color: Color(0xFF25D366)),
                          tooltip: 'Share on WhatsApp',
                          onPressed: () => _shareOrderOnWhatsApp(order),
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
    );
  }
}
