import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/collection_provider.dart';
import '../services/firebase_service.dart';
import '../utils/theme.dart';

class FirebaseConfigDialog extends StatefulWidget {
  const FirebaseConfigDialog({super.key});

  @override
  State<FirebaseConfigDialog> createState() => _FirebaseConfigDialogState();
}

class _FirebaseConfigDialogState extends State<FirebaseConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _projectIdController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _appIdController;
  late final TextEditingController _storageBucketController;

  bool _isConnecting = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    final currentConfig = FirebaseService().config;
    _projectIdController = TextEditingController(text: currentConfig?.projectId ?? '');
    _apiKeyController = TextEditingController(text: currentConfig?.apiKey ?? '');
    _appIdController = TextEditingController(text: currentConfig?.appId ?? '');
    _storageBucketController = TextEditingController(text: currentConfig?.storageBucket ?? '');
  }

  @override
  void dispose() {
    _projectIdController.dispose();
    _apiKeyController.dispose();
    _appIdController.dispose();
    _storageBucketController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isConnecting = true;
      _statusMessage = null;
    });

    final config = FirebaseConfig(
      projectId: _projectIdController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      appId: _appIdController.text.trim(),
      messagingSenderId: '978582714167',
      storageBucket: _storageBucketController.text.trim().isEmpty
          ? '${_projectIdController.text.trim()}.firebasestorage.app'
          : _storageBucketController.text.trim(),
    );

    final success = await context.read<CollectionProvider>().connectFirebase(config);

    if (mounted) {
      setState(() {
        _isConnecting = false;
        _statusMessage = success
            ? 'Connected to Firebase Cloud Firestore successfully!'
            : 'Could not connect: ${FirebaseService().lastError ?? "Check configuration"}';
      });

      if (success) {
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) Navigator.pop(context);
        });
      }
    }
  }

  Future<void> _disconnect() async {
    await context.read<CollectionProvider>().disconnectFirebase();
    if (mounted) {
      setState(() {
        _statusMessage = 'Disconnected from Firebase. Switched to offline local storage.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CollectionProvider>();
    final isConnected = provider.isFirebaseConnected;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isConnected
                          ? const Color(0xFF10B981).withValues(alpha: 0.15)
                          : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isConnected ? Icons.cloud_done_outlined : Icons.cloud_sync_outlined,
                      color: isConnected ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Firebase Cloud Database',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          isConnected ? 'Cloud Firestore Active & Connected' : 'Local Fast Mode (Offline Ready)',
                          style: TextStyle(
                            fontSize: 12,
                            color: isConnected ? const Color(0xFF10B981) : Colors.blueGrey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Status Banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isConnected
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isConnected
                        ? const Color(0xFFA7F3D0)
                        : AppTheme.border,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isConnected ? Icons.check_circle : Icons.info_outline,
                      size: 18,
                      color: isConnected ? const Color(0xFF059669) : Colors.blueGrey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isConnected
                            ? 'All records and invoice images are backed up live to Cloud Firestore & Storage.'
                            : 'All records are saved instantly to fast offline storage with 0 delay. Enter your Firebase project credentials below to enable live cloud sync.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isConnected ? const Color(0xFF065F46) : Colors.blueGrey.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_statusMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isConnected
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isConnected
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444),
                    ),
                  ),
                  child: Text(
                    _statusMessage!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isConnected ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Configuration Form
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _projectIdController,
                      decoration: const InputDecoration(
                        labelText: 'Firebase Project ID *',
                        hintText: 'e.g. daily-collection-agency',
                        prefixIcon: Icon(Icons.corporate_fare, size: 20),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _apiKeyController,
                      decoration: const InputDecoration(
                        labelText: 'Firebase Web API Key *',
                        hintText: 'e.g. AIzaSy...',
                        prefixIcon: Icon(Icons.key, size: 20),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _appIdController,
                      decoration: const InputDecoration(
                        labelText: 'Firebase App ID *',
                        hintText: 'e.g. 1:123456789:web:abcdef',
                        prefixIcon: Icon(Icons.apps, size: 20),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _storageBucketController,
                      decoration: const InputDecoration(
                        labelText: 'Storage Bucket (Optional)',
                        hintText: 'e.g. daily-collection-agency.appspot.com',
                        prefixIcon: Icon(Icons.cloud_upload_outlined, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (isConnected) ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.cloud_upload_outlined, size: 20),
                  label: const Text('Push All Local Records to Firestore Now'),
                  onPressed: () async {
                    setState(() {
                      _isConnecting = true;
                      _statusMessage = null;
                    });
                    final ok = await context.read<CollectionProvider>().syncAllToCloud();
                    if (mounted) {
                      setState(() {
                        _isConnecting = false;
                        _statusMessage = ok
                            ? 'Successfully pushed all collections, shops, and routes to Firestore!'
                            : 'Sync failed: check your network';
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],

              // Action Buttons
              Row(
                children: [
                  if (isConnected) ...[
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.balanceDueColor,
                          side: const BorderSide(color: AppTheme.balanceDueColor),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        onPressed: _isConnecting ? null : _disconnect,
                        child: const Text('Disconnect'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: _isConnecting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.cloud_sync, size: 18),
                      label: Text(_isConnecting ? 'Connecting...' : (isConnected ? 'Update Config' : 'Connect Firebase')),
                      onPressed: _isConnecting ? null : _connect,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
