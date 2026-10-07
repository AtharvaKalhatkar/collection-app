import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as xl;
import '../providers/collection_provider.dart';
import '../models/route_model.dart';
import '../models/shop_model.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';
import '../utils/file_download/file_download.dart';
import 'add_route_dialog.dart';
import 'add_shop_screen.dart';
import 'send_reminder_dialog.dart';
import 'package:flutter/services.dart';
import '../utils/firm_details.dart';
import '../services/location_service.dart';
import '../utils/marathi_search_helper.dart';

class RoutesShopsScreen extends StatefulWidget {
  const RoutesShopsScreen({super.key});

  @override
  State<RoutesShopsScreen> createState() => _RoutesShopsScreenState();
}

class _RoutesShopsScreenState extends State<RoutesShopsScreen> {
  String? _selectedRouteId;
  String? _selectedShopId;
  String _shopSearch = '';

  Future<void> _exportOutletsToExcel(CollectionProvider provider) async {
    try {
      final excel = xl.Excel.createExcel();
      final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
      final outletSheet = excel['Outlets'];
      excel.setDefaultSheet('Outlets');
      if (defaultSheet != 'Outlets') {
        excel.delete(defaultSheet);
      }

      // Setup professional column widths for Outlets
      final outletColWidths = <int, double>{
        0: 8.0,   // Sr No
        1: 34.0,  // Outlet / Store Name
        2: 20.0,  // Beat Route
        3: 16.0,  // Mobile Number
        4: 32.0,  // Address
        5: 22.0,  // Owner / Contact Person
        6: 45.0,  // Google Maps URL
        7: 14.0,  // Latitude
        8: 14.0,  // Longitude
        9: 18.0,  // Registration Date
      };
      outletColWidths.forEach((col, w) => outletSheet.setColumnWidth(col, w));

      // Executive Header Style
      final headerStyle = xl.CellStyle(
        bold: true,
        fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
        backgroundColorHex: xl.ExcelColor.fromHexString('#1E293B'),
        horizontalAlign: xl.HorizontalAlign.Center,
        verticalAlign: xl.VerticalAlign.Center,
        topBorder: xl.Border(borderStyle: xl.BorderStyle.Thin, borderColorHex: xl.ExcelColor.fromHexString('#0F172A')),
        bottomBorder: xl.Border(borderStyle: xl.BorderStyle.Medium, borderColorHex: xl.ExcelColor.fromHexString('#0F172A')),
      );

      final thinBorder = xl.Border(
        borderStyle: xl.BorderStyle.Thin,
        borderColorHex: xl.ExcelColor.fromHexString('#E2E8F0'),
      );

      final outletHeaders = [
        'Sr No',
        'Outlet / Store Name',
        'Beat Route',
        'Mobile Number',
        'Address',
        'Owner / Contact Person',
        'Google Maps URL',
        'Latitude',
        'Longitude',
        'Registration Date',
      ];

      for (int c = 0; c < outletHeaders.length; c++) {
        final cell = outletSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
        cell.value = xl.TextCellValue(outletHeaders[c]);
        cell.cellStyle = headerStyle;
      }

      final shops = provider.shops;
      for (int i = 0; i < shops.length; i++) {
        final s = shops[i];
        final mapsUrl = s.mapsUrl ?? '';
        final isEven = (i % 2 == 0);
        final rowBg = isEven ? xl.ExcelColor.fromHexString('#FFFFFF') : xl.ExcelColor.fromHexString('#F8FAFC');

        final rowValues = <xl.CellValue>[
          xl.IntCellValue(i + 1),
          xl.TextCellValue(s.name),
          xl.TextCellValue(s.routeName),
          xl.TextCellValue(s.mobileNumber),
          xl.TextCellValue(s.address),
          xl.TextCellValue(s.ownerName ?? ''),
          xl.TextCellValue(mapsUrl),
          xl.TextCellValue(s.latitude?.toString() ?? ''),
          xl.TextCellValue(s.longitude?.toString() ?? ''),
          xl.TextCellValue(DateFormat('yyyy-MM-dd').format(s.createdAt)),
        ];

        for (int c = 0; c < rowValues.length; c++) {
          final cell = outletSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: i + 1));
          cell.value = rowValues[c];
          final isCenter = (c == 0 || c == 3 || c == 7 || c == 8 || c == 9);
          cell.cellStyle = xl.CellStyle(
            horizontalAlign: isCenter ? xl.HorizontalAlign.Center : xl.HorizontalAlign.Left,
            verticalAlign: xl.VerticalAlign.Center,
            backgroundColorHex: rowBg,
            bottomBorder: thinBorder,
          );
        }
      }

