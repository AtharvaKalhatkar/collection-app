import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/route_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/collection_provider.dart';
import '../utils/marathi_search_helper.dart';
import '../utils/quick_alert.dart';
import '../utils/theme.dart';

/// Production route-assignment dialog usable by Super Admin, Collection, and Sales logins.
/// Supports assigning different routes cleanly per individual login.
class AssignRoutesDialog extends StatefulWidget {
  final UserModel? initialUser;

  const AssignRoutesDialog({super.key, this.initialUser});

  static Future<void> show(BuildContext context, {UserModel? initialUser}) async {
    final currentUser = context.read<AuthProvider>().currentUser;
    if (currentUser == null || !currentUser.canAssignRoutes) return;

    await showDialog<void>(
      context: context,
      builder: (_) => AssignRoutesDialog(initialUser: initialUser),
    );
  }

  @override
  State<AssignRoutesDialog> createState() => _AssignRoutesDialogState();
}

class _AssignRoutesDialogState extends State<AssignRoutesDialog> {
  UserRole? _roleFilter;
  String? _selectedUserId;
  late List<String> _selectedRoutes;
  String _routeQuery = '';
  bool _isSaving = false;
  final TextEditingController _routeSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final assignable = _getAssignableUsers(context.read<AuthProvider>().users);
    if (widget.initialUser != null && !widget.initialUser!.isSuperAdmin) {
      _selectedUserId = widget.initialUser!.id;
      _roleFilter = widget.initialUser!.role;
      _selectedRoutes = List<String>.from(widget.initialUser!.assignedRouteIds);
    } else if (assignable.isNotEmpty) {
      _selectedUserId = assignable.first.id;
      _selectedRoutes = List<String>.from(assignable.first.assignedRouteIds);
    } else {
      _selectedRoutes = [];
    }
  }

  @override
  void dispose() {
    _routeSearchCtrl.dispose();
    super.dispose();
  }

  List<UserModel> _getAssignableUsers(List<UserModel> allUsers) {
    final list = allUsers.where((u) => u.isActive && !u.isSuperAdmin).toList();
    int roleRank(UserRole r) {
      switch (r) {
        case UserRole.driver:
          return 0;
        case UserRole.salesman:
          return 1;
        case UserRole.collection:
          return 2;
        case UserRole.order:
          return 3;
        case UserRole.office:
          return 4;
        case UserRole.superAdmin:
          return 5;
      }
    }

    list.sort((a, b) {
      final cmp = roleRank(a.role).compareTo(roleRank(b.role));
      if (cmp != 0) return cmp;
      return a.plainName.toLowerCase().compareTo(b.plainName.toLowerCase());
    });
    return list;
  }

  Color _roleColor(UserRole role) {
    switch (role) {
      case UserRole.superAdmin:
        return AppTheme.purvaPrimary;
      case UserRole.office:
        return AppTheme.manasPrimary;
      case UserRole.salesman:
        return const Color(0xFFD97706);
      case UserRole.collection:
        return const Color(0xFF059669);
      case UserRole.driver:
        return const Color(0xFF0284C7);
      case UserRole.order:
        return const Color(0xFF7C3AED);
    }
  }

  IconData _roleIcon(UserRole role) {
    switch (role) {
      case UserRole.superAdmin:
        return Icons.admin_panel_settings_outlined;
      case UserRole.office:
        return Icons.business_center_outlined;
      case UserRole.salesman:
        return Icons.two_wheeler_outlined;
      case UserRole.collection:
        return Icons.payments_outlined;
      case UserRole.driver:
        return Icons.local_shipping_outlined;
      case UserRole.order:
        return Icons.shopping_bag_outlined;
    }
  }

  void _selectUser(UserModel? user) {
    setState(() {
      _selectedUserId = user?.id;
      _selectedRoutes = List<String>.from(user?.assignedRouteIds ?? []);
    });
  }

  Future<bool> _saveSelectedUser(UserModel user) async {
    setState(() => _isSaving = true);
    try {
      final auth = context.read<AuthProvider>();
      final provider = context.read<CollectionProvider>();
      final updated = user.copyWith(assignedRouteIds: List<String>.from(_selectedRoutes));
      await auth.saveUser(updated);
      if (auth.currentUser != null) {
        provider.setCurrentUser(auth.currentUser);
      }
      return true;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<CollectionProvider>();
    final allRoutes = provider.allRoutes;
    final allStaff = _getAssignableUsers(auth.users);

    final filteredStaff = _roleFilter == null
        ? allStaff
        : allStaff.where((u) => u.role == _roleFilter).toList();

    UserModel? selectedUser;
    if (filteredStaff.isNotEmpty) {
      selectedUser = filteredStaff.where((u) => u.id == _selectedUserId).firstOrNull ?? filteredStaff.first;
      if (_selectedUserId != selectedUser.id) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _selectUser(selectedUser);
        });
      }
    }

    final filteredRoutes = allRoutes.where((r) {
      if (_routeQuery.trim().isEmpty) return true;
      return MarathiSearchHelper.matches(r.name, _routeQuery) ||
          r.name.toLowerCase().contains(_routeQuery.toLowerCase().trim());
    }).toList();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.manasLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.manasBorder),
            ),
            child: const Icon(Icons.alt_route_rounded, color: AppTheme.manasPrimary, size: 20),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Assign Routes',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppTheme.primary),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Role Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildRoleChip('All', null),
                    const SizedBox(width: 6),
                    _buildRoleChip('Sales & Coll', UserRole.salesman),
                    const SizedBox(width: 6),
                    _buildRoleChip('Collection', UserRole.collection),
                    const SizedBox(width: 6),
                    _buildRoleChip('Sales', UserRole.order),
                    const SizedBox(width: 6),
                    _buildRoleChip('Driver', UserRole.driver),
                    const SizedBox(width: 6),
                    _buildRoleChip('Office', UserRole.office),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 2. Staff Login Dropdown (Keyed per selectedUser so state never goes stale!)
              if (filteredStaff.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.subtleSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: const Text(
                    'No active staff logins found for this role.',
                    style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  key: ValueKey('assign_login_${_roleFilter?.name ?? "all"}_${selectedUser?.id}'),
                  initialValue: selectedUser?.id,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Select Login Account',
                    prefixIcon: selectedUser != null
                        ? Icon(_roleIcon(selectedUser.role), color: _roleColor(selectedUser.role), size: 19)
                        : const Icon(Icons.person_outline),
                  ),
                  items: filteredStaff.map((u) {
                    final color = _roleColor(u.role);
                    return DropdownMenuItem<String>(
                      value: u.id,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${u.plainName} (${u.roleDisplayName})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              u.assignedRouteIds.isEmpty ? 'All' : '${u.assignedRouteIds.length}',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      final matched = filteredStaff.where((u) => u.id == val).firstOrNull;
                      _selectUser(matched);
                    }
                  },
                ),
              const SizedBox(height: 12),

              // 3. Route Header & Bulk Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _selectedRoutes.isEmpty
                        ? 'All Routes (${allRoutes.length}) Accessible'
                        : 'Selected: ${_selectedRoutes.length} of ${allRoutes.length}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppTheme.primary),
                  ),
                  Row(
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () {
                          setState(() {
                            _selectedRoutes = allRoutes.map((r) => r.id).toList();
                          });
                        },
                        child: const Text('All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () {
                          setState(() => _selectedRoutes.clear());
                        },
                        child: const Text('Clear', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.balanceDueColor)),
                      ),
                    ],
                  ),
                ],
              ),

              // Search Routes Field
              TextField(
                controller: _routeSearchCtrl,
                onChanged: (v) => setState(() => _routeQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search route...',
                  prefixIcon: const Icon(Icons.search, size: 17),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  suffixIcon: _routeQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _routeSearchCtrl.clear();
                            setState(() => _routeQuery = '');
                          },
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 8),

              // 4. Route Checklist
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: filteredRoutes.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No matching routes found.', style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: filteredRoutes.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, idx) {
                          final RouteModel route = filteredRoutes[idx];
                          final isChecked = _selectedRoutes.contains(route.id);
                          final outletCount = provider.allShops.where((s) => s.routeId == route.id).length;
                          final otherAssignees = allStaff
                              .where((u) => u.id != selectedUser?.id && u.assignedRouteIds.contains(route.id))
                              .map((u) => u.plainName)
                              .take(2)
                              .toList();

                          return CheckboxListTile(
                            dense: true,
                            value: isChecked,
                            activeColor: AppTheme.manasPrimary,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              route.name,
                              style: TextStyle(
                                fontWeight: isChecked ? FontWeight.w700 : FontWeight.w600,
                                fontSize: 13,
                                color: isChecked ? AppTheme.manasPrimary : AppTheme.primary,
                              ),
                            ),
                            subtitle: Text(
                              otherAssignees.isEmpty
                                  ? '$outletCount outlets'
                                  : '$outletCount outlets • Assigned: ${otherAssignees.join(', ')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  if (!_selectedRoutes.contains(route.id)) {
                                    _selectedRoutes.add(route.id);
                                  }
                                } else {
                                  _selectedRoutes.remove(route.id);
                                }
                              });
                            },
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
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (selectedUser != null && filteredStaff.length > 1)
          OutlinedButton(
            onPressed: _isSaving
                ? null
                : () async {
                    final target = selectedUser!;
                    final ok = await _saveSelectedUser(target);
                    if (!context.mounted) return;
                    if (ok) {
                      QuickAlert.success(
                        context,
                        'Saved ${_selectedRoutes.isEmpty ? "All Routes" : "${_selectedRoutes.length} route(s)"} for ${target.plainName}',
                      );
                      final currIdx = filteredStaff.indexWhere((u) => u.id == target.id);
                      final next = filteredStaff[(currIdx + 1) % filteredStaff.length];
                      _selectUser(next);
                    }
                  },
            child: const Text('Save & Next'),
          ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.manasPrimary),
          onPressed: (selectedUser == null || _isSaving)
              ? null
              : () async {
                  final target = selectedUser!;
                  final ok = await _saveSelectedUser(target);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  if (ok) {
                    QuickAlert.success(
                      context,
                      'Assigned ${_selectedRoutes.isEmpty ? "All Routes" : "${_selectedRoutes.length} route(s)"} to ${target.plainName}',
                    );
                  }
                },
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save Routes'),
        ),
      ],
    );
  }

  Widget _buildRoleChip(String label, UserRole? role) {
    final isSelected = _roleFilter == role;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      visualDensity: VisualDensity.compact,
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
        color: isSelected ? Colors.white : AppTheme.primary,
      ),
      selectedColor: AppTheme.purvaPrimary,
      backgroundColor: AppTheme.subtleSurface,
      side: BorderSide(color: isSelected ? AppTheme.purvaPrimary : AppTheme.border),
      onSelected: (_) {
        setState(() {
          _roleFilter = role;
          final candidates = _getAssignableUsers(context.read<AuthProvider>().users)
              .where((u) => role == null || u.role == role)
              .toList();
          if (candidates.isNotEmpty) {
            _selectedUserId = candidates.first.id;
            _selectedRoutes = List<String>.from(candidates.first.assignedRouteIds);
          } else {
            _selectedUserId = null;
            _selectedRoutes = [];
          }
        });
      },
    );
  }
}
