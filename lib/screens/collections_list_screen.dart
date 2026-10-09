import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/collection_provider.dart';
import '../models/payment_mode.dart';
import '../models/bill_summary.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';
import 'collection_details_dialog.dart';
import 'make_collection_screen.dart';
import 'send_reminder_dialog.dart';
import 'add_shop_screen.dart';
import '../widgets/fullscreen_image_viewer.dart';
import '../utils/image_compress_helper.dart';
import '../models/shop_model.dart';
import '../utils/marathi_search_helper.dart';

class CollectionsListScreen extends StatefulWidget {
  final int initialTabIndex;

  const CollectionsListScreen({super.key, this.initialTabIndex = 0});

  @override
  State<CollectionsListScreen> createState() => _CollectionsListScreenState();
}

enum InvoiceFilterStatus { pending, paid, all }

class _CollectionsListScreenState extends State<CollectionsListScreen> {
  PaymentMode? _selectedModeFilter;
  InvoiceFilterStatus _invoiceStatusFilter = InvoiceFilterStatus.all;
  String _invoiceSearchQuery = '';
  DateTime? _invoiceDateFilter;
  String? _invoiceRouteIdFilter;
  String? _invoiceShopIdFilter;

  Color _getModeColor(PaymentMode mode) {
    switch (mode) {
      case PaymentMode.cash:
        return AppTheme.cashColor;
      case PaymentMode.upi:
        return AppTheme.upiColor;
      case PaymentMode.cheque:
        return AppTheme.chequeColor;
      case PaymentMode.netBanking:
        return AppTheme.netBankingColor;
    }
  }

  Future<void> _pickDate(BuildContext context) async {
    final provider = context.read<CollectionProvider>();
    final picked = await showDatePicker(
      context: context,
      initialDate: provider.selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      provider.setSelectedDate(picked);
    }
  }