      final routeSheet = excel['Routes'];
      final routeColWidths = <int, double>{
        0: 8.0,   // Sr No
        1: 24.0,  // Route Name
        2: 36.0,  // Description / Areas
        3: 14.0,  // Priority
        4: 16.0,  // Total Outlets
      };
      routeColWidths.forEach((col, w) => routeSheet.setColumnWidth(col, w));

      final routeHeaders = [
        'Sr No',
        'Route Name',
        'Description / Areas',
        'Priority',
        'Total Outlets',
      ];

      for (int c = 0; c < routeHeaders.length; c++) {
        final cell = routeSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
        cell.value = xl.TextCellValue(routeHeaders[c]);
        cell.cellStyle = headerStyle;
      }

      final routes = provider.routes;
      for (int i = 0; i < routes.length; i++) {
        final r = routes[i];
        final count = provider.getShopsForRoute(r.id).length;
        final isEven = (i % 2 == 0);
        final rowBg = isEven ? xl.ExcelColor.fromHexString('#FFFFFF') : xl.ExcelColor.fromHexString('#F8FAFC');

        final rowValues = <xl.CellValue>[
          xl.IntCellValue(i + 1),
          xl.TextCellValue(r.name),
          xl.TextCellValue(r.description ?? ''),
          xl.IntCellValue(r.priority),
          xl.IntCellValue(count),
        ];

        for (int c = 0; c < rowValues.length; c++) {
          final cell = routeSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: i + 1));
          cell.value = rowValues[c];
          final isCenter = (c == 0 || c == 3 || c == 4);
          cell.cellStyle = xl.CellStyle(
            horizontalAlign: isCenter ? xl.HorizontalAlign.Center : xl.HorizontalAlign.Left,
            verticalAlign: xl.VerticalAlign.Center,
            backgroundColorHex: rowBg,
            bottomBorder: thinBorder,
          );
        }
      }

      final bytes = excel.encode();
      if (bytes != null) {
        await downloadFile(
          bytes: bytes,
          fileName: 'Registered_Outlets_and_Routes.xlsx',
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.table_view_outlined, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(child: Text('Excel file "Registered_Outlets_and_Routes.xlsx" downloaded!')),
                ],
              ),
              backgroundColor: Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export Excel: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _confirmAndDeleteShop(ShopModel shop) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Outlet?'),
        content: Text('Are you sure you want to delete "${shop.name}"?\nThis cannot be undone.'),
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
      await context.read<CollectionProvider>().deleteShop(shop.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Store "${shop.name}" deleted'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _showAddLocationDialog(BuildContext context, ShopModel shop) async {
    final locCtrl = TextEditingController(text: shop.locationUrl ?? (shop.mapsUrl ?? ''));
    double? tempLat = shop.latitude;
    double? tempLng = shop.longitude;
    bool isDetecting = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.add_location_alt_outlined, color: AppTheme.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    shop.hasLocation ? 'Update Location: ${shop.name}' : 'Set Location: ${shop.name}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Add a Google Maps link or capture GPS coordinates so you can easily locate or share this store.',
                    style: TextStyle(fontSize: 12.5, color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: locCtrl,
                    decoration: InputDecoration(
                      labelText: 'Google Maps Link / Coords',
                      hintText: 'https://maps.google.com/?q=... or 18.75,73.85',
                      prefixIcon: const Icon(Icons.link, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: isDetecting
                        ? null
                        : () async {
                            setDialogState(() => isDetecting = true);
                            final pos = await LocationService.getCurrentLocation();
                            setDialogState(() => isDetecting = false);
                            if (pos != null) {
                              tempLat = pos.latitude;
                              tempLng = pos.longitude;
                              locCtrl.text = LocationService.buildMapsUrl(pos.latitude, pos.longitude);
                            } else {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Could not fetch GPS. Please enter maps link manually.'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            }
                          },
                    icon: isDetecting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location, size: 16),
                    label: Text(isDetecting ? 'Detecting GPS...' : 'Use Current GPS Location'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                onPressed: () async {
                  final text = locCtrl.text.trim();
                  await context.read<CollectionProvider>().updateShopLocation(
                    shop.id,
                    locationUrl: text.isNotEmpty ? text : null,
                    latitude: tempLat,
                    longitude: tempLng,
                  );
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Location saved for "${shop.name}"!'),
                        backgroundColor: const Color(0xFF10B981),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                child: const Text('Save Location', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _shareShopLocation(ShopModel shop) async {
    final url = shop.mapsUrl;
    if (url == null || url.isEmpty) {
      _showAddLocationDialog(context, shop);
      return;
    }

    final lines = <String>[
      shop.name,
      if (shop.address.trim().isNotEmpty) 'Address: ${shop.address.trim()}',
      if (shop.mobileNumber.trim().isNotEmpty) 'Mobile: ${shop.mobileNumber.trim()}',
      'Google Maps: $url',
    ];
    final shareText = lines.join('\n');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.location_on, color: Color(0xFF10B981), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (shop.address.isNotEmpty) shop.address,
                          if (shop.mobileNumber.isNotEmpty) shop.mobileNumber,
                        ].join(' • '),
                        style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.map_outlined, size: 18, color: Colors.blueGrey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      url,
                      style: const TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Primary Share on WhatsApp button
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                final waUrl = 'https://api.whatsapp.com/send?text=${Uri.encodeComponent(shareText)}';
                await launchUrl(Uri.parse(waUrl), mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.share, size: 18),
              label: const Text('Share Location on WhatsApp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                    },
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open Maps'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await Clipboard.setData(ClipboardData(text: url));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Maps link copied to clipboard!'),
                            backgroundColor: Color(0xFF10B981),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy Link'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            // Edit or Delete Location Options
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showAddLocationDialog(context, shop);
                    },
                    icon: const Icon(Icons.edit_location_alt_outlined, size: 16, color: AppTheme.primary),
                    label: const Text('Edit Location', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _confirmAndDeleteLocation(shop);
                    },
                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                    label: const Text('Delete Location', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndDeleteLocation(ShopModel shop) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Location?'),
        content: Text('Remove saved Google Maps location for "${shop.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<CollectionProvider>().deleteShopLocation(shop.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Location deleted for "${shop.name}"'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CollectionProvider>();
    final routes = provider.routes;

    final isAllRoutes = _selectedRouteId == null || _selectedRouteId == 'all';

    final selectedRoute = isAllRoutes
        ? RouteModel(id: 'all', name: 'All Routes')
        : routes.firstWhere(
            (r) => r.id == _selectedRouteId,
            orElse: () => routes.isNotEmpty
                ? routes.first
                : RouteModel(id: '', name: 'No Beat Selected'),
          );

    final outletsInSelectedRoute = isAllRoutes
        ? provider.shops
        : provider.getShopsForRoute(_selectedRouteId!);

    final shopsInRoute = provider.shops.where((s) {
      if (!isAllRoutes) {
        if (s.routeId != _selectedRouteId) return false;
      }
      if (_selectedShopId != null && _selectedShopId!.isNotEmpty) {
        if (s.id != _selectedShopId) return false;
      }
      if (_shopSearch.isNotEmpty) {
        final q = _shopSearch.trim();
        return MarathiSearchHelper.matches(s.name, q) ||
            MarathiSearchHelper.matches(s.address, q) ||
            (s.ownerName != null && MarathiSearchHelper.matches(s.ownerName!, q)) ||
            s.mobileNumber.contains(q);
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Routes & Outlets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_location_alt_outlined, size: 20),
            tooltip: 'Add Route',
            onPressed: () async {
              final newRoute = await showDialog<RouteModel>(
                context: context,
                builder: (ctx) => const AddRouteDialog(),
              );
              if (newRoute != null) {
                setState(() {
                  _selectedRouteId = newRoute.id;
                  _selectedShopId = null;
                });
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.table_view_outlined, size: 20),
            tooltip: 'Export Outlets to Excel',
            onPressed: () => _exportOutletsToExcel(provider),
          ),
          IconButton(
            icon: const Icon(Icons.add_business_outlined, size: 20),
            tooltip: 'Add Outlet',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddShopScreen(
                    initialRouteId: isAllRoutes ? (routes.isNotEmpty ? routes.first.id : null) : _selectedRouteId,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Route Dropdown Selector Bar
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ROUTE',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Colors.blueGrey,
                  ),
                ),
                const SizedBox(height: 8),
                if (routes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Center(
                      child: TextButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Create your first beat (e.g. Chakan)'),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (ctx) => const AddRouteDialog(),
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border, width: 1.2),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: isAllRoutes
                            ? 'all'
                            : (routes.any((r) => r.id == _selectedRouteId) ? _selectedRouteId : 'all'),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.primary, size: 24),
                        items: [
                          DropdownMenuItem<String>(
                            value: 'all',
                            child: Row(
                              children: [
                                const Icon(Icons.alt_route_rounded, size: 18, color: AppTheme.primary),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'All Routes',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0F172A)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${provider.shops.length} outlets',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...routes.map((r) {
                            final count = provider.getShopsForRoute(r.id).length;
                            return DropdownMenuItem<String>(
                              value: r.id,
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on_outlined, size: 18, color: AppTheme.primary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      r.name,
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0F172A)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '$count outlets',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedRouteId = val;
                              _selectedShopId = null;
                            });
                          }
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Route Details Banner, Outlet Dropdown, & Search
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (selectedRoute.id.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  selectedRoute.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${outletsInSelectedRoute.length} outlets',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (selectedRoute.description != null && selectedRoute.description!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text(
                                  selectedRoute.description!,
                                  style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (selectedRoute.id != 'all' && selectedRoute.id.isNotEmpty)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.edit_outlined, size: 14, color: AppTheme.primary),
                          label: const Text('Edit Route', style: TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            side: const BorderSide(color: AppTheme.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: () async {
                            final result = await showDialog(
                              context: context,
                              builder: (ctx) => AddRouteDialog(existingRoute: selectedRoute),
                            );
                            if (result == 'deleted') {
                              setState(() {
                                _selectedRouteId = null;
                                _selectedShopId = null;
                              });
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Outlet Dropdown Selector for this Route
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border, width: 1.2),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _selectedShopId,
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.primary, size: 22),
                        hint: Row(
                          children: [
                            const Icon(Icons.storefront_outlined, size: 18, color: AppTheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                outletsInSelectedRoute.isEmpty
                                    ? 'No outlets in ${selectedRoute.name}'
                                    : 'All Outlets in ${selectedRoute.name} (${outletsInSelectedRoute.length})',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF0F172A)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        selectedItemBuilder: (ctx) {
                          if (outletsInSelectedRoute.isEmpty) {
                            return [
                              Row(
                                children: [
                                  const Icon(Icons.storefront_outlined, size: 18, color: Colors.blueGrey),
                                  const SizedBox(width: 8),
                                  Text(
                                    'No outlets in ${selectedRoute.name}',
                                    style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade600),
                                  ),
                                ],
                              ),
                            ];
                          }
                          return [
                            Row(
                              children: [
                                const Icon(Icons.storefront_outlined, size: 18, color: AppTheme.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'All Outlets in ${selectedRoute.name} (${outletsInSelectedRoute.length})',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0F172A)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            ...outletsInSelectedRoute.map(
                              (s) => Row(
                                children: [
                                  const Icon(Icons.store_outlined, size: 18, color: AppTheme.primary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(
                                        text: s.name,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                        children: [
                                          if (s.address.trim().isNotEmpty)
                                            TextSpan(
                                              text: ' • ${s.address.trim()}',
                                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.blueGrey.shade600),
                                            ),
                                        ],
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ];
                        },
                        items: outletsInSelectedRoute.isEmpty
                            ? [
                                DropdownMenuItem<String?>(
                                  value: null,
                                  child: Row(
                                    children: [
                                      const Icon(Icons.storefront_outlined, size: 18, color: Colors.blueGrey),
                                      const SizedBox(width: 8),
                                      Text(
                                        'No outlets in ${selectedRoute.name}',
                                        style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                              ]
                            : [
                                DropdownMenuItem<String?>(
                                  value: null,
                                  child: Row(
                                    children: [
                                      const Icon(Icons.storefront_outlined, size: 18, color: AppTheme.primary),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'All Outlets in ${selectedRoute.name} (${outletsInSelectedRoute.length})',
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0F172A)),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ...outletsInSelectedRoute.map(
                                  (s) => DropdownMenuItem<String?>(
                                    value: s.id,
                                    child: Row(
                                      children: [
                                        const Icon(Icons.store_outlined, size: 18, color: AppTheme.primary),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                s.name,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF0F172A),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (s.address.trim().isNotEmpty) ...[
                                                const SizedBox(height: 1),
                                                Text(
                                                  s.address.trim(),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.blueGrey.shade600,
                                                    fontWeight: FontWeight.w400,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                        onChanged: (val) {
                          setState(() => _selectedShopId = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Search Box
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search outlet...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.secondary, width: 1.5),
                    ),
                    suffixIcon: _shopSearch.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () => setState(() => _shopSearch = ''),
                          )
                        : null,
                  ),
                  onChanged: (val) => setState(() => _shopSearch = val),
                ),
              ],
            ),
          ),

          // Outlets List
          Expanded(
            child: shopsInRoute.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.storefront_outlined, size: 48, color: Colors.blueGrey.shade200),
                        const SizedBox(height: 10),
                        Text(
                          _shopSearch.isNotEmpty
                              ? 'No outlets matching "$_shopSearch"'
                              : 'No outlets registered under "${selectedRoute.name}" yet',
                          style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add, size: 16),
                          label: Text('Add Outlet to ${selectedRoute.name}'),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AddShopScreen(initialRouteId: _selectedRouteId),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: shopsInRoute.length,
                    itemBuilder: (context, index) {
                      final shop = shopsInRoute[index];
                      final balanceDue = provider.getTotalBalanceForShop(shop.id);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppTheme.border),
                                    ),
                                    child: Center(
                                      child: Text(
                                        shop.name.isNotEmpty ? shop.name[0].toUpperCase() : 'S',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primary),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          shop.name,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                        if (shop.ownerName != null && shop.ownerName!.isNotEmpty)
                                          Text(
                                            'Contact: ${shop.ownerName}',
                                            style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                                          ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            const Icon(Icons.phone_outlined, size: 13, color: Colors.blueGrey),
                                            const SizedBox(width: 4),
                                            Text(
                                              shop.mobileNumber,
                                              style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade800),
                                            ),
                                            const Spacer(),
                                            // Call button
                                            InkWell(
                                              onTap: () => launchUrl(Uri.parse('tel:${shop.mobileNumber}')),
                                              borderRadius: BorderRadius.circular(6),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.call, size: 14, color: Color(0xFF10B981)),
                                                    SizedBox(width: 4),
                                                    Text('Call', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF10B981))),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            // SMS button
                                            InkWell(
                                              onTap: () => launchUrl(Uri.parse('sms:${shop.mobileNumber}')),
                                              borderRadius: BorderRadius.circular(6),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.primary.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.message_outlined, size: 14, color: AppTheme.primary),
                                                    SizedBox(width: 4),
                                                    Text('SMS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            const Icon(Icons.place_outlined, size: 13, color: Colors.blueGrey),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                shop.address,
                                                style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade500),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        // Location Actions Bar
                                        Row(
                                          children: [
                                            if (shop.hasLocation)
                                              InkWell(
                                                onTap: () => _shareShopLocation(shop),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF10B981).withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(5),
                                                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.share_location, size: 12, color: Color(0xFF059669)),
                                                      SizedBox(width: 4),
                                                      Text('Share Location', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF059669))),
                                                    ],
                                                  ),
                                                ),
                                              )
                                            else
                                              InkWell(
                                                onTap: () => _showAddLocationDialog(context, shop),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(5),
                                                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.add_location_alt_outlined, size: 12, color: Color(0xFFD97706)),
                                                      SizedBox(width: 4),
                                                      Text('+ Add Location', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFD97706))),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, size: 20, color: Colors.blueGrey),
                                    padding: EdgeInsets.zero,
                                    tooltip: 'Options',
                                    onSelected: (val) async {
                                      if (val == 'bank') {
                                        FirmDetailsHelper.showQuickShareModal(
                                          context,
                                          recipientMobile: shop.mobileNumber,
                                          recipientName: shop.name,
                                        );
                                      } else if (val == 'loc_edit') {
                                        _showAddLocationDialog(context, shop);
                                      } else if (val == 'loc_share') {
                                        _shareShopLocation(shop);
                                      } else if (val == 'loc_delete') {
                                        _confirmAndDeleteLocation(shop);
                                      } else if (val == 'edit') {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => AddShopScreen(existingShop: shop),
                                          ),
                                        );
                                      } else if (val == 'delete') {
                                        _confirmAndDeleteShop(shop);
                                      }
                                    },
                                    itemBuilder: (ctx) => [
                                      const PopupMenuItem(
                                        value: 'bank',
                                        child: Row(
                                          children: [
                                            Icon(Icons.send_rounded, size: 18, color: Color(0xFF25D366)),
                                            SizedBox(width: 8),
                                            Text('Send Bank Details'),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'loc_edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.location_on_outlined, size: 18, color: AppTheme.secondary),
                                            SizedBox(width: 8),
                                            Text(shop.hasLocation ? 'Update Location' : 'Add Location'),
                                          ],
                                        ),
                                      ),
                                      if (shop.hasLocation)
                                        const PopupMenuItem(
                                          value: 'loc_share',
                                          child: Row(
                                            children: [
                                              Icon(Icons.share_location, size: 18, color: AppTheme.secondary),
                                              SizedBox(width: 8),
                                              Text('Share Location Link'),
                                            ],
                                          ),
                                        ),
                                      if (shop.hasLocation)
                                        const PopupMenuItem(
                                          value: 'loc_delete',
                                          child: Row(
                                            children: [
                                              Icon(Icons.location_off_outlined, size: 18, color: AppTheme.error),
                                              SizedBox(width: 8),
                                              Text('Delete Location', style: TextStyle(color: AppTheme.error)),
                                            ],
                                          ),
                                        ),
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit_outlined, size: 18, color: AppTheme.primary),
                                            SizedBox(width: 8),
                                            Text('Edit Store'),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: const [
                                            Icon(Icons.delete_outline, size: 18, color: AppTheme.error),
                                            SizedBox(width: 8),
                                            Text('Delete Store', style: TextStyle(color: AppTheme.error)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (balanceDue > 0) ...[
                                const Divider(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Due: ${CurrencyFormatter.format(balanceDue)}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.partialBadgeColor,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.notifications_active_outlined, size: 13, color: AppTheme.chequeColor),
                                      label: const Text('Remind', style: TextStyle(color: AppTheme.chequeColor, fontSize: 12, fontWeight: FontWeight.bold)),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        side: const BorderSide(color: AppTheme.chequeColor),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                      ),
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (ctx) => SendReminderDialog(
                                            shopName: shop.name,
                                            mobileNumber: shop.mobileNumber,
                                            businessName: provider.businesses.first,
                                            salesmanName: provider.salesmanName,
                                            balanceAmount: balanceDue,
                                          ),
                                        );
                                      },
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
        heroTag: 'routes_fab_add_store',
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add_business_outlined, color: Colors.white),
        label: const Text('Add Outlet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddShopScreen(initialRouteId: _selectedRouteId),
            ),
          );
        },
      ),
    );
  }
}
