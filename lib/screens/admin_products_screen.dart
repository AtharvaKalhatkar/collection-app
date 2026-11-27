import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/order_model.dart';
import '../providers/auth_provider.dart';
import '../providers/collection_provider.dart';
import '../services/order_catalog_service.dart';
import '../services/tally_integration_service.dart';
import '../utils/image_compress_helper.dart';
import '../utils/quick_alert.dart';
import '../utils/theme.dart';
import '../widgets/add_product_dialog.dart';

class AdminProductsScreen extends StatefulWidget {
  const AdminProductsScreen({super.key});

  /// Shared Tally Stock XML/Excel picker + preview + bulk apply helper.
  /// Used by both AdminProductsScreen and TallySyncDialog.
  static Future<void> pickAndImportTallyStock(
    BuildContext context,
    CollectionProvider provider, {
    String defaultFirm = OrderCatalogService.purva,
  }) async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml', 'xlsx', 'xls'],
      );
      if (files.isEmpty || !context.mounted) return;

      final file = files.first;
      final bytes = await file.xFile.readAsBytes();
      if (bytes.isEmpty) {
        if (context.mounted) {
          QuickAlert.error(context, 'Selected file is empty or could not be read.');
        }
        return;
      }

      final fileName = file.name.toLowerCase();
      final TallyStockImportResult result = fileName.endsWith('.xml')
          ? TallyIntegrationService.parseStockSummaryFromTallyXml(
              xmlContent: utf8.decode(bytes, allowMalformed: true),
              defaultFirm: defaultFirm,
            )
          : TallyIntegrationService.parseStockSummaryFromExcel(
              bytes: bytes,
              defaultFirm: defaultFirm,
            );

      if (!context.mounted) return;
      if (!result.success || result.items.isEmpty) {
        QuickAlert.error(context, result.message);
        return;
      }

      await _showTallyStockPreviewDialog(
        context,
        provider,
        result,
        defaultFirm: defaultFirm,
      );
    } catch (e) {
      if (context.mounted) {
        QuickAlert.error(context, 'Failed to read Tally Stock file: $e');
      }
    }
  }

  static Future<void> _showTallyStockPreviewDialog(
    BuildContext context,
    CollectionProvider provider,
    TallyStockImportResult result, {
    required String defaultFirm,
  }) async {
    final existingByNormName = {
      for (final p in provider.customProducts)
        p.name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '): p,
    };

    int matchedCount = 0;
    for (final row in result.items) {
      final norm = row.name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      if (existingByNormName.containsKey(norm)) {
        matchedCount++;
      }
    }
    final unmatchedCount = result.items.length - matchedCount;
    bool createUnmatched = true;
    String chosenFirm = defaultFirm;

    await showDialog<void>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.inventory_rounded, color: AppTheme.primary, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tally Stock Import Preview',
                  style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _statBox('Parsed', '${result.items.length}', const Color(0xFF15429E)),
                      const SizedBox(width: 8),
                      _statBox('Matched', '$matchedCount', const Color(0xFF16A34A)),
                      const SizedBox(width: 8),
                      _statBox('New Items', '$unmatchedCount', const Color(0xFFD97706)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (unmatchedCount > 0) ...[
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Add unmatched Tally items as new products',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                      value: createUnmatched,
                      onChanged: (v) => setDlgState(() => createUnmatched = v),
                    ),
                    if (createUnmatched) ...[
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        initialValue: chosenFirm,
                        decoration: InputDecoration(
                          labelText: 'Default Firm for New Items',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: OrderCatalogService.purva,
                            child: Text('Purva Enterprises'),
                          ),
                          DropdownMenuItem(
                            value: OrderCatalogService.manas,
                            child: Text('Manas Sales'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setDlgState(() => chosenFirm = val);
                        },
                      ),
                    ],
                    const SizedBox(height: 10),
                  ],
                  const Text(
                    'Preview (first 15 items):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: result.items.length > 15 ? 15 : result.items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, idx) {
                        final item = result.items[idx];
                        final norm = item.name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
                        final existing = existingByNormName[norm];
                        final qtyLabel = item.closingQty == item.closingQty.roundToDouble()
                            ? '${item.closingQty.toInt()}'
                            : item.closingQty.toStringAsFixed(1);
                        return ListTile(
                          dense: true,
                          title: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            existing != null
                                ? 'Updates existing (${existing.formattedStock} -> $qtyLabel ${item.unit})'
                                : 'New item • $qtyLabel ${item.unit}${item.scheme.isNotEmpty ? " • ${item.scheme}" : ""}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: existing != null
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              existing != null ? 'Match' : 'New',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: existing != null
                                    ? const Color(0xFF15803D)
                                    : const Color(0xFFB45309),
                              ),
                            ),
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
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF15429E),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Update Stock'),
              onPressed: () async {
                Navigator.pop(dlgCtx);
                final summary = await provider.importTallyStock(
                  result.items,
                  defaultFirm: chosenFirm,
                  createUnmatched: createUnmatched,
                );
                if (context.mounted) {
                  QuickAlert.success(
                    context,
                    'Stock updated! ${summary.updatedCount} updated, ${summary.addedCount} added.',
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  static Widget _statBox(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> {
  static const Color _adminBlue = Color(0xFF15429E);
  static const List<String> _schemePresets = [
    '10+1 Free',
    '12+1 Free',
    '24+2 Free',
    '5% Off',
    '2% Cash Disc',
    'No Scheme',
  ];

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _firmFilter = 'All'; // 'All', 'Purva Enterprises', 'Manas Sales'
  String _companyFilter = 'All Companies';
  String _quickFilter = 'All'; // 'All', 'Has Scheme', 'In Stock', 'No Stock'

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<CatalogProduct> _filterProducts(List<CatalogProduct> all) {
    final q = _searchQuery.trim().toLowerCase();
    final filtered = all.where((p) {
      if (_firmFilter != 'All' && p.firm.toLowerCase() != _firmFilter.toLowerCase()) {
        return false;
      }
      if (_companyFilter != 'All Companies' &&
          p.company.toLowerCase() != _companyFilter.toLowerCase()) {
        return false;
      }
      if (_quickFilter == 'Has Scheme' && p.scheme.trim().isEmpty) return false;
      if (_quickFilter == 'In Stock' && p.stock <= 0) return false;
      if (_quickFilter == 'No Stock' && p.stock > 0) return false;

      if (q.isNotEmpty) {
        final hay =
            '${p.name} ${p.company} ${p.category} ${p.subcategory} ${p.scheme} ${p.firm}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return filtered;
  }

  Future<void> _openAddOrEditDialog({CatalogProduct? existing}) async {
    await showDialog<CatalogProduct>(
      context: context,
      builder: (_) => AddProductDialog(
        initialFirm: _firmFilter == 'All' ? null : _firmFilter,
        existingProduct: existing,
        enableSchemeAndStock: true,
      ),
    );
  }

  Future<void> _showQuickSchemeDialog(
    CatalogProduct product,
    CollectionProvider provider,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _QuickSchemeDialog(
        productName: product.name,
        initialScheme: product.scheme,
        presets: _schemePresets,
      ),
    );
    if (result == null) return;
    await provider.addCustomProduct(product.copyWith(scheme: result));
    if (mounted) {
      QuickAlert.success(
        context,
        result.isEmpty
            ? 'Scheme cleared for ${product.name}'
            : 'Scheme "$result" saved for ${product.name}',
      );
    }
  }

  Future<void> _confirmDelete(
    CatalogProduct product,
    CollectionProvider provider,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Product?'),
        content: Text(
          'Delete "${product.name}" (${product.company}) from the product catalog?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await provider.deleteCustomProduct(product.id);
      if (mounted) {
        QuickAlert.success(context, '"${product.name}" deleted from catalog.');
      }
    }
  }

  Widget _buildThumbnail(CatalogProduct product) {
    final base64Bytes = ImageCompressHelper.safeBase64Decode(product.photoBase64);
    Widget inner;
    if (base64Bytes != null) {
      inner = Image.memory(
        base64Bytes,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(Icons.inventory_2_outlined, size: 24, color: Color(0xFF94A3B8)),
      );
    } else if (product.photoUrl != null && product.photoUrl!.isNotEmpty) {
      inner = Image.network(
        product.photoUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(Icons.inventory_2_outlined, size: 24, color: Color(0xFF94A3B8)),
      );
    } else {
      inner = const Icon(Icons.inventory_2_outlined, size: 24, color: Color(0xFF94A3B8));
    }
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: inner,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().currentUser;
    if (currentUser?.isSuperAdmin != true) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: _adminBlue,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white, size: 22),
          title: const Text('Products & Schemes', style: TextStyle(color: Colors.white)),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded, size: 48, color: Color(0xFFDC2626)),
                SizedBox(height: 12),
                Text(
                  'Super Admin Access Only',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 6),
                Text(
                  'Only Super Admin login can edit, delete, import stock, and update product schemes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final provider = context.watch<CollectionProvider>();
    final allProducts = provider.customProducts;
    final companies = <String>{
      'All Companies',
      ...allProducts
          .where((p) => _firmFilter == 'All' || p.firm.toLowerCase() == _firmFilter.toLowerCase())
          .map((p) => p.company)
          .where((c) => c.trim().isNotEmpty),
    }.toList();
    if (!companies.contains(_companyFilter)) {
      _companyFilter = 'All Companies';
    }

    final filtered = _filterProducts(allProducts);
    final withSchemeCount = allProducts.where((p) => p.scheme.trim().isNotEmpty).length;
    final inStockCount = allProducts.where((p) => p.stock > 0).length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: _adminBlue,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white, size: 22),
        actionsIconTheme: const IconThemeData(color: Colors.white, size: 22),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Products, Stock & Schemes',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white),
            ),
            Text(
              '${allProducts.length} SKUs • $withSchemeCount Schemes • $inStockCount In Stock',
              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.85)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box_outlined),
            tooltip: 'Add New Product',
            onPressed: () => _openAddOrEditDialog(),
          ),
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Sync Catalog',
            onPressed: () => provider.syncAllWithCloud(notify: true),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _adminBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Add Product', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
        onPressed: () => _openAddOrEditDialog(),
      ),
      body: Column(
        children: [
          // Top Controls & Tally Stock Import Strip
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Firm Toggle + Company Dropdown
                Row(
                  children: [
                    _firmPill('All'),
                    const SizedBox(width: 6),
                    _firmPill(OrderCatalogService.purva, shortLabel: 'Purva'),
                    const SizedBox(width: 6),
                    _firmPill(OrderCatalogService.manas, shortLabel: 'Manas'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _companyFilter,
                            isExpanded: true,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                            items: companies
                                .map((c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(c, overflow: TextOverflow.ellipsis),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _companyFilter = v);
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Search Box
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search product, company, or scheme...',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 8),

                // Filter Chips + Tally Import Bar
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final f in ['All', 'Has Scheme', 'In Stock', 'No Stock'])
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(f, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                                  selected: _quickFilter == f,
                                  selectedColor: _adminBlue.withValues(alpha: 0.12),
                                  labelStyle: TextStyle(
                                    color: _quickFilter == f ? _adminBlue : AppTheme.textSecondary,
                                  ),
                                  onSelected: (_) => setState(() => _quickFilter = f),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Tally Stock Import Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F9FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBAE6FD)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.upload_file_rounded, color: Color(0xFF0369A1), size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tally Closing Stock',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF0C4A6E)),
                            ),
                            Text(
                              'Import XML or Excel stock summary to update quantities',
                              style: TextStyle(fontSize: 10.5, color: Color(0xFF0369A1)),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await TallyIntegrationService.downloadSampleStockExcel();
                          if (context.mounted) {
                            QuickAlert.success(context, 'Sample Stock Excel downloaded!');
                          }
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Sample', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 4),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0369A1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.file_upload_outlined, size: 15),
                        label: const Text('Import Stock', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                        onPressed: () => AdminProductsScreen.pickAndImportTallyStock(
                          context,
                          provider,
                          defaultFirm: _firmFilter == 'All' ? OrderCatalogService.purva : _firmFilter,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Product Catalog List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 10),
                          Text(
                            allProducts.isEmpty
                                ? 'No products in catalog yet'
                                : 'No products match current filters',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tap "Add Product" or import Tally Stock XML/Excel above.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, idx) {
                      final product = filtered[idx];
                      final isManas = product.firm.toLowerCase().contains('manas');
                      final hasScheme = product.scheme.trim().isNotEmpty;
                      final hasStock = product.stock > 0;

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildThumbnail(product),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              product.name,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isManas
                                                  ? AppTheme.manasLight
                                                  : AppTheme.purvaLight,
                                              borderRadius: BorderRadius.circular(5),
                                            ),
                                            child: Text(
                                              isManas ? 'Manas' : 'Purva',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: isManas
                                                    ? AppTheme.manasText
                                                    : AppTheme.purvaText,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${product.company} • ${product.category} (${product.subcategory}) • 1 CS = ${product.unitsPerCase} ${product.defaultUnit}',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: AppTheme.textSecondary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          // Stock Pill
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: hasStock
                                                  ? const Color(0xFFDCFCE7)
                                                  : const Color(0xFFF1F5F9),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.inventory_2_outlined,
                                                  size: 12,
                                                  color: hasStock
                                                      ? const Color(0xFF15803D)
                                                      : const Color(0xFF64748B),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Stock: ${product.formattedStock} ${product.defaultUnit}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: hasStock
                                                        ? const Color(0xFF15803D)
                                                        : const Color(0xFF64748B),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          // Scheme Pill
                                          InkWell(
                                            onTap: () => _showQuickSchemeDialog(product, provider),
                                            borderRadius: BorderRadius.circular(6),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: hasScheme
                                                    ? const Color(0xFFFEF3C7)
                                                    : const Color(0xFFF8FAFC),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: hasScheme
                                                      ? const Color(0xFFFCD34D)
                                                      : const Color(0xFFE2E8F0),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.local_offer_outlined,
                                                    size: 12,
                                                    color: hasScheme
                                                        ? const Color(0xFFB45309)
                                                        : const Color(0xFF64748B),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    hasScheme ? 'Scheme: ${product.scheme}' : 'No Scheme',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w700,
                                                      color: hasScheme
                                                          ? const Color(0xFFB45309)
                                                          : const Color(0xFF64748B),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Divider(height: 1),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _showQuickSchemeDialog(product, provider),
                                    icon: const Icon(Icons.local_offer_outlined, size: 15, color: Color(0xFFD97706)),
                                    label: Text(
                                      hasScheme ? 'Change Scheme' : 'Add Scheme',
                                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                                      minimumSize: Size.zero,
                                      side: const BorderSide(color: Color(0xFFFCD34D)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () => _openAddOrEditDialog(existing: product),
                                  icon: const Icon(Icons.edit_outlined, size: 15, color: _adminBlue),
                                  label: const Text(
                                    'Edit',
                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _adminBlue),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                                    minimumSize: Size.zero,
                                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: () => _confirmDelete(product, provider),
                                  icon: const Icon(Icons.delete_outline_rounded, size: 19, color: Color(0xFFDC2626)),
                                  tooltip: 'Delete Product',
                                  padding: const EdgeInsets.all(6),
                                  constraints: const BoxConstraints(),
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
      ),
    );
  }

  Widget _firmPill(String firmValue, {String? shortLabel}) {
    final selected = _firmFilter == firmValue;
    return InkWell(
      onTap: () => setState(() => _firmFilter = firmValue),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _adminBlue : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          shortLabel ?? firmValue,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _QuickSchemeDialog extends StatefulWidget {
  final String productName;
  final String initialScheme;
  final List<String> presets;

  const _QuickSchemeDialog({
    required this.productName,
    required this.initialScheme,
    required this.presets,
  });

  @override
  State<_QuickSchemeDialog> createState() => _QuickSchemeDialogState();
}

class _QuickSchemeDialogState extends State<_QuickSchemeDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialScheme);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.local_offer_rounded, color: Color(0xFFD97706), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Scheme: ${widget.productName}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Active Scheme / Offer',
                  hintText: 'e.g. 10+1 Free, 2% Disc (leave empty to clear)',
                  prefixIcon: const Icon(Icons.local_offer_outlined, size: 18),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    tooltip: 'Clear Scheme',
                    onPressed: () => _ctrl.clear(),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Quick Select:',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.presets.map((preset) {
                  return ActionChip(
                    label: Text(preset, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                    backgroundColor: preset == 'No Scheme'
                        ? const Color(0xFFF1F5F9)
                        : const Color(0xFFFEF3C7),
                    side: BorderSide(
                      color: preset == 'No Scheme'
                          ? const Color(0xFFCBD5E1)
                          : const Color(0xFFFCD34D),
                    ),
                    onPressed: () {
                      _ctrl.text = preset == 'No Scheme' ? '' : preset;
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF15429E),
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Save Scheme'),
        ),
      ],
    );
  }
}