  void _shareSummary(BuildContext context) {
    final provider = context.read<CollectionProvider>();
    final text = provider.generateWhatsAppReportText();

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Daily Report copied to clipboard'),
        backgroundColor: AppTheme.secondary,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CollectionProvider>();

    return DefaultTabController(
      initialIndex: widget.initialTabIndex,
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ledger'),
          actions: [
            IconButton(
              icon: const Icon(Icons.add_business_outlined, size: 21),
              tooltip: 'Add Outlet',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddShopScreen()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined, size: 20),
              tooltip: 'Copy',
              onPressed: () => _shareSummary(context),
            ),
            IconButton(
              icon: const Icon(Icons.calendar_month_outlined, size: 20),
              tooltip: 'Date',
              onPressed: () => _pickDate(context),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(44),
            child: Container(
              color: AppTheme.primary,
              child: TabBar(
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                tabs: const [
                  Tab(
                    height: 44,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 16),
                        SizedBox(width: 6),
                        Text('Daily'),
                      ],
                    ),
                  ),
                  Tab(
                    height: 44,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.pending_actions_outlined, size: 16),
                        SizedBox(width: 6),
                        Text('Invoices'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _buildDailyLedgerTab(context, provider),
            _buildInvoiceStatusTab(context, provider),
          ],
        ),
      ),
    );
  }

  // --- DUAL-FIRM QUICK SWITCHER (PURVA VS MANAS) ---
  Widget _buildFirmFilterBar(CollectionProvider provider) {
    final purvaTotal = provider.getTotalCollectionForBusiness('Purva Enterprises');
    final manasTotal = provider.getTotalCollectionForBusiness('Manas Sales');
    final combinedTotal = purvaTotal + manasTotal;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          // ALL FIRMS
          Expanded(
            child: InkWell(
              onTap: () => provider.setFilterBusiness(null),
              borderRadius: BorderRadius.circular(7),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: provider.filterBusiness == null ? AppTheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ALL FIRMS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: provider.filterBusiness == null ? Colors.white : Colors.blueGrey.shade800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      CurrencyFormatter.format(combinedTotal),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: provider.filterBusiness == null ? Colors.white : AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),

          // PURVA
          Expanded(
            child: InkWell(
              onTap: () => provider.setFilterBusiness('Purva Enterprises'),
              borderRadius: BorderRadius.circular(7),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: provider.filterBusiness == 'Purva Enterprises'
                      ? AppTheme.purvaPrimary
                      : AppTheme.purvaLight,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: provider.filterBusiness == 'Purva Enterprises'
                        ? AppTheme.purvaPrimary
                        : AppTheme.purvaBorder,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'PURVA',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: provider.filterBusiness == 'Purva Enterprises'
                            ? Colors.white
                            : AppTheme.purvaText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      CurrencyFormatter.format(purvaTotal),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: provider.filterBusiness == 'Purva Enterprises'
                            ? Colors.white
                            : AppTheme.purvaPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),

          // MANAS
          Expanded(
            child: InkWell(
              onTap: () => provider.setFilterBusiness('Manas Sales'),
              borderRadius: BorderRadius.circular(7),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: provider.filterBusiness == 'Manas Sales'
                      ? AppTheme.manasPrimary
                      : AppTheme.manasLight,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: provider.filterBusiness == 'Manas Sales'
                        ? AppTheme.manasPrimary
                        : AppTheme.manasBorder,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'MANAS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: provider.filterBusiness == 'Manas Sales'
                            ? Colors.white
                            : AppTheme.manasText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      CurrencyFormatter.format(manasTotal),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: provider.filterBusiness == 'Manas Sales'
                            ? Colors.white
                            : AppTheme.manasPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- TAB 1: DAILY TRANSACTION LEDGER ---
  Widget _buildDailyLedgerTab(BuildContext context, CollectionProvider provider) {
    final allForDay = provider.getFilteredCollections();
    final filteredList = _selectedModeFilter == null
        ? allForDay
        : allForDay.where((c) => c.paymentMode == _selectedModeFilter).toList();

    final dateStr = DateFormat('dd MMM yyyy').format(provider.selectedDate);
    final isToday = DateFormat('yyyy-MM-dd').format(provider.selectedDate) ==
        DateFormat('yyyy-MM-dd').format(DateTime.now());

    final subtotalCollected = filteredList.fold(0.0, (s, c) => s + c.collectedAmount);
    final subtotalBalance = filteredList.fold(0.0, (s, c) => s + c.balanceAmount);

    return Column(
      children: [
        // Filter Bar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          color: Colors.white,
          child: Column(
            children: [
              _buildFirmFilterBar(provider),
              // Date & Business Filter Row
              Row(
                children: [
                  InkWell(
                    onTap: () => _pickDate(context),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.event, size: 15, color: AppTheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            isToday ? 'Today ($dateStr)' : dateStr,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: AppTheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!isToday)
                    TextButton(
                      onPressed: () => provider.setSelectedDate(DateTime.now()),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: const Text('Today', style: TextStyle(fontSize: 12)),
                    ),
                  const Spacer(),
                  if (provider.filterBusiness != null)
                    InkWell(
                      onTap: () => provider.setFilterBusiness(null),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.getBusinessLightColor(provider.filterBusiness!),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.getBusinessBorderColor(provider.filterBusiness!)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              provider.filterBusiness == 'Purva Enterprises' ? 'PURVA ✓' : 'MANAS ✓',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.getBusinessTextColor(provider.filterBusiness!),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.close, size: 12, color: AppTheme.getBusinessTextColor(provider.filterBusiness!)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Search Bar
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search store, bill, route...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  suffixIcon: provider.searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () => provider.setSearchQuery(''),
                        )
                      : null,
                ),
                onChanged: (val) => provider.setSearchQuery(val),
              ),
              const SizedBox(height: 8),

              // Mode Filter Dropdown
              DropdownButtonFormField<PaymentMode?>(
                key: ValueKey('ledger_mode_dd_$_selectedModeFilter'),
                initialValue: _selectedModeFilter,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Mode',
                  prefixIcon: Icon(
                    _selectedModeFilter?.icon ?? Icons.payments_outlined,
                    size: 18,
                    color: _selectedModeFilter != null ? _getModeColor(_selectedModeFilter!) : AppTheme.primary,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                items: [
                  DropdownMenuItem<PaymentMode?>(
                    value: null,
                    child: Text(
                      'All Modes (${allForDay.length} collections)',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  ...PaymentMode.values.map((mode) {
                    final count = allForDay.where((c) => c.paymentMode == mode).length;
                    return DropdownMenuItem<PaymentMode?>(
                      value: mode,
                      child: Row(
                        children: [
                          Icon(mode.icon, size: 16, color: _getModeColor(mode)),
                          const SizedBox(width: 8),
                          Text(
                            '${mode.label} ($count)',
                            style: TextStyle(
                              fontSize: 13,
                              color: _getModeColor(mode),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
                onChanged: (val) {
                  setState(() => _selectedModeFilter = val);
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Subtotal Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey.shade50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${filteredList.length} Entries',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700, fontWeight: FontWeight.w600),
              ),
              Row(
                children: [
                  if (subtotalBalance > 0) ...[
                    Text(
                      'Due: ${CurrencyFormatter.format(subtotalBalance)}  |  ',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.partialBadgeColor),
                    ),
                  ],
                  Text(
                    'Collected: ${CurrencyFormatter.format(subtotalCollected)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // List of Collections
        Expanded(
          child: filteredList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 48, color: Colors.blueGrey.shade200),
                      const SizedBox(height: 10),
                      Text(
                        'No collections found',
                        style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Collect'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const MakeCollectionScreen()),
                          );
                        },
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: filteredList.length,
                  itemBuilder: (context, index) {
                    final item = filteredList[index];
                    final modeColor = _getModeColor(item.paymentMode);
                    final timeStr = DateFormat('hh:mm a').format(item.collectedAt);
                    final isPartial = item.isPartial;
                    final billPhotos = item.allPhotos.isNotEmpty
                        ? item.allPhotos
                        : provider.getPhotosForBill(item.billNumber, shopId: item.shopId, shopName: item.shopName);
                    final firstPhoto = billPhotos.isNotEmpty ? billPhotos.first : item.photoBase64;
                    final photoBytes = ImageCompressHelper.safeBase64Decode(firstPhoto);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => CollectionDetailsDialog(collection: item),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            children: [
                              Builder(
                                builder: (ctx) {
                                  if (photoBytes != null) {
                                    final hasMultiple = billPhotos.length > 1;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 10.0),
                                      child: InkWell(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => FullScreenImageViewer(
                                                imagesBase64: billPhotos.isNotEmpty ? billPhotos : (firstPhoto != null ? [firstPhoto] : null),
                                                title: 'Bill No: ${item.billNumber} - ${item.shopName}',
                                                subtitle: hasMultiple
                                                    ? '${billPhotos.length} Photos Attached • ${item.businessName}'
                                                    : '${item.businessName} • ${item.routeName}',
                                              ),
                                            ),
                                          );
                                        },
                                        child: Stack(
                                          alignment: Alignment.bottomRight,
                                          children: [
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: Image.memory(
                                                photoBytes,
                                                width: 44,
                                                height: 44,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, _, _) => Container(
                                                  width: 44,
                                                  height: 44,
                                                  color: Colors.grey.shade200,
                                                  child: const Icon(Icons.broken_image, size: 20),
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(alpha: 0.7),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (hasMultiple) ...[
                                                    Text(
                                                      '${billPhotos.length}',
                                                      style: const TextStyle(fontSize: 9, color: Colors.amberAccent, fontWeight: FontWeight.bold),
                                                    ),
                                                    const SizedBox(width: 2),
                                                  ],
                                                  const Icon(Icons.zoom_in, size: 10, color: Colors.white),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }

                                  return Container(
                                    width: 40,
                                    height: 40,
                                    margin: const EdgeInsets.only(right: 12),
                                    decoration: BoxDecoration(
                                      color: modeColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        item.paymentMode.icon,
                                        size: 20,
                                        color: modeColor,
                                      ),
                                    ),
                                  );
                                },
                              ),

                              // Details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.shopName,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF0F172A),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (photoBytes != null)
                                          const Padding(
                                            padding: EdgeInsets.only(left: 4.0),
                                            child: Icon(Icons.attach_file, size: 14, color: Colors.blueGrey),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Text(
                                          'Bill No: ${item.billNumber}',
                                          style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Total: ${CurrencyFormatter.format(item.billAmount)}',
                                          style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade500),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: AppTheme.getBusinessLightColor(item.businessName),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: AppTheme.getBusinessBorderColor(item.businessName), width: 0.8),
                                          ),
                                          child: Text(
                                            item.businessName == 'Purva Enterprises' ? 'PURVA' : (item.businessName == 'Manas Sales' ? 'MANAS' : item.businessName),
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.getBusinessTextColor(item.businessName),
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${item.routeName} • $timeStr',
                                          style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade400),
                                        ),
                                        if (isPartial) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: AppTheme.chequeColor.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                            child: Text(
                                              'Due: ${CurrencyFormatter.format(item.balanceAmount)}',
                                              style: const TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.partialBadgeColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Amount & Mode Badge
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    CurrencyFormatter.format(item.collectedAmount),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: modeColor,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: modeColor.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      item.paymentMode.label,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: modeColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // Searchable Route Picker Dialog / BottomSheet for Invoices
  void _openInvoiceRoutePicker(CollectionProvider provider) {
    final routes = provider.routes;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        String routeQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredRoutes = routes.where((r) {
              if (routeQuery.trim().isEmpty) return true;
              return MarathiSearchHelper.matches(r.name, routeQuery.trim().toLowerCase());
            }).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  top: 16,
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.65,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Filter by Route',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
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
                          hintText: 'Search route...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        onChanged: (val) => setModalState(() => routeQuery = val),
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.all_inclusive, color: AppTheme.primary, size: 20),
                        title: const Text('All Routes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        selected: _invoiceRouteIdFilter == null,
                        trailing: _invoiceRouteIdFilter == null
                            ? const Icon(Icons.check, color: AppTheme.primary, size: 18)
                            : null,
                        onTap: () {
                          setState(() {
                            _invoiceRouteIdFilter = null;
                          });
                          Navigator.pop(ctx);
                        },
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: filteredRoutes.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(20.0),
                                  child: Text('No routes found', style: TextStyle(color: Colors.blueGrey.shade600)),
                                ),
                              )
                            : ListView.separated(
                                itemCount: filteredRoutes.length,
                                separatorBuilder: (_, _) => const Divider(height: 1),
                                itemBuilder: (context, idx) {
                                  final r = filteredRoutes[idx];
                                  final isSelected = _invoiceRouteIdFilter == r.id;
                                  final shopCount = provider.getShopsForRoute(r.id).length;
                                  return ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 14,
                                      backgroundColor: isSelected ? AppTheme.primary : Colors.grey.shade200,
                                      child: Icon(Icons.alt_route, size: 15, color: isSelected ? Colors.white : Colors.blueGrey),
                                    ),
                                    title: Text(
                                      r.name,
                                      style: TextStyle(
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                        fontSize: 13,
                                        color: isSelected ? AppTheme.primary : Colors.black87,
                                      ),
                                    ),
                                    subtitle: Text('$shopCount outlets', style: const TextStyle(fontSize: 11)),
                                    trailing: isSelected
                                        ? const Icon(Icons.check, color: AppTheme.primary, size: 18)
                                        : null,
                                    onTap: () {
                                      setState(() {
                                        _invoiceRouteIdFilter = r.id;
                                        if (_invoiceShopIdFilter != null) {
                                          final currentShop = provider.getShopById(_invoiceShopIdFilter!);
                                          if (currentShop != null && currentShop.routeId != r.id) {
                                            _invoiceShopIdFilter = null;
                                          }
                                        }
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
              ),
            );
          },
        );
      },
    );
  }

  // Searchable Outlet Picker Dialog / BottomSheet for Invoices
  void _openInvoiceShopPicker(CollectionProvider provider) {
    final List<ShopModel> availableShops = _invoiceRouteIdFilter != null
        ? provider.getShopsForRoute(_invoiceRouteIdFilter!)
        : provider.shops;

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
            final filtered = availableShops.where((s) {
              if (query.trim().isEmpty) return true;
              final q = query.trim().toLowerCase();
              return MarathiSearchHelper.matches(s.name, q) ||
                  s.mobileNumber.contains(q) ||
                  MarathiSearchHelper.matches(s.address, q);
            }).toList();

            return SafeArea(
              child: Padding(
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
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Filter by Outlet',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                              ),
                              if (_invoiceRouteIdFilter != null)
                                Text(
                                  'Route: ${provider.getRouteName(_invoiceRouteIdFilter!)}',
                                  style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700),
                                ),
                            ],
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
                          hintText: 'Search outlet by name, phone...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        onChanged: (val) {
                          setModalState(() => query = val);
                        },
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.all_inclusive, color: AppTheme.primary, size: 20),
                        title: const Text('All Outlets', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        selected: _invoiceShopIdFilter == null,
                        trailing: _invoiceShopIdFilter == null
                            ? const Icon(Icons.check, color: AppTheme.primary, size: 18)
                            : null,
                        onTap: () {
                          setState(() {
                            _invoiceShopIdFilter = null;
                          });
                          Navigator.pop(ctx);
                        },
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(20.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.storefront_outlined, size: 40, color: Colors.blueGrey.shade300),
                                      const SizedBox(height: 8),
                                      Text(
                                        query.isEmpty
                                            ? 'No outlets found'
                                            : 'No outlets match "$query"',
                                        style: TextStyle(color: Colors.blueGrey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, _) => const Divider(height: 1),
                                itemBuilder: (context, idx) {
                                  final s = filtered[idx];
                                  final isSelected = s.id == _invoiceShopIdFilter;
                                  return ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    leading: CircleAvatar(
                                      radius: 14,
                                      backgroundColor: isSelected ? AppTheme.primary : Colors.grey.shade200,
                                      foregroundColor: isSelected ? Colors.white : Colors.blueGrey.shade800,
                                      child: Text(
                                        s.name.isNotEmpty ? s.name[0].toUpperCase() : 'S',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    ),
                                    title: Text(
                                      s.name,
                                      style: TextStyle(
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                        fontSize: 13,
                                        color: isSelected ? AppTheme.primary : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${s.mobileNumber} • ${provider.getRouteName(s.routeId)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600),
                                    ),
                                    trailing: isSelected
                                        ? const Icon(Icons.check_circle, color: AppTheme.primary, size: 18)
                                        : null,
                                    onTap: () {
                                      setState(() {
                                        _invoiceShopIdFilter = s.id;
                                        if (_invoiceRouteIdFilter == null && s.routeId.isNotEmpty) {
                                          _invoiceRouteIdFilter = s.routeId;
                                        }
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
              ),
            );
          },
        );
      },
    );
  }

  // --- TAB 2: INVOICE STATUS TRACKER (PENDING VS PAID) ---
  Widget _buildInvoiceStatusTab(BuildContext context, CollectionProvider provider) {
    var allSummaries = provider.getAllBillSummaries(forBusiness: provider.filterBusiness);

    // Apply Route filter
    if (_invoiceRouteIdFilter != null && _invoiceRouteIdFilter!.isNotEmpty) {
      allSummaries = allSummaries.where((b) => b.routeId == _invoiceRouteIdFilter).toList();
    }

    // Apply Shop filter
    if (_invoiceShopIdFilter != null && _invoiceShopIdFilter!.isNotEmpty) {
      allSummaries = allSummaries.where((b) => b.shopId == _invoiceShopIdFilter).toList();
    }

    // Apply Date filter
    if (_invoiceDateFilter != null) {
      final filterDateStr = DateFormat('yyyy-MM-dd').format(_invoiceDateFilter!);
      allSummaries = allSummaries.where((b) {
        final bDateStr = DateFormat('yyyy-MM-dd').format(b.billDate);
        return bDateStr == filterDateStr;
      }).toList();
    }

    final pendingBills = allSummaries.where((b) => b.isPending).toList();
    final paidBills = allSummaries.where((b) => b.isPaid).toList();

    List<BillSummary> displayedList;
    switch (_invoiceStatusFilter) {
      case InvoiceFilterStatus.pending:
        displayedList = pendingBills;
        break;
      case InvoiceFilterStatus.paid:
        displayedList = paidBills;
        break;
      case InvoiceFilterStatus.all:
        displayedList = allSummaries;
        break;
    }

    if (_invoiceSearchQuery.trim().isNotEmpty) {
      final q = _invoiceSearchQuery.toLowerCase().trim();
      displayedList = displayedList.where((b) {
        return MarathiSearchHelper.matches(b.shopName, q) ||
            b.billNumber.toLowerCase().contains(q) ||
            MarathiSearchHelper.matches(b.routeName, q);
      }).toList();
    }

    final totalPendingDue = pendingBills.fold(0.0, (s, b) => s + b.balanceDue);
    final totalInvoiced = allSummaries.fold(0.0, (s, b) => s + b.billTotal);

    return Column(
      children: [
        // Filter bar for invoices
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          color: Colors.white,
          child: Column(
            children: [
              _buildFirmFilterBar(provider),
              // Date & Reset Filters Row
              Row(
                children: [
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _invoiceDateFilter ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) {
                        setState(() => _invoiceDateFilter = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _invoiceDateFilter != null
                            ? AppTheme.primary.withValues(alpha: 0.1)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _invoiceDateFilter != null ? AppTheme.primary : AppTheme.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_month_outlined,
                            size: 15,
                            color: _invoiceDateFilter != null ? AppTheme.primary : Colors.blueGrey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _invoiceDateFilter != null
                                ? 'Date: ${DateFormat('dd MMM yyyy').format(_invoiceDateFilter!)}'
                                : 'All Dates',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: _invoiceDateFilter != null ? AppTheme.primary : Colors.blueGrey.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_invoiceDateFilter != null) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => setState(() => _invoiceDateFilter = null),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.close, size: 14, color: Colors.blueGrey),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (_invoiceRouteIdFilter != null || _invoiceShopIdFilter != null || _invoiceDateFilter != null)
                    InkWell(
                      onTap: () {
                        setState(() {
                          _invoiceDateFilter = null;
                          _invoiceRouteIdFilter = null;
                          _invoiceShopIdFilter = null;
                        });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh, size: 12, color: Colors.red.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'Reset Filters',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Route & Outlet Filters Row
              Row(
                children: [
                  // Route Filter
                  Expanded(
                    child: InkWell(
                      onTap: () => _openInvoiceRoutePicker(provider),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: _invoiceRouteIdFilter != null
                              ? AppTheme.primary.withValues(alpha: 0.1)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _invoiceRouteIdFilter != null ? AppTheme.primary : AppTheme.border,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.alt_route,
                              size: 15,
                              color: _invoiceRouteIdFilter != null ? AppTheme.primary : Colors.blueGrey,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _invoiceRouteIdFilter != null
                                    ? provider.getRouteName(_invoiceRouteIdFilter!)
                                    : 'All Routes',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: _invoiceRouteIdFilter != null ? AppTheme.primary : Colors.blueGrey.shade800,
                                ),
                              ),
                            ),
                            if (_invoiceRouteIdFilter != null)
                              GestureDetector(
                                onTap: () {
                                  setState(() => _invoiceRouteIdFilter = null);
                                },
                                child: const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child: Icon(Icons.close, size: 14, color: AppTheme.primary),
                                ),
                              )
                            else
                              const Icon(Icons.arrow_drop_down, size: 18, color: Colors.blueGrey),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Outlet Filter
                  Expanded(
                    child: InkWell(
                      onTap: () => _openInvoiceShopPicker(provider),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: _invoiceShopIdFilter != null
                              ? AppTheme.primary.withValues(alpha: 0.1)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _invoiceShopIdFilter != null ? AppTheme.primary : AppTheme.border,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.storefront_outlined,
                              size: 15,
                              color: _invoiceShopIdFilter != null ? AppTheme.primary : Colors.blueGrey,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _invoiceShopIdFilter != null
                                    ? (provider.getShopById(_invoiceShopIdFilter!)?.name ?? 'Selected Outlet')
                                    : 'All Outlets',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: _invoiceShopIdFilter != null ? AppTheme.primary : Colors.blueGrey.shade800,
                                ),
                              ),
                            ),
                            if (_invoiceShopIdFilter != null)
                              GestureDetector(
                                onTap: () {
                                  setState(() => _invoiceShopIdFilter = null);
                                },
                                child: const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child: Icon(Icons.close, size: 14, color: AppTheme.primary),
                                ),
                              )
                            else
                              const Icon(Icons.arrow_drop_down, size: 18, color: Colors.blueGrey),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Active Firm & Pending Balance Badge Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    provider.filterBusiness == null
                        ? 'All Firms'
                        : '${provider.filterBusiness}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: provider.filterBusiness == null
                          ? Colors.blueGrey.shade700
                          : AppTheme.getBusinessColor(provider.filterBusiness!),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.chequeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.chequeColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'Due: ${CurrencyFormatter.format(totalPendingDue)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.balanceDueColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Search Bar
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search bill, store...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  suffixIcon: _invoiceSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () => setState(() => _invoiceSearchQuery = ''),
                        )
                      : null,
                ),
                onChanged: (val) => setState(() => _invoiceSearchQuery = val),
              ),
              const SizedBox(height: 8),

              // Status Filter Chips
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: Center(child: Text('All (${allSummaries.length})')),
                      selected: _invoiceStatusFilter == InvoiceFilterStatus.all,
                      selectedColor: AppTheme.primary,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _invoiceStatusFilter == InvoiceFilterStatus.all
                            ? Colors.white
                            : Colors.blueGrey.shade800,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _invoiceStatusFilter = InvoiceFilterStatus.all);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: Center(child: Text('Pending (${pendingBills.length})')),
                      selected: _invoiceStatusFilter == InvoiceFilterStatus.pending,
                      selectedColor: const Color(0xFFD97706),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _invoiceStatusFilter == InvoiceFilterStatus.pending
                            ? Colors.white
                            : Colors.blueGrey.shade800,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _invoiceStatusFilter = InvoiceFilterStatus.pending);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: Center(child: Text('Paid (${paidBills.length})')),
                      selected: _invoiceStatusFilter == InvoiceFilterStatus.paid,
                      selectedColor: AppTheme.cashColor,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _invoiceStatusFilter == InvoiceFilterStatus.paid
                            ? Colors.white
                            : Colors.blueGrey.shade800,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _invoiceStatusFilter = InvoiceFilterStatus.paid);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Subtotal overview
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey.shade50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${displayedList.length} Invoices',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700, fontWeight: FontWeight.w600),
              ),
              Text(
                'Billed: ${CurrencyFormatter.format(totalInvoiced)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
              ),
            ],
          ),
        ),

        // Invoices List
        Expanded(
          child: displayedList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline, size: 48, color: Colors.blueGrey.shade200),
                      const SizedBox(height: 10),
                      Text(
                        _invoiceStatusFilter == InvoiceFilterStatus.pending
                            ? 'All bills paid!'
                            : 'No invoices found',
                        style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: displayedList.length,
                  itemBuilder: (context, index) {
                    final bill = displayedList[index];
                    final isPending = bill.isPending;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header Row: Shop Name & Status Badge
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        bill.shopName,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Text(
                                            'Bill No: ${bill.billNumber}',
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blueGrey.shade800),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: AppTheme.getBusinessLightColor(bill.businessName),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: AppTheme.getBusinessBorderColor(bill.businessName), width: 0.8),
                                            ),
                                            child: Text(
                                              bill.businessName == 'Purva Enterprises' ? 'PURVA' : (bill.businessName == 'Manas Sales' ? 'MANAS' : bill.businessName),
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                                color: AppTheme.getBusinessTextColor(bill.businessName),
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isPending
                                        ? const Color(0xFFFEF3C7)
                                        : const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isPending
                                          ? const Color(0xFFD97706)
                                          : const Color(0xFF16A34A),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isPending ? Icons.pending_outlined : Icons.check_circle,
                                        size: 13,
                                        color: isPending ? const Color(0xFFD97706) : const Color(0xFF16A34A),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isPending ? 'PENDING' : 'PAID (100%)',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: isPending ? const Color(0xFF92400E) : const Color(0xFF166534),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Progress Bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: bill.percentPaid / 100,
                                minHeight: 6,
                                backgroundColor: Colors.grey.shade200,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isPending ? const Color(0xFFD97706) : AppTheme.cashColor,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Amounts Breakdown
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total: ${CurrencyFormatter.format(bill.billTotal)}',
                                  style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                                ),
                                Text(
                                  'Collected: ${CurrencyFormatter.format(bill.totalCollected)} (${bill.percentPaid.toStringAsFixed(0)}%)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isPending ? Colors.blueGrey.shade800 : AppTheme.cashColor,
                                  ),
                                ),
                                Text(
                                  isPending
                                      ? 'Due: ${CurrencyFormatter.format(bill.balanceDue)}'
                                      : 'Settled',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isPending ? AppTheme.balanceDueColor : AppTheme.cashColor,
                                  ),
                                ),
                              ],
                            ),

                            // Action Buttons
                            if (isPending) ...[
                              const Divider(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.payments_outlined, size: 15),
                                      label: Text(
                                        'Collect (${CurrencyFormatter.format(bill.balanceDue)})',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.primary,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                      ),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => MakeCollectionScreen(
                                              initialBusiness: bill.businessName,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.notifications_active_outlined, size: 14, color: AppTheme.chequeColor),
                                      label: const Text(
                                        'Remind',
                                        style: TextStyle(color: AppTheme.chequeColor, fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: AppTheme.chequeColor),
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                      ),
                                      onPressed: () {
                                        final shop = provider.getShopById(bill.shopId);
                                        showDialog(
                                          context: context,
                                          builder: (ctx) => SendReminderDialog(
                                            shopName: bill.shopName,
                                            mobileNumber: shop?.mobileNumber ?? '',
                                            businessName: bill.businessName,
                                            salesmanName: provider.salesmanName,
                                            balanceAmount: bill.balanceDue,
                                            billNumber: bill.billNumber,
                                            billTotal: bill.billTotal,
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
    );
  }
}
