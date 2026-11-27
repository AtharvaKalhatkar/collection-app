import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';

import '../providers/collection_provider.dart';
import '../models/collection_model.dart';
import '../models/order_model.dart';
import '../models/route_model.dart';
import '../services/tally_integration_service.dart';
import '../screens/admin_products_screen.dart';
import '../utils/currency_formatter.dart';
import '../utils/quick_alert.dart';

class TallySyncDialog extends StatefulWidget {
  final int initialTabIndex; // 0 for Export, 1 for Import
  final String? initialFirm;

  const TallySyncDialog({
    super.key,
    this.initialTabIndex = 0,
    this.initialFirm,
  });

  static Future<void> show(
    BuildContext context, {
    int initialTabIndex = 0,
    String? initialFirm,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TallySyncDialog(
        initialTabIndex: initialTabIndex,
        initialFirm: initialFirm,
      ),
    );
  }

  @override
  State<TallySyncDialog> createState() => _TallySyncDialogState();
}

class _TallySyncDialogState extends State<TallySyncDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late String _selectedFirm;
  String _dateRange = 'today'; // 'today', 'week', 'all'
  String? _importFallbackRouteId;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    _selectedFirm = widget.initialFirm ?? 'Purva Enterprises';
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<CollectionModel> _getFilteredCollections(CollectionProvider provider) {
    final now = DateTime.now();
    return provider.collections.where((c) {
      if (_selectedFirm != 'All' && c.businessName != _selectedFirm) return false;
      if (_dateRange == 'today') {
        return c.collectedAt.year == now.year &&
            c.collectedAt.month == now.month &&
            c.collectedAt.day == now.day;
      } else if (_dateRange == 'week') {
        return now.difference(c.collectedAt).inDays <= 7;
      }
      return true;
    }).toList();
  }

  List<SalesOrderModel> _getFilteredOrders(CollectionProvider provider) {
    final now = DateTime.now();
    return provider.salesOrders.where((o) {
      if (_selectedFirm != 'All' && o.firm != _selectedFirm) return false;
      if (_dateRange == 'today') {
        return o.orderDate.year == now.year &&
            o.orderDate.month == now.month &&
            o.orderDate.day == now.day;
      } else if (_dateRange == 'week') {
        return now.difference(o.orderDate).inDays <= 7;
      }
      return true;
    }).toList();
  }

  Future<void> _exportReceiptsXml(CollectionProvider provider) async {
    final list = _getFilteredCollections(provider);
    if (list.isEmpty) {
      QuickAlert.info(context, 'No collections found for selected filters to export.');
      return;
    }
    setState(() => _isProcessing = true);
    try {
      await TallyIntegrationService.exportCollectionsToTallyXml(
        collections: list,
        companyName: _selectedFirm == 'All' ? 'Purva_and_Manas' : _selectedFirm,
      );
      if (mounted) {
        QuickAlert.success(context, 'Exported ${list.length} Receipt Vouchers to Tally XML!');
      }
    } catch (e) {
      if (mounted) QuickAlert.error(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _exportReceiptsExcel(CollectionProvider provider) async {
    final list = _getFilteredCollections(provider);
    if (list.isEmpty) {
      QuickAlert.info(context, 'No collections found for selected filters to export.');
      return;
    }
    setState(() => _isProcessing = true);
    try {
      await TallyIntegrationService.exportCollectionsToTallyExcel(
        collections: list,
        companyName: _selectedFirm == 'All' ? 'Purva_and_Manas' : _selectedFirm,
      );
      if (mounted) {
        QuickAlert.success(context, 'Exported ${list.length} Receipts to Tally Prime Excel!');
      }
    } catch (e) {
      if (mounted) QuickAlert.error(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _exportSalesOrdersXml(CollectionProvider provider) async {
    final list = _getFilteredOrders(provider);
    if (list.isEmpty) {
      QuickAlert.info(context, 'No booked orders found for selected filters.');
      return;
    }
    setState(() => _isProcessing = true);
    try {
      await TallyIntegrationService.exportSalesOrdersToTallyXml(
        orders: list,
        companyName: _selectedFirm,
      );
      if (mounted) {
        QuickAlert.success(context, 'Exported ${list.length} Sales Orders to Tally XML!');
      }
    } catch (e) {
      if (mounted) QuickAlert.error(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _exportOutletsXml(CollectionProvider provider) async {
    final shops = provider.allShops;
    if (shops.isEmpty) {
      QuickAlert.info(context, 'No outlets available to export.');
      return;
    }
    setState(() => _isProcessing = true);
    try {
      await TallyIntegrationService.exportOutletsToTallyXml(shops: shops);
      if (mounted) {
        QuickAlert.success(context, 'Exported ${shops.length} Outlets to Tally XML!');
      }
    } catch (e) {
      if (mounted) QuickAlert.error(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _pickAndImportTallyFile(CollectionProvider provider) async {
    setState(() => _isProcessing = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml', 'xlsx', 'xls'],
      );

      if (files.isEmpty) {
        setState(() => _isProcessing = false);
        return;
      }

      final file = files.first;
      final bytes = await file.xFile.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('File is empty or could not be read.');
      }

      final fileName = file.name.toLowerCase();
      TallyImportResult importResult;

      if (fileName.endsWith('.xml')) {
        final xmlString = utf8.decode(bytes, allowMalformed: true);
        importResult = TallyIntegrationService.parsePendingBillsFromTallyXml(
          xmlContent: xmlString,
          existingRoutes: provider.routes,
          existingShops: provider.allShops,
          defaultFirm: _selectedFirm == 'All' ? 'Purva Enterprises' : _selectedFirm,
          fallbackRouteId: _importFallbackRouteId,
        );
      } else {
        // Excel (.xlsx, .xls)
        importResult = TallyIntegrationService.parsePendingBillsFromExcel(
          bytes: bytes,
          existingRoutes: provider.routes,
          existingShops: provider.allShops,
          defaultFirm: _selectedFirm == 'All' ? 'Purva Enterprises' : _selectedFirm,
          fallbackRouteId: _importFallbackRouteId,
        );
      }

      if (!mounted) return;
      setState(() => _isProcessing = false);

      if (!importResult.success || importResult.importedBills.isEmpty) {
        QuickAlert.error(context, importResult.message);
        return;
      }

      // Show Import Confirmation Dialog
      _showImportPreviewDialog(provider, importResult);
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        QuickAlert.error(context, 'Failed to import file: $e');
      }
    }
  }

  void _showImportPreviewDialog(CollectionProvider provider, TallyImportResult result) {
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A8A).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.file_download_done_rounded, color: Color(0xFF1E3A8A), size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Tally Bills Import Preview',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Summary Cards
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E3A8A).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF1E3A8A).withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total Bills', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                            const SizedBox(height: 4),
                            Text(
                              '${result.importedBills.length}',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total Outstanding', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                            const SizedBox(height: 4),
                            Text(
                              CurrencyFormatter.format(result.totalAmount),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (result.newShops.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.add_business_rounded, color: Colors.amber.shade800, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${result.newShops.length} new shops will be auto-added to your outlets registry.',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 14),
                const Text(
                  'Bills Preview (First 5):',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: result.importedBills.length > 5 ? 5 : result.importedBills.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, idx) {
                      final b = result.importedBills[idx];
                      return ListTile(
                        dense: true,
                        title: Text(
                          b.shopName,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '#${b.billNumber} • ${DateFormat('dd-MMM-yyyy').format(b.invoiceDate)} • Route: ${b.routeName}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                        trailing: Text(
                          CurrencyFormatter.format(b.totalAmount),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF1E3A8A)),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(dlgCtx);
              setState(() => _isProcessing = true);
              try {
                // 1. Add new shops if any
                if (result.newShops.isNotEmpty) {
                  await provider.addShopsBulk(result.newShops);
                }
                // 2. Add pending bills in bulk
                final addedCount = await provider.addPendingBillsBulk(result.importedBills);
                if (mounted) {
                  QuickAlert.success(
                    context,
                    'Successfully imported $addedCount pending bills into the app!',
                  );
                }
              } catch (e) {
                if (mounted) QuickAlert.error(context, 'Failed saving bills: $e');
              } finally {
                if (mounted) setState(() => _isProcessing = false);
              }
            },
            child: const Text('Confirm & Import to App', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CollectionProvider>();
    final routes = provider.routes;
    final screenHeight = MediaQuery.of(context).size.height;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: screenHeight * 0.90,
        ),
        child: Container(
          height: screenHeight * 0.88,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(color: Colors.black26, blurRadius: 24, spreadRadius: 4),
            ],
          ),
          child: SafeArea(
            top: false,
            bottom: true,
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 14,
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Grab Handle
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Title Bar
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E3A8A).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF1E3A8A), size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tally Prime & ERP 9 Hub',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              'Seamless two-way XML & Excel integration',
                              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Filter Controls (Firm & Date Range)
                  Row(
                    children: [
                      // Firm Selector
                      Expanded(
                        child: Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedFirm,
                              isExpanded: true,
                              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF1E3A8A)),
                              items: const [
                                DropdownMenuItem(value: 'Purva Enterprises', child: Text('Purva Enterprises', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                                DropdownMenuItem(value: 'Manas Sales', child: Text('Manas Sales', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                                DropdownMenuItem(value: 'All', child: Text('All Companies', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedFirm = val);
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Date Range
                      Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _dateRange,
                            icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF1E3A8A)),
                            items: const [
                              DropdownMenuItem(value: 'today', child: Text('Today Only', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                              DropdownMenuItem(value: 'week', child: Text('Last 7 Days', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                              DropdownMenuItem(value: 'all', child: Text('All Records', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _dateRange = val);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Tab Selector (Export / Import)
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      labelColor: Colors.white,
                      unselectedLabelColor: const Color(0xFF475569),
                      indicator: BoxDecoration(
                        color: const Color(0xFF1E3A8A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      tabs: const [
                        Tab(
                          icon: Icon(Icons.file_upload_outlined, size: 18),
                          text: 'Export to Tally',
                        ),
                        Tab(
                          icon: Icon(Icons.file_download_outlined, size: 18),
                          text: 'Import from Tally',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Tab Views
                  if (_isProcessing)
                    const Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Color(0xFF1E3A8A)),
                            SizedBox(height: 12),
                            Text('Processing Tally Data...', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                          ],
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // TAB 1: EXPORT
                          _buildExportTab(provider),
                          // TAB 2: IMPORT
                          _buildImportTab(provider, routes),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExportTab(CollectionProvider provider) {
    final filteredCollections = _getFilteredCollections(provider);
    final filteredOrders = _getFilteredOrders(provider);

    return ListView(
      children: [
        // Card 1: Receipts XML
        _buildActionTile(
          icon: Icons.receipt_long_rounded,
          iconColor: const Color(0xFF059669),
          title: 'Collections XML (${filteredCollections.length})',
          buttonText: 'Export XML',
          onTap: () => _exportReceiptsXml(provider),
        ),
        const SizedBox(height: 10),

        // Card 2: Receipts Excel (Tally Prime)
        _buildActionTile(
          icon: Icons.table_chart_rounded,
          iconColor: const Color(0xFF0284C7),
          title: 'Tally Prime Excel (${filteredCollections.length})',
          buttonText: 'Export Excel',
          onTap: () => _exportReceiptsExcel(provider),
        ),
        const SizedBox(height: 10),

        // Card 3: Sales Orders XML
        _buildActionTile(
          icon: Icons.shopping_bag_rounded,
          iconColor: const Color(0xFFD97706),
          title: 'Sales Orders XML (${filteredOrders.length})',
          buttonText: 'Export Orders',
          onTap: () => _exportSalesOrdersXml(provider),
        ),
        const SizedBox(height: 10),

        // Card 4: Outlets XML
        _buildActionTile(
          icon: Icons.storefront_rounded,
          iconColor: const Color(0xFF7C3AED),
          title: 'Outlets Ledgers XML (${provider.allShops.length})',
          buttonText: 'Export Masters',
          onTap: () => _exportOutletsXml(provider),
        ),
      ],
    );
  }

  Widget _buildImportTab(CollectionProvider provider, List<RouteModel> routes) {
    return ListView(
      children: [
        // Route Fallback Selector
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Assign Route to Imported Bills (if not in file):',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 6),
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: routes.any((r) => r.id == _importFallbackRouteId)
                        ? _importFallbackRouteId
                        : (routes.isNotEmpty ? routes.first.id : null),
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF1E3A8A)),
                    items: routes.map((r) {
                      return DropdownMenuItem<String>(
                        value: r.id,
                        child: Text(r.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _importFallbackRouteId = val);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Main Import Button Tile
        Container(
          padding: const EdgeInsets.all(16),
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
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.file_open_rounded, color: Colors.white, size: 24),
                  SizedBox(width: 10),
                  Text(
                    'Select Tally File (XML or Excel)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Supports Tally Sales XML, Outstanding Bills XML, or Excel reports from Tally ERP 9 / Tally Prime.',
                style: TextStyle(fontSize: 12, color: Color(0xFFBFDBFE)),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1E3A8A),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('Browse & Import File', style: TextStyle(fontWeight: FontWeight.w800)),
                onPressed: () => _pickAndImportTallyFile(provider),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Product Stock Import Card (XML / Excel)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F9FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBAE6FD)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.inventory_rounded, color: Color(0xFF0369A1), size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Import Product Closing Stock (XML / Excel)',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0C4A6E)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              const Text(
                'Update catalog stock from Tally Stock Summary XML or Excel sheet.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF0369A1)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0369A1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.file_upload_outlined, size: 17),
                      label: const Text('Import Stock', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                      onPressed: () => AdminProductsScreen.pickAndImportTallyStock(
                        context,
                        provider,
                        defaultFirm: _selectedFirm == 'All' ? 'Purva Enterprises' : _selectedFirm,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0369A1),
                      side: const BorderSide(color: Color(0xFF7DD3FC)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Sample', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    onPressed: () async {
                      await TallyIntegrationService.downloadSampleStockExcel();
                      if (mounted) {
                        QuickAlert.success(context, 'Sample Stock Excel downloaded!');
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Sample Template Downloads
        const Text(
          'Sample Tally Templates:',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1E3A8A),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Sample Excel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () async {
                  await TallyIntegrationService.downloadSamplePendingBillsExcel();
                  if (mounted) {
                    QuickAlert.success(context, 'Sample Excel downloaded!');
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1E3A8A),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.code_rounded, size: 16),
                label: const Text('Sample XML', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () async {
                  await TallyIntegrationService.downloadSamplePendingBillsXml();
                  if (mounted) {
                    QuickAlert.success(context, 'Sample XML downloaded!');
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String buttonText,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 34),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: onTap,
            child: Text(buttonText, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
