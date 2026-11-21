import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/order_model.dart';
import '../providers/auth_provider.dart';
import '../providers/collection_provider.dart';
import '../services/godown_billing_pdf_service.dart';
import '../utils/currency_formatter.dart';
import '../utils/marathi_search_helper.dart';

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
  String _selectedStaff = 'ALL';
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
    buffer.writeln('*PURVA ENTERPRISES - STORE ORDER*');
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
      buffer.writeln('   Qty: ${it.cases} CS + ${it.units} UT @ ₹${it.rate.toStringAsFixed(2)} = ₹${CurrencyFormatter.format(it.subtotal)}');
    }
    buffer.writeln('--------------------------------');
    buffer.writeln('*Total CS:* ${order.totalCases} Cases');
    buffer.writeln('*Total UT:* ${order.totalLooseUnits} Loose');
    buffer.writeln('*Total Weight:* ${order.totalWeightKg.toStringAsFixed(2)} kg');
    buffer.writeln('*GRAND TOTAL: ₹${CurrencyFormatter.format(order.totalAmount)}*');
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
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<CollectionProvider>();
    final isToday = _isSameDay(_selectedDate, DateTime.now());

    // All orders matching selected date
    final dateOrders = provider.salesOrders
        .where((o) => _isSameDay(o.orderDate, _selectedDate))
        .toList();

    // Collect distinct staff names who have orders or are order/sales users
    final Set<String> staffSet = {};
    for (final o in dateOrders) {
      if (o.salesmanName.isNotEmpty) {
        staffSet.add(o.salesmanName);
      }
    }
    // Also add known staff from auth users
    for (final u in auth.users) {
      if (u.isSalesman || u.isOrder || u.isSuperAdmin) {
        staffSet.add(u.plainName);
      }
    }
    final sortedStaffList = staffSet.toList()..sort();

    // Filter by staff
    final staffFilteredOrders = _selectedStaff == 'ALL'
        ? dateOrders
        : dateOrders.where((o) => o.salesmanName.toLowerCase().trim() == _selectedStaff.toLowerCase().trim()).toList();

    // Filter by search query (shop name, order number, route name)
    final filteredOrders = staffFilteredOrders.where((o) {
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
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A8A), // Deep navy
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Store Orders Master',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 0.3),
            ),
            Text(
              'Separated staff orders & godown slips',
              style: TextStyle(fontSize: 11, color: Color(0xFF93C5FD)),
            ),
          ],
        ),
        actions: [
          if (filteredOrders.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
              tooltip: 'Export Godown Slip PDF',
              onPressed: () {
                GodownBillingPdfService.previewOrSharePdf(
                  context,
                  orders: filteredOrders,
                  salesmanName: _selectedStaff == 'ALL' ? 'All Staff' : _selectedStaff,
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: () async {
              await provider.syncAllWithCloud(notify: true);
              setState(() {});
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Date Selector Bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, size: 24, color: Color(0xFF0F172A)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _stepDate(-1),
                ),
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
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
                          Icon(Icons.calendar_today_rounded, size: 14, color: isToday ? const Color(0xFF16A34A) : const Color(0xFF1E3A8A)),
                          const SizedBox(width: 6),
                          Text(
                            isToday ? 'Today: ${DateFormat('dd MMM yyyy').format(_selectedDate)}' : DateFormat('EEE, dd MMM yyyy').format(_selectedDate),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isToday ? const Color(0xFF16A34A) : const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, size: 24, color: Color(0xFF0F172A)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _stepDate(1),
                ),
              ],
            ),
          ),

          // 2. Staff Filter Chips (Separated: All Staff, Akash, Atharva, Order 1, etc.)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildStaffFilterChip(
                    label: 'All Staff',
                    staffName: 'ALL',
                    count: dateOrders.length,
                    isSelected: _selectedStaff == 'ALL',
                    color: const Color(0xFF1E3A8A),
                    icon: Icons.groups_rounded,
                  ),
                  for (final staff in sortedStaffList) ...[
                    const SizedBox(width: 8),
                    _buildStaffFilterChip(
                      label: staff,
                      staffName: staff,
                      count: dateOrders.where((o) => o.salesmanName.toLowerCase().trim() == staff.toLowerCase().trim()).length,
                      isSelected: _selectedStaff.toLowerCase().trim() == staff.toLowerCase().trim(),
                      color: _getStaffColor(staff),
                      icon: _getStaffIcon(staff),
                    ),
                  ],
                ],
              ),
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

          // 4. Summary Strip
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1E3A8A).withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryCol('Orders', '${filteredOrders.length}'),
                _buildSummaryDivider(),
                _buildSummaryCol('Total Cases', '$totalCases CS'),
                _buildSummaryDivider(),
                _buildSummaryCol('Loose Units', '$totalUnits UT'),
                _buildSummaryDivider(),
                _buildSummaryCol('Weight', '${totalWeight.toStringAsFixed(1)} kg'),
                _buildSummaryDivider(),
                _buildSummaryCol('Total Value', '₹${CurrencyFormatter.format(totalAmount)}', isBoldVal: true),
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

  Widget _buildStaffFilterChip({
    required String label,
    required String staffName,
    required int count,
    required bool isSelected,
    required Color color,
    required IconData icon,
  }) {
    return InkWell(
      onTap: () => setState(() => _selectedStaff = staffName),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : color,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : color,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withValues(alpha: 0.25) : color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCol(String label, String value, {bool isBoldVal = false}) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFFBFDBFE), fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: isBoldVal ? 13 : 12.5,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryDivider() {
    return Container(
      width: 1,
      height: 24,
      color: Colors.white.withValues(alpha: 0.2),
    );
  }

  Widget _buildOrderCard(SalesOrderModel order) {
    final staffColor = _getStaffColor(order.salesmanName);
    final staffIcon = _getStaffIcon(order.salesmanName);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      elevation: 0,
      color: Colors.white,
      child: ExpansionTile(
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
            Text(
              '₹${CurrencyFormatter.format(order.totalAmount)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF16A34A)),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Row(
            children: [
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
                '${order.totalCases} CS + ${order.totalLooseUnits} UT (${order.totalWeightKg.toStringAsFixed(1)} kg)',
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
                  const SizedBox(width: 14),
                  Text(
                    '₹${CurrencyFormatter.format(it.subtotal)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                  ),
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
              const SizedBox(width: 8),
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
            ],
          ),
        ],
      ),
    );
  }
}
