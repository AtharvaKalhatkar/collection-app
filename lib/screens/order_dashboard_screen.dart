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
import '../utils/currency_formatter.dart';
import '../utils/marathi_search_helper.dart';
import '../widgets/add_product_dialog.dart';
import 'outlet_order_booking_screen.dart';
import 'all_orders_screen.dart';

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
  int _currentBottomNavIndex = 0; // 0: Retailers, 1: Map, 2: Transactions
  late TabController _retailerStatusTabController; // 0: Pending, 1: Completed, 2: All

  DateTime _selectedDate = DateTime.now();
  String? _selectedRouteId;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final MapController _mapController = MapController();
  bool _isSatellite = false;

  @override
  void initState() {
    super.initState();
    _retailerStatusTabController = TabController(length: 3, vsync: this);
    _selectedRouteId = widget.initialRouteId;
  }

  @override
  void dispose() {
    _retailerStatusTabController.dispose();
    _searchController.dispose();
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
    setState(() {});
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
    if (result == true) {
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
              await provider.deleteSalesOrder(order.id);
              if (mounted) setState(() {});
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Order Booked',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
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
              'Amount: ₹${CurrencyFormatter.format(order.totalAmount)} • ${order.totalCases} CS, ${order.totalLooseUnits} UT (${order.items.length} lines)',
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
                      backgroundColor: const Color(0xFF1E40AF),
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

    // Filter available routes for this user
    List<RouteModel> availableRoutes = provider.allRoutes;
    if (user != null && !user.isSuperAdmin && !user.isOffice && user.assignedRouteIds.isNotEmpty) {
      availableRoutes = provider.allRoutes
          .where((r) => user.assignedRouteIds.contains(r.id))
          .toList();
    }

    if (availableRoutes.isNotEmpty) {
      if (_selectedRouteId == null || !availableRoutes.any((r) => r.id == _selectedRouteId)) {
        _selectedRouteId = availableRoutes.first.id;
      }
    }

    final selectedRoute = availableRoutes.firstWhere(
      (r) => r.id == _selectedRouteId,
      orElse: () => availableRoutes.isNotEmpty
          ? availableRoutes.first
          : RouteModel(id: '', name: 'General Route'),
    );

    // Get all shops for this route
    final allRouteShops = provider.allShops
        .where((s) => s.routeId == _selectedRouteId)
        .toList();

    // Today's orders for this date
    final allDateOrders = provider.salesOrders
        .where((o) => _isSameDay(o.orderDate, _selectedDate))
        .toList();

    // Separate orders by staff: if non-admin/office, show only this user's orders in Orders tab
    final userDateOrders = (user != null && !user.isSuperAdmin && !user.isOffice)
        ? allDateOrders.where((o) => o.salesmanName.toLowerCase().trim() == user.plainName.toLowerCase().trim()).toList()
        : allDateOrders;

    final bookedShopIds = allDateOrders.map((o) => o.shopId).toSet();

    // Group shops: Completed vs Pending
    final completedShops = allRouteShops.where((s) => bookedShopIds.contains(s.id)).toList();
    final pendingShops = allRouteShops.where((s) => !bookedShopIds.contains(s.id)).toList();

    final bool canGoBack = widget.onBackToOverview != null || Navigator.canPop(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E40AF), // Bizom royal blue
        foregroundColor: Colors.white,
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
        title: Row(
          children: [
            const Icon(Icons.store_mall_directory_rounded, size: 22, color: Colors.white),
            const SizedBox(width: 8),
            const Text(
              'RETAILER',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.8),
            ),
            const Spacer(),
            if (user != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person, size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      user.plainName,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box_rounded),
            tooltip: 'Add Product to Catalog',
            onPressed: _openAddProduct,
          ),
          if (!widget.isEmbedded)
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Sign Out',
              onPressed: () => auth.logout(),
            ),
        ],
        bottom: widget.isEmbedded
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Container(
                  color: const Color(0xFF1E3A8A),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    children: [
                      _buildHeaderTabChip(
                        title: 'Retailers (${pendingShops.length})',
                        icon: Icons.storefront,
                        isSelected: _currentBottomNavIndex == 0,
                        onTap: () => setState(() => _currentBottomNavIndex = 0),
                      ),
                      const SizedBox(width: 6),
                      _buildHeaderTabChip(
                        title: 'Route Map',
                        icon: Icons.map,
                        isSelected: _currentBottomNavIndex == 1,
                        onTap: () => setState(() => _currentBottomNavIndex = 1),
                      ),
                      const SizedBox(width: 6),
                      _buildHeaderTabChip(
                        title: 'Orders (${userDateOrders.length})',
                        icon: Icons.receipt_long,
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
          _buildRetailersTab(
            availableRoutes,
            selectedRoute,
            pendingShops,
            completedShops,
            allRouteShops,
            allDateOrders,
          ),
          _buildOrderMapTab(
            allRouteShops,
            completedShops,
            bookedShopIds,
          ),
          _buildTransactionsTab(userDateOrders),
        ],
      ),
      bottomNavigationBar: widget.isEmbedded
          ? null
          : NavigationBar(
              selectedIndex: _currentBottomNavIndex,
              onDestinationSelected: (idx) => setState(() => _currentBottomNavIndex = idx),
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.storefront_outlined),
                  selectedIcon: const Icon(Icons.storefront, color: Color(0xFF1E40AF)),
                  label: 'Retailers (${pendingShops.length})',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map, color: Color(0xFF1E40AF)),
                  label: 'Route Map',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.receipt_long_outlined),
                  selectedIcon: const Icon(Icons.receipt_long, color: Color(0xFF1E40AF)),
                  label: 'Orders (${userDateOrders.length})',
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
            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? const Color(0xFF1E40AF) : Colors.white70,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? const Color(0xFF1E40AF) : Colors.white,
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
  ) {
    final isToday = _isSameDay(_selectedDate, DateTime.now());

    return Column(
      children: [
        // Green "Today" Bar matching Bizom UI
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 6),
          color: const Color(0xFF16A34A),
          child: Text(
            isToday ? 'Today' : DateFormat('EEEE').format(_selectedDate),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),

        // Route & Date Selector
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            children: [
              // Date Switcher (< 21 November >)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 24, color: Color(0xFF64748B)),
                    onPressed: () => _stepDate(-1),
                  ),
                  InkWell(
                    onTap: _pickDate,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            DateFormat('dd MMMM yyyy').format(_selectedDate),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF1E40AF)),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, size: 24, color: Color(0xFF64748B)),
                    onPressed: () => _stepDate(1),
                  ),
                ],
              ),

              // Route Display / Dropdown
              if (availableRoutes.length > 1)
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedRouteId,
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down_circle_outlined, color: Color(0xFF1E40AF), size: 18),
                    items: availableRoutes.map((r) {
                      return DropdownMenuItem(
                        value: r.id,
                        child: Text(
                          r.name.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A)),
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
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E3A8A), letterSpacing: 0.5),
                ),
            ],
          ),
        ),

        // 3 Status Tabs: Pending (X) | Completed (Y) | All (Z)
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _retailerStatusTabController,
            indicatorColor: const Color(0xFF1E40AF),
            indicatorWeight: 3,
            labelColor: const Color(0xFF1E40AF),
            unselectedLabelColor: const Color(0xFF64748B),
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: [
              Tab(text: 'Pending (${pendingShops.length})'),
              Tab(text: 'Completed (${completedShops.length})'),
              Tab(text: 'All (${allRouteShops.length})'),
            ],
          ),
        ),

        // Search bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          color: Colors.white,
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search outlet name or address...',
                hintStyle: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                prefixIcon: Icon(Icons.search, size: 18, color: Color(0xFF64748B)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
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
              _buildShopsListView(pendingShops, false, dateOrders),
              _buildShopsListView(completedShops, true, dateOrders),
              _buildShopsListView(allRouteShops, null, dateOrders),
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
  ) {
    final filtered = shops.where((s) {
      if (_searchQuery.trim().isEmpty) return true;
      return MarathiSearchHelper.matches(s.name, _searchQuery) ||
          MarathiSearchHelper.matches(s.address, _searchQuery) ||
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

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: filtered.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (ctx, index) {
        final shop = filtered[index];
        final orderForShop = dateOrders.where((o) => o.shopId == shop.id).firstOrNull;
        final hasOrder = orderForShop != null;

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: hasOrder ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
              width: hasOrder ? 1.5 : 1.0,
            ),
          ),
          child: InkWell(
            onTap: () => hasOrder ? _showCompletedShopSheet(shop, orderForShop) : _openOutletOrder(shop),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Store Icon Box
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: hasOrder ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.storefront_rounded,
                          color: hasOrder ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Store Name & ID
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // Status chip matching Bizom UI
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: hasOrder ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    hasOrder ? 'Completed' : 'Not Started',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: hasOrder ? const Color(0xFF15803D) : const Color(0xFFB45309),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (shop.hasLocation)
                                  const Icon(Icons.check_circle, size: 14, color: Color(0xFF16A34A))
                                else
                                  const Icon(Icons.location_off_outlined, size: 14, color: Color(0xFF94A3B8)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              shop.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'ID: ${shop.id.length > 6 ? shop.id.substring(0, 6) : shop.id} • ${shop.address}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),

                      // Quick Action Menu
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF94A3B8)),
                        onSelected: (val) {
                          if (val == 'call' && shop.mobileNumber.isNotEmpty) {
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

                  // Bottom Subtext / Order Info
                  const SizedBox(height: 8),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Last Visited: ${DateFormat('dd MMMM yyyy').format(_selectedDate)}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                      ),
                      if (hasOrder)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF86EFAC)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check, size: 12, color: Color(0xFF16A34A)),
                              const SizedBox(width: 4),
                              Text(
                                '${CurrencyFormatter.format(orderForShop.totalAmount)} (${orderForShop.items.length} lines)',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF15803D)),
                              ),
                            ],
                          ),
                        )
                      else
                        const Row(
                          children: [
                            Text('Tap to book order', style: TextStyle(fontSize: 11, color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                            Icon(Icons.chevron_right, size: 14, color: Color(0xFF2563EB)),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
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
    final shopsWithLoc = allRouteShops.where((s) => s.latitude != null && s.longitude != null).toList();

    LatLng initialCenter = const LatLng(18.8567, 73.8847); // Default Khed / Pune
    if (shopsWithLoc.isNotEmpty) {
      initialCenter = LatLng(shopsWithLoc.first.latitude!, shopsWithLoc.first.longitude!);
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: 13.0,
            minZoom: 6.0,
            maxZoom: 18.0,
          ),
          children: [
            TileLayer(
              urlTemplate: _isSatellite
                  ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.purva.collection.app',
            ),
            MarkerLayer(
              markers: shopsWithLoc.map((s) {
                final hasOrder = bookedShopIds.contains(s.id);
                return Marker(
                  point: LatLng(s.latitude!, s.longitude!),
                  width: 40,
                  height: 40,
                  child: GestureDetector(
                    onTap: () => _showShopMapBottomSheet(s, hasOrder),
                    child: Container(
                      decoration: BoxDecoration(
                        color: hasOrder ? const Color(0xFF16A34A) : const Color(0xFF1E40AF),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                        ],
                      ),
                      child: Icon(
                        hasOrder ? Icons.check_circle_rounded : Icons.store_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),

        // Controls overlay
        Positioned(
          top: 12,
          right: 12,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'map_sat_toggle',
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F172A),
                onPressed: () => setState(() => _isSatellite = !_isSatellite),
                child: Icon(_isSatellite ? Icons.map_rounded : Icons.satellite_alt_rounded),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'map_recenter',
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F172A),
                onPressed: () {
                  if (shopsWithLoc.isNotEmpty) {
                    _mapController.move(LatLng(shopsWithLoc.first.latitude!, shopsWithLoc.first.longitude!), 13.0);
                  }
                },
                child: const Icon(Icons.my_location_rounded),
              ),
            ],
          ),
        ),

        // Bottom Map Summary Strip
        Positioned(
          bottom: 12,
          left: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Row(
                  children: [
                    Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('Completed (${completedShops.length})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                Row(
                  children: [
                    Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFF1E40AF), shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('Pending (${allRouteShops.length - completedShops.length})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
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
                'Booked: ₹${CurrencyFormatter.format(orderForShop.totalAmount)} (${orderForShop.totalCases} CS, ${orderForShop.totalLooseUnits} UT)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF15803D)),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                if (shop.mobileNumber.isNotEmpty) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.phone, size: 16),
                      label: const Text('Call'),
                      onPressed: () => launchUrl(Uri.parse('tel:${shop.mobileNumber}')),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (shop.mapsUrl != null) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.navigation, size: 16),
                      label: const Text('Navigate'),
                      onPressed: () => launchUrl(Uri.parse(shop.mapsUrl!), mode: LaunchMode.externalApplication),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E40AF)),
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

    final totalDayAmount = dateOrders.fold(0.0, (sum, o) => sum + o.totalAmount);
    final totalDayCases = dateOrders.fold(0, (sum, o) => sum + o.totalCases);
    final totalDayUnits = dateOrders.fold(0, (sum, o) => sum + o.totalLooseUnits);

    return Column(
      children: [
        // Summary Header Strip matching screenshot 13119784-f9d6-418d-9265-d1fbed783d06.jpeg
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildTransactionStat('Orders', '${dateOrders.length}'),
              _buildTransactionStat('Total Cases', '$totalDayCases CS'),
              _buildTransactionStat('Total Units', '$totalDayUnits UT'),
              _buildTransactionStat('Total Amount', CurrencyFormatter.format(totalDayAmount)),
            ],
          ),
        ),
        if (context.watch<AuthProvider>().currentUser?.isOrder != true)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                    Icon(Icons.filter_list_rounded, size: 16, color: Color(0xFF1E40AF)),
                    SizedBox(width: 6),
                    Text(
                      'Filter Orders by Staff (Akash, Atharva, Order 1) →',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const Divider(height: 1),

        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: dateOrders.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (ctx, index) {
              final order = dateOrders[index];

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            order.shopName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('✓ Order Fulfilled', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            order.salesmanName,
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Order: ${order.orderNumber} • ${DateFormat('hh:mm a').format(order.orderDate)}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 8),

                    // SKU Items
                    ...order.items.map((it) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(it.productName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                            Text('CS: ${it.cases}  UT: ${it.units}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                            const SizedBox(width: 10),
                            Text('₹${it.subtotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      );
                    }),

                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const SizedBox(height: 8),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total: ${order.totalCases} CS, ${order.totalLooseUnits} UT',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                        ),
                        Text(
                          CurrencyFormatter.format(order.totalAmount),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Sharing & Management actions
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
                            onPressed: () async {
                              final text = '📦 *Order #${order.orderNumber}* for *${order.shopName}*\nTotal: ₹${order.totalAmount} (${order.totalCases} CS, ${order.totalLooseUnits} UT)';
                              final url = Uri.parse('https://api.whatsapp.com/send?text=${Uri.encodeComponent(text)}');
                              try {
                                await launchUrl(url, mode: LaunchMode.externalApplication);
                              } catch (_) {}
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Edit Order',
                          icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF1E40AF), size: 22),
                          onPressed: () {
                            final shop = provider.allShops.where((s) => s.id == order.shopId).firstOrNull ??
                                ShopModel(id: order.shopId, name: order.shopName, address: '', routeId: order.routeId, routeName: order.routeName, mobileNumber: order.shopMobile);
                            _openOutletOrder(shop, existingOrder: order);
                          },
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
