import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/collection_provider.dart';
import '../models/route_model.dart';
import '../models/shop_model.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';
import 'add_route_dialog.dart';
import 'add_shop_screen.dart';
import 'send_reminder_dialog.dart';

class RoutesShopsScreen extends StatefulWidget {
  const RoutesShopsScreen({super.key});

  @override
  State<RoutesShopsScreen> createState() => _RoutesShopsScreenState();
}

class _RoutesShopsScreenState extends State<RoutesShopsScreen> {
  String? _selectedRouteId;
  String? _selectedShopId;
  String _shopSearch = '';

  void _showPriorityDialog(BuildContext context, CollectionProvider provider) {
    final routes = List<RouteModel>.from(provider.routes);
    routes.sort((a, b) => a.priority.compareTo(b.priority));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.low_priority_rounded, color: AppTheme.primary),
                SizedBox(width: 8),
                Text('Set Route Priorities', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Order route beats by visit sequence (Priority 1 will be visited first on the field):',
                    style: TextStyle(fontSize: 12.5, color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: routes.length,
                      separatorBuilder: (_, index) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final r = routes[idx];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                            child: Text(
                              'P${idx + 1}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                          title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text('${provider.getShopsForRoute(r.id).length} outlets', style: const TextStyle(fontSize: 11.5)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_upward, size: 18),
                                tooltip: 'Move Higher Priority',
                                onPressed: idx > 0
                                    ? () {
                                        final currentPriority = idx + 1;
                                        final prevRoute = routes[idx - 1];
                                        final prevPriority = idx;
                                        provider.updateRoutePriority(r.id, prevPriority);
                                        provider.updateRoutePriority(prevRoute.id, currentPriority);
                                        setDialogState(() {
                                          routes[idx] = r.copyWith(priority: prevPriority);
                                          routes[idx - 1] = prevRoute.copyWith(priority: currentPriority);
                                          routes.sort((a, b) => a.priority.compareTo(b.priority));
                                        });
                                      }
                                    : null,
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_downward, size: 18),
                                tooltip: 'Move Lower Priority',
                                onPressed: idx < routes.length - 1
                                    ? () {
                                        final currentPriority = idx + 1;
                                        final nextRoute = routes[idx + 1];
                                        final nextPriority = idx + 2;
                                        provider.updateRoutePriority(r.id, nextPriority);
                                        provider.updateRoutePriority(nextRoute.id, currentPriority);
                                        setDialogState(() {
                                          routes[idx] = r.copyWith(priority: nextPriority);
                                          routes[idx + 1] = nextRoute.copyWith(priority: currentPriority);
                                          routes.sort((a, b) => a.priority.compareTo(b.priority));
                                        });
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmAndDeleteShop(ShopModel shop) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Store?'),
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
            icon: const Icon(Icons.low_priority_rounded, size: 21),
            tooltip: 'Set Route Priorities',
            onPressed: () => _showPriorityDialog(context, provider),
          ),
          IconButton(
            icon: const Icon(Icons.add_location_alt_outlined, size: 20),
            tooltip: 'Add Beat Route',
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
          // Route Horizontal Selector Bar with Priority Badges
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'SALES ROUTES (BY PRIORITY)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: Colors.blueGrey,
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () => _showPriorityDialog(context, provider),
                          child: const Icon(Icons.edit_note, size: 16, color: AppTheme.primary),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: () => _showPriorityDialog(context, provider),
                      child: const Row(
                        children: [
                          Icon(Icons.sort_rounded, size: 14, color: AppTheme.primary),
                          SizedBox(width: 4),
                          Text(
                            'Set Priority',
                            style: TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: routes.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final r = entry.value;
                        final isSelected = _selectedRouteId == r.id;
                        final count = provider.getShopsForRoute(r.id).length;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: FilterChip(
                            avatar: CircleAvatar(
                              radius: 10,
                              backgroundColor: isSelected ? Colors.white.withValues(alpha: 0.25) : AppTheme.primary.withValues(alpha: 0.15),
                              child: Text(
                                '${idx + 1}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: isSelected ? Colors.white : AppTheme.primary,
                                ),
                              ),
                            ),
                            label: Text('${r.name} ($count)'),
                            selected: isSelected,
                            selectedColor: AppTheme.primary,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : Colors.blueGrey.shade800,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 12,
                            ),
                            backgroundColor: Colors.grey.shade100,
                            onSelected: (val) {
                              if (val) {
                                setState(() {
                                  _selectedRouteId = r.id;
                                  _selectedShopId = null;
                                });
                              }
                            },
                          ),
                        );
                      }).toList(),
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
                  DropdownButtonFormField<String?>(
                    key: ValueKey('outlet_dd_${_selectedRouteId}_$_selectedShopId'),
                    initialValue: _selectedShopId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Select Outlet / Shop',
                      prefixIcon: const Icon(Icons.storefront, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          'All Outlets in ${selectedRoute.name} (${outletsInSelectedRoute.length})',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                      ...outletsInSelectedRoute.map(
                        (s) => DropdownMenuItem<String?>(
                          value: s.id,
                          child: Text('${s.name} (${s.mobileNumber})', style: const TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedShopId = val);
                    },
                  ),
                  const SizedBox(height: 8),
                ],

                // Search Box
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search outlet name, phone, or address...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, size: 20, color: Colors.blueGrey),
                                    padding: EdgeInsets.zero,
                                    tooltip: 'Store options',
                                    onSelected: (val) async {
                                      if (val == 'edit') {
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
                                          'Pending Balance: ${CurrencyFormatter.format(balanceDue)}',
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
                                            'No Outstanding Dues',
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
