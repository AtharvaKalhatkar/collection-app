import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user_model.dart';
import '../models/shop_model.dart';
import '../models/location_timeline_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/collection_provider.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';
import '../utils/quick_alert.dart';
import '../services/location_tracking_service.dart';
import '../services/location_service.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';

class LiveStaffLocationsScreen extends StatefulWidget {
  final String? initialStaffName;
  final int initialTabIndex; // 0: Timeline, 1: Live Status & Map

  const LiveStaffLocationsScreen({
    super.key,
    this.initialStaffName,
    this.initialTabIndex = 0,
  });

  @override
  State<LiveStaffLocationsScreen> createState() => _LiveStaffLocationsScreenState();
}

class _LiveStaffLocationsScreenState extends State<LiveStaffLocationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final MapController _mapController;

  DateTime _selectedDate = DateTime.now();
  String _selectedStaffFilter = 'all';
  String _liveRoleFilter = 'all';
  bool _isRefreshing = false;
  bool _isLoadingTimeline = false;
  final bool _earliestFirst = true;

  // Tab 2 view mode: 'map' (interactive in-app map) or 'list' (fleet cards)
  String _fleetViewMode = 'map';

  // Map state
  String _mapLayer = 'satellite'; // 'satellite' (Google Hybrid Satellite) or 'streets' (Google Streets)
  bool _showOutletsOnMap = true;
  ShopModel? _selectedShop;
  UserModel? _selectedStaffUser;
  String? _selectedMapRouteId;
  String _shopSearchQuery = '';

  static String cleanLandmark(String raw) {
    var s = raw.trim();
    if (s.startsWith(RegExp(r'^(At|Near)\s+', caseSensitive: false))) {
      s = s.replaceFirst(RegExp(r'^(At|Near)\s+', caseSensitive: false), '');
    }
    s = s.replaceAll(RegExp(r'\s*\(\s*~?\s*\d+\s*m\s*\)', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s*\([^)]*\)'), '');
    return s.trim();
  }

  String _getMapUrlTemplate() {
    if (_mapLayer == 'satellite') {
      // Google Hybrid Satellite (photographic imagery + roads + town labels)
      return 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
    }
    // Google Standard Roadmap
    return 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}';
  }

  List<LocationTimelineEntry> _timelineEntries = [];

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    if (widget.initialStaffName != null && widget.initialStaffName!.isNotEmpty) {
      _selectedStaffFilter = widget.initialStaffName!;
    }
    _loadTimeline();
  }

  @override
  void dispose() {
    _mapController.dispose();
    _tabController.dispose();
    super.dispose();
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
      await _loadTimeline();
    } catch (_) {}

    if (mounted) {
      setState(() => _isRefreshing = false);
      QuickAlert.success(context, 'Locations & timeline refreshed');
    }
  }

  Future<void> _loadTimeline() async {
    setState(() => _isLoadingTimeline = true);

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
          final s = _selectedStaffFilter.toLowerCase();
          final matches = e.staffName.toLowerCase() == s ||
              e.userId.toLowerCase() == s ||
              e.staffName.toLowerCase().contains(s);
          if (!matches) return false;
        }
        return true;
      }).toList();

      if (!mounted) return;

      // 3. Synthesize collection checkpoints from CollectionProvider
      final collectionProvider = context.read<CollectionProvider>();
      final dayCollections = collectionProvider
          .getFilteredCollections(forDate: _selectedDate)
          .where((c) {
        if (_selectedStaffFilter != 'all') {
          return c.salesmanName.toLowerCase() == _selectedStaffFilter.toLowerCase() ||
              c.salesmanName.toLowerCase().contains(_selectedStaffFilter.toLowerCase());
        }
        return true;
      }).toList();

      final synthesizedCollectionEntries = dayCollections.map((c) {
        final shop = collectionProvider.getShopById(c.shopId);
        final lat = shop?.latitude ?? 18.5204;
        final lng = shop?.longitude ?? 73.8567;
        final landmark = shop != null
            ? shop.name
            : c.shopName;

        return LocationTimelineEntry(
          id: 'coll_${c.id}',
          userId: c.salesmanName,
          staffName: c.salesmanName,
          staffRole: 'salesman',
          timestamp: c.collectedAt,
          latitude: lat,
          longitude: lng,
          landmark: landmark,
          eventType: 'collection',
          details:
              'Collected ${CurrencyFormatter.format(c.collectedAmount)} (${c.paymentMode.displayName}) for Bill #${c.billNumber}',
          amount: c.collectedAmount,
          shopName: c.shopName,
          routeName: c.routeName,
          billNumber: c.billNumber,
        );
      }).toList();

      // Combine and deduplicate
      final Map<String, LocationTimelineEntry> mergedMap = {};

      for (final e in filteredLocal) {
        mergedMap[e.id] = e;
      }
      for (final e in cloudEntries) {
        mergedMap[e.id] = e;
      }
      for (final e in synthesizedCollectionEntries) {
        final exists = mergedMap.values.any((m) =>
            m.isCollection &&
            m.billNumber == e.billNumber &&
            m.staffName.toLowerCase() == e.staffName.toLowerCase());
        if (!exists) {
          mergedMap[e.id] = e;
        }
      }

      var list = mergedMap.values.toList();

      if (_selectedStaffFilter != 'all') {
        final s = _selectedStaffFilter.toLowerCase();
        list = list.where((e) {
          return e.staffName.toLowerCase() == s ||
              e.userId.toLowerCase() == s ||
              e.staffName.toLowerCase().contains(s) ||
              s.contains(e.staffName.toLowerCase());
        }).toList();
      }

      list.sort((a, b) => _earliestFirst
          ? a.timestamp.compareTo(b.timestamp)
          : b.timestamp.compareTo(a.timestamp));

      if (mounted) {
        setState(() {
          _timelineEntries = list;
          _isLoadingTimeline = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingTimeline = false);
      }
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
    final text = 'Live Location of ${user.name} (${user.roleDisplayName}):\n'
        '• Status: ${user.isOnline ? "Active Online" : "Last seen ${user.locationTimeAgo}"}\n'
        '• Landmark: ${user.locationLandmark ?? "Field"}\n'
        '• Coordinates: ${user.latitude}, ${user.longitude}';
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showDriverRouteDialog(UserModel driver) {
    final provider = context.read<CollectionProvider>();
    final auth = context.read<AuthProvider>();
    final allRoutes = provider.allRoutes;
    List<String> selectedRoutes = List<String>.from(driver.assignedRouteIds);

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
                  color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.local_shipping_rounded, color: Color(0xFF0284C7), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Assign Routes: ${driver.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const Text('Driver only delivers to selected routes', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
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
                        activeColor: const Color(0xFF0284C7),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(dlgCtx);
                final updated = driver.copyWith(assignedRouteIds: selectedRoutes);
                await auth.saveUser(updated);
                provider.setCurrentUser(auth.currentUser);
                if (mounted) {
                  QuickAlert.success(context, 'Assigned routes saved for ${driver.name}!');
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
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.pin_drop, color: Color(0xFF0284C7)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Exact Location: ${shop.name}',
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
                    Text(
                      'Address: ${shop.address}',
                      style: const TextStyle(fontSize: 11.5, color: Colors.blueGrey),
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Set exact GPS pin so this store appears on its exact real-world spot on the map.',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                  ),
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
                                    content: Text('Could not fetch GPS. Please enter coordinates manually.'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            }
                          },
                    icon: isDetecting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location, size: 16),
                    label: Text(isDetecting ? 'Detecting Device GPS...' : 'Use Current Device GPS Pin'),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                ),
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
                      setState(() {
                        _selectedShop = updated;
                      });
                      final newPos = _getShopLatLng(updated);
                      _mapController.move(newPos, 16.0);
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Exact location saved for "${shop.name}"!'),
                        backgroundColor: const Color(0xFF10B981),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                child: const Text('Save Exact Pin', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  // Deterministically derive coordinate for shop if not yet set
  ll.LatLng _getShopLatLng(ShopModel shop) {
    if (shop.latitude != null && shop.longitude != null && shop.latitude != 0.0) {
      return ll.LatLng(shop.latitude!, shop.longitude!);
    }

    // Check if locationUrl contains coordinates: e.g. "18.7565,73.8550" or "q=18.7565,73.8550" or "@18.7565,73.8550"
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

    // 1. खराबवाडी महाळुंगे (Kharabwadi / Mahalunge / Sara City / Kelkar Nagar)
    if (r.contains('खराबवाडी') ||
        r.contains('महाळुंगे') ||
        r.contains('महालुंगे') ||
        r.contains('kharabwadi') ||
        r.contains('mahalunge') ||
        r.contains('सारा सिटी') ||
        r.contains('केळकर नगर') ||
        r.contains('द्वारका सिटी') ||
        r.contains('sara city')) {
      return ll.LatLng(18.7380 + jitterLat, 73.8120 + jitterLng);
    }

    // 2. बालाजीनगर / मेदनकरवाडी (Balajinagar / Medankarwadi)
    if (r.contains('बालाजीनगर') ||
        r.contains('मेदनकरवाडी') ||
        r.contains('balaji') ||
        r.contains('medankarwadi')) {
      return ll.LatLng(18.7460 + jitterLat, 73.8520 + jitterLng);
    }

    // 3. नाणेकरवाडी कुरुळी / चिंबळी (Nanekarwadi / Kuruli / Chimbali)
    if (r.contains('नाणेकरवाडी') ||
        r.contains('कुरुळी') ||
        r.contains('चिंबळी') ||
        r.contains('nanekarwadi') ||
        r.contains('kuruli') ||
        r.contains('chimbali')) {
      return ll.LatLng(18.7300 + jitterLat, 73.8580 + jitterLng);
    }

    // 4. आंबेठाण वासुलीफाटा (Ambethan / Vasuli Phata)
    if (r.contains('आंबेठाण') ||
        r.contains('वासुली') ||
        r.contains('ambethan') ||
        r.contains('vasuli')) {
      return ll.LatLng(18.7480 + jitterLat, 73.8050 + jitterLng);
    }

    // 5. चाकण (Chakan)
    if (r.contains('चाकण') || r.contains('chakan')) {
      return ll.LatLng(18.7565 + jitterLat, 73.8550 + jitterLng);
    }

    // 6. वाकी भाम (Waki / Bham)
    if (r.contains('वाकी') || r.contains('भाम') || r.contains('waki') || r.contains('bham')) {
      return ll.LatLng(18.7820 + jitterLat, 73.8520 + jitterLng);
    }

    // 7. दावडी निमगाव (Dawadi / Nimgaon)
    if (r.contains('दावडी') ||
        r.contains('निमगाव') ||
        r.contains('dawadi') ||
        r.contains('nimgaon')) {
      return ll.LatLng(18.9050 + jitterLat, 73.9280 + jitterLng);
    }

    // 8. वाफगाव / कनेरसर (Wafgaon / Kanersar)
    if (r.contains('वाफगाव') ||
        r.contains('वाफगावं') ||
        r.contains('कनेरसर') ||
        r.contains('wafgaon') ||
        r.contains('kanersar')) {
      return ll.LatLng(18.9280 + jitterLat, 73.9850 + jitterLng);
    }

    // 9. कडूस पाइट (Kadus / Pait)
    if (r.contains('कडूस') ||
        r.contains('पाइट') ||
        r.contains('kadus') ||
        r.contains('pait')) {
      return ll.LatLng(18.9250 + jitterLat, 73.7850 + jitterLng);
    }

    // 10. वाडा चास (Wada / Chas)
    if (r.contains('चास') ||
        (r.contains('वाडा') && !r.contains('वाडा रोड')) ||
        r.contains('chas')) {
      return ll.LatLng(18.9350 + jitterLat, 73.7700 + jitterLng);
    }

    // 11. पाबळ रोड (Pabal Road)
    if (r.contains('पाबळ') || r.contains('pabal') || r.contains('pabl')) {
      return ll.LatLng(18.8450 + jitterLat, 73.9350 + jitterLng);
    }

    // 12. वाडा रोड (Wada Road)
    if (r.contains('वाडा रोड') || r.contains('wada road')) {
      return ll.LatLng(18.8680 + jitterLat, 73.8550 + jitterLng);
    }

    // 13. खेड / राजगुरूनगर (Khed / Rajgurunagar)
    if (r.contains('खेड') ||
        r.contains('राजगुरूनगर') ||
        r.contains('राजगुरु') ||
        r.contains('khed') ||
        r.contains('rajgurunagar') ||
        r.contains('rajguru')) {
      return ll.LatLng(18.8550 + jitterLat, 73.8880 + jitterLng);
    }

    // 14. मंचर (Manchar)
    if (r.contains('मंचर') || r.contains('manchar')) {
      return ll.LatLng(19.0060 + jitterLat, 73.9450 + jitterLng);
    }

    // 15. नारायणगाव (Narayangaon)
    if (r.contains('नारायणगाव') || r.contains('narayan')) {
      return ll.LatLng(19.1200 + jitterLat, 73.9800 + jitterLng);
    }

    // 16. भोसरी / मोशी / PCMC
    if (r.contains('भोसरी') ||
        r.contains('मोशी') ||
        r.contains('bhosari') ||
        r.contains('moshi') ||
        r.contains('pcmc')) {
      return ll.LatLng(18.6490 + jitterLat, 73.8460 + jitterLng);
    }

    // 17. आळंदी (Alandi)
    if (r.contains('आळंदी') || r.contains('alandi')) {
      return ll.LatLng(18.6750 + jitterLat, 73.8960 + jitterLng);
    }

    // 18. तळेगाव (Talegaon)
    if (r.contains('तळेगाव') || r.contains('talegaon')) {
      return ll.LatLng(18.7350 + jitterLat, 73.6760 + jitterLng);
    }

    // 19. शिक्रापूर (Shikrapur)
    if (r.contains('शिक्रापूर') || r.contains('shikrapur')) {
      return ll.LatLng(18.7480 + jitterLat, 74.1200 + jitterLng);
    }

    // Regional market hub around Khed / Rajgurunagar
    return ll.LatLng(18.8550 + jitterLat, 73.8880 + jitterLng);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final users = auth.users
        .where((u) =>
            u.id != 'config_gemini_api' &&
            !u.isSuperAdmin &&
            !u.isOffice &&
            (u.isSalesman || u.isDriver))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Staff Tracking & Map',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Refresh GPS & Timeline',
            onPressed: _isRefreshing ? null : _refresh,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.7),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
          tabs: const [
            Tab(icon: Icon(Icons.route_outlined, size: 20), text: 'Location Timeline'),
            Tab(icon: Icon(Icons.map_outlined, size: 20), text: 'Live Fleet & Map'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(), // Map needs full touch gesture control
        children: [
          // TAB 1: Visual Chronological Route Timeline
          _buildTimelineTab(users),

          // TAB 2: Live In-App Interactive Map & Fleet Cards
          _buildLiveFleetTab(users),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 1: LOCATION TIMELINE
  // =========================================================================
  Widget _buildTimelineTab(List<UserModel> users) {
    double totalCollected = 0.0;
    int stopsCount = _timelineEntries.length;

    for (int i = 0; i < _timelineEntries.length; i++) {
      final cur = _timelineEntries[i];
      if (cur.amount != null) totalCollected += cur.amount!;
    }

    final isToday = _selectedDate.year == DateTime.now().year &&
        _selectedDate.month == DateTime.now().month &&
        _selectedDate.day == DateTime.now().day;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        children: [
          // Filter Row: Staff dropdown + Date picker
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // Staff Selector
                    Expanded(
                      flex: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedStaffFilter,
                            isExpanded: true,
                            icon: const Icon(Icons.arrow_drop_down, color: Colors.blueGrey),
                            items: [
                              const DropdownMenuItem(
                                value: 'all',
                                child: Text('All Staff', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                              ...users.map((u) {
                                return DropdownMenuItem(
                                  value: u.name,
                                  child: Text(
                                    '${u.name} (${u.roleDisplayName})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }),
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
                    const SizedBox(width: 8),

                    // Date Button
                    Expanded(
                      flex: 4,
                      child: InkWell(
                        onTap: () async {
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
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.calendar_today, size: 14, color: Color(0xFF0F172A)),
                              const SizedBox(width: 6),
                              Text(
                                isToday ? 'Today' : DateFormat('d MMM').format(_selectedDate),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Daily Summary Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTimelineStat('Stops', '$stopsCount', Icons.pin_drop),
                Container(width: 1, height: 30, color: Colors.white24),
                _buildTimelineStat('Collected', CurrencyFormatter.format(totalCollected), Icons.payments),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Timeline Cards List
          if (_isLoadingTimeline)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (_timelineEntries.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: const Text('No timeline movements recorded for this date.'),
            )
          else
            ..._buildTimelineCards(),
        ],
      ),
    );
  }

  Widget _buildTimelineStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF38BDF8), size: 16),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13.5)),
        Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5, fontWeight: FontWeight.bold)),
      ],
    );
  }

  List<Widget> _buildTimelineCards() {
    return _timelineEntries.map((entry) {
      final isColl = entry.isCollection;
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: isColl ? const Color(0xFF86EFAC) : Colors.grey.shade300),
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: isColl
                ? const Color(0xFFDCFCE7)
                : const Color(0xFFEFF6FF),
            foregroundColor: isColl ? const Color(0xFF15803D) : const Color(0xFF2563EB),
            child: Icon(isColl ? Icons.payments : Icons.location_on, size: 18),
          ),
          title: Text(
            cleanLandmark(entry.landmark.isNotEmpty ? entry.landmark : (entry.shopName ?? 'Breadcrumb')),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${entry.staffName} · ${entry.timeFormatted}',
                  style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600)),
              if (entry.details.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(entry.details,
                    style: TextStyle(
                        fontSize: 11,
                        color: isColl ? const Color(0xFF15803D) : Colors.black87,
                        fontWeight: isColl ? FontWeight.bold : FontWeight.normal)),
              ],
            ],
          ),
          trailing: InkWell(
            onTap: () {
              // Switch to in-app map and focus on this point!
              _tabController.animateTo(1);
              setState(() {
                _fleetViewMode = 'map';
              });
              _mapController.move(ll.LatLng(entry.latitude, entry.longitude), 14.5);
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.map, size: 12, color: Colors.white),
                  SizedBox(width: 4),
                  Text('In-App Map', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  // =========================================================================
  // TAB 2: LIVE FLEET & IN-APP SMOOTH MAP
  // =========================================================================
  Widget _buildLiveFleetTab(List<UserModel> users) {
    final provider = context.watch<CollectionProvider>();
    final allShops = provider.allShops;

    return Column(
      children: [
        // Mode Selector: In-App Interactive Map vs Fleet List
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _fleetViewMode = 'map'),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _fleetViewMode == 'map' ? const Color(0xFF0F172A) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.map,
                            size: 16,
                            color: _fleetViewMode == 'map' ? Colors.white : Colors.black87),
                        const SizedBox(width: 6),
                        Text(
                          'In-App Map (${allShops.length} Outlets)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _fleetViewMode == 'map' ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _fleetViewMode = 'list'),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _fleetViewMode == 'list' ? const Color(0xFF0F172A) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.view_list,
                            size: 16,
                            color: _fleetViewMode == 'list' ? Colors.white : Colors.black87),
                        const SizedBox(width: 6),
                        Text(
                          'Fleet List (${users.length} Staff)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _fleetViewMode == 'list' ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Body: In-App Interactive Map OR Fleet List
        Expanded(
          child: _fleetViewMode == 'map'
              ? _buildInAppMap(users, allShops)
              : _buildFleetListView(users),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // IN-APP INTERACTIVE GOOGLE MAP (Google Satellite Hybrid, Clean Pins, Staff)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildInAppMap(List<UserModel> users, List<ShopModel> allShops) {
    final provider = context.watch<CollectionProvider>();
    final allRoutes = provider.allRoutes;

    var baseShops = allShops;
    if (_selectedMapRouteId != null && _selectedMapRouteId!.isNotEmpty) {
      baseShops = baseShops.where((s) => s.routeId == _selectedMapRouteId).toList();
    }

    // Filter shops if user searches
    final displayShops = _shopSearchQuery.trim().isEmpty
        ? baseShops
        : baseShops.where((s) {
            final q = _shopSearchQuery.toLowerCase().trim();
            return s.name.toLowerCase().contains(q) ||
                s.routeName.toLowerCase().contains(q) ||
                s.address.toLowerCase().contains(q);
          }).toList();

    return Stack(
      children: [
        // 1. FlutterMap Widget with Google Hybrid Satellite / Streets tiles
        FlutterMap(
          key: ValueKey('map_$_mapLayer'),
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: ll.LatLng(18.8400, 73.8800), // Khed / Rajgurunagar region
            initialZoom: 11.5,
            minZoom: 6.0,
            maxZoom: 20.0,
            interactionOptions: InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            // Google Maps Tile Layer
            TileLayer(
              key: ValueKey(_mapLayer),
              urlTemplate: _getMapUrlTemplate(),
              userAgentPackageName: 'com.purva.dailycollection',
              maxZoom: 20,
            ),

            // Shop / Outlet Markers (Small clean 16x16 circular pins that don't block satellite roads)
            if (_showOutletsOnMap)
              MarkerLayer(
                markers: displayShops.map((shop) {
                  final pos = _getShopLatLng(shop);
                  final isSelected = _selectedShop?.id == shop.id;

                  return Marker(
                    point: pos,
                    width: isSelected ? 30 : 16,
                    height: isSelected ? 30 : 16,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedShop = shop;
                          _selectedStaffUser = null;
                        });
                        _mapController.move(pos, 15.0);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFEF4444) : const Color(0xFF0284C7),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: isSelected ? 2.5 : 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: isSelected
                            ? const Center(
                                child: Icon(Icons.store, color: Colors.white, size: 16),
                              )
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),

            // Live Staff Markers (Google Maps Professional Live Location)
            MarkerLayer(
              markers: users.where((u) => u.hasLocation).map((user) {
                final pos = ll.LatLng(user.latitude!, user.longitude!);
                final isDriver = user.isDriver;
                final isOnline = user.isOnline;
                final color = isDriver ? const Color(0xFF0284C7) : const Color(0xFF16A34A);

                return Marker(
                  point: pos,
                  width: 110,
                  height: 72,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedStaffUser = user;
                        _selectedShop = null;
                      });
                      _mapController.move(pos, 15.5);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Compact Google Maps style Name Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isOnline ? color : Colors.grey.shade400,
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
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
                                  user.name,
                                  style: const TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 3),
                        // Live Google Location Beacon (Pulsing Halo + Vehicle Glyph)
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Pulsing outer halo ring
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: color.withValues(alpha: 0.22),
                                  border: Border.all(
                                    color: color.withValues(alpha: 0.45),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              // Core vehicle badge
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.35),
                                      blurRadius: 5,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  isDriver ? Icons.local_shipping_rounded : Icons.two_wheeler_rounded,
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

        // 2. Top Controls Bar: Search & Layer Switches
        Positioned(
          top: 10,
          left: 12,
          right: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Search Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 18, color: Colors.blueGrey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Search outlets or beats (e.g. Khed, Chakan)...',
                          hintStyle: TextStyle(fontSize: 12, color: Colors.blueGrey),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        onChanged: (val) => setState(() => _shopSearchQuery = val),
                      ),
                    ),
                    if (_shopSearchQuery.isNotEmpty)
                      InkWell(
                        onTap: () => setState(() => _shopSearchQuery = ''),
                        child: const Icon(Icons.clear, size: 16, color: Colors.grey),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // Route & Staff Dropdowns Row
              Row(
                children: [
                  // 1. Route Dropdown
                  Expanded(
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 1)),
                        ],
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _selectedMapRouteId,
                          isExpanded: true,
                          icon: const Icon(Icons.arrow_drop_down, size: 18, color: Colors.blueGrey),
                          hint: const Text('All Routes', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.black87)),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All Routes', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                            ),
                            ...allRoutes.map((r) => DropdownMenuItem<String?>(
                                  value: r.id,
                                  child: Text(r.name, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                )),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedMapRouteId = val;
                              _selectedShop = null;
                            });
                            if (val != null) {
                              final routeShops = allShops.where((s) => s.routeId == val).toList();
                              if (routeShops.isNotEmpty) {
                                final s = routeShops.firstWhere((s) => s.latitude != null && s.longitude != null, orElse: () => routeShops.first);
                                final pos = _getShopLatLng(s);
                                _mapController.move(pos, 13.0);
                              }
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 2. Staff Dropdown (Salesman & Driver Only)
                  Expanded(
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 1)),
                        ],
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _selectedStaffUser?.id,
                          isExpanded: true,
                          icon: const Icon(Icons.arrow_drop_down, size: 18, color: Colors.blueGrey),
                          hint: const Text('All Live Staff', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.black87)),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All Live Staff', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                            ),
                            ...users.map((u) => DropdownMenuItem<String?>(
                                  value: u.id,
                                  child: Text('${u.name} (${u.roleDisplayName})',
                                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                )),
                          ],
                          onChanged: (val) {
                            setState(() {
                              if (val == null) {
                                _selectedStaffUser = null;
                              } else {
                                _selectedStaffUser = users.firstWhere((u) => u.id == val);
                                _selectedShop = null;
                                if (_selectedStaffUser!.hasLocation) {
                                  _mapController.move(
                                    ll.LatLng(_selectedStaffUser!.latitude!, _selectedStaffUser!.longitude!),
                                    15.5,
                                  );
                                }
                              }
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Filter & Mode Pills Row
              Row(
                children: [
                  // Satellite Mode Toggle Pill
                  InkWell(
                    onTap: () {
                      setState(() {
                        _mapLayer = _mapLayer == 'satellite' ? 'streets' : 'satellite';
                      });
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _mapLayer == 'satellite' ? const Color(0xFF0F172A) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _mapLayer == 'satellite' ? const Color(0xFF38BDF8) : Colors.grey.shade300,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _mapLayer == 'satellite' ? Icons.satellite_alt_rounded : Icons.map_outlined,
                            size: 14,
                            color: _mapLayer == 'satellite' ? const Color(0xFF38BDF8) : const Color(0xFF0F172A),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _mapLayer == 'satellite' ? 'Satellite' : 'Roadmap',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _mapLayer == 'satellite' ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Outlets vs Staff-Only Toggle Pill
                  InkWell(
                    onTap: () {
                      setState(() {
                        _showOutletsOnMap = !_showOutletsOnMap;
                      });
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _showOutletsOnMap ? const Color(0xFF0284C7) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _showOutletsOnMap ? const Color(0xFF0284C7) : Colors.grey.shade300,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.storefront_rounded,
                            size: 14,
                            color: _showOutletsOnMap ? Colors.white : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _showOutletsOnMap ? 'Outlets (${allShops.length})' : 'Staff Only',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _showOutletsOnMap ? Colors.white : const Color(0xFF0F172A),
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

        // 3. Floating Quick Actions (Center on Staff, Center on Khed, Zoom Controls)
        Positioned(
          right: 12,
          bottom: _selectedShop != null || _selectedStaffUser != null ? 140 : 20,
          child: Column(
            children: [
              // Recenter on Staff
              FloatingActionButton.small(
                heroTag: 'recenter_staff',
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF16A34A),
                tooltip: 'Focus on Staff',
                onPressed: () {
                  final liveUser = users.firstWhere(
                    (u) => u.hasLocation,
                    orElse: () => users.first,
                  );
                  if (liveUser.hasLocation) {
                    _mapController.move(ll.LatLng(liveUser.latitude!, liveUser.longitude!), 15.0);
                  }
                },
                child: const Icon(Icons.my_location, size: 18),
              ),
              const SizedBox(height: 6),

              // Focus on Regional Trade Hub (Khed)
              FloatingActionButton.small(
                heroTag: 'recenter_khed',
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F172A),
                tooltip: 'Focus on Khed Region',
                onPressed: () {
                  _mapController.move(const ll.LatLng(18.8550, 73.8880), 12.0);
                },
                child: const Icon(Icons.hub, size: 18),
              ),
              const SizedBox(height: 6),

              // Zoom In
              FloatingActionButton.small(
                heroTag: 'zoom_in',
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                onPressed: () {
                  _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  );
                },
                child: const Icon(Icons.add, size: 18),
              ),
              const SizedBox(height: 6),

              // Zoom Out
              FloatingActionButton.small(
                heroTag: 'zoom_out',
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                onPressed: () {
                  _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  );
                },
                child: const Icon(Icons.remove, size: 18),
              ),
            ],
          ),
        ),

        // 4. Selected Outlet Detail Card at Bottom
        if (_selectedShop != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF0284C7), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _selectedShop!.name,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _selectedShop = null),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  Text(
                    '${_selectedShop!.routeName} • ${_selectedShop!.address.isNotEmpty ? _selectedShop!.address : "Beat Outlet"}',
                    style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (_selectedShop!.mobileNumber.isNotEmpty) ...[
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.phone, size: 13),
                          label: const Text('Call', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () => _callPhone(_selectedShop!.mobileNumber),
                        ),
                        const SizedBox(width: 8),
                      ],
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.edit_location_alt, size: 13),
                        label: Text(
                          _selectedShop!.hasLocation ? 'Update Pin' : 'Set Exact Pin',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _openSetShopLocationDialog(_selectedShop!),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: _selectedShop!.hasLocation ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _selectedShop!.hasLocation ? const Color(0xFF86EFAC) : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _selectedShop!.hasLocation ? Icons.check_circle : Icons.near_me,
                              size: 11,
                              color: _selectedShop!.hasLocation ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _selectedShop!.hasLocation ? 'Exact GPS Set' : 'Beat Estimated',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _selectedShop!.hasLocation ? const Color(0xFF15803D) : const Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

        // 5. Selected Staff Detail Card at Bottom
        if (_selectedStaffUser != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _selectedStaffUser!.isDriver ? const Color(0xFF0284C7) : const Color(0xFF16A34A),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: _selectedStaffUser!.isDriver
                            ? const Color(0xFF0284C7)
                            : const Color(0xFF16A34A),
                        foregroundColor: Colors.white,
                        child: Icon(
                          _selectedStaffUser!.isDriver ? Icons.local_shipping_rounded : Icons.two_wheeler_rounded,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _selectedStaffUser!.name,
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _selectedStaffUser!.isOnline
                                        ? const Color(0xFFDCFCE7)
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: _selectedStaffUser!.isOnline
                                              ? const Color(0xFF16A34A)
                                              : Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        _selectedStaffUser!.isOnline
                                            ? 'LIVE'
                                            : _selectedStaffUser!.locationTimeAgo,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: _selectedStaffUser!.isOnline
                                              ? const Color(0xFF15803D)
                                              : Colors.blueGrey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${_selectedStaffUser!.roleDisplayName} • ${_selectedStaffUser!.locationLandmark ?? "Active on Field"}',
                              style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => setState(() => _selectedStaffUser = null),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (_selectedStaffUser!.phone.isNotEmpty) ...[
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.phone, size: 13),
                          label: const Text('Call', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () => _callPhone(_selectedStaffUser!.phone),
                        ),
                        const SizedBox(width: 6),
                      ],
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.share, size: 13),
                        label: const Text('WhatsApp GPS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        onPressed: () => _shareLocationViaWhatsApp(_selectedStaffUser!),
                      ),
                      if (_selectedStaffUser!.isDriver) ...[
                        const SizedBox(width: 6),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0284C7),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.alt_route, size: 13),
                          label: const Text('Routes', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () => _showDriverRouteDialog(_selectedStaffUser!),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // FLEET LIST VIEW
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildFleetListView(List<UserModel> users) {
    final provider = context.watch<CollectionProvider>();

    final filteredUsers = users.where((u) {
      if (_liveRoleFilter == 'salesman') return u.isSalesman;
      if (_liveRoleFilter == 'driver') return u.isDriver;
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // Filter Tabs
          Row(
            children: [
              _buildLiveFilterTab('all', 'All (${users.length})'),
              _buildLiveFilterTab('salesman', 'Salesmen (${users.where((u) => u.isSalesman).length})'),
              _buildLiveFilterTab('driver', 'Drivers (${users.where((u) => u.isDriver).length})'),
            ],
          ),
          const SizedBox(height: 12),

          ...filteredUsers.map((u) {
            final hasLoc = u.hasLocation;
            final isOnline = u.isOnline;
            final summary = provider.getStaffSummary(u.name);

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: isOnline ? const Color(0xFF86EFAC) : AppTheme.border),
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
                              ? const Color(0xFF0284C7).withValues(alpha: 0.15)
                              : const Color(0xFF10B981).withValues(alpha: 0.15),
                          foregroundColor: u.isDriver ? const Color(0xFF0284C7) : const Color(0xFF10B981),
                          child: Icon(u.isDriver ? Icons.local_shipping : Icons.two_wheeler, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(u.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                              Text('${u.roleDisplayName} • ${u.phone}',
                                  style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: isOnline ? const Color(0xFFDCFCE7) : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isOnline ? 'ONLINE' : (hasLoc ? u.locationTimeAgo : 'OFFLINE'),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: isOnline ? const Color(0xFF15803D) : Colors.blueGrey,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Landmark: ${u.locationLandmark ?? (hasLoc ? "Active in beat" : "No GPS shared")}',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    if (u.isDriver) ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0284C7),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.alt_route, size: 16),
                              label: Text(
                                u.assignedRouteIds.isEmpty
                                    ? 'Assign Delivery Routes'
                                    : 'Routes (${u.assignedRouteIds.length} assigned)',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              onPressed: () => _showDriverRouteDialog(u),
                            ),
                          ),
                          if (hasLoc) ...[
                            const SizedBox(width: 6),
                            IconButton(
                              icon: const Icon(Icons.share, size: 18, color: Color(0xFF16A34A)),
                              tooltip: 'Share Live GPS (WhatsApp)',
                              onPressed: () => _shareLocationViaWhatsApp(u),
                            ),
                          ],
                          if (u.phone.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.phone, size: 18, color: Color(0xFF2563EB)),
                              tooltip: 'Call Driver',
                              onPressed: () => _callPhone(u.phone),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Today: ${CurrencyFormatter.format(summary.totalAmount)} (${summary.collectionsCount} bills)',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                        ),
                        Row(
                          children: [
                            if (!u.isDriver && hasLoc)
                              IconButton(
                                icon: const Icon(Icons.share, size: 18, color: Color(0xFF16A34A)),
                                tooltip: 'Share Live GPS (WhatsApp)',
                                onPressed: () => _shareLocationViaWhatsApp(u),
                                visualDensity: VisualDensity.compact,
                              ),
                            if (hasLoc) ...[
                              const SizedBox(width: 4),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F172A),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.map, size: 14),
                                label: const Text('In-App Map', style: TextStyle(fontSize: 11)),
                                onPressed: () {
                                  setState(() {
                                    _fleetViewMode = 'map';
                                    _selectedStaffUser = u;
                                  });
                                  _mapController.move(ll.LatLng(u.latitude!, u.longitude!), 14.5);
                                },
                              ),
                            ],
                          ],
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

  Widget _buildLiveFilterTab(String role, String label) {
    final isSelected = _liveRoleFilter == role;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _liveRoleFilter = role),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : Colors.blueGrey.shade800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
