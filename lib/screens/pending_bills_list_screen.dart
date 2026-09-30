import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/collection_provider.dart';
import '../models/pending_bill_model.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';
import '../widgets/fullscreen_image_viewer.dart';
import 'add_pending_bill_screen.dart';
import 'make_collection_screen.dart';

class PendingBillsListScreen extends StatefulWidget {
  final DateTime? initialInvoiceDate;
  final String? initialFirm;

  const PendingBillsListScreen({
    super.key,
    this.initialInvoiceDate,
    this.initialFirm,
  });

  @override
  State<PendingBillsListScreen> createState() => _PendingBillsListScreenState();
}

class _PendingBillsListScreenState extends State<PendingBillsListScreen> {
  DateTime? _selectedInvoiceDate;
  String? _selectedFirm;
  String? _selectedRouteId;
  String _searchQuery = '';
  String _statusFilter = 'pending'; // 'pending', 'all', 'paid'

  @override
  void initState() {
    super.initState();
    _selectedInvoiceDate = widget.initialInvoiceDate;
    _selectedFirm = widget.initialFirm;
  }

  Future<void> _pickInvoiceDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedInvoiceDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => _selectedInvoiceDate = picked);
    }
  }

  void _stepDate(int days) {
    setState(() {
      final base = _selectedInvoiceDate ?? DateTime.now();
      _selectedInvoiceDate = base.add(Duration(days: days));
    });
  }

  Future<void> _confirmDelete(PendingBillModel bill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Bill?'),
        content: Text('Delete Bill #${bill.billNumber} for "${bill.shopName}"?\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<CollectionProvider>().deletePendingBill(bill.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bill #${bill.billNumber} deleted'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CollectionProvider>();
    final allBills = provider.pendingBills;
    final routes = provider.routes;

    // Filter bills
    final filteredBills = allBills.where((b) {
      // Firm filter
      if (_selectedFirm != null && _selectedFirm!.isNotEmpty) {
        if (b.firmName != _selectedFirm) return false;
      }

      // Route filter
      if (_selectedRouteId != null && _selectedRouteId!.isNotEmpty) {
        if (b.routeId != _selectedRouteId) return false;
      }

      // Invoice Date filter
      if (_selectedInvoiceDate != null) {
        final filterStr = DateFormat('yyyy-MM-dd').format(_selectedInvoiceDate!);
        final billDateStr = DateFormat('yyyy-MM-dd').format(b.invoiceDate);
        if (billDateStr != filterStr) return false;
      }

      // Status filter
      if (_statusFilter == 'pending' && b.isPaid) return false;
      if (_statusFilter == 'paid' && !b.isPaid) return false;

      // Search query
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase().trim();
        return b.billNumber.toLowerCase().contains(q) ||
            b.shopName.toLowerCase().contains(q) ||
            b.routeName.toLowerCase().contains(q);
      }

      return true;
    }).toList();

    // Summary calculations
    final totalPendingAmount = filteredBills.fold(0.0, (sum, b) => sum + b.balanceDue);
    final totalBilledAmount = filteredBills.fold(0.0, (sum, b) => sum + b.totalAmount);

    final purvaPendingCount = allBills.where((b) => b.firmName == 'Purva Enterprises' && !b.isPaid).length;
    final manasPendingCount = allBills.where((b) => b.firmName == 'Manas Sales' && !b.isPaid).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Bills'),
        actions: [
          IconButton(
            icon: const Icon(Icons.note_add_outlined, size: 22),
            tooltip: 'Upload New Bill',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddPendingBillScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Bar
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Firm Selector (All / Purva / Manas)
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      // All Firms
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _selectedFirm = null),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: _selectedFirm == null ? AppTheme.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                'All Firms',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: _selectedFirm == null ? Colors.white : Colors.blueGrey.shade800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Purva
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _selectedFirm = 'Purva Enterprises'),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: _selectedFirm == 'Purva Enterprises' ? AppTheme.purvaPrimary : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                'Purva ($purvaPendingCount)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: _selectedFirm == 'Purva Enterprises' ? Colors.white : AppTheme.purvaText,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Manas
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _selectedFirm = 'Manas Sales'),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: _selectedFirm == 'Manas Sales' ? AppTheme.manasPrimary : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                'Manas ($manasPendingCount)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: _selectedFirm == 'Manas Sales' ? Colors.white : AppTheme.manasText,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Invoice Date Filter Bar
                Row(
                  children: [
                    // Date Pill with Calendar Picker
                    Expanded(
                      child: InkWell(
                        onTap: _pickInvoiceDate,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedInvoiceDate != null
                                ? AppTheme.primary.withValues(alpha: 0.08)
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _selectedInvoiceDate != null ? AppTheme.primary : AppTheme.border,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 16,
                                color: _selectedInvoiceDate != null ? AppTheme.primary : Colors.blueGrey,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _selectedInvoiceDate != null
                                      ? 'Invoice Date: ${DateFormat('dd MMM yyyy').format(_selectedInvoiceDate!)}'
                                      : 'All Dates',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: _selectedInvoiceDate != null ? AppTheme.primary : Colors.blueGrey.shade800,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    if (_selectedInvoiceDate != null) ...[
                      const SizedBox(width: 4),
                      // Previous Day (<)
                      IconButton(
                        icon: const Icon(Icons.chevron_left, size: 20),
                        tooltip: 'Previous Day',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _stepDate(-1),
                      ),
                      // Next Day (>)
                      IconButton(
                        icon: const Icon(Icons.chevron_right, size: 20),
                        tooltip: 'Next Day',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _stepDate(1),
                      ),
                      // Clear (All Dates)
                      InkWell(
                        onTap: () => setState(() => _selectedInvoiceDate = null),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.close, size: 16, color: Colors.blueGrey),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(width: 6),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade100,
                          foregroundColor: Colors.blueGrey.shade800,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => setState(() => _selectedInvoiceDate = DateTime.now()),
                        child: const Text('Today', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),

                // Route Filter Dropdown & Status Filter Chips
                Row(
                  children: [
                    // Route Dropdown
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        initialValue: _selectedRouteId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          hintText: 'All Routes',
                          prefixIcon: const Icon(Icons.location_on_outlined, size: 16),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All Routes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                          ...routes.map(
                            (r) => DropdownMenuItem<String?>(
                              value: r.id,
                              child: Text(r.name, style: const TextStyle(fontSize: 12)),
                            ),
                          ),
                        ],
                        onChanged: (val) => setState(() => _selectedRouteId = val),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Status Dropdown
                    DropdownButton<String>(
                      value: _statusFilter,
                      underline: const SizedBox(),
                      borderRadius: BorderRadius.circular(8),
                      items: const [
                        DropdownMenuItem(
                          value: 'pending',
                          child: Text('Pending Only', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFD97706))),
                        ),
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('All Bills', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        DropdownMenuItem(
                          value: 'paid',
                          child: Text('Paid Only', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _statusFilter = val);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Search Box
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search bill, store...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () => setState(() => _searchQuery = ''),
                          )
                        : null,
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Subtotal Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: Colors.grey.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${filteredBills.length} Bills',
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade800, fontWeight: FontWeight.w700),
                ),
                Row(
                  children: [
                    Text(
                      'Billed: ${CurrencyFormatter.format(totalBilledAmount)}  |  ',
                      style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade600),
                    ),
                    Text(
                      'Due: ${CurrencyFormatter.format(totalPendingAmount)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.partialBadgeColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // List of Pending Bills
          Expanded(
            child: filteredBills.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 54, color: Colors.blueGrey.shade200),
                          const SizedBox(height: 12),
                          Text(
                            _selectedInvoiceDate != null
                                ? 'No pending bills found for ${DateFormat('dd MMM yyyy').format(_selectedInvoiceDate!)}'
                                : 'No pending bills recorded yet',
                            style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 14, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Delivered bills uploaded by delivery staff will appear here for collection.',
                            style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add Bill'),
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AddPendingBillScreen(
                                    initialInvoiceDate: _selectedInvoiceDate,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: filteredBills.length,
                    itemBuilder: (context, index) {
                      final bill = filteredBills[index];
                      final isPurva = bill.firmName == 'Purva Enterprises';
                      final isPaid = bill.isPaid;
                      final isPartial = bill.status == 'partial';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: isPaid
                                ? Colors.green.shade200
                                : (isPartial ? Colors.amber.shade200 : AppTheme.border),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header: Bill Number, Firm Tag, Status Badge, & Menu
                              Row(
                                children: [
                                  // Firm Tag
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isPurva ? AppTheme.purvaLight : AppTheme.manasLight,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: isPurva ? AppTheme.purvaBorder : AppTheme.manasBorder,
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Text(
                                      isPurva ? 'PURVA' : 'MANAS',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: isPurva ? AppTheme.purvaText : AppTheme.manasText,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Bill Number
                                  Text(
                                    'Bill #${bill.billNumber}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const Spacer(),

                                  // Status Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isPaid
                                          ? const Color(0xFFDCFCE7)
                                          : (isPartial ? const Color(0xFFFEF3C7) : const Color(0xFFFEE2E2)),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isPaid ? 'PAID' : (isPartial ? 'PARTIAL' : 'PENDING'),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: isPaid
                                            ? const Color(0xFF166534)
                                            : (isPartial ? const Color(0xFF92400E) : const Color(0xFF991B1B)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),

                                  // Delete / Options
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, size: 18, color: Colors.blueGrey),
                                    padding: EdgeInsets.zero,
                                    tooltip: 'Options',
                                    onSelected: (val) {
                                      if (val == 'delete') {
                                        _confirmDelete(bill);
                                      }
                                    },
                                    itemBuilder: (ctx) => [
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline, color: AppTheme.error, size: 18),
                                            SizedBox(width: 8),
                                            Text('Delete Bill', style: TextStyle(color: AppTheme.error)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),

                              // Store Name & Route
                              Row(
                                children: [
                                  const Icon(Icons.storefront, size: 16, color: AppTheme.primary),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      bill.shopName,
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0F172A),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  const Icon(Icons.place_outlined, size: 13, color: Colors.blueGrey),
                                  const SizedBox(width: 4),
                                  Text(
                                    bill.routeName,
                                    style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Dates Row (Invoice Date & Delivery Date)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          const Icon(Icons.event_note, size: 13, color: Colors.blueGrey),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Inv: ${DateFormat('dd MMM yyyy').format(bill.invoiceDate)}',
                                            style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade800, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(width: 1, height: 14, color: Colors.grey.shade300),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Row(
                                        children: [
                                          const Icon(Icons.local_shipping_outlined, size: 13, color: Colors.blueGrey),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Del: ${DateFormat('dd MMM yyyy').format(bill.deliveryDate)}',
                                            style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade800, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Amounts and Photo Thumbnail Row
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Photo thumbnail if uploaded
                                  if (bill.photoBase64 != null) ...[
                                    InkWell(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => FullScreenImageViewer(
                                              imageBase64: bill.photoBase64!,
                                              title: 'Bill #${bill.billNumber} - ${bill.shopName}',
                                            ),
                                          ),
                                        );
                                      },
                                      child: Stack(
                                        alignment: Alignment.bottomRight,
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(6),
                                            child: Image.memory(
                                              base64Decode(bill.photoBase64!),
                                              width: 52,
                                              height: 52,
                                              fit: BoxFit.cover,
                                              errorBuilder: (ctx, err, stack) => Container(
                                                width: 52,
                                                height: 52,
                                                color: Colors.grey.shade200,
                                                child: const Icon(Icons.broken_image, size: 20),
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(alpha: 0.6),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Icon(Icons.zoom_in, size: 12, color: Colors.white),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                  ],

                                  // Financials
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Total Bill: ${CurrencyFormatter.format(bill.totalAmount)}',
                                              style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700),
                                            ),
                                            if (bill.collectedAmount > 0)
                                              Text(
                                                'Paid: ${CurrencyFormatter.format(bill.collectedAmount)}',
                                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF16A34A), fontWeight: FontWeight.w600),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          isPaid
                                              ? 'Balance: Cleared'
                                              : 'Due: ${CurrencyFormatter.format(bill.balanceDue)}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: isPaid ? const Color(0xFF16A34A) : AppTheme.partialBadgeColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              // Collect Action Button
                              if (!isPaid) ...[
                                const Divider(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        icon: const Icon(Icons.payments_outlined, size: 16),
                                        label: Text(
                                          'Collect ${CurrencyFormatter.format(bill.balanceDue)}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF0D9488),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        ),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => MakeCollectionScreen(
                                                initialBusiness: bill.firmName,
                                                initialRouteId: bill.routeId,
                                                initialPendingBillId: bill.id,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
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
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'pending_bills_list_fab',
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Bill', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddPendingBillScreen(
                initialInvoiceDate: _selectedInvoiceDate,
              ),
            ),
          );
        },
      ),
    );
  }
}
