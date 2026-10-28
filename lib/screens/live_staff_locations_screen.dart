import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user_model.dart';
import '../models/location_timeline_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/collection_provider.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';
import '../utils/quick_alert.dart';
import '../services/location_tracking_service.dart';
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
  DateTime _selectedDate = DateTime.now();
  String _selectedStaffFilter = 'all'; // 'all', or staff name
  String _liveRoleFilter = 'all'; // 'all', 'salesman', 'driver'
  bool _isRefreshing = false;
  bool _isLoadingTimeline = false;
  bool _earliestFirst = true;

  List<LocationTimelineEntry> _timelineEntries = [];

  @override
  void initState() {
    super.initState();
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
      QuickAlert.success(context, 'Staff locations & timeline refreshed');
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
      final dayCollections = collectionProvider.getFilteredCollections(forDate: _selectedDate).where((c) {
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
            ? '${shop.name} (${shop.routeName})'
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
          details: 'Collected ${CurrencyFormatter.format(c.collectedAmount)} (${c.paymentMode.displayName}) for Bill #${c.billNumber}',
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
        // Only add if not already present
        final exists = mergedMap.values.any((m) =>
            m.isCollection &&
            m.billNumber == e.billNumber &&
            m.staffName.toLowerCase() == e.staffName.toLowerCase());
        if (!exists) {
          mergedMap[e.id] = e;
        }
      }

      var list = mergedMap.values.toList();

      // Apply staff filter
      if (_selectedStaffFilter != 'all') {
        final s = _selectedStaffFilter.toLowerCase();
        list = list.where((e) {
          return e.staffName.toLowerCase() == s ||
              e.userId.toLowerCase() == s ||
              e.staffName.toLowerCase().contains(s) ||
              s.contains(e.staffName.toLowerCase());
        }).toList();
      }

      // Sort
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

  void _openMaps(double lat, double lng) async {
    final url = 'https://maps.google.com/?q=$lat,$lng';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openFullDayRoute(List<LocationTimelineEntry> points) async {
    if (points.isEmpty) return;
    if (points.length == 1) {
      _openMaps(points.first.latitude, points.first.longitude);
      return;
    }

    // Google Maps multi-waypoint URL
    final validPoints = points.where((p) => p.latitude != 0.0 && p.longitude != 0.0).toList();
    if (validPoints.isEmpty) return;

    final origin = '${validPoints.first.latitude},${validPoints.first.longitude}';
    final destination = '${validPoints.last.latitude},${validPoints.last.longitude}';

    String url;
    if (validPoints.length > 2) {
      // Pick up to 8 evenly spaced intermediate waypoints to stay within URL limits
      final intermediates = <String>[];
      final step = ((validPoints.length - 2) / 8).ceil();
      for (int i = 1; i < validPoints.length - 1; i += (step > 0 ? step : 1)) {
        intermediates.add('${validPoints[i].latitude},${validPoints[i].longitude}');
      }
      url = 'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination&waypoints=${intermediates.join('|')}';
    } else {
      url = 'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination';
    }

    final uri = Uri.parse(url);
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
    final text = 'Live Location of ${user.name} (${user.roleDisplayName}):\n'
        '• Status: ${user.isOnline ? "Active Online" : "Last seen ${user.locationTimeAgo}"}\n'
        '• Landmark: ${user.locationLandmark ?? "Field"}\n'
        '• Google Maps: ${user.mapsUrl}';
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final users = auth.users.where((u) => u.id != 'config_gemini_api' && !u.isSuperAdmin).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Staff Tracking & Timeline',
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
            Tab(
              icon: Icon(Icons.route_outlined, size: 20),
              text: 'Location Timeline',
            ),
            Tab(
              icon: Icon(Icons.sensors, size: 20),
              text: 'Live Fleet & Map',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: Visual Chronological Route Timeline
          _buildTimelineTab(users),

          // TAB 2: Live Status Cards & Fleet Map
          _buildLiveFleetTab(users),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 1: LOCATION TIMELINE
  // =========================================================================
  Widget _buildTimelineTab(List<UserModel> users) {
    // Calculate daily route summary metrics
    double totalKm = 0.0;
    double totalCollected = 0.0;
    int stopsCount = _timelineEntries.length;

    for (int i = 0; i < _timelineEntries.length; i++) {
      final cur = _timelineEntries[i];
      if (cur.amount != null) totalCollected += cur.amount!;
      if (i > 0) {
        final prev = _timelineEntries[i - 1];
        if (cur.latitude != 0.0 && prev.latitude != 0.0) {
          totalKm += LocationTrackingService.haversineDistanceKm(
            prev.latitude,
            prev.longitude,
            cur.latitude,
            cur.longitude,
          );
        }
      }
    }

    final isToday = _selectedDate.year == DateTime.now().year &&
        _selectedDate.month == DateTime.now().month &&
        _selectedDate.day == DateTime.now().day;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        children: [
          // 1. Date Selector Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 22),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Previous Day',
                  onPressed: () {
                    setState(() {
                      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                    });
                    _loadTimeline();
                  },
                ),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now().add(const Duration(days: 30)),
                    );
                    if (picked != null) {
                      setState(() => _selectedDate = picked);
                      _loadTimeline();
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16, color: AppTheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          isToday
                              ? 'Today, ${DateFormat("dd MMM yyyy").format(_selectedDate)}'
                              : DateFormat("EEE, dd MMM yyyy").format(_selectedDate),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down, size: 18, color: Colors.blueGrey),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 22),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Next Day',
                  onPressed: () {
                    setState(() {
                      _selectedDate = _selectedDate.add(const Duration(days: 1));
                    });
                    _loadTimeline();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 2. Staff Selector Chips (Horizontal Scroll)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTimelineStaffFilterChip(
                  label: 'All Staff',
                  icon: Icons.groups_outlined,
                  isSelected: _selectedStaffFilter == 'all',
                  onTap: () {
                    setState(() => _selectedStaffFilter = 'all');
                    _loadTimeline();
                  },
                ),
                const SizedBox(width: 6),
                ...users.map((u) {
                  final isSel = _selectedStaffFilter.toLowerCase() == u.name.toLowerCase() ||
                      _selectedStaffFilter.toLowerCase() == u.phone.toLowerCase();
                  final icon = u.isDriver
                      ? Icons.local_shipping
                      : (u.isSalesman ? Icons.two_wheeler : Icons.business_center);
                  final roleTag = u.isDriver ? 'Driver' : (u.isSalesman ? 'Sales' : 'Office');

                  return Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: _buildTimelineStaffFilterChip(
                      label: '${u.name} ($roleTag)',
                      icon: icon,
                      isSelected: isSel,
                      isOnline: u.isOnline,
                      onTap: () {
                        setState(() => _selectedStaffFilter = u.name);
                        _loadTimeline();
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 3. Route Summary Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFF0F172A), const Color(0xFF1E293B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.timeline, color: Color(0xFF38BDF8), size: 16),
                        const SizedBox(width: 6),
                        Text(
                          _selectedStaffFilter == 'all'
                              ? 'Combined Fleet Route Summary'
                              : '$_selectedStaffFilter\'s Daily Route',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: () {
                        setState(() => _earliestFirst = !_earliestFirst);
                        _loadTimeline();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _earliestFirst ? Icons.arrow_downward : Icons.arrow_upward,
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _earliestFirst ? 'Earliest first' : 'Latest first',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildSummaryStatItem('Stops / Logs', '$stopsCount', Icons.location_on_outlined),
                    _buildSummaryStatItem('Distance', '${totalKm.toStringAsFixed(1)} km', Icons.straighten),
                    _buildSummaryStatItem('Collections', CurrencyFormatter.format(totalCollected), Icons.account_balance_wallet_outlined),
                  ],
                ),
                if (_timelineEntries.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.map, size: 16),
                      label: const Text(
                        'Open Full Day Route on Google Maps',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => _openFullDayRoute(_timelineEntries),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 4. Chronological Timeline List
          if (_isLoadingTimeline)
            Container(
              padding: const EdgeInsets.all(40),
              alignment: Alignment.center,
              child: const CircularProgressIndicator(),
            )
          else if (_timelineEntries.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.route, size: 36, color: Color(0xFF2563EB)),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No Route Activity Recorded on ${DateFormat("dd MMM").format(_selectedDate)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _selectedStaffFilter == 'all'
                        ? 'When salesmen or driver log in and move across shop beats, their live GPS pings, collection checkpoints, and deliveries will show here.'
                        : 'No GPS pings or collection stops logged for $_selectedStaffFilter on this date.',
                    style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh GPS Now'),
                    onPressed: _refresh,
                  ),
                ],
              ),
            )
          else
            ..._buildTimelineCards(),
        ],
      ),
    );
  }

  Widget _buildTimelineStaffFilterChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    bool isOnline = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0, 2))]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOnline) ...[
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF16A34A),
                ),
              ),
              const SizedBox(width: 5),
            ],
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.white : Colors.blueGrey.shade700,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryStatItem(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 12, color: const Color(0xFF94A3B8)),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTimelineCards() {
    final widgets = <Widget>[];

    for (int i = 0; i < _timelineEntries.length; i++) {
      final entry = _timelineEntries[i];
      final isLast = i == _timelineEntries.length - 1;

      // Distance from previous stop
      double? distKm;
      int? timeDiffMin;
      if (i > 0) {
        final prev = _timelineEntries[i - 1];
        if (entry.latitude != 0.0 && prev.latitude != 0.0) {
          distKm = LocationTrackingService.haversineDistanceKm(
            prev.latitude,
            prev.longitude,
            entry.latitude,
            entry.longitude,
          );
        }
        timeDiffMin = entry.timestamp.difference(prev.timestamp).inMinutes.abs();
      }

      // Visual styling according to event type
      Color nodeColor;
      IconData nodeIcon;
      String eventBadgeText;
      Color eventBadgeBg;
      Color eventBadgeTextCol;

      if (entry.isCollection) {
        nodeColor = const Color(0xFF16A34A);
        nodeIcon = Icons.payments;
        eventBadgeText = 'COLLECTION';
        eventBadgeBg = const Color(0xFFDCFCE7);
        eventBadgeTextCol = const Color(0xFF15803D);
      } else if (entry.isDelivery) {
        nodeColor = const Color(0xFF0284C7);
        nodeIcon = Icons.local_shipping;
        eventBadgeText = 'DELIVERY VISIT';
        eventBadgeBg = const Color(0xFFE0F2FE);
        eventBadgeTextCol = const Color(0xFF0369A1);
      } else if (entry.isLogin) {
        nodeColor = const Color(0xFF6366F1);
        nodeIcon = Icons.login;
        eventBadgeText = 'SHIFT START';
        eventBadgeBg = const Color(0xFFEEF2FF);
        eventBadgeTextCol = const Color(0xFF4338CA);
      } else {
        nodeColor = const Color(0xFF2563EB);
        nodeIcon = entry.isDriver ? Icons.local_shipping : Icons.two_wheeler;
        eventBadgeText = entry.isDriver ? 'DRIVER PING' : 'SALES GPS';
        eventBadgeBg = const Color(0xFFEFF6FF);
        eventBadgeTextCol = const Color(0xFF1D4ED8);
      }

      widgets.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left Column: Timestamp & Timeline Line + Node Icon
              SizedBox(
                width: 76,
                child: Column(
                  children: [
                    Text(
                      entry.timeFormatted,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: nodeColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: nodeColor.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(nodeIcon, color: Colors.white, size: 14),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: Colors.blueGrey.shade200,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                        ),
                      ),
                  ],
                ),
              ),

              // Right Column: Event Content Card
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: entry.isCollection
                            ? const Color(0xFF86EFAC)
                            : AppTheme.border,
                        width: entry.isCollection ? 1.5 : 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header: Staff Name + Event Badge
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(
                                  entry.staffName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '(${entry.staffRole})',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.blueGrey.shade600,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: eventBadgeBg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                eventBadgeText,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: eventBadgeTextCol,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Landmark / Shop
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.location_on, size: 15, color: Color(0xFFDC2626)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                entry.landmark.isNotEmpty
                                    ? entry.landmark
                                    : (entry.shopName ?? 'Transit Breadcrumb'),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Details text
                        if (entry.details.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            entry.details,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: entry.isCollection
                                  ? const Color(0xFF15803D)
                                  : Colors.blueGrey.shade700,
                              fontWeight: entry.isCollection ? FontWeight.w700 : FontWeight.normal,
                            ),
                          ),
                        ],

                        // Distance and travel time since last stop
                        if (distKm != null && distKm > 0.05) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.turn_sharp_right, size: 12, color: Colors.blueGrey),
                              const SizedBox(width: 3),
                              Text(
                                '${distKm.toStringAsFixed(1)} km traveled${timeDiffMin != null ? ' in $timeDiffMin min' : ''}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.blueGrey.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],

                        // Bottom Actions: Open in Maps
                        if (entry.latitude != 0.0 && entry.longitude != 0.0) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'GPS: ${entry.latitude.toStringAsFixed(4)}, ${entry.longitude.toStringAsFixed(4)}',
                                style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade500),
                              ),
                              InkWell(
                                onTap: () => _openMaps(entry.latitude, entry.longitude),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.map_outlined, color: Colors.white, size: 11),
                                      SizedBox(width: 4),
                                      Text(
                                        'View on Maps',
                                        style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return widgets;
  }

  // =========================================================================
  // TAB 2: LIVE FLEET & REAL-TIME STATUS
  // =========================================================================
  Widget _buildLiveFleetTab(List<UserModel> users) {
    final provider = context.watch<CollectionProvider>();

    final filteredUsers = users.where((u) {
      if (_liveRoleFilter == 'salesman') return u.isSalesman;
      if (_liveRoleFilter == 'driver') return u.isDriver;
      return true;
    }).toList();

    final onlineCount = users.where((u) => u.isOnline).length;
    final locatedCount = users.where((u) => u.hasLocation).length;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        children: [
          // Status Summary Cards
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.groups_outlined, size: 16, color: Colors.blueGrey),
                          SizedBox(width: 4),
                          Text('Staff', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${users.length}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.sensors, size: 16, color: Color(0xFF16A34A)),
                          SizedBox(width: 4),
                          Text('Online', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$onlineCount Live',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF15803D)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.location_on, size: 16, color: Color(0xFF2563EB)),
                          SizedBox(width: 4),
                          Text('Tracked', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$locatedCount / ${users.length}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1D4ED8)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Role Filter Segment
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                _buildLiveFilterTab('all', 'All (${users.length})'),
                _buildLiveFilterTab('salesman', 'Salesmen (${users.where((u) => u.isSalesman).length})'),
                _buildLiveFilterTab('driver', 'Drivers (${users.where((u) => u.isDriver).length})'),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Staff Location Cards List
          if (filteredUsers.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: const Text('No staff members found matching filter.'),
            )
          else
            ...filteredUsers.map((u) {
              final summary = provider.getStaffSummary(u.name);
              final hasLoc = u.hasLocation;
              final isOnline = u.isOnline;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isOnline ? const Color(0xFF86EFAC) : AppTheme.border,
                    width: isOnline ? 1.5 : 1.0,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Card Header: Avatar, Name, Role, Online Badge
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: u.isDriver
                                  ? const Color(0xFF0284C7).withValues(alpha: 0.15)
                                  : (u.isSalesman
                                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                      : Colors.amber.shade100),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              u.isDriver
                                  ? Icons.local_shipping
                                  : (u.isSalesman ? Icons.two_wheeler : Icons.business_center),
                              color: u.isDriver
                                  ? const Color(0xFF0284C7)
                                  : (u.isSalesman ? const Color(0xFF059669) : Colors.amber.shade800),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      u.name,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.blueGrey.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        u.roleDisplayName.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blueGrey.shade800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  u.phone,
                                  style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade600),
                                ),
                              ],
                            ),
                          ),

                          // Online/Offline Status Indicator
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isOnline
                                  ? const Color(0xFFDCFCE7)
                                  : (hasLoc ? Colors.grey.shade100 : Colors.red.shade50),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isOnline
                                    ? const Color(0xFF86EFAC)
                                    : (hasLoc ? Colors.grey.shade300 : Colors.red.shade200),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isOnline
                                        ? const Color(0xFF16A34A)
                                        : (hasLoc ? Colors.blueGrey : Colors.red),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  isOnline
                                      ? 'LIVE'
                                      : (hasLoc ? u.locationTimeAgo : 'No GPS'),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: isOnline
                                        ? const Color(0xFF15803D)
                                        : (hasLoc ? Colors.blueGrey.shade700 : Colors.red.shade700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Location Details Container
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.location_on, size: 16, color: Color(0xFFDC2626)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        hasLoc
                                            ? (u.locationLandmark ?? 'Active in Beat Route')
                                            : 'Location not shared yet',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: hasLoc ? const Color(0xFF0F172A) : Colors.blueGrey.shade500,
                                        ),
                                      ),
                                      if (hasLoc) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'GPS: ${u.latitude?.toStringAsFixed(5)}, ${u.longitude?.toStringAsFixed(5)} • Updated: ${u.locationTimeAgo}',
                                          style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (u.isDriver && u.assignedRouteIds.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.alt_route, size: 14, color: Color(0xFF0284C7)),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Assigned: ${u.assignedRouteIds.map((id) => provider.getRouteName(id)).join(", ")}',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF0369A1), fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Performance & Summary Strip
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Today: ${CurrencyFormatter.format(summary.totalAmount)} (${summary.collectionsCount} bills)',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                          ),
                          Row(
                            children: [
                              // View Timeline Button
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.route, size: 15, color: AppTheme.primary),
                                label: const Text('Timeline', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                onPressed: () {
                                  setState(() {
                                    _selectedStaffFilter = u.name;
                                    _tabController.animateTo(0);
                                  });
                                  _loadTimeline();
                                },
                              ),
                              if (u.phone.isNotEmpty && RegExp(r'^\d+$').hasMatch(u.phone))
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.phone_outlined, size: 18, color: Color(0xFF2563EB)),
                                  tooltip: 'Call Staff',
                                  onPressed: () => _callPhone(u.phone),
                                ),
                              if (hasLoc)
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.share_outlined, size: 18, color: Color(0xFF16A34A)),
                                  tooltip: 'Share Live Location',
                                  onPressed: () => _shareLocationViaWhatsApp(u),
                                ),
                            ],
                          ),
                        ],
                      ),

                      // Main Action Button: Open Google Maps
                      if (hasLoc) ...[
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.map_outlined, size: 16),
                            label: Text(
                              'Track ${u.name} on Google Maps',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                            ),
                            onPressed: () => _openMaps(u.latitude!, u.longitude!),
                          ),
                        ),
                      ],
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
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : Colors.transparent,
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
