import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/collection_provider.dart';
import '../models/route_model.dart';
import '../models/shop_model.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';
import 'add_route_dialog.dart';
import 'add_shop_screen.dart';
import 'send_reminder_dialog.dart';
import 'package:flutter/services.dart';
import '../utils/firm_details.dart';
import '../services/location_service.dart';
import 'orders_screen.dart';

class RoutesShopsScreen extends StatefulWidget {
  const RoutesShopsScreen({super.key});

  @override
  State<RoutesShopsScreen> createState() => _RoutesShopsScreenState();
}

class _RoutesShopsScreenState extends State<RoutesShopsScreen> {
  String? _selectedRouteId;
  String? _selectedShopId;
  String _shopSearch = '';

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

    final shareText = '''
📍 *STORE LOCATION - ${shop.name}*
📌 *Address:* ${shop.address}
🗺️ *Google Maps:* $url
'''.trim();

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
                        shop.address,
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
            // WhatsApp to Shop
            if (shop.mobileNumber.isNotEmpty) ...[
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  String cleanPhone = shop.mobileNumber.replaceAll(RegExp(r'[^0-9]'), '');
                  if (cleanPhone.length == 10) cleanPhone = '91$cleanPhone';
                  final waUrl = 'https://wa.me/$cleanPhone?text=${Uri.encodeComponent(shareText)}';
                  await launchUrl(Uri.parse(waUrl), mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text('Send to ${shop.name} on WhatsApp'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
            ],
            // WhatsApp to Any Contact
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                final waUrl = 'https://api.whatsapp.com/send?text=${Uri.encodeComponent(shareText)}';
                await launchUrl(Uri.parse(waUrl), mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.share, size: 18, color: Color(0xFF25D366)),
              label: const Text('Share to Any WhatsApp Contact', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                side: const BorderSide(color: Color(0xFF25D366)),
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
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showAddLocationDialog(context, shop);
                },
                icon: const Icon(Icons.edit_location_alt_outlined, size: 16),
                label: const Text('Edit / Re-detect Location'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CollectionProvider>();
    final routes = provider.routes;

    if (_selectedRouteId == null && routes.isNotEmpty) {
      _selectedRouteId = routes.first.id;
    }

    final selectedRoute = routes.firstWhere(
      (r) => r.id == _selectedRouteId,
      orElse: () => routes.isNotEmpty
          ? routes.first
          : RouteModel(id: '', name: 'No Beat Selected'),
    );

    final outletsInSelectedRoute = _selectedRouteId != null && _selectedRouteId!.isNotEmpty
        ? provider.getShopsForRoute(_selectedRouteId!)
        : provider.shops;

    final shopsInRoute = provider.shops.where((s) {
      if (_selectedRouteId != null && _selectedRouteId!.isNotEmpty) {
        if (s.routeId != _selectedRouteId) return false;
      }
      if (_selectedShopId != null && _selectedShopId!.isNotEmpty) {
        if (s.id != _selectedShopId) return false;
      }
      if (_shopSearch.isNotEmpty) {
        final q = _shopSearch.toLowerCase();
        return s.name.toLowerCase().contains(q) ||
            s.mobileNumber.contains(q) ||
            s.address.toLowerCase().contains(q);
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
            icon: const Icon(Icons.add_business_outlined, size: 20),
            tooltip: 'Add Outlet',
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
                        value: routes.any((r) => r.id == _selectedRouteId)
                            ? _selectedRouteId
                            : routes.first.id,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.primary, size: 24),
                        items: routes.map((r) {
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
                        }).toList(),
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
                                          child: Text(
                                            '${s.name} (${s.mobileNumber})',
                                            style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                                            overflow: TextOverflow.ellipsis,
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
                                        // Location & Payment Actions Bar
                                        Row(
                                          children: [
                                            if (shop.hasLocation) ...[
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.location_on, size: 11, color: Color(0xFF10B981)),
                                                    SizedBox(width: 2),
                                                    Text('Maps Added', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF10B981))),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              InkWell(
                                                onTap: () => _shareShopLocation(shop),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: Colors.blueGrey.shade50,
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: AppTheme.border),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.share_location, size: 12, color: AppTheme.secondary),
                                                      SizedBox(width: 3),
                                                      Text('Share Loc', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppTheme.secondary)),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              InkWell(
                                                onTap: () => launchUrl(Uri.parse(shop.mapsUrl!), mode: LaunchMode.externalApplication),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: Colors.blueGrey.shade50,
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: AppTheme.border),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.map_outlined, size: 12, color: Colors.blueGrey),
                                                      SizedBox(width: 3),
                                                      Text('Maps', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.blueGrey)),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ] else ...[
                                              InkWell(
                                                onTap: () => _showAddLocationDialog(context, shop),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.add_location_alt_outlined, size: 12, color: Color(0xFFD97706)),
                                                      SizedBox(width: 3),
                                                      Text('+ Add Location', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFD97706))),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                            const Spacer(),
                                            // Send Payment Info button
                                            InkWell(
                                              onTap: () => FirmDetailsHelper.showQuickShareModal(
                                                context,
                                                recipientMobile: shop.mobileNumber,
                                                recipientName: shop.name,
                                              ),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.primary.withValues(alpha: 0.08),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.account_balance_outlined, size: 12, color: AppTheme.primary),
                                                    SizedBox(width: 3),
                                                    Text('Bank Info', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppTheme.primary)),
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
                                      } else if (val == 'order') {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => OrdersScreen(
                                              initialRouteId: shop.routeId,
                                              initialShopId: shop.id,
                                            ),
                                          ),
                                        );
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
                                            const SizedBox(width: 8),
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
                                      const PopupMenuItem(
                                        value: 'order',
                                        child: Row(
                                          children: [
                                            Icon(Icons.shopping_bag_outlined, size: 18, color: Color(0xFFF59E0B)),
                                            SizedBox(width: 8),
                                            Text('Take Order'),
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
                              const Divider(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (balanceDue > 0)
                                        Text(
                                          'Due: ${CurrencyFormatter.format(balanceDue)}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: AppTheme.partialBadgeColor,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        )
                                      else
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppTheme.cashColor.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'All Clear',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: AppTheme.cashColor,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (balanceDue > 0)
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
