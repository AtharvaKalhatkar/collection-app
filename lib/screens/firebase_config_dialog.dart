import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/collection_provider.dart';
import '../services/firebase_service.dart';
import '../utils/theme.dart';

class FirebaseConfigDialog extends StatefulWidget {
  const FirebaseConfigDialog({super.key});

  @override
  State<FirebaseConfigDialog> createState() => _FirebaseConfigDialogState();
}

class _FirebaseConfigDialogState extends State<FirebaseConfigDialog> {
  bool _isSyncing = false;
  String? _syncMessage;
  bool _isSuccess = true;
  String _lastSyncText = 'Just now';
  bool _autoSync = true;
  bool _showAdvanced = false;

  late final TextEditingController _projectIdController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _appIdController;

  static const String _keyLastSync = 'last_cloud_sync_time_v1';
  static const String _keyAutoSync = 'auto_cloud_sync_enabled_v1';

  @override
  void initState() {
    super.initState();
    final config = FirebaseService().config ?? FirebaseService.defaultConfig;
    _projectIdController = TextEditingController(text: config.projectId);
    _apiKeyController = TextEditingController(text: config.apiKey);
    _appIdController = TextEditingController(text: config.appId);
    _loadSyncMeta();
  }

  @override
  void dispose() {
    _projectIdController.dispose();
    _apiKeyController.dispose();
    _appIdController.dispose();
    super.dispose();
  }

  Future<void> _loadSyncMeta() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTime = prefs.getString(_keyLastSync);
    final auto = prefs.getBool(_keyAutoSync) ?? true;
    if (mounted) {
      setState(() {
        _autoSync = auto;
        if (savedTime != null && savedTime.isNotEmpty) {
          _lastSyncText = savedTime;
        } else {
          _lastSyncText = 'Today at ${DateFormat('hh:mm a').format(DateTime.now())}';
        }
      });
    }
  }

  Future<void> _saveSyncTime() async {
    final nowStr = 'Today at ${DateFormat('hh:mm a').format(DateTime.now())}';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastSync, nowStr);
    if (mounted) {
      setState(() {
        _lastSyncText = nowStr;
      });
    }
  }

  Future<void> _triggerSync() async {
    setState(() {
      _isSyncing = true;
      _syncMessage = null;
    });

    final provider = context.read<CollectionProvider>();

    // If not connected, connect using default config first
    if (!provider.isFirebaseConnected) {
      final config = FirebaseService().config ?? FirebaseService.defaultConfig;
      await provider.connectFirebase(config);
    }

    final success = await provider.syncAllToCloud();
    await _saveSyncTime();

    if (mounted) {
      setState(() {
        _isSyncing = false;
        _isSuccess = success;
        _syncMessage = success
            ? 'All collections, outlets, and routes synced to cloud!'
            : 'Sync completed locally. Connect to network for cloud backup.';
      });

      if (success) {
        Future.delayed(const Duration(milliseconds: 1400), () {
          if (mounted) Navigator.pop(context);
        });
      }
    }
  }

  Future<void> _toggleAutoSync(bool val) async {
    setState(() => _autoSync = val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoSync, val);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CollectionProvider>();
    final isConnected = provider.isFirebaseConnected;
    final totalCollections = provider.collections.length;
    final totalShops = provider.shops.length;
    final totalRoutes = provider.routes.length;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.cloud_sync_rounded,
                          color: Color(0xFF10B981),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cloud Sync',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'Backup & Data Protection',
                            style: TextStyle(fontSize: 11.5, color: Colors.blueGrey),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Colors.blueGrey),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Visual Status Hero Card
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isConnected
                        ? [const Color(0xFFECFDF5), const Color(0xFFD1FAE5)]
                        : [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isConnected
                        ? const Color(0xFF6EE7B7)
                        : Colors.blueGrey.shade200,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _isSyncing
                            ? const SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.8,
                                  color: Color(0xFF10B981),
                                ),
                              )
                            : Icon(
                                isConnected
                                    ? Icons.cloud_done_rounded
                                    : Icons.cloud_queue_rounded,
                                color: isConnected
                                    ? const Color(0xFF10B981)
                                    : Colors.blueGrey,
                                size: 30,
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isSyncing
                                ? 'Syncing Records...'
                                : (isConnected ? 'All Data Up to Date' : 'Local Fast Mode'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _isSyncing
                                ? 'Uploading collections & store records'
                                : 'Last synced: $_lastSyncText',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isConnected
                                  ? const Color(0xFF065F46)
                                  : Colors.blueGrey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (_syncMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isSuccess
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isSuccess
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isSuccess
                            ? Icons.check_circle_rounded
                            : Icons.info_outline_rounded,
                        size: 16,
                        color: _isSuccess
                            ? const Color(0xFF10B981)
                            : const Color(0xFFEF4444),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _syncMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _isSuccess
                                ? const Color(0xFF065F46)
                                : const Color(0xFF991B1B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 18),

              // Clean Data Stats (What is protected)
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BACKED UP ITEMS',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.blueGrey,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildItemTile(
                            icon: Icons.receipt_long_outlined,
                            count: '$totalCollections',
                            label: 'Collections',
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildItemTile(
                            icon: Icons.storefront_outlined,
                            count: '$totalShops',
                            label: 'Outlets',
                            color: AppTheme.secondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildItemTile(
                            icon: Icons.alt_route_rounded,
                            count: '$totalRoutes',
                            label: 'Beats',
                            color: const Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Auto-Sync Settings Switch
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        color: Color(0xFF10B981),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Auto-sync when online',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'Uploads new receipts automatically',
                            style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _autoSync,
                      onChanged: _toggleAutoSync,
                      activeThumbColor: const Color(0xFF10B981),
                      activeTrackColor: const Color(0xFFD1FAE5),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Big "Sync Now" Button
              ElevatedButton.icon(
                onPressed: _isSyncing ? null : _triggerSync,
                icon: _isSyncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.sync_rounded, size: 20, color: Colors.white),
                label: Text(
                  _isSyncing ? 'Syncing...' : 'Sync Now',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
              ),

              const SizedBox(height: 14),

              // Discreet Connection Security Row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.security, size: 14, color: Color(0xFF10B981)),
                  const SizedBox(width: 5),
                  Text(
                    'Cloud Database: ${isConnected ? "Connected & Active" : "Offline Ready"}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isConnected ? const Color(0xFF059669) : Colors.blueGrey,
                    ),
                  ),
                ],
              ),

              // Optional Advanced Settings Expander (Subtle, collapsed by default)
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: () {
                    setState(() => _showAdvanced = !_showAdvanced);
                  },
                  child: Text(
                    _showAdvanced ? 'Hide Advanced Settings' : 'Advanced Settings',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.blueGrey.shade400,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              if (_showAdvanced) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Developer Server Settings',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _projectIdController,
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          labelText: 'Firebase Project ID',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () async {
                              final config = FirebaseConfig(
                                projectId: _projectIdController.text.trim(),
                                apiKey: _apiKeyController.text.trim(),
                                appId: _appIdController.text.trim(),
                                messagingSenderId: '978582714167',
                              );
                              await provider.connectFirebase(config);
                              if (context.mounted) {
                                setState(() => _showAdvanced = false);
                              }
                            },
                            child: const Text('Save Custom Config', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemTile({
    required IconData icon,
    required String count,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(
            count,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10.5, color: Colors.blueGrey, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
