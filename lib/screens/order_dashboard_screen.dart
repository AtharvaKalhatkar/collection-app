import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/order_model.dart';
import '../models/route_model.dart';
import '../models/shop_model.dart';
import '../providers/auth_provider.dart';
import '../providers/collection_provider.dart';
import '../services/godown_billing_pdf_service.dart';
import '../services/location_service.dart';
import '../services/location_tracking_service.dart';
import '../utils/currency_formatter.dart';
import '../utils/marathi_search_helper.dart';
import '../utils/theme.dart';
import '../widgets/add_product_dialog.dart';
import '../widgets/assign_routes_dialog.dart';
import 'add_shop_screen.dart';
import 'admin_products_screen.dart';
import 'all_orders_screen.dart';
import 'outlet_order_booking_screen.dart';
import '../widgets/clean_ui.dart';

const Color _bizomBlue = Color(0xFF15429E);

class OrderDashboardScreen extends StatefulWidget {
  final String? initialRouteId;
  final bool isEmbedded;
  final VoidCallback? onBackToOverview;

  const OrderDashboardScreen({
    super.key,
    this.initialRouteId,
    this.isEmbedded = false,
    this.onBackToOverview,
  });

  @override
  State<OrderDashboardScreen> createState() => _OrderDashboardScreenState();
}

