import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/location_timeline_entry.dart';
import '../models/shop_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/collection_provider.dart';
import '../services/location_service.dart';
import '../services/location_tracking_service.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';
import '../utils/currency_formatter.dart';
import '../utils/quick_alert.dart';
import '../utils/theme.dart';
import '../utils/timeline_segment_builder.dart';

class LiveStaffLocationsScreen extends StatefulWidget {
  final String? initialStaffName;
  final int initialTabIndex; // 0: Timeline, 1: Live Map, 2: Staff List

  const LiveStaffLocationsScreen({
    super.key,
    this.initialStaffName,
    this.initialTabIndex = 0,
  });

  @override
  State<LiveStaffLocationsScreen> createState() =>
      _LiveStaffLocationsScreenState();
}

class _LiveStaffLocationsScreenState extends State<LiveStaffLocationsScreen>
    with SingleTickerProviderStateMixin {
  static const Color _primaryBlue = Color(0xFF15429E);
  static const Color _tealAccent = Color(0xFF0284C7);

  late TabController _tabController;
  late final MapController _mapController;

  DateTime _selectedDate = DateTime.now();
  String _selectedStaffFilter = 'all';
  String _liveRoleFilter = 'all';
  int _timelineSubTabIndex = 0; // 0: Day, 1: Trips, 2: Places
  bool _isRefreshing = false;
  bool _isLoadingTimeline = false;

  // Map state
  bool _mapReady = false;
  ({ll.LatLng center, double zoom})? _pendingMapMove;
  String _mapLayer = 'streets'; // 'streets' (Google Roadmap) | 'satellite' (Google Hybrid)
  bool _showOutletsOnMap = true;
  bool _showTrailOnMap = true;
  ShopModel? _selectedShop;
  UserModel? _selectedStaffUser;
  String? _selectedMapRouteId;
  String _shopSearchQuery = '';
  final TextEditingController _mapSearchCtrl = TextEditingController();

  List<LocationTimelineEntry> _timelineEntries = [];
  Timer? _livePollTimer;

  static String cleanLandmark(
    String raw, {
    double? lat,
    double? lng,
    List<ShopModel> allShops = const [],
  }) {
    if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
      final cached = LocationTrackingService.getCachedPlace(lat, lng);
      if (cached != null) return cached.displayLabel;
    }

    var s = raw.trim().replaceAll(';', ',');
    if (s.startsWith(RegExp(r'^(At|Near)\s+', caseSensitive: false))) {
      s = s.replaceFirst(RegExp(r'^(At|Near)\s+', caseSensitive: false), '');
    }
    s = s
        .replaceAll(
            RegExp(r'\s*\(\s*~?\s*\d+\s*[a-zA-Z]*\s*\)', caseSensitive: false),
            '')
        .trim();

    final isGeneric = s.isEmpty ||
        s == 'Khed, खेड' ||
        s == 'Khed' ||
        s == 'खेड' ||
        s.startsWith('GPS:') ||
        s == 'Active in Beat' ||
        s == 'Active on sales route' ||
        s == 'Transit on delivery beat';

    if (isGeneric && lat != null && lng != null && lat != 0.0 && lng != 0.0) {
      final reg = LocationTrackingService.getKnownRegion(lat, lng);
      if (reg != null && reg.isNotEmpty) {
        return reg;
      }
      return LocationTrackingService.findNearestLandmark(lat, lng, allShops);
    }

    if (s == 'Khed, खेड' || s == 'Khed' || s == 'खेड') {
      return 'Rajgurunagar';
    }

    return s.isNotEmpty ? s : 'Active on Route';
  }

  String _getMapUrlTemplate() {
    if (_mapLayer == 'satellite') {
      return 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
    }
    return 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}';
  }

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    if (widget.initialStaffName != null && widget.initialStaffName!.isNotEmpty) {
      _selectedStaffFilter = widget.initialStaffName!;
    }
    _loadTimeline();
    if (!SupabaseService().isTestMode) {
      _livePollTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        _silentLiveRefresh();
      });
    }
  }

  @override
  void dispose() {
    _livePollTimer?.cancel();
    _mapController.dispose();
    _tabController.dispose();
    _mapSearchCtrl.dispose();
    super.dispose();
  }

  void _safeMoveMap(ll.LatLng target, double zoom) {
    if (_mapReady) {
      try {
        _mapController.move(target, zoom);
      } catch (_) {
        _pendingMapMove = (center: target, zoom: zoom);
      }
    } else {
      _pendingMapMove = (center: target, zoom: zoom);
    }
  }

  void _focusMapOn(ll.LatLng target, {double zoom = 15.0}) {
    _tabController.animateTo(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _safeMoveMap(target, zoom);
    });
  }

  Future<void> _silentLiveRefresh() async {
    if (!mounted) return;
    try {
      final auth = context.read<AuthProvider>();
      await auth.refreshUsers();
      if (_isToday(_selectedDate)) {
        await _loadTimeline(showSpinner: false);
      }
    } catch (_) {}
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    final auth = context.read<AuthProvider>();
    final collectionProvider = context.read<CollectionProvider>();

    try {
      await LocationTrackingService().captureImmediate(
        auth: auth,
        collectionProvider: collectionProvider,
      );
      await auth.refreshUsers();
      await _loadTimeline(showSpinner: false);
    } catch (_) {}

    if (mounted) {
      setState(() => _isRefreshing = false);
      QuickAlert.success(context, 'Live locations & timeline refreshed');
    }
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  bool _isYesterday(DateTime d) {
    final y = DateTime.now().subtract(const Duration(days: 1));
    return d.year == y.year && d.month == y.month && d.day == y.day;
  }

  String _formatDateSelectorLabel(DateTime d) {
    if (_isToday(d)) return 'Today (${DateFormat('d MMM').format(d)})';
    if (_isYesterday(d)) return 'Yesterday (${DateFormat('d MMM').format(d)})';
    return DateFormat('EEE, d MMM yyyy').format(d);
  }

  Future<void> _loadTimeline({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() => _isLoadingTimeline = true);
    }

    try {
      // 1. Fetch from Supabase cloud
      final cloudEntries = await SupabaseService().fetchLocationTimeline(
        date: _selectedDate,
        staffName: _selectedStaffFilter == 'all' ? null : _selectedStaffFilter,
      );

      // 2. Fetch from local cache
      final localEntries = await StorageService().loadLocationTimeline();
      final filteredLocal = localEntries.where((e) {
        final sameDay = e.timestamp.year == _selectedDate.year &&
            e.timestamp.month == _selectedDate.month &&
            e.timestamp.day == _selectedDate.day;
        if (!sameDay) return false;
        if (_selectedStaffFilter != 'all') {
          return _matchesStaffFilter(e.staffName, e.userId, _selectedStaffFilter);
        }
        return true;
      }).toList();

      if (!mounted) return;
      final collectionProvider = context.read<CollectionProvider>();

      // 3. Synthesize collections recorded on this date
      final dayCollections = collectionProvider
          .getFilteredCollections(forDate: _selectedDate)
          .where((c) =>
              _selectedStaffFilter == 'all' ||
              _matchesStaffFilter(c.salesmanName, '', _selectedStaffFilter))
          .toList();

      final synthesizedCollections = dayCollections.map((c) {
        final shop = collectionProvider.getShopById(c.shopId);
        final pos = shop != null ? _getShopLatLng(shop) : null;
        return LocationTimelineEntry(
          id: 'coll_${c.id}',
          userId: c.salesmanName,
          staffName: c.salesmanName,
          staffRole: 'salesman',
          timestamp: c.collectedAt,
          latitude: pos?.latitude ?? 0.0,
          longitude: pos?.longitude ?? 0.0,
          landmark: shop != null ? shop.name : c.shopName,
          eventType: 'collection',
          details:
              'Collected ${CurrencyFormatter.format(c.collectedAmount)} (${c.paymentMode.displayName}) • Bill #${c.billNumber}',
          amount: c.collectedAmount,
          shopName: c.shopName,
          routeName: c.routeName,
          billNumber: c.billNumber,
        );
      }).toList();

      // 4. Synthesize sales orders booked on this date
      final dayOrders = collectionProvider.salesOrders.where((o) {
        final sameDay = o.orderDate.year == _selectedDate.year &&
            o.orderDate.month == _selectedDate.month &&
            o.orderDate.day == _selectedDate.day;
        if (!sameDay) return false;
        return _selectedStaffFilter == 'all' ||
            _matchesStaffFilter(o.salesmanName, '', _selectedStaffFilter);
      }).toList();

      final synthesizedOrders = dayOrders.map((o) {
        final shop = collectionProvider.getShopById(o.shopId);
        final pos = shop != null ? _getShopLatLng(shop) : null;
        return LocationTimelineEntry(
          id: 'ord_${o.id}',
          userId: o.salesmanName,
          staffName: o.salesmanName,
          staffRole: 'order',
          timestamp: o.orderDate,
          latitude: pos?.latitude ?? 0.0,
          longitude: pos?.longitude ?? 0.0,
          landmark: shop != null ? shop.name : o.shopName,
          eventType: 'orderBooked',
          details:
              'Order #${o.orderNumber} (${o.items.length} items, ${o.totalCases} CS ${o.totalLooseUnits} UT)',
          amount: o.totalAmount > 0 ? o.totalAmount : null,
          shopName: o.shopName,
          routeName: o.routeName,
          billNumber: o.orderNumber,
        );
      }).toList();

      // Combine & deduplicate
      final Map<String, LocationTimelineEntry> mergedMap = {};
      for (final e in filteredLocal) {
        mergedMap[e.id] = e;
      }
      for (final e in cloudEntries) {
        mergedMap[e.id] = e;
      }
      for (final e in synthesizedCollections) {
        final exists = mergedMap.values.any((m) =>
            m.isCollection &&
            m.billNumber == e.billNumber &&
            _matchesStaffFilter(m.staffName, m.userId, e.staffName));
        if (!exists) mergedMap[e.id] = e;
      }
      for (final e in synthesizedOrders) {
        final exists = mergedMap.values.any((m) =>
            m.isOrderBooked &&
            m.billNumber == e.billNumber &&
            _matchesStaffFilter(m.staffName, m.userId, e.staffName));
        if (!exists) mergedMap[e.id] = e;
      }

      var list = mergedMap.values.toList();
      if (_selectedStaffFilter != 'all') {
        list = list
            .where((e) => _matchesStaffFilter(e.staffName, e.userId, _selectedStaffFilter))
            .toList();
      }
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      if (mounted) {
        setState(() {
          _timelineEntries = list;
          _isLoadingTimeline = false;
        });
      }

      // Background address enrichment for clean Google-Maps-style street & locality display
      _enrichTimelineAddresses(list);
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingTimeline = false);
      }
    }
  }

  Future<void> _enrichTimelineAddresses(List<LocationTimelineEntry> entries) async {
    if (SupabaseService().isTestMode || entries.isEmpty) return;

    final seenCells = <String>{};
    bool resolvedAny = false;
    int lookups = 0;

    for (final e in entries) {
      if (lookups >= 15 || !mounted) break;
      if (e.latitude == 0.0 && e.longitude == 0.0) continue;
      final cell = '${(e.latitude * 1000).round()}_${(e.longitude * 1000).round()}';
      if (!seenCells.add(cell)) continue;
      if (LocationTrackingService.getCachedPlace(e.latitude, e.longitude) != null) {
        continue;
      }

      lookups++;
      final place = await LocationTrackingService.reverseGeocodePlace(e.latitude, e.longitude);
      if (place != null) resolvedAny = true;
    }

    if (resolvedAny && mounted) {
      setState(() {});
    }
  }

  bool _matchesStaffFilter(String staffName, String userId, String filter) {
    final f = UserModel.cleanPlainName(filter).toLowerCase();
    final n = UserModel.cleanPlainName(staffName).toLowerCase();
    final u = userId.toLowerCase();
    return n == f ||
        u == f ||
        n.contains(f) ||
        f.contains(n);
  }

  void _stepDate(int deltaDays) {
    final next = _selectedDate.add(Duration(days: deltaDays));
    if (next.isAfter(DateTime.now())) return;
    setState(() => _selectedDate = next);
    _loadTimeline();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadTimeline();
    }
  }

  Future<void> _openExternalGoogleMaps(double lat, double lng) async {
    final uri = Uri.parse(LocationService.buildMapsUrl(lat, lng));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _callPhone(String phone) async {
    if (phone.trim().isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _shareLocationViaWhatsApp(UserModel user) async {
    if (!user.hasLocation) return;
    final addr = cleanLandmark(
      user.locationLandmark ?? '',
      lat: user.latitude,
      lng: user.longitude,
    );
    final text = 'Live Location of ${user.plainName} (${user.roleDisplayName}):\n'
        '• Status: ${user.isOnline ? "Active Online" : "Last seen ${user.locationTimeAgo}"}\n'
        '• Location: $addr\n'
        '• Maps: ${user.mapsUrl}';
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showDriverRouteDialog(UserModel driver) {
    final provider = context.read<CollectionProvider>();
    final auth = context.read<AuthProvider>();
    final allRoutes = provider.allRoutes;
    final selectedRoutes = List<String>.from(driver.assignedRouteIds);

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _tealAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.local_shipping_rounded, color: _tealAccent, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Assign Routes: ${driver.plainName}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const Text(
                      'Staff can access selected route outlets',
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: allRoutes.isEmpty
                ? const Text('No routes available.')
                : ListView(
                    shrinkWrap: true,
                    children: allRoutes.map((route) {
                      final isChecked = selectedRoutes.contains(route.id);
                      return CheckboxListTile(
                        dense: true,
                        value: isChecked,
                        activeColor: _tealAccent,
                        title: Text(route.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                        subtitle: Text('${provider.shops.where((s) => s.routeId == route.id).length} outlets'),
                        onChanged: (val) {
                          setDlgState(() {
                            if (val == true) {
                              selectedRoutes.add(route.id);
                            } else {
                              selectedRoutes.remove(route.id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _tealAccent, foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(dlgCtx);
                final updated = driver.copyWith(assignedRouteIds: selectedRoutes);
                await auth.saveUser(updated);
                provider.setCurrentUser(auth.currentUser);
                if (mounted) {
                  QuickAlert.success(context, 'Assigned routes saved for ${driver.plainName}!');
                }
              },
              child: const Text('Save Routes', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _openSetShopLocationDialog(ShopModel shop) {
    final locCtrl = TextEditingController(
      text: shop.locationUrl ?? (shop.hasLocation ? '${shop.latitude}, ${shop.longitude}' : ''),
    );
    double? tempLat = shop.latitude;
    double? tempLng = shop.longitude;
    bool isDetecting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.pin_drop, color: _tealAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Exact Pin: ${shop.name}',
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Route: ${shop.routeName}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                ),
                if (shop.address.isNotEmpty)
                  Text('Address: ${shop.address}', style: const TextStyle(fontSize: 11.5, color: Colors.blueGrey)),
                const SizedBox(height: 12),
                TextField(
                  controller: locCtrl,
                  decoration: InputDecoration(
                    labelText: 'Google Maps Link or Lat, Lng',
                    hintText: 'https://maps.google.com/?q=... or 18.7565, 73.8550',
                    prefixIcon: const Icon(Icons.link, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                  onChanged: (val) {
                    final match = RegExp(r'(-?\d{1,2}\.\d+)[,\s]+(-?\d{1,3}\.\d+)').firstMatch(val);
                    if (match != null) {
                      tempLat = double.tryParse(match.group(1)!);
                      tempLng = double.tryParse(match.group(2)!);
                    }
                  },
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: isDetecting
                      ? null
                      : () async {
                          setDialogState(() => isDetecting = true);
                          final fix = await LocationService.getCurrentLocationWithStatus();
                          setDialogState(() => isDetecting = false);
                          if (fix.hasLocation) {
                            tempLat = fix.latitude;
                            tempLng = fix.longitude;
                            locCtrl.text = LocationService.buildMapsUrl(fix.latitude!, fix.longitude!);
                          } else if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(fix.errorMessage ?? 'Could not fetch GPS.'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                  icon: isDetecting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location, size: 16),
                  label: Text(isDetecting ? 'Detecting GPS...' : 'Use Current GPS Pin'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _tealAccent, foregroundColor: Colors.white),
              onPressed: () async {
                final text = locCtrl.text.trim();
                if (tempLat == null || tempLng == null) {
                  final match = RegExp(r'(-?\d{1,2}\.\d+)[,\s]+(-?\d{1,3}\.\d+)').firstMatch(text);
                  if (match != null) {
                    tempLat = double.tryParse(match.group(1)!);
                    tempLng = double.tryParse(match.group(2)!);
                  }
                }

                final updated = await context.read<CollectionProvider>().updateShopLocation(
                      shop.id,
                      locationUrl: text.isNotEmpty ? text : null,
                      latitude: tempLat,
                      longitude: tempLng,
                    );

                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  if (updated != null) {
                    setState(() => _selectedShop = updated);
                    _safeMoveMap(_getShopLatLng(updated), 16.0);
                  }
                  QuickAlert.success(context, 'Exact location saved for "${shop.name}"!');
                }
              },
              child: const Text('Save Exact Pin', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  ll.LatLng _getShopLatLng(ShopModel shop) {
    if (shop.latitude != null && shop.longitude != null && shop.latitude != 0.0) {
      return ll.LatLng(shop.latitude!, shop.longitude!);
    }
    if (shop.locationUrl != null && shop.locationUrl!.trim().isNotEmpty) {
      final match = RegExp(r'(-?\d{1,2}\.\d+)[,\s]+(-?\d{1,3}\.\d+)').firstMatch(shop.locationUrl!);
      if (match != null) {
        final lat = double.tryParse(match.group(1)!);
        final lng = double.tryParse(match.group(2)!);
        if (lat != null && lng != null && lat != 0.0) {
          return ll.LatLng(lat, lng);
        }
      }
    }

    final hash = shop.id.hashCode.abs();
    final jitterLat = ((hash % 60) - 30) * 0.00030;
    final jitterLng = (((hash ~/ 60) % 60) - 30) * 0.00030;
    final r = '${shop.routeName} ${shop.address}'.toLowerCase();

    if (r.contains('खराबवाडी') || r.contains('महाळुंगे') || r.contains('महालुंगे') ||
        r.contains('kharabwadi') || r.contains('mahalunge') || r.contains('सारा सिटी') ||
        r.contains('sara city')) {
      return ll.LatLng(18.7380 + jitterLat, 73.8120 + jitterLng);
    }
    if (r.contains('बालाजीनगर') || r.contains('मेदनकरवाडी') || r.contains('balaji') || r.contains('medankarwadi')) {
      return ll.LatLng(18.7460 + jitterLat, 73.8520 + jitterLng);
    }
    if (r.contains('नाणेकरवाडी') || r.contains('कुरुळी') || r.contains('चिंबळी') || r.contains('nanekarwadi') || r.contains('kuruli')) {
      return ll.LatLng(18.7300 + jitterLat, 73.8580 + jitterLng);
    }
    if (r.contains('आंबेठाण') || r.contains('वासुली') || r.contains('ambethan') || r.contains('vasuli')) {
      return ll.LatLng(18.7480 + jitterLat, 73.8050 + jitterLng);
    }
    if (r.contains('चाकण') || r.contains('chakan')) {
      return ll.LatLng(18.7565 + jitterLat, 73.8550 + jitterLng);
    }
    if (r.contains('दावडी') || r.contains('निमगाव') || r.contains('dawadi') || r.contains('nimgaon')) {
      return ll.LatLng(18.9050 + jitterLat, 73.9280 + jitterLng);
    }
    if (r.contains('वाफगाव') || r.contains('वाफगावं') || r.contains('कनेरसर') || r.contains('wafgaon')) {
      return ll.LatLng(18.9280 + jitterLat, 73.9850 + jitterLng);
    }
    if (r.contains('मंचर') || r.contains('manchar')) {
      return ll.LatLng(19.0060 + jitterLat, 73.9450 + jitterLng);
    }
    if (r.contains('भोसरी') || r.contains('मोशी') || r.contains('bhosari') || r.contains('moshi')) {
      return ll.LatLng(18.6490 + jitterLat, 73.8460 + jitterLng);
    }
    if (r.contains('आळंदी') || r.contains('alandi')) {
      return ll.LatLng(18.6750 + jitterLat, 73.8960 + jitterLng);
    }
    if (r.contains('तळेगाव') || r.contains('talegaon')) {
      return ll.LatLng(18.7350 + jitterLat, 73.6760 + jitterLng);
    }
    if (r.contains('शिक्रापूर') || r.contains('shikrapur')) {
      return ll.LatLng(18.7480 + jitterLat, 74.1200 + jitterLng);
    }
    if (r.contains('वाघोली') || r.contains('wagholi')) {
      return ll.LatLng(18.5810 + jitterLat, 73.9800 + jitterLng);
    }
    return ll.LatLng(18.8550 + jitterLat, 73.8880 + jitterLng);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    // Include ALL field roles: Sales & Collection, Order Booking, Collection, and Drivers
    final users = auth.users
        .where((u) =>
            u.id != 'config_gemini_api' &&
            !u.isSuperAdmin &&
            !u.isOffice &&
            (u.isSalesman || u.isDriver || u.isOrder || u.isCollection))
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white, size: 22),
        actionsIconTheme: const IconThemeData(color: Colors.white, size: 22),
        elevation: 0,
        title: const Text(
          'Timeline & Live Map',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh Live GPS & Timeline',
            onPressed: _isRefreshing ? null : _refresh,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              indicatorColor: _primaryBlue,
              indicatorWeight: 2.5,
              labelColor: _primaryBlue,
              unselectedLabelColor: AppTheme.textSecondary,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              tabs: [
                const Tab(text: 'Timeline'),
                const Tab(text: 'Live Map'),
                Tab(text: 'Staff (${users.length})'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildGoogleStyleTimelineTab(users),
          _buildGoogleStyleMapTab(users),
          _buildStaffDirectoryTab(users),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 1: GOOGLE MAPS STYLE TIMELINE (Day | Trips | Places)
  // ===========================================================================
  Widget _buildGoogleStyleTimelineTab(List<UserModel> users) {
    final shops = context.watch<CollectionProvider>().shops;
    final daySummary = TimelineSegmentBuilder.build(_timelineEntries, shops: shops);

    return Column(
      children: [
        // Google Maps style Sub-Tabs: Day | Trips | Places + Staff Selector + < Date >
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            children: [
              // Sub-tabs: Day | Trips | Places
              Row(
                children: [
                  _timelineSubTab(0, 'Day', Icons.calendar_today_outlined),
                  const SizedBox(width: 8),
                  _timelineSubTab(1, 'Trips (${daySummary.trips.length})', Icons.two_wheeler_outlined),
                  const SizedBox(width: 8),
                  _timelineSubTab(2, 'Places (${daySummary.places.length})', Icons.place_outlined),
                ],
              ),
              const SizedBox(height: 10),

              // Date Stepper (< Today v >) + Staff Dropdown Pill
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left_rounded, size: 20),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32),
                            onPressed: () => _stepDate(-1),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: _pickDate,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      _formatDateSelectorLabel(_selectedDate),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ),
                                  const Icon(Icons.arrow_drop_down_rounded, size: 18),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: _isToday(_selectedDate)
                                  ? Colors.grey.shade300
                                  : AppTheme.textPrimary,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32),
                            onPressed: _isToday(_selectedDate) ? null : () => _stepDate(1),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedStaffFilter == 'all' ||
                                  users.any((u) => u.name == _selectedStaffFilter)
                              ? _selectedStaffFilter
                              : 'all',
                          isExpanded: true,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                          items: [
                            const DropdownMenuItem(value: 'all', child: Text('All Staff')),
                            ...users.map((u) => DropdownMenuItem(
                                  value: u.name,
                                  child: Text(u.plainName, overflow: TextOverflow.ellipsis),
                                )),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedStaffFilter = val);
                              _loadTimeline();
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Compact Metric Pills Row
              Row(
                children: [
                  _metricChip(
                    Icons.route_outlined,
                    '${daySummary.totalDistanceKm.toStringAsFixed(1)} km',
                    const Color(0xFF0369A1),
                  ),
                  const SizedBox(width: 6),
                  _metricChip(
                    Icons.place_outlined,
                    '${daySummary.stops.length} stops',
                    _primaryBlue,
                  ),
                  const SizedBox(width: 6),
                  _metricChip(
                    Icons.payments_outlined,
                    CurrencyFormatter.format(daySummary.totalCollected),
                    const Color(0xFF15803D),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Sub-Tab Body
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: _isLoadingTimeline
                ? const Center(child: CircularProgressIndicator())
                : _timelineEntries.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(32),
                        children: [
                          Icon(Icons.timeline_rounded, size: 52, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          const Text(
                            'No Timeline Activity Recorded',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Pull down to refresh live GPS or choose another date above.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
                          ),
                        ],
                      )
                    : _buildTimelineSubTabContent(daySummary),
          ),
        ),
      ],
    );
  }

  Widget _timelineSubTab(int idx, String label, IconData icon) {
    final active = _timelineSubTabIndex == idx;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _timelineSubTabIndex = idx),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
          decoration: BoxDecoration(
            color: active ? _tealAccent.withValues(alpha: 0.12) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active ? _tealAccent : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: active ? _tealAccent : AppTheme.textSecondary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: active ? _tealAccent : AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricChip(IconData icon, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13.5, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineSubTabContent(TimelineDaySummary summary) {
    if (_timelineSubTabIndex == 1) {
      // TRIPS SUB-TAB
      if (summary.trips.isEmpty) {
        return ListView(
          padding: const EdgeInsets.all(32),
          children: const [
            Center(child: Text('No travel trips recorded between stops on this date.')),
          ],
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: summary.trips.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _buildTripListCard(summary.trips[i]),
      );
    }

    if (_timelineSubTabIndex == 2) {
      // PLACES SUB-TAB
      if (summary.places.isEmpty) {
        return ListView(
          padding: const EdgeInsets.all(32),
          children: const [
            Center(child: Text('No places recorded on this date.')),
          ],
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: summary.places.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _buildPlaceListCard(summary.places[i]),
      );
    }

    // DAY SUB-TAB (Google Maps Vertical Timeline Rail)
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: summary.dayNodes.length,
      itemBuilder: (_, idx) {
        final node = summary.dayNodes[idx];
        final isFirst = idx == 0;
        final isLast = idx == summary.dayNodes.length - 1;
        if (node is TimelineStopItem) {
          return _buildGoogleDayStopRow(node, isFirst: isFirst, isLast: isLast);
        } else if (node is TimelineTripItem) {
          return _buildGoogleDayTripRow(node);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildGoogleDayStopRow(
    TimelineStopItem stop, {
    required bool isFirst,
    required bool isLast,
  }) {
    final Color circleColor;
    final IconData iconData;
    if (stop.hasCollection) {
      circleColor = const Color(0xFF16A34A);
      iconData = Icons.payments_rounded;
    } else if (stop.hasOrder) {
      circleColor = const Color(0xFFD97706);
      iconData = Icons.shopping_bag_rounded;
    } else if (stop.hasDelivery) {
      circleColor = _tealAccent;
      iconData = Icons.local_shipping_rounded;
    } else if (stop.shopName != null && stop.shopName!.isNotEmpty) {
      circleColor = const Color(0xFF2563EB);
      iconData = Icons.storefront_rounded;
    } else {
      circleColor = _primaryBlue;
      iconData = Icons.place_rounded;
    }

    final startStr = DateFormat('HH:mm').format(stop.startTime);
    final endStr = DateFormat('HH:mm').format(stop.endTime);
    final durStr = stop.durationMinutes >= 2
        ? ' • ${TimelineSegmentBuilder.formatDuration(stop.durationMinutes)}'
        : '';
    final timeRange = startStr == endStr ? startStr : '$startStr - $endStr$durStr';

    return IntrinsicHeight(
      child: InkWell(
        onTap: () {
          if (stop.latitude != 0.0 && stop.longitude != 0.0) {
            _focusMapOn(ll.LatLng(stop.latitude, stop.longitude), zoom: 16.0);
          }
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Google Timeline vertical rail
            SizedBox(
              width: 44,
              child: Column(
                children: [
                  Expanded(
                    flex: 1,
                    child: Container(
                      width: 2,
                      color: isFirst ? Colors.transparent : const Color(0xFFCBD5E1),
                    ),
                  ),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: circleColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: circleColor.withValues(alpha: 0.25),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Icon(iconData, color: Colors.white, size: 17),
                  ),
                  Expanded(
                    flex: 3,
                    child: Container(
                      width: 2,
                      color: isLast ? Colors.transparent : const Color(0xFFCBD5E1),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Right Stop Card
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: stop.hasCollection
                        ? const Color(0xFF86EFAC)
                        : AppTheme.border,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                stop.placeTitle,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              if (stop.placeAddress.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  stop.placeAddress,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, size: 18, color: AppTheme.textSecondary),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onSelected: (choice) {
                            if (choice == 'map' && stop.latitude != 0.0) {
                              _focusMapOn(ll.LatLng(stop.latitude, stop.longitude), zoom: 16.0);
                            } else if (choice == 'gmaps' && stop.latitude != 0.0) {
                              _openExternalGoogleMaps(stop.latitude, stop.longitude);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'map', child: Text('View on App Map')),
                            PopupMenuItem(value: 'gmaps', child: Text('Open in Google Maps')),
                          ],
                        ),
                      ],
                    ),
                    // Meaningful events at this stop (Collections / Orders / Deliveries)
                    for (final ev in stop.events.where((e) => !e.isGpsPing)) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: ev.isCollection
                              ? const Color(0xFFDCFCE7)
                              : (ev.isOrderBooked
                                  ? const Color(0xFFFEF3C7)
                                  : const Color(0xFFE0F2FE)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          ev.details,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: ev.isCollection
                                ? const Color(0xFF15803D)
                                : (ev.isOrderBooked
                                    ? const Color(0xFFB45309)
                                    : const Color(0xFF0369A1)),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          timeRange,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        if (_selectedStaffFilter == 'all') ...[
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              stop.staffName,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleDayTripRow(TimelineTripItem trip) {
    final IconData modeIcon = trip.travelMode == 'Walking'
        ? Icons.directions_walk_rounded
        : (trip.travelMode == 'Driving'
            ? Icons.local_shipping_outlined
            : Icons.two_wheeler_rounded);
    final startStr = DateFormat('HH:mm').format(trip.startTime);
    final endStr = DateFormat('HH:mm').format(trip.endTime);

    return IntrinsicHeight(
      child: InkWell(
        onTap: () {
          if (trip.pathPoints.isNotEmpty) {
            _focusMapOn(
              ll.LatLng(trip.pathPoints.last.lat, trip.pathPoints.last.lng),
              zoom: 14.0,
            );
          }
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left connector rail with outlined transit icon matching Google Maps
            SizedBox(
              width: 44,
              child: Column(
                children: [
                  Expanded(
                    child: Container(width: 2, color: const Color(0xFFCBD5E1)),
                  ),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF64748B), width: 1.5),
                    ),
                    child: Icon(modeIcon, size: 15, color: const Color(0xFF334155)),
                  ),
                  Expanded(
                    child: Container(width: 2, color: const Color(0xFFCBD5E1)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Right Trip Info Row
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.travelMode,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${trip.distanceKm.toStringAsFixed(1)} km • ${TimelineSegmentBuilder.formatDuration(trip.durationMinutes)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    Text(
                      '$startStr - $endStr',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripListCard(TimelineTripItem trip) {
    final IconData modeIcon = trip.travelMode == 'Walking'
        ? Icons.directions_walk_rounded
        : (trip.travelMode == 'Driving'
            ? Icons.local_shipping_outlined
            : Icons.two_wheeler_rounded);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFE0F2FE),
            foregroundColor: _tealAccent,
            child: Icon(modeIcon, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${trip.fromTitle} → ${trip.toTitle}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 3),
                Text(
                  '${trip.travelMode} • ${trip.distanceKm.toStringAsFixed(1)} km • ${TimelineSegmentBuilder.formatDuration(trip.durationMinutes)}',
                  style: const TextStyle(fontSize: 11.5, color: _tealAccent, fontWeight: FontWeight.w700),
                ),
                Text(
                  '${DateFormat('HH:mm').format(trip.startTime)} - ${DateFormat('HH:mm').format(trip.endTime)} • ${trip.staffName}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.map_outlined, color: _primaryBlue),
            onPressed: () {
              if (trip.pathPoints.isNotEmpty) {
                _focusMapOn(
                  ll.LatLng(trip.pathPoints.last.lat, trip.pathPoints.last.lng),
                  zoom: 14.0,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceListCard(TimelinePlaceSummary place) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFEFF6FF),
            foregroundColor: _primaryBlue,
            child: Icon(Icons.place_rounded, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.placeTitle,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
                if (place.placeAddress.isNotEmpty)
                  Text(
                    place.placeAddress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                  ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  children: [
                    Text(
                      '${place.visitCount} visit${place.visitCount > 1 ? "s" : ""}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _primaryBlue),
                    ),
                    if (place.totalMinutes > 0)
                      Text(
                        '• ${TimelineSegmentBuilder.formatDuration(place.totalMinutes)}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    if (place.totalAmount > 0)
                      Text(
                        '• ${CurrencyFormatter.format(place.totalAmount)}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF15803D)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.my_location_rounded, color: _primaryBlue),
            onPressed: () {
              if (place.latitude != 0.0 && place.longitude != 0.0) {
                _focusMapOn(ll.LatLng(place.latitude, place.longitude), zoom: 16.0);
              }
            },
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 2: CLEAN GOOGLE-MAPS-STYLE INTERACTIVE LIVE MAP (Mobile-First)
  // ===========================================================================
  Widget _buildGoogleStyleMapTab(List<UserModel> users) {
    final provider = context.watch<CollectionProvider>();
    final allShops = provider.allShops;
    final allRoutes = provider.allRoutes;

    List<ShopModel> displayShops;
    if (_shopSearchQuery.trim().isNotEmpty) {
      final q = _shopSearchQuery.toLowerCase().trim();
      displayShops = allShops.where((s) {
        return s.name.toLowerCase().contains(q) ||
            s.routeName.toLowerCase().contains(q) ||
            s.address.toLowerCase().contains(q);
      }).toList();
    } else if (_selectedMapRouteId != null && _selectedMapRouteId!.isNotEmpty) {
      displayShops = allShops.where((s) => s.routeId == _selectedMapRouteId).toList();
    } else {
      displayShops = const [];
    }

    final liveStaffUsers = users.where((u) => u.hasLocation).toList();

    // Route trail polyline points for currently selected staff member (if any)
    final trailPoints = <ll.LatLng>[];
    if (_showTrailOnMap && _selectedStaffUser != null) {
      final matchingEntries = _timelineEntries
          .where((e) =>
              e.latitude != 0.0 &&
              e.longitude != 0.0 &&
              _matchesStaffFilter(e.staffName, e.userId, _selectedStaffUser!.name))
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      for (final e in matchingEntries) {
        trailPoints.add(ll.LatLng(e.latitude, e.longitude));
      }
      if (_selectedStaffUser!.hasLocation) {
        trailPoints.add(ll.LatLng(_selectedStaffUser!.latitude!, _selectedStaffUser!.longitude!));
      }
    }

    final initialCenter = liveStaffUsers.isNotEmpty
        ? ll.LatLng(liveStaffUsers.first.latitude!, liveStaffUsers.first.longitude!)
        : const ll.LatLng(18.8550, 73.8880);

    return Stack(
      children: [
        FlutterMap(
          key: ValueKey('map_$_mapLayer'),
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: 12.5,
            minZoom: 5.0,
            maxZoom: 20.0,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
            onMapReady: () {
              _mapReady = true;
              if (_pendingMapMove != null) {
                final pending = _pendingMapMove!;
                _pendingMapMove = null;
                _mapController.move(pending.center, pending.zoom);
              }
            },
            onTap: (_, _) {
              if (_selectedShop != null || _selectedStaffUser != null) {
                setState(() {
                  _selectedShop = null;
                  _selectedStaffUser = null;
                });
              }
            },
          ),
          children: [
            TileLayer(
              key: ValueKey(_mapLayer),
              urlTemplate: _getMapUrlTemplate(),
              userAgentPackageName: 'com.purva.dailycollection',
              maxZoom: 20,
            ),

            // Selected Staff Day Trail Polyline
            if (trailPoints.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: trailPoints,
                    strokeWidth: 4.0,
                    color: _primaryBlue.withValues(alpha: 0.85),
                  ),
                ],
              ),

            // Shop / Outlet Markers (only when searching or route selected)
            if (_showOutletsOnMap && displayShops.isNotEmpty)
              MarkerLayer(
                markers: displayShops.map((shop) {
                  final pos = _getShopLatLng(shop);
                  final isSelected = _selectedShop?.id == shop.id;
                  return Marker(
                    point: pos,
                    width: 110,
                    height: 44,
                    alignment: Alignment.bottomCenter,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedShop = shop;
                          _selectedStaffUser = null;
                        });
                        _safeMoveMap(pos, 15.5);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFDC2626) : Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSelected ? Colors.red.shade900 : _tealAccent,
                              ),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
                            ),
                            child: Text(
                              shop.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? Colors.white : AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.location_on_rounded,
                            size: isSelected ? 22 : 16,
                            color: isSelected ? const Color(0xFFDC2626) : _tealAccent,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

            // Live Staff Beacons
            MarkerLayer(
              markers: liveStaffUsers.map((user) {
                final pos = ll.LatLng(user.latitude!, user.longitude!);
                final isOnline = user.isOnline;
                final isSelected = _selectedStaffUser?.id == user.id;
                final color = user.isDriver
                    ? _tealAccent
                    : (user.isOrder ? const Color(0xFFD97706) : const Color(0xFF16A34A));

                return Marker(
                  point: pos,
                  width: 116,
                  height: 70,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedStaffUser = user;
                        _selectedShop = null;
                      });
                      _safeMoveMap(pos, 15.5);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: isSelected ? _primaryBlue : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected ? _primaryBlue : (isOnline ? color : Colors.grey.shade400),
                              width: 1.4,
                            ),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isOnline ? const Color(0xFF22C55E) : Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  user.plainName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 3),
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (isOnline || isSelected)
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: color.withValues(alpha: 0.22),
                                  ),
                                ),
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                                ),
                                child: Icon(
                                  user.isDriver
                                      ? Icons.local_shipping_rounded
                                      : Icons.two_wheeler_rounded,
                                  color: Colors.white,
                                  size: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),

        // Top Google-Maps Search Pill + Sleek Horizontal Quick Chips
        Positioned(
          top: 10,
          left: 12,
          right: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Floating Rounded Search Pill
              Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(28),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, size: 20, color: AppTheme.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _mapSearchCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Search staff, outlet, or beat...',
                            hintStyle: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                          onChanged: (val) => setState(() => _shopSearchQuery = val),
                        ),
                      ),
                      if (_shopSearchQuery.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            _mapSearchCtrl.clear();
                            setState(() => _shopSearchQuery = '');
                          },
                        ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: Icon(
                          Icons.tune_rounded,
                          size: 20,
                          color: _selectedMapRouteId != null ? _primaryBlue : AppTheme.textPrimary,
                        ),
                        tooltip: 'Filter Routes & Map Options',
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(),
                        onPressed: () => _openMapFilterSheet(allRoutes, allShops),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Compact Scrollable Quick Staff & Route Chips
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _mapQuickChip(
                      label: 'All Live (${liveStaffUsers.length})',
                      icon: Icons.groups_rounded,
                      selected: _selectedStaffUser == null && _selectedMapRouteId == null,
                      onTap: () {
                        setState(() {
                          _selectedStaffUser = null;
                          _selectedShop = null;
                        });
                        _fitAllStaffOnMap(liveStaffUsers);
                      },
                    ),
                    ...liveStaffUsers.map((u) {
                      final active = _selectedStaffUser?.id == u.id;
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _mapQuickChip(
                          label: '${u.plainName} • ${u.isOnline ? "LIVE" : u.locationTimeAgo}',
                          dotColor: u.isOnline ? const Color(0xFF22C55E) : Colors.grey,
                          selected: active,
                          onTap: () {
                            setState(() {
                              _selectedStaffUser = u;
                              _selectedShop = null;
                            });
                            _safeMoveMap(ll.LatLng(u.latitude!, u.longitude!), 15.5);
                          },
                        ),
                      );
                    }),
                    if (_selectedMapRouteId != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _mapQuickChip(
                          label: 'Clear Route',
                          icon: Icons.close_rounded,
                          selected: true,
                          onTap: () => setState(() {
                            _selectedMapRouteId = null;
                            _selectedShop = null;
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Right-Side Google Maps Circular Control Buttons
        Positioned(
          right: 12,
          bottom: (_selectedShop != null || _selectedStaffUser != null)
              ? 185
              : (liveStaffUsers.isNotEmpty ? 96 : 20),
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'map_layer_switch',
                backgroundColor: Colors.white,
                foregroundColor: _mapLayer == 'satellite' ? _primaryBlue : AppTheme.textPrimary,
                tooltip: _mapLayer == 'satellite' ? 'Switch to Road Map' : 'Switch to Satellite',
                onPressed: () {
                  setState(() {
                    _mapLayer = _mapLayer == 'satellite' ? 'streets' : 'satellite';
                  });
                },
                child: Icon(_mapLayer == 'satellite' ? Icons.map_rounded : Icons.layers_rounded, size: 20),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'map_my_gps',
                backgroundColor: Colors.white,
                foregroundColor: _tealAccent,
                tooltip: 'My GPS Location',
                onPressed: () async {
                  final fix = await LocationService.getCurrentLocationWithStatus();
                  if (!mounted) return;
                  if (fix.hasLocation) {
                    _safeMoveMap(ll.LatLng(fix.latitude!, fix.longitude!), 15.5);
                  } else {
                    QuickAlert.error(context, fix.errorMessage ?? 'Could not fetch GPS.');
                  }
                },
                child: const Icon(Icons.my_location_rounded, size: 20),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'map_fit_staff',
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.textPrimary,
                tooltip: 'Fit All Live Staff',
                onPressed: () => _fitAllStaffOnMap(liveStaffUsers),
                child: const Icon(Icons.center_focus_strong_rounded, size: 20),
              ),
            ],
          ),
        ),

        // Bottom Selected Outlet Detail Card OR Staff Detail Card OR Quick Staff Strip
        if (_selectedShop != null)
          _buildSelectedShopMapSheet(_selectedShop!)
        else if (_selectedStaffUser != null)
          _buildSelectedStaffMapSheet(_selectedStaffUser!)
        else if (liveStaffUsers.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            height: 72,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: liveStaffUsers.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, idx) {
                final u = liveStaffUsers[idx];
                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedStaffUser = u;
                      _selectedShop = null;
                    });
                    _safeMoveMap(ll.LatLng(u.latitude!, u.longitude!), 15.5);
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 215,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: u.isOnline
                              ? const Color(0xFFDCFCE7)
                              : const Color(0xFFF1F5F9),
                          foregroundColor: u.isOnline
                              ? const Color(0xFF15803D)
                              : AppTheme.textSecondary,
                          child: Icon(
                            u.isDriver ? Icons.local_shipping_rounded : Icons.two_wheeler_rounded,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${u.plainName} • ${u.isOnline ? "LIVE" : u.locationTimeAgo}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                              ),
                              Text(
                                cleanLandmark(
                                  u.locationLandmark ?? '',
                                  lat: u.latitude,
                                  lng: u.longitude,
                                  allShops: allShops,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10.5, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
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

  void _fitAllStaffOnMap(List<UserModel> liveStaffUsers) {
    if (liveStaffUsers.isEmpty) {
      _safeMoveMap(const ll.LatLng(18.8550, 73.8880), 11.5);
      return;
    }
    if (liveStaffUsers.length == 1) {
      final u = liveStaffUsers.first;
      _safeMoveMap(ll.LatLng(u.latitude!, u.longitude!), 14.5);
      return;
    }
    double avgLat = 0;
    double avgLng = 0;
    for (final u in liveStaffUsers) {
      avgLat += u.latitude!;
      avgLng += u.longitude!;
    }
    _safeMoveMap(
      ll.LatLng(avgLat / liveStaffUsers.length, avgLng / liveStaffUsers.length),
      11.5,
    );
  }

  Widget _mapQuickChip({
    required String label,
    IconData? icon,
    Color? dotColor,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(18),
      color: selected ? _primaryBlue : Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dotColor != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
                ),
                const SizedBox(width: 5),
              ] else if (icon != null) ...[
                Icon(icon, size: 14, color: selected ? Colors.white : AppTheme.textPrimary),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMapFilterSheet(List<dynamic> allRoutes, List<ShopModel> allShops) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Map Options & Beat Outlets',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show Route Outlets on Map', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  value: _showOutletsOnMap,
                  onChanged: (v) {
                    setModalState(() {});
                    setState(() => _showOutletsOnMap = v);
                  },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show Selected Staff Trail Path', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  value: _showTrailOnMap,
                  onChanged: (v) {
                    setModalState(() {});
                    setState(() => _showTrailOnMap = v);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: allRoutes.any((r) => r.id == _selectedMapRouteId)
                      ? _selectedMapRouteId
                      : null,
                  decoration: InputDecoration(
                    labelText: 'Overlay Beat Route Outlets',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('None (Clean Map)')),
                    ...allRoutes.map((r) => DropdownMenuItem<String?>(
                          value: r.id as String,
                          child: Text(r.name as String),
                        )),
                  ],
                  onChanged: (val) {
                    Navigator.pop(ctx);
                    setState(() {
                      _selectedMapRouteId = val;
                      _selectedShop = null;
                      _showOutletsOnMap = true;
                    });
                    if (val != null) {
                      final routeShops = allShops.where((s) => s.routeId == val).toList();
                      if (routeShops.isNotEmpty) {
                        final target = routeShops.firstWhere(
                          (s) => s.latitude != null && s.longitude != null,
                          orElse: () => routeShops.first,
                        );
                        _safeMoveMap(_getShopLatLng(target), 13.5);
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedShopMapSheet(ShopModel shop) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    shop.name,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _selectedShop = null),
                ),
              ],
            ),
            Text(
              '${shop.routeName} • ${shop.address.isNotEmpty ? shop.address : "Beat Outlet"}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (shop.mobileNumber.isNotEmpty)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.phone, size: 14),
                    label: const Text('Call', style: TextStyle(fontSize: 11.5)),
                    onPressed: () => _callPhone(shop.mobileNumber),
                  ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryBlue,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.edit_location_alt, size: 14),
                  label: Text(shop.hasLocation ? 'Update Pin' : 'Set GPS Pin', style: const TextStyle(fontSize: 11.5)),
                  onPressed: () => _openSetShopLocationDialog(shop),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.directions, size: 14),
                  label: const Text('Google Maps', style: TextStyle(fontSize: 11.5)),
                  onPressed: () {
                    final pos = _getShopLatLng(shop);
                    _openExternalGoogleMaps(pos.latitude, pos.longitude);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedStaffMapSheet(UserModel user) {
    final allShops = context.read<CollectionProvider>().shops;
    final addr = cleanLandmark(
      user.locationLandmark ?? '',
      lat: user.latitude,
      lng: user.longitude,
      allShops: allShops,
    );

    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: user.isDriver ? _tealAccent : const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  child: Icon(user.isDriver ? Icons.local_shipping_rounded : Icons.two_wheeler_rounded, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            user.plainName,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: user.isOnline ? const Color(0xFFDCFCE7) : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              user.isOnline ? 'LIVE' : user.locationTimeAgo,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: user.isOnline ? const Color(0xFF15803D) : AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${user.roleDisplayName} • $addr',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _selectedStaffUser = null),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryBlue,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.timeline_rounded, size: 14),
                    label: const Text('Timeline', style: TextStyle(fontSize: 11.5)),
                    onPressed: () {
                      setState(() => _selectedStaffFilter = user.name);
                      _tabController.animateTo(0);
                      _loadTimeline();
                    },
                  ),
                  const SizedBox(width: 6),
                  if (user.phone.isNotEmpty) ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _tealAccent,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.phone, size: 14),
                      label: const Text('Call', style: TextStyle(fontSize: 11.5)),
                      onPressed: () => _callPhone(user.phone),
                    ),
                    const SizedBox(width: 6),
                  ],
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.share, size: 14),
                    label: const Text('WhatsApp', style: TextStyle(fontSize: 11.5)),
                    onPressed: () => _shareLocationViaWhatsApp(user),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.alt_route, size: 14),
                    label: const Text('Routes', style: TextStyle(fontSize: 11.5)),
                    onPressed: () => _showDriverRouteDialog(user),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 3: CLEAN STAFF DIRECTORY
  // ===========================================================================
  Widget _buildStaffDirectoryTab(List<UserModel> users) {
    final provider = context.watch<CollectionProvider>();
    final filtered = users.where((u) {
      if (_liveRoleFilter == 'online') return u.isOnline;
      if (_liveRoleFilter == 'sales') return u.isSalesman || u.isCollection || u.isOrder;
      if (_liveRoleFilter == 'driver') return u.isDriver;
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _roleChip('all', 'All (${users.length})'),
                const SizedBox(width: 6),
                _roleChip('online', 'Online (${users.where((u) => u.isOnline).length})'),
                const SizedBox(width: 6),
                _roleChip('sales', 'Sales / Order (${users.where((u) => u.isSalesman || u.isCollection || u.isOrder).length})'),
                const SizedBox(width: 6),
                _roleChip('driver', 'Drivers (${users.where((u) => u.isDriver).length})'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No staff members match this filter.')),
            ),

          ...filtered.map((u) {
            final summary = provider.getStaffSummary(u.name);
            final addr = u.hasLocation
                ? cleanLandmark(
                    u.locationLandmark ?? '',
                    lat: u.latitude,
                    lng: u.longitude,
                    allShops: provider.shops,
                  )
                : 'GPS not shared yet';

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: u.isOnline ? const Color(0xFF86EFAC) : AppTheme.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: u.isDriver
                              ? _tealAccent.withValues(alpha: 0.14)
                              : const Color(0xFF16A34A).withValues(alpha: 0.14),
                          foregroundColor: u.isDriver ? _tealAccent : const Color(0xFF15803D),
                          child: Icon(u.isDriver ? Icons.local_shipping_rounded : Icons.two_wheeler_rounded, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(u.plainName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                              Text('${u.roleDisplayName} • ${u.phone}',
                                  style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: u.isOnline ? const Color(0xFFDCFCE7) : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            u.isOnline ? 'LIVE' : (u.hasLocation ? u.locationTimeAgo : 'OFFLINE'),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: u.isOnline ? const Color(0xFF15803D) : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.place_outlined, size: 14, color: _primaryBlue),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            addr,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Today: ${CurrencyFormatter.format(summary.totalAmount)}',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF15803D)),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                          icon: const Icon(Icons.timeline_rounded, size: 14),
                          label: const Text('Timeline', style: TextStyle(fontSize: 11.5)),
                          onPressed: () {
                            setState(() => _selectedStaffFilter = u.name);
                            _tabController.animateTo(0);
                            _loadTimeline();
                          },
                        ),
                        if (u.hasLocation)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryBlue,
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.map_rounded, size: 14),
                            label: const Text('Locate', style: TextStyle(fontSize: 11.5)),
                            onPressed: () {
                              setState(() {
                                _selectedStaffUser = u;
                                _selectedShop = null;
                              });
                              _focusMapOn(ll.LatLng(u.latitude!, u.longitude!), zoom: 15.5);
                            },
                          ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                          icon: const Icon(Icons.alt_route_rounded, size: 14),
                          label: Text(
                            u.assignedRouteIds.isEmpty ? 'Routes' : 'Routes (${u.assignedRouteIds.length})',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          onPressed: () => _showDriverRouteDialog(u),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _roleChip(String value, String label) {
    final active = _liveRoleFilter == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
      selected: active,
      selectedColor: _primaryBlue.withValues(alpha: 0.14),
      labelStyle: TextStyle(color: active ? _primaryBlue : AppTheme.textSecondary),
      onSelected: (_) => setState(() => _liveRoleFilter = value),
    );
  }
}
