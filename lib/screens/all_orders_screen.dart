import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/order_model.dart';
import '../models/shop_model.dart';
import '../providers/auth_provider.dart';
import '../providers/collection_provider.dart';
import '../services/godown_billing_pdf_service.dart';
import '../utils/currency_formatter.dart';
import '../utils/marathi_search_helper.dart';
import '../utils/theme.dart';
import 'outlet_order_booking_screen.dart';
import '../widgets/tally_sync_dialog.dart';

class AllOrdersScreen extends StatefulWidget {
  final DateTime? initialDate;
  final String? initialStaffName;

  const AllOrdersScreen({
    super.key,
    this.initialDate,
    this.initialStaffName,
  });

  @override
  State<AllOrdersScreen> createState() => _AllOrdersScreenState();
}

class _AllOrdersScreenState extends State<AllOrdersScreen> {
  late DateTime _selectedDate;
  bool _allDates = false;
  String _selectedFirm = 'ALL';
  String _selectedStatus = 'ALL';
  String _selectedStaff = 'ALL';
  String _selectedRouteId = 'ALL';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    if (widget.initialStaffName != null && widget.initialStaffName!.isNotEmpty) {
      _selectedStaff = widget.initialStaffName!;
    }
  }

  @override
  void dispose() {
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

  Color _getStaffColor(String staffName) {
    final s = staffName.toLowerCase();
    if (s.contains('akash')) return const Color(0xFFD97706); // Amber
    if (s.contains('atharva')) return const Color(0xFF7C3AED); // Purple
    if (s.contains('order')) return const Color(0xFF2563EB); // Royal Blue
    if (s.contains('admin')) return const Color(0xFF0D9488); // Teal
    return const Color(0xFF475569); // Slate
  }

  IconData _getStaffIcon(String staffName) {
    final s = staffName.toLowerCase();
    if (s.contains('akash') || s.contains('atharva')) return Icons.two_wheeler_rounded;
    if (s.contains('order')) return Icons.shopping_bag_rounded;
    if (s.contains('admin')) return Icons.shield_rounded;
    return Icons.person_rounded;
  }

  Future<void> _shareOnWhatsApp(SalesOrderModel order) async {
    final buffer = StringBuffer();
    buffer.writeln('*${order.firm.toUpperCase()} - STORE ORDER*');
    buffer.writeln('--------------------------------');
    buffer.writeln('Order No: ${order.orderNumber}');
    buffer.writeln('Store: ${order.shopName}');
    buffer.writeln('Route: ${order.routeName}');
    buffer.writeln('Booked By: ${order.salesmanName}');
    buffer.writeln('Date: ${DateFormat('dd-MMM-yyyy hh:mm a').format(order.orderDate)}');
    buffer.writeln('--------------------------------');
    buffer.writeln('*ORDERED ITEMS:*');
    for (int i = 0; i < order.items.length; i++) {
      final it = order.items[i];
      buffer.writeln('${i + 1}. ${it.productName} [${it.subcategory}]');
      if (it.rate > 0) {
        buffer.writeln('   Qty: ${it.cases} CS + ${it.units} UT @ ₹${it.rate.toStringAsFixed(2)} = ${CurrencyFormatter.format(it.subtotal)}');
      } else {
        buffer.writeln('   Qty: ${it.cases} CS + ${it.units} UT (${it.totalUnits} ${it.unit})');
      }
    }
    buffer.writeln('--------------------------------');
    buffer.writeln('*Total CS:* ${order.totalCases} Cases');
    buffer.writeln('*Total UT:* ${order.totalLooseUnits} Loose');
    if (order.totalWeightKg > 0) {
      buffer.writeln('*Total Weight:* ${order.totalWeightKg.toStringAsFixed(2)} kg');
    }
    if (order.totalAmount > 0) {
      buffer.writeln('*GRAND TOTAL: ${CurrencyFormatter.format(order.totalAmount)}*');
    }
    if (order.notes != null && order.notes!.isNotEmpty) {
      buffer.writeln('Notes: ${order.notes}');
    }

    final url = Uri.parse('https://api.whatsapp.com/send?text=${Uri.encodeComponent(buffer.toString())}');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
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
                        : 'Deleted locally (will sync deletion when online)'),
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

  Future<void> _openEditOrder(SalesOrderModel order) async {
    final provider = Provider.of<CollectionProvider>(context, listen: false);
    final shop = provider.allShops.where((s) => s.id == order.shopId).firstOrNull ??
        ShopModel(
          id: order.shopId,
          name: order.shopName,
          address: '',
          routeId: order.routeId,
          routeName: order.routeName,
          mobileNumber: order.shopMobile,
        );

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => OutletOrderBookingScreen(
          shop: shop,
          selectedDate: order.orderDate,
          existingOrder: order,
        ),
      ),
    );
    if (result == true && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<CollectionProvider>();
    final accessibleRoutes = provider.routes;
    final isToday = _isSameDay(_selectedDate, DateTime.now());

    // Orders scoped to current user's accessible scope + selected date (or All Dates)
    var dateOrders = provider.getAccessibleSalesOrders(auth.currentUser).where((o) {
      if (!_allDates && !_isSameDay(o.orderDate, _selectedDate)) return false;
      return true;
    }).toList();

    if (_selectedFirm != 'ALL') {
      dateOrders = dateOrders.where((o) => o.firm == _selectedFirm).toList();
    }

    if (_selectedStatus != 'ALL') {
      dateOrders = dateOrders.where((o) => o.status == _selectedStatus).toList();
    }

    // Collect distinct staff names who have orders or are order/sales users
    final Set<String> staffSet = {};
    for (final o in dateOrders) {
      if (o.salesmanName.isNotEmpty) {
        staffSet.add(o.salesmanName);
      }
    }
    // Also add known staff from auth users
    for (final u in auth.users) {
      if (u.canAccessOrders) {
        staffSet.add(u.plainName);
      }
    }
    final sortedStaffList = staffSet.toList()..sort();

    // Filter by staff
    final validStaffSelection = (_selectedStaff == 'ALL' || sortedStaffList.contains(_selectedStaff))
        ? _selectedStaff
        : 'ALL';

    var filteredOrders = dateOrders;

    if (validStaffSelection != 'ALL') {
      filteredOrders = filteredOrders
          .where((o) => o.salesmanName.toLowerCase().trim() == validStaffSelection.toLowerCase().trim())
          .toList();
    }

    if (_selectedRouteId != 'ALL') {
      filteredOrders = filteredOrders
          .where((o) => o.routeId == _selectedRouteId)
          .toList();
    }

    // Filter by search query (shop name, order number, route name)
    filteredOrders = filteredOrders.where((o) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase().trim();
      return MarathiSearchHelper.matches(o.shopName, q) ||
          o.orderNumber.toLowerCase().contains(q) ||
          o.routeName.toLowerCase().contains(q) ||
          o.salesmanName.toLowerCase().contains(q);
    }).toList();

    // Calculate totals for filtered orders
    final totalAmount = filteredOrders.fold(0.0, (sum, o) => sum + o.totalAmount);
    final totalCases = filteredOrders.fold(0, (sum, o) => sum + o.totalCases);
    final totalUnits = filteredOrders.fold(0, (sum, o) => sum + o.totalLooseUnits);
    final totalWeight = filteredOrders.fold(0.0, (sum, o) => sum + o.totalWeightKg);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primary,
        elevation: 0,
        title: const Text('Orders Master'),
        actions: [
          if (filteredOrders.isNotEmpty) ...[
            if (auth.currentUser?.canAccessTally == true)
              IconButton(
                icon: const Icon(Icons.swap_horiz_rounded, color: AppTheme.primary),
                tooltip: 'Export Orders to Tally XML',
                onPressed: () => TallySyncDialog.show(
                  context,
                  initialTabIndex: 0,
                  initialFirm: _selectedFirm == 'ALL' ? null : _selectedFirm,
                ),
              ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_rounded, color: AppTheme.primary),
              tooltip: 'Export Godown Slip PDF',
              onPressed: () {
                GodownBillingPdfService.previewOrSharePdf(
                  context,
                  orders: filteredOrders,
                  salesmanName: _selectedStaff == 'ALL' ? 'All Staff' : _selectedStaff,
                  firmFilter: _selectedFirm == 'ALL' ? null : _selectedFirm,
                  reportDate: _allDates ? null : _selectedDate,
                );
              },
            ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.primary),
            tooltip: 'Refresh',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final ok = await provider.syncAllWithCloud(notify: true);
              if (mounted) {
                setState(() {});
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Orders synced from cloud' : 'Showing offline cached orders'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Date Selector Bar + All Dates toggle
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                if (!_allDates)
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 24, color: Color(0xFF0F172A)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _stepDate(-1),
                  ),
                Expanded(
                  child: InkWell(
                    onTap: _allDates ? () => setState(() => _allDates = false) : _pickDate,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _allDates ? Icons.date_range_rounded : Icons.calendar_today_rounded,
                            size: 14,
                            color: _allDates
                                ? AppTheme.purvaPrimary
                                : (isToday ? const Color(0xFF16A34A) : const Color(0xFF1E3A8A)),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _allDates
                                  ? 'All Dates'
                                  : (isToday
                                      ? 'Today: ${DateFormat('dd MMM yyyy').format(_selectedDate)}'
                                      : DateFormat('EEE, dd MMM yyyy').format(_selectedDate)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _allDates
                                    ? AppTheme.purvaPrimary
                                    : (isToday ? const Color(0xFF16A34A) : const Color(0xFF0F172A)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!_allDates)
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, size: 24, color: Color(0xFF0F172A)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _stepDate(1),
                  ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => setState(() => _allDates = !_allDates),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _allDates ? AppTheme.purvaPrimary : AppTheme.subtleSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _allDates ? AppTheme.purvaPrimary : AppTheme.border),
                    ),
                    child: Text(
                      'All Dates',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: _allDates ? Colors.white : AppTheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Firm Segmented Pill (All | Purva | Manas)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppTheme.subtleSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  _buildFirmFilterBtn('All Firms', 'ALL', AppTheme.primary),
                  _buildFirmFilterBtn('Purva', 'Purva Enterprises', AppTheme.purvaPrimary),
                  _buildFirmFilterBtn('Manas', 'Manas Sales', AppTheme.manasPrimary),
                ],
              ),
            ),
          ),

          // Status Filter Chips
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['ALL', 'Booked', 'Dispatched', 'Billed', 'Delivered', 'Cancelled']
                    .map((status) {
                  final selected = _selectedStatus == status;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(status == 'ALL' ? 'All Status' : status),
                      selected: selected,
                      visualDensity: VisualDensity.compact,
                      selectedColor: AppTheme.primary.withValues(alpha: 0.12),
                      labelStyle: TextStyle(
                        fontSize: 11,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected ? AppTheme.primary : AppTheme.textSecondary,
                      ),
                      onSelected: (_) => setState(() => _selectedStatus = status),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // 2. Filter Dropdowns Bar (Staff & Route Filter)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(
              children: [
                // Staff Selector Dropdown
                Expanded(
                  flex: 6,
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: validStaffSelection,
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF1E3A8A)),
                        items: [
                          DropdownMenuItem<String>(
                            value: 'ALL',
                            child: Row(
                              children: [
                                const Icon(Icons.groups_rounded, size: 16, color: Color(0xFF1E3A8A)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'All Staff (${dateOrders.length})',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...sortedStaffList.map((staff) {
                            final count = dateOrders.where((o) => o.salesmanName.toLowerCase().trim() == staff.toLowerCase().trim()).length;
                            final color = _getStaffColor(staff);
                            return DropdownMenuItem<String>(
                              value: staff,
                              child: Row(
                                children: [
                                  Icon(_getStaffIcon(staff), size: 16, color: color),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '$staff ($count)',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedStaff = val);
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Route Selector Dropdown
                Expanded(
                  flex: 5,
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: accessibleRoutes.any((r) => r.id == _selectedRouteId) ? _selectedRouteId : 'ALL',
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF0F766E)),
                        items: [
                          const DropdownMenuItem<String>(
                            value: 'ALL',
                            child: Row(
                              children: [
                                Icon(Icons.alt_route_rounded, size: 16, color: Color(0xFF0F766E)),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'All Routes',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...accessibleRoutes.map((r) {
                            return DropdownMenuItem<String>(
                              value: r.id,
                              child: Row(
                                children: [
                                  const Icon(Icons.place_outlined, size: 15, color: Color(0xFF475569)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      r.name,
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedRouteId = val);
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. Search Bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search by store, route, order #...',
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
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
            ),
          ),

          // 4. Clean White Executive Summary Strip
          Container(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryCol('Orders', '${filteredOrders.length}'),
                _buildSummaryDivider(),
                _buildSummaryCol('Cases', '$totalCases CS'),
                _buildSummaryDivider(),
                _buildSummaryCol('Units', '$totalUnits UT'),
                if (totalWeight > 0) ...[
                  _buildSummaryDivider(),
                  _buildSummaryCol('Weight', '${totalWeight.toStringAsFixed(1)} kg'),
                ],
                if (totalAmount > 0) ...[
                  _buildSummaryDivider(),
                  _buildSummaryCol('Value', CurrencyFormatter.format(totalAmount), isBoldVal: true),
                ],
              ],
            ),
          ),

          // 5. Orders List
          Expanded(
            child: filteredOrders.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 54, color: Color(0xFF94A3B8)),
                          const SizedBox(height: 12),
                          Text(
                            _selectedStaff == 'ALL'
                                ? 'No store orders found for this date'
                                : 'No store orders booked by $_selectedStaff on this date',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Book store orders via "Book Orders" on Overview.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    itemCount: filteredOrders.length,
                    itemBuilder: (context, idx) {
                      final order = filteredOrders[idx];
                      return _buildOrderCard(order);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFirmFilterBtn(String label, String firmKey, Color activeColor) {
    final isSelected = _selectedFirm == firmKey;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedFirm = firmKey),
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCol(String label, String value, {bool isBoldVal = false}) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTheme.tabularAmount(
            fontSize: isBoldVal ? 13 : 12.5,
            fontWeight: FontWeight.w800,
            color: isBoldVal ? AppTheme.purvaPrimary : AppTheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryDivider() {
    return Container(
      width: 1,
      height: 24,
      color: AppTheme.border,
    );
  }

  Widget _buildOrderCard(SalesOrderModel order) {
    final staffColor = _getStaffColor(order.salesmanName);
    final staffIcon = _getStaffIcon(order.salesmanName);
    final isPurva = order.firm == 'Purva Enterprises';
    final firmColor = isPurva ? AppTheme.purvaPrimary : AppTheme.manasPrimary;
    final canUpdateStatus = context.read<AuthProvider>().currentUser?.canAccessTally == true;
    final statusColor = order.status == 'Billed' || order.status == 'Delivered'
        ? AppTheme.manasPrimary
        : (order.status == 'Cancelled' ? AppTheme.balanceDueColor : AppTheme.purvaPrimary);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      elevation: 0,
      color: Colors.white,
      child: ExpansionTile(
        key: ValueKey('order_card_${order.id}'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: staffColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(staffIcon, color: staffColor, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                order.shopName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: canUpdateStatus
                  ? () => _showStatusPicker(order)
                  : null,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  order.status,
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: statusColor),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              order.totalAmount > 0
                  ? CurrencyFormatter.format(order.totalAmount)
                  : '${order.totalCases} CS, ${order.totalLooseUnits} UT',
              style: AppTheme.tabularAmount(fontWeight: FontWeight.w800, fontSize: 13, color: const Color(0xFF16A34A)),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: firmColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isPurva ? 'PURVA' : 'MANAS',
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: firmColor),
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: staffColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(staffIcon, size: 11, color: staffColor),
                    const SizedBox(width: 3),
                    Text(
                      order.salesmanName,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: staffColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${order.routeName} • ${DateFormat('hh:mm a').format(order.orderDate)}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        children: [
          const Divider(height: 12),
          // Quantity info chips
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Order: ${order.orderNumber}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                ),
              ),
              const Spacer(),
              Text(
                order.totalWeightKg > 0
                    ? '${order.totalCases} CS + ${order.totalLooseUnits} UT (${order.totalWeightKg.toStringAsFixed(1)} kg)'
                    : '${order.totalCases} CS + ${order.totalLooseUnits} UT',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Items List
          for (final it in order.items) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3.0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          it.productName,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                        ),
                        Text(
                          '${it.subcategory} • 1 CS = ${it.unitsPerCase} UT',
                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${it.cases} CS + ${it.units} UT',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                  ),
                  if (it.subtotal > 0) ...[
                    const SizedBox(width: 14),
                    Text(
                      CurrencyFormatter.format(it.subtotal),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                    ),
                  ],
                ],
              ),
            ),
          ],

          if (order.notes != null && order.notes!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Note: ${order.notes}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF92400E)),
              ),
            ),
          ],

          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 15, color: Color(0xFF1E3A8A)),
                  label: const Text('Godown Slip', style: TextStyle(fontSize: 12, color: Color(0xFF1E3A8A))),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: const BorderSide(color: Color(0xFF1E3A8A)),
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
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.send_rounded, size: 15, color: Colors.white),
                  label: const Text('WhatsApp', style: TextStyle(fontSize: 12, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () => _shareOnWhatsApp(order),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Edit Order',
                icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF1E3A8A), size: 22),
                onPressed: () => _openEditOrder(order),
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
  }

  void _showStatusPicker(SalesOrderModel order) {
    const statuses = ['Booked', 'Dispatched', 'Billed', 'Delivered', 'Cancelled'];
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Order Status • ${order.orderNumber}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              for (final st in statuses)
                ListTile(
                  leading: Icon(
                    order.status == st ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: order.status == st ? AppTheme.purvaPrimary : AppTheme.textSecondary,
                  ),
                  title: Text(st, style: TextStyle(fontWeight: order.status == st ? FontWeight.w700 : FontWeight.w500)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await context.read<CollectionProvider>().updateSalesOrderStatus(order.id, st);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