class _OrderDashboardScreenState extends State<OrderDashboardScreen>
    with SingleTickerProviderStateMixin {
  int _currentBottomNavIndex = 0; // 0: Retailers, 1: Route Map, 2: Transactions
  late TabController _retailerStatusTabController; // 0: Pending, 1: Completed, 2: All

  DateTime _selectedDate = DateTime.now();
  String? _selectedRouteId;
  String _searchQuery = '';
  bool _showSearchBar = false;
  String _txnFilter = 'All'; // All | Purva | Manas | Booked | Billed
  final TextEditingController _searchController = TextEditingController();

  final MapController _mapController = MapController();
  bool _isSatellite = false;

  @override
  void initState() {
    super.initState();
    _retailerStatusTabController = TabController(length: 3, vsync: this);
    _selectedRouteId = widget.initialRouteId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final provider = context.read<CollectionProvider>();
      if (auth.currentUser != null) {
        LocationTrackingService().startTracking(
          auth: auth,
          collectionProvider: provider,
        );
      }
    });
  }

  @override
  void dispose() {
    _retailerStatusTabController.dispose();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _stepDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _openAddProduct() async {
    await showDialog(
      context: context,
      builder: (_) => const AddProductDialog(),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openAddShop(String? routeId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddShopScreen(initialRouteId: routeId),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openOutletInfo(ShopModel shop) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _OutletInfoDetailScreen(
          shop: shop,
          selectedDate: _selectedDate,
          onBookOrder: ({SalesOrderModel? existingOrder}) =>
              _openOutletOrder(shop, existingOrder: existingOrder),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openOutletOrder(ShopModel shop, {SalesOrderModel? existingOrder}) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => OutletOrderBookingScreen(
          shop: shop,
          selectedDate: _selectedDate,
          existingOrder: existingOrder,
        ),
      ),
    );
    if (result == true && mounted) {
      setState(() {});
    }
  }

  void _confirmDeleteOrder(SalesOrderModel order) {
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Delete Order?'),
        content: Text('Are you sure you want to delete order #${order.orderNumber} for ${order.shopName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () async {
              Navigator.pop(dlgCtx);
              final provider = Provider.of<CollectionProvider>(context, listen: false);
              final messenger = ScaffoldMessenger.of(context);
              final deletedCloud = await provider.deleteSalesOrder(order.id);
              if (mounted) {
                setState(() {});
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(deletedCloud
                        ? 'Deleted order #${order.orderNumber}'
                        : 'Deleted locally (will sync when online)'),
                    backgroundColor: const Color(0xFF0F172A),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _shareOrderWhatsApp(SalesOrderModel order) async {
    final buf = StringBuffer()
      ..writeln('*${order.firm.toUpperCase()} - STORE ORDER*')
      ..writeln('Order #${order.orderNumber} • ${DateFormat('dd MMM yyyy').format(order.orderDate)}')
      ..writeln('Store: ${order.shopName} (${order.routeName})');
    for (int i = 0; i < order.items.length; i++) {
      final it = order.items[i];
      if (it.subtotal > 0) {
        buf.writeln('${i + 1}. ${it.productName} - ${it.cases} CS, ${it.units} UT (${CurrencyFormatter.format(it.subtotal)})');
      } else {
        buf.writeln('${i + 1}. ${it.productName} - ${it.cases} CS, ${it.units} UT');
      }
    }
    buf.writeln(
      order.totalAmount > 0
          ? '*Total: ${CurrencyFormatter.format(order.totalAmount)}* (${order.totalCases} CS, ${order.totalLooseUnits} UT)'
          : '*Total: ${order.totalCases} CS, ${order.totalLooseUnits} UT (${order.items.length} items)*',
    );
    if (order.notes != null && order.notes!.isNotEmpty) {
      buf.writeln('Notes: ${order.notes}');
    }
    final url = Uri.parse('https://api.whatsapp.com/send?text=${Uri.encodeComponent(buf.toString())}');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _showCompletedShopSheet(ShopModel shop, SalesOrderModel order) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    shop.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: order.status == 'Cancelled'
                        ? const Color(0xFFFEF2F2)
                        : const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${order.firm == 'Purva Enterprises' ? 'PURVA' : 'MANAS'} • ${order.status}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: order.status == 'Cancelled'
                          ? AppTheme.balanceDueColor
                          : const Color(0xFF15803D),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Order #${order.orderNumber} • ${DateFormat('dd MMM hh:mm a').format(order.orderDate)}',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
            Text(
              order.totalAmount > 0
                  ? 'Amount: ${CurrencyFormatter.format(order.totalAmount)} • ${order.totalCases} CS, ${order.totalLooseUnits} UT (${order.items.length} lines)'
                  : '${order.totalCases} CS, ${order.totalLooseUnits} UT • ${order.items.length} lines',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 16, color: Color(0xFFDC2626)),
                    label: const Text('Godown Slip'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFDC2626)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
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
                    icon: const Icon(Icons.edit_note_rounded, size: 16, color: Colors.white),
                    label: const Text('Edit Order', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _bizomBlue,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openOutletOrder(shop, existingOrder: order);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                    label: const Text('Delete Order', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _confirmDeleteOrder(order);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add_shopping_cart, size: 16, color: Color(0xFF16A34A)),
                    label: const Text('Book Additional', style: TextStyle(color: Color(0xFF16A34A))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF16A34A)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openOutletOrder(shop);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<CollectionProvider>();
    final user = auth.currentUser;

    // Filter available routes cleanly; never leak stale routes if unassigned/reassigned
    List<RouteModel> availableRoutes = provider.allRoutes;
    if (user != null && !user.isSuperAdmin && user.assignedRouteIds.isNotEmpty) {
      availableRoutes = provider.allRoutes
          .where((r) => user.assignedRouteIds.contains(r.id))
          .toList();
    }

    final String? effectiveRouteId = availableRoutes.isEmpty
        ? null
        : (availableRoutes.any((r) => r.id == _selectedRouteId)
            ? _selectedRouteId
            : availableRoutes.first.id);
    _selectedRouteId = effectiveRouteId;

    final selectedRoute = availableRoutes.firstWhere(
      (r) => r.id == effectiveRouteId,
      orElse: () => availableRoutes.isNotEmpty
          ? availableRoutes.first
          : RouteModel(id: '', name: 'No Route Available'),
    );

    // Get all shops for this route
    final allRouteShops = effectiveRouteId == null
        ? <ShopModel>[]
        : provider.allShops
            .where((s) => s.routeId == effectiveRouteId)
            .toList();

    // Selected-date orders (newest first so lookup matches latest order)
    final allDateOrders = provider.salesOrders
        .where((o) => _isSameDay(o.orderDate, _selectedDate))
        .toList()
      ..sort((a, b) => b.orderDate.compareTo(a.orderDate));

    // Staff visibility: non-admin/office see own orders on Transactions tab
    final userDateOrders = (user != null && !user.isSuperAdmin && !user.isOffice)
        ? allDateOrders.where((o) {
            final staff = o.salesmanName.toLowerCase().trim();
            return staff == user.plainName.toLowerCase().trim() ||
                staff == user.name.toLowerCase().trim();
          }).toList()
        : allDateOrders;

    final bookedShopIds = allDateOrders.map((o) => o.shopId).toSet();

    // Group shops: Completed vs Pending
    final completedShops = allRouteShops.where((s) => bookedShopIds.contains(s.id)).toList();
    final pendingShops = allRouteShops.where((s) => !bookedShopIds.contains(s.id)).toList();

    final bool canGoBack = widget.onBackToOverview != null || Navigator.canPop(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: widget.isEmbedded ? Colors.white : _bizomBlue,
        foregroundColor: widget.isEmbedded ? AppTheme.primary : Colors.white,
        iconTheme: IconThemeData(
          color: widget.isEmbedded ? AppTheme.primary : Colors.white,
          size: 22,
        ),
        actionsIconTheme: IconThemeData(
          color: widget.isEmbedded ? AppTheme.primary : Colors.white,
          size: 22,
        ),
        elevation: 0,
        leading: canGoBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () {
                  if (widget.onBackToOverview != null) {
                    widget.onBackToOverview!();
                  } else if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                },
              )
            : null,
        titleSpacing: canGoBack ? 4 : 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isEmbedded) ...[
                  const Icon(Icons.store_mall_directory_rounded, size: 18, color: _bizomBlue),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    _currentBottomNavIndex == 2 ? 'Transactions' : 'RETAILER',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16.5,
                      letterSpacing: 0.4,
                      color: widget.isEmbedded ? AppTheme.primary : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            if (user != null)
              Text(
                user.plainName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: widget.isEmbedded
                      ? AppTheme.textSecondary
                      : Colors.white.withValues(alpha: 0.85),
                ),
              ),
          ],
        ),
        actions: [
          if (_currentBottomNavIndex == 0)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(_showSearchBar ? Icons.search_off_rounded : Icons.search_rounded),
              tooltip: 'Search Retailers',
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
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_box_outlined),
            tooltip: 'Add Product to Catalog',
            onPressed: _openAddProduct,
          ),
          if (MediaQuery.sizeOf(context).width >= 520) ...[
            if (user?.canAssignRoutes == true)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.alt_route_rounded),
                tooltip: 'Assign Routes',
                onPressed: () => AssignRoutesDialog.show(context),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.list_alt_rounded),
              tooltip: 'All Booked Orders',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AllOrdersScreen(initialDate: _selectedDate)),
                );
              },
            ),
            if (user?.isSuperAdmin == true)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.inventory_2_outlined),
                tooltip: 'Products, Stock & Schemes',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminProductsScreen()),
                  );
                },
              ),
            if (!widget.isEmbedded)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.logout_rounded),
                tooltip: 'Sign Out',
                onPressed: () => auth.logout(),
              ),
          ] else
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'More Options',
              onSelected: (val) {
                if (val == 'assign_routes') {
                  AssignRoutesDialog.show(context);
                } else if (val == 'all_orders') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => AllOrdersScreen(initialDate: _selectedDate)),
                  );
                } else if (val == 'products_admin') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminProductsScreen()),
                  );
                } else if (val == 'logout') {
                  auth.logout();
                }
              },
              itemBuilder: (_) => [
                if (user?.canAssignRoutes == true)
                  const PopupMenuItem(value: 'assign_routes', child: Text('Assign Routes')),
                const PopupMenuItem(value: 'all_orders', child: Text('All Booked Orders')),
                if (user?.isSuperAdmin == true)
                  const PopupMenuItem(value: 'products_admin', child: Text('Products, Stock & Schemes')),
                if (!widget.isEmbedded)
                  const PopupMenuItem(value: 'logout', child: Text('Sign Out')),
              ],
            ),
        ],
        bottom: widget.isEmbedded
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: AppTheme.border)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    children: [
                      _buildHeaderTabChip(
                        title: 'Retailers (${pendingShops.length})',
                        icon: Icons.storefront_outlined,
                        isSelected: _currentBottomNavIndex == 0,
                        onTap: () => setState(() => _currentBottomNavIndex = 0),
                      ),
                      const SizedBox(width: 6),
                      _buildHeaderTabChip(
                        title: 'Route Map',
                        icon: Icons.map_outlined,
                        isSelected: _currentBottomNavIndex == 1,
                        onTap: () => setState(() => _currentBottomNavIndex = 1),
                      ),
                      const SizedBox(width: 6),
                      _buildHeaderTabChip(
                        title: 'Orders (${userDateOrders.length})',
                        icon: Icons.receipt_long_outlined,
                        isSelected: _currentBottomNavIndex == 2,
                        onTap: () => setState(() => _currentBottomNavIndex = 2),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: IndexedStack(
        index: _currentBottomNavIndex,
        children: [
          ResponsiveContent(
            maxWidth: 860,
            child: _buildRetailersTab(
              availableRoutes,
              selectedRoute,
              pendingShops,
              completedShops,
              allRouteShops,
              allDateOrders,
              provider,
            ),
          ),
          _buildOrderMapTab(
            allRouteShops,
            completedShops,
            bookedShopIds,
          ),
          ResponsiveContent(
            maxWidth: 860,
            child: _buildTransactionsTab(userDateOrders),
          ),
        ],
      ),
      bottomNavigationBar: widget.isEmbedded
          ? null
          : NavigationBar(
              selectedIndex: _currentBottomNavIndex,
              onDestinationSelected: (idx) => setState(() => _currentBottomNavIndex = idx),
              indicatorColor: _bizomBlue.withValues(alpha: 0.12),
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.storefront_outlined),
                  selectedIcon: const Icon(Icons.storefront, color: _bizomBlue),
                  label: 'Retailers (${pendingShops.length})',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map, color: _bizomBlue),
                  label: 'Route Map',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.receipt_long_outlined),
                  selectedIcon: const Icon(Icons.receipt_long, color: _bizomBlue),
                  label: 'Transactions (${userDateOrders.length})',
                ),
              ],
            ),
    );
  }

  Widget _buildHeaderTabChip({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? _bizomBlue : AppTheme.subtleSurface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? Colors.white : AppTheme.textSecondary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRetailersTab(
    List<RouteModel> availableRoutes,
    RouteModel selectedRoute,
    List<ShopModel> pendingShops,
    List<ShopModel> completedShops,
    List<ShopModel> allRouteShops,
    List<SalesOrderModel> dateOrders,
    CollectionProvider provider,
  ) {
    final isToday = _isSameDay(_selectedDate, DateTime.now());

    return Column(
      children: [
        // Green "Today" Bar matching Bizom Reference Image 1
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 5),
          color: const Color(0xFF16A34A),
          child: Text(
            isToday ? 'Today' : DateFormat('EEEE').format(_selectedDate),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
          ),
        ),

        // Date & Beat Header (< Date + Beat Selector >)
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Icon(Icons.chevron_left_rounded, size: 18, color: Color(0xFF475569)),
                ),
                onPressed: () => _stepDate(-1),
              ),
              Expanded(
                child: Column(
                  children: [
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              DateFormat('dd MMMM').format(_selectedDate),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                                color: Color(0xFF475569),
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Icon(Icons.calendar_today_outlined, size: 13, color: _bizomBlue),
                          ],
                        ),
                      ),
                    ),
                    if (availableRoutes.length > 1)
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: availableRoutes.any((r) => r.id == _selectedRouteId)
                              ? _selectedRouteId
                              : availableRoutes.first.id,
                          isDense: true,
                          alignment: Alignment.center,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _bizomBlue, size: 18),
                          items: availableRoutes.map((r) {
                            return DropdownMenuItem(
                              value: r.id,
                              child: Text(
                                r.name.toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedRouteId = val);
                          },
                        ),
                      )
                    else
                      Text(
                        selectedRoute.name.toUpperCase(),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF475569)),
                ),
                onPressed: () => _stepDate(1),
              ),
            ],
          ),
        ),

        // 3 Status Tabs: Pending (X) | Completed (Y) | All (Z) + Add Shop Button
        Container(
          color: Colors.white,
          padding: const EdgeInsets.only(right: 10),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _retailerStatusTabController,
                  indicatorColor: _bizomBlue,
                  indicatorWeight: 2.5,
                  labelColor: _bizomBlue,
                  unselectedLabelColor: const Color(0xFF64748B),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                  tabs: [
                    Tab(text: 'Pending (${pendingShops.length})'),
                    Tab(text: 'Completed (${completedShops.length})'),
                    Tab(text: 'All (${allRouteShops.length})'),
                  ],
                ),
              ),
              InkWell(
                onTap: () => _openAddShop(selectedRoute.id.isNotEmpty ? selectedRoute.id : null),
                borderRadius: BorderRadius.circular(8),
                child: Tooltip(
                  message: 'Add New Retailer / Outlet',
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _bizomBlue.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.add_business_outlined, size: 18, color: _bizomBlue),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Expandable Search bar
        if (_showSearchBar || _searchQuery.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            color: Colors.white,
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: _searchController,
                autofocus: _showSearchBar && _searchQuery.isEmpty,
                decoration: InputDecoration(
                  hintText: 'Search outlet name, ID or address...',
                  hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
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
          ),

        const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

        // Outlets List View
        Expanded(
          child: TabBarView(
            controller: _retailerStatusTabController,
            children: [
              _buildShopsListView(pendingShops, false, dateOrders, provider),
              _buildShopsListView(completedShops, true, dateOrders, provider),
              _buildShopsListView(allRouteShops, null, dateOrders, provider),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShopsListView(
    List<ShopModel> shops,
    bool? isCompletedFilter,
    List<SalesOrderModel> dateOrders,
    CollectionProvider provider,
  ) {
    final filtered = shops.where((s) {
      if (_searchQuery.trim().isEmpty) return true;
      return MarathiSearchHelper.matches(s.name, _searchQuery) ||
          MarathiSearchHelper.matches(s.address, _searchQuery) ||
          s.id.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          s.mobileNumber.contains(_searchQuery);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isCompletedFilter == true
                    ? Icons.check_circle_outline_rounded
                    : Icons.storefront_outlined,
                size: 56,
                color: const Color(0xFFCBD5E1),
              ),
              const SizedBox(height: 10),
              Text(
                isCompletedFilter == true
                    ? 'No orders booked yet today on this route.'
                    : 'No outlets found.',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    // Two-month activity badges (matching OCT NOV in reference screenshot 1)
    final prevMonthDate = DateTime(_selectedDate.year, _selectedDate.month - 1, 1);
    final currMonthLabel = DateFormat('MMM').format(_selectedDate).toUpperCase();
    final prevMonthLabel = DateFormat('MMM').format(prevMonthDate).toUpperCase();

    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: filtered.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (ctx, index) {
        final shop = filtered[index];
        final orderForShop = dateOrders.where((o) => o.shopId == shop.id).firstOrNull;
        final hasOrder = orderForShop != null;

        final allShopHistory = provider.getPreviousOrdersForShop(shop.id, limit: 25);
        final lastVisitDate = allShopHistory.isNotEmpty
            ? DateFormat('dd MMMM yyyy').format(allShopHistory.first.orderDate)
            : 'Not visited';
        final hasPrevMonth = allShopHistory.any(
          (o) => o.orderDate.year == prevMonthDate.year && o.orderDate.month == prevMonthDate.month,
        );
        final hasCurrMonth = hasOrder ||
            allShopHistory.any(
              (o) => o.orderDate.year == _selectedDate.year && o.orderDate.month == _selectedDate.month,
            );

        final shortId = shop.id.length > 6 ? shop.id.substring(shop.id.length - 6) : shop.id;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hasOrder ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
              width: hasOrder ? 1.3 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => hasOrder ? _showCompletedShopSheet(shop, orderForShop) : _openOutletOrder(shop),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 6, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Store Square Thumbnail
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: hasOrder ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.storefront_rounded,
                              color: hasOrder ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 11),

                          // Status + Store Name + ID + Address
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      hasOrder ? 'Completed' : 'Not Started',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: hasOrder ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.verified_rounded,
                                      size: 12.5,
                                      color: shop.hasLocation ? const Color(0xFF16A34A) : const Color(0xFFCBD5E1),
                                    ),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        shop.hasLocation ? 'Verified' : 'GPS Unset',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: shop.hasLocation ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  shop.name.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'ID: $shortId${shop.address.trim().isNotEmpty ? ' • ${shop.address.trim()}' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),

                          // Top-Right Pin + Info (i) + 3-Dot Action Cluster
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 2),
                                child: Icon(
                                  shop.hasLocation ? Icons.location_on_rounded : Icons.location_off_outlined,
                                  size: 18,
                                  color: shop.hasLocation ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                                ),
                              ),
                              InkWell(
                                onTap: () => _openOutletInfo(shop),
                                borderRadius: BorderRadius.circular(14),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(Icons.info_outline_rounded, size: 19, color: Color(0xFF334155)),
                                ),
                              ),
                              PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.more_vert, size: 19, color: Color(0xFF64748B)),
                                onSelected: (val) {
                                  if (val == 'info') {
                                    _openOutletInfo(shop);
                                  } else if (val == 'call' && shop.mobileNumber.isNotEmpty) {
                                    launchUrl(Uri.parse('tel:${shop.mobileNumber}'));
                                  } else if (val == 'navigate' && shop.mapsUrl != null) {
                                    launchUrl(Uri.parse(shop.mapsUrl!), mode: LaunchMode.externalApplication);
                                  } else if (val == 'order') {
                                    _openOutletOrder(shop);
                                  } else if (val == 'edit_order' && orderForShop != null) {
                                    _openOutletOrder(shop, existingOrder: orderForShop);
                                  } else if (val == 'delete_order' && orderForShop != null) {
                                    _confirmDeleteOrder(orderForShop);
                                  } else if (val == 'pdf' && orderForShop != null) {
                                    GodownBillingPdfService.previewOrSharePdf(
                                      context,
                                      orders: [orderForShop],
                                      salesmanName: orderForShop.salesmanName,
                                    );
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(value: 'info', child: Text('Outlet Info')),
                                  if (hasOrder) ...[
                                    const PopupMenuItem(value: 'edit_order', child: Text('Edit Booked Order')),
                                    const PopupMenuItem(value: 'order', child: Text('Book Additional Order')),
                                    const PopupMenuItem(value: 'pdf', child: Text('Godown Slip PDF')),
                                    const PopupMenuItem(value: 'delete_order', child: Text('Delete Order', style: TextStyle(color: Colors.red))),
                                  ] else
                                    const PopupMenuItem(value: 'order', child: Text('Book Order')),
                                  if (shop.mobileNumber.isNotEmpty)
                                    const PopupMenuItem(value: 'call', child: Text('Call Store')),
                                  if (shop.hasLocation)
                                    const PopupMenuItem(value: 'navigate', child: Text('Navigate on Map')),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),
                      // Last Visited + Two-Month Indicator (matching OCT NOV in Reference Image 1)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              'Last Visited: $lastVisitDate',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  prevMonthLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: hasPrevMonth ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  currMonthLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: hasCurrMonth ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
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

                // Bottom Green Strip on Completed Cards (matching Image 1)
                if (hasOrder)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    color: const Color(0xFFECFDF5),
                    child: Row(
                      children: [
                        const Icon(Icons.check_rounded, size: 15, color: Color(0xFF15803D)),
                        const SizedBox(width: 6),
                        Text(
                          'Orders',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF15803D),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          orderForShop.totalAmount > 0
                              ? '${orderForShop.totalCases} CS, ${orderForShop.totalLooseUnits} UT • ${CurrencyFormatter.format(orderForShop.totalAmount)}'
                              : '${orderForShop.totalCases} CS, ${orderForShop.totalLooseUnits} UT • ${orderForShop.items.length} items',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF15803D),
                          ),
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
  }

  Widget _buildOrderMapTab(
    List<ShopModel> allRouteShops,
    List<ShopModel> completedShops,
    Set<String> bookedShopIds,
  ) {
    final authUser = context.watch<AuthProvider>().currentUser;
    final shopsWithLoc = allRouteShops.where((s) => s.latitude != null && s.longitude != null).toList();

    LatLng initialCenter = const LatLng(18.8567, 73.8847); // Default Khed / Pune
    if (authUser != null && authUser.hasLocation) {
      initialCenter = LatLng(authUser.latitude!, authUser.longitude!);
    } else if (shopsWithLoc.isNotEmpty) {
      initialCenter = LatLng(shopsWithLoc.first.latitude!, shopsWithLoc.first.longitude!);
    }

    return Stack(
      children: [
        FlutterMap(
          key: ValueKey('order_map_$_isSatellite'),
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: 13.5,
            minZoom: 6.0,
            maxZoom: 20.0,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
          ),
          children: [
            TileLayer(
              key: ValueKey(_isSatellite),
              urlTemplate: _isSatellite
                  ? 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}'
                  : 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
              userAgentPackageName: 'com.purva.dailycollection',
              maxZoom: 20,
            ),
            MarkerLayer(
              markers: [
                ...shopsWithLoc.map((s) {
                  final hasOrder = bookedShopIds.contains(s.id);
                  return Marker(
                    point: LatLng(s.latitude!, s.longitude!),
                    width: 105,
                    height: 46,
                    alignment: Alignment.bottomCenter,
                    child: GestureDetector(
                      onTap: () => _showShopMapBottomSheet(s, hasOrder),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: hasOrder ? const Color(0xFF16A34A) : _bizomBlue,
                              ),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
                            ),
                            child: Text(
                              s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          Icon(
                            hasOrder ? Icons.check_circle_rounded : Icons.location_on_rounded,
                            color: hasOrder ? const Color(0xFF16A34A) : _bizomBlue,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                if (authUser != null && authUser.hasLocation)
                  Marker(
                    point: LatLng(authUser.latitude!, authUser.longitude!),
                    width: 34,
                    height: 34,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 5)],
                      ),
                      child: const Icon(Icons.my_location_rounded, color: Colors.white, size: 17),
                    ),
                  ),
              ],
            ),
          ],
        ),

        // Non-overlapping SafeArea Controls & Bottom Summary Strip
        Positioned.fill(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton.small(
                          heroTag: 'map_sat_toggle',
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF0F172A),
                          tooltip: _isSatellite ? 'Road Map' : 'Satellite View',
                          onPressed: () => setState(() => _isSatellite = !_isSatellite),
                          child: Icon(_isSatellite ? Icons.map_rounded : Icons.layers_rounded),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'map_recenter',
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF0284C7),
                          tooltip: 'My GPS Location',
                          onPressed: () async {
                            final fix = await LocationService.getCurrentLocationWithStatus();
                            if (!mounted) return;
                            if (fix.hasLocation) {
                              _mapController.move(LatLng(fix.latitude!, fix.longitude!), 15.0);
                            } else if (shopsWithLoc.isNotEmpty) {
                              _mapController.move(LatLng(shopsWithLoc.first.latitude!, shopsWithLoc.first.longitude!), 13.5);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(fix.errorMessage ?? 'Could not fetch GPS.'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                          child: const Icon(Icons.my_location_rounded),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Completed (${completedShops.length})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 10, height: 10, decoration: const BoxDecoration(color: _bizomBlue, shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Pending (${allRouteShops.length - completedShops.length})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showShopMapBottomSheet(ShopModel shop, bool hasOrder) {
    final provider = Provider.of<CollectionProvider>(context, listen: false);
    final orderForShop = provider.salesOrders
        .where((o) => o.shopId == shop.id && _isSameDay(o.orderDate, _selectedDate))
        .firstOrNull;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    shop.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: hasOrder ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    hasOrder ? 'Order Completed' : 'Pending',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: hasOrder ? const Color(0xFF15803D) : const Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(shop.address, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
            if (orderForShop != null) ...[
              const SizedBox(height: 6),
              Text(
                orderForShop.totalAmount > 0
                    ? 'Booked: ${CurrencyFormatter.format(orderForShop.totalAmount)} (${orderForShop.totalCases} CS, ${orderForShop.totalLooseUnits} UT)'
                    : 'Booked: ${orderForShop.totalCases} CS, ${orderForShop.totalLooseUnits} UT (${orderForShop.items.length} items)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF15803D)),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.info_outline_rounded, size: 16),
                  label: const Text('Info'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openOutletInfo(shop);
                  },
                ),
                const SizedBox(width: 8),
                if (shop.mapsUrl != null) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.navigation, size: 16),
                    label: const Text('Map'),
                    onPressed: () => launchUrl(Uri.parse(shop.mapsUrl!), mode: LaunchMode.externalApplication),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: _bizomBlue),
                    icon: Icon(hasOrder ? Icons.edit_note_rounded : Icons.add_shopping_cart, size: 16, color: Colors.white),
                    label: Text(hasOrder ? 'Edit Order' : 'Book Order', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openOutletOrder(shop, existingOrder: orderForShop);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Transactions Tab (Matching Bizom Reference Image 3)
  Widget _buildTransactionsTab(List<SalesOrderModel> dateOrders) {
    final provider = context.watch<CollectionProvider>();
    if (dateOrders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.receipt_long_outlined, size: 56, color: Color(0xFFCBD5E1)),
              const SizedBox(height: 10),
              const Text('No orders booked for this date.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF64748B))),
              const SizedBox(height: 4),
              const Text('Orders placed from the Retailers tab will appear here.', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
            ],
          ),
        ),
      );
    }

    final filteredOrders = dateOrders.where((o) {
      switch (_txnFilter) {
        case 'Purva':
          return o.firm == 'Purva Enterprises';
        case 'Manas':
          return o.firm == 'Manas Sales';
        case 'Booked':
          return o.status == 'Booked';
        case 'Billed':
          return o.status == 'Billed';
        default:
          return true;
      }
    }).toList();

    final totalDayAmount = filteredOrders.fold(0.0, (sum, o) => sum + o.totalAmount);
    final totalDayCases = filteredOrders.fold(0, (sum, o) => sum + o.totalCases);
    final totalDayUnits = filteredOrders.fold(0, (sum, o) => sum + o.totalLooseUnits);

    return Column(
      children: [
        // Filter Chips Strip (matching Image 3 pill row)
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['All', 'Purva', 'Manas', 'Booked', 'Billed'].map((chip) {
                final isSelected = _txnFilter == chip;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () => setState(() => _txnFilter = chip),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFE0E7FF) : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected ? _bizomBlue : const Color(0xFFCBD5E1),
                        ),
                      ),
                      child: Text(
                        chip,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? _bizomBlue : const Color(0xFF334155),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // Summary Header Strip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: const Color(0xFFF8FAFC),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildTransactionStat('Orders', '${filteredOrders.length}'),
              _buildTransactionStat('Total Cases', '$totalDayCases CS'),
              _buildTransactionStat('Total Units', '$totalDayUnits UT'),
              if (totalDayAmount > 0)
                _buildTransactionStat('Total Amount', CurrencyFormatter.format(totalDayAmount)),
            ],
          ),
        ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AllOrdersScreen(initialDate: _selectedDate)),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.filter_list_rounded, size: 16, color: _bizomBlue),
                  SizedBox(width: 6),
                  Text(
                    'All Booked Orders Master (Staff & Tally)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _bizomBlue),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),

        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(10),
            itemCount: filteredOrders.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (ctx, index) {
              final order = filteredOrders[index];
              final showAmountCol = order.totalAmount > 0;
              final shop = provider.allShops.where((s) => s.id == order.shopId).firstOrNull ??
                  ShopModel(
                    id: order.shopId,
                    name: order.shopName,
                    address: '',
                    routeId: order.routeId,
                    routeName: order.routeName,
                    mobileNumber: order.shopMobile,
                  );

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Shop Title + Status Pill
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            order.shopName,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: Color(0xFF0F172A)),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3E8FF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            order.status == 'Booked' ? 'Fulfilled' : order.status,
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF6B21A8)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          'Order ID: ${order.orderNumber}',
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '• ${order.firm == 'Purva Enterprises' ? 'Purva' : 'Manas'} • ${DateFormat('hh:mm a').format(order.orderDate)}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Staff: ${order.salesmanName} (${order.routeName})',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const SizedBox(height: 8),

                    // Tabular Header Row (matching Image 3: Sku Name | Case/Bags | Unit | Amount)
                    Row(
                      children: [
                        const Expanded(
                          flex: 5,
                          child: Text('Sku Name', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                        ),
                        const Expanded(
                          flex: 2,
                          child: Text('Case/Bags', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                        ),
                        const Expanded(
                          flex: 2,
                          child: Text('Unit', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                        ),
                        if (showAmountCol)
                          const Expanded(
                            flex: 2,
                            child: Text('Amount', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),

                    // Line Items Table
                    ...order.items.map((it) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: Text(
                                it.productName,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '${it.cases}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '${it.units}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (showAmountCol)
                              Expanded(
                                flex: 2,
                                child: Text(
                                  it.subtotal > 0 ? it.subtotal.toStringAsFixed(2) : '-',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),

                    const SizedBox(height: 6),
                    const Divider(height: 1),
                    const SizedBox(height: 6),

                    // Total Summary Row
                    Row(
                      children: [
                        const Expanded(
                          flex: 5,
                          child: Text('Total', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${order.totalCases}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${order.totalLooseUnits}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                          ),
                        ),
                        if (showAmountCol)
                          Expanded(
                            flex: 2,
                            child: Text(
                              order.totalAmount.toStringAsFixed(0),
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Sharing & Action Row
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.picture_as_pdf_rounded, size: 15, color: Color(0xFFDC2626)),
                            label: const Text('Slip', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                              side: const BorderSide(color: Color(0xFFDC2626)),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            onPressed: () => GodownBillingPdfService.previewOrSharePdf(
                              context,
                              orders: [order],
                              salesmanName: order.salesmanName,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.send_rounded, size: 15, color: Colors.white),
                            label: const Text('WhatsApp', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF25D366),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            onPressed: () => _shareOrderWhatsApp(order),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Edit Order',
                          icon: const Icon(Icons.edit_note_rounded, color: _bizomBlue, size: 22),
                          onPressed: () => _openOutletOrder(shop, existingOrder: order),
                        ),
                        IconButton(
                          tooltip: 'Delete Order',
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                          onPressed: () => _confirmDeleteOrder(order),
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

  Widget _buildTransactionStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
      ],
    );
  }
}

/// Dedicated Bizom-style Outlet Info Screen (Matching Reference Image 8: Pasted image (3).png)
class _OutletInfoDetailScreen extends StatelessWidget {
  final ShopModel shop;
  final DateTime selectedDate;
  final Future<void> Function({SalesOrderModel? existingOrder}) onBookOrder;

  const _OutletInfoDetailScreen({
    required this.shop,
    required this.selectedDate,
    required this.onBookOrder,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CollectionProvider>();
    final pendingDue = provider.getTotalBalanceForShop(shop.id);
    final history = provider.getPreviousOrdersForShop(shop.id, limit: 15);
    final todayOrder = history.where((o) =>
        o.orderDate.year == selectedDate.year &&
        o.orderDate.month == selectedDate.month &&
        o.orderDate.day == selectedDate.day).firstOrNull;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: _bizomBlue,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white, size: 22),
        actionsIconTheme: const IconThemeData(color: Colors.white, size: 22),
        elevation: 0,
        title: const Text('Outlet Info', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Outlet',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AddShopScreen(existingShop: shop)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Sync',
            onPressed: () => provider.syncAllWithCloud(notify: true),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                // Store Identity Card + 4 Action Icons Bar
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.storefront_rounded, color: _bizomBlue, size: 26),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  shop.name.toUpperCase(),
                                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                                ),
                                const SizedBox(height: 2),
                                if (shop.ownerName != null && shop.ownerName!.isNotEmpty)
                                  Text(
                                    'Owner: ${shop.ownerName}',
                                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
                                  ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        shop.routeName.toUpperCase(),
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF92400E)),
                                      ),
                                    ),
                                    if (shop.address.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          shop.address,
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 4 Quick Icon Buttons Row (Directions, GPS Pin, WhatsApp, Call)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildActionIconBtn(
                            icon: Icons.directions_outlined,
                            label: 'Navigate',
                            enabled: shop.mapsUrl != null,
                            onTap: () {
                              if (shop.mapsUrl != null) {
                                launchUrl(Uri.parse(shop.mapsUrl!), mode: LaunchMode.externalApplication);
                              }
                            },
                          ),
                          _buildActionIconBtn(
                            icon: Icons.add_location_alt_outlined,
                            label: 'Update GPS',
                            enabled: true,
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => AddShopScreen(existingShop: shop)),
                              );
                            },
                          ),
                          _buildActionIconBtn(
                            icon: Icons.chat_outlined,
                            label: 'WhatsApp',
                            enabled: shop.mobileNumber.isNotEmpty,
                            onTap: () {
                              final clean = shop.mobileNumber.replaceAll(RegExp(r'[^0-9]'), '');
                              final phone = clean.length == 10 ? '91$clean' : clean;
                              launchUrl(Uri.parse('https://wa.me/$phone'), mode: LaunchMode.externalApplication);
                            },
                          ),
                          _buildActionIconBtn(
                            icon: Icons.call_outlined,
                            label: 'Call',
                            enabled: shop.mobileNumber.isNotEmpty,
                            onTap: () => launchUrl(Uri.parse('tel:${shop.mobileNumber}')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Pending Due Line
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Pending Balance Due',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                      ),
                      Text(
                        CurrencyFormatter.format(pendingDue),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: pendingDue > 0 ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Recent Transactions Section
                const Text(
                  'Recent Orders',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 8),
                if (history.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Center(
                      child: Text('No previous orders recorded for this outlet.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5)),
                    ),
                  )
                else
                  ...history.map((ord) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(ord.orderNumber, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${DateFormat('dd MMM yyyy').format(ord.orderDate)} • ${ord.totalCases} CS, ${ord.totalLooseUnits} UT (${ord.firm == 'Purva Enterprises' ? 'Purva' : 'Manas'})',
                                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            if (ord.totalAmount > 0)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(
                                  CurrencyFormatter.format(ord.totalAmount),
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                ),
                              ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                onBookOrder(existingOrder: ord);
                              },
                              child: const Text('Open', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      )),
              ],
            ),
          ),

          // Sticky Bottom Full-Width Book Order CTA (Matching Reference Image 8)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _bizomBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    onBookOrder(existingOrder: todayOrder);
                  },
                  child: Text(
                    todayOrder != null ? 'Edit Today\'s Order' : 'Book Order',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionIconBtn({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            children: [
              Icon(icon, size: 22, color: enabled ? _bizomBlue : const Color(0xFFCBD5E1)),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: enabled ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
