import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/pending_bill_model.dart';
import '../models/shop_model.dart';
import '../providers/collection_provider.dart';
import '../utils/theme.dart';
import '../widgets/fullscreen_image_viewer.dart';
import '../utils/image_compress_helper.dart';
import 'add_shop_screen.dart';
import 'pending_bills_list_screen.dart';
import '../utils/marathi_search_helper.dart';
import '../utils/quick_alert.dart';
import '../widgets/in_app_bill_camera_screen.dart';
import '../services/bill_ocr_service.dart';
import '../services/party_name_matcher.dart';

class AddPendingBillScreen extends StatefulWidget {
  final String? initialRouteId;
  final String? initialShopId;
  final DateTime? initialInvoiceDate;
  final String? initialBusiness;

  const AddPendingBillScreen({
    super.key,
    this.initialRouteId,
    this.initialShopId,
    this.initialInvoiceDate,
    this.initialBusiness,
  });

  @override
  State<AddPendingBillScreen> createState() => _AddPendingBillScreenState();
}

class _AddPendingBillScreenState extends State<AddPendingBillScreen> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();

  // Static in-memory retention across screen navigations (ONLY Route and Shop - NO Dates!)
  static String? lastUsedRouteId;
  static String? lastUsedShopId;

  String _selectedBusiness = 'Purva Enterprises';
  String? _selectedRouteId;
  String? _selectedShopId;

  // Invoice Date & Delivery Date (NO DEFAULT - Must be freshly selected per bill)
  DateTime? _invoiceDate;
  DateTime? _deliveryDate;

  final _billNoController = TextEditingController();
  final _amountController = TextEditingController();

  final List<String> _photosBase64 = [];
  final Map<String, Uint8List> _photoBytesCache = {};
  bool _isSaving = false;

  // OCR Extraction state
  bool _isExtracting = false;
  String? _ocrStatusText;
  String? _extractedPartyRawName;
  ShopMatchResult? _matchedShopResult;

  @override
  void initState() {
    super.initState();
    _selectedBusiness = widget.initialBusiness ?? 'Purva Enterprises';
    _selectedRouteId = widget.initialRouteId ?? lastUsedRouteId;
    _selectedShopId = widget.initialShopId ?? lastUsedShopId;
    _invoiceDate = widget.initialInvoiceDate;
    _deliveryDate = null;
    _loadPersistedDefaults();
  }

  Future<void> _loadPersistedDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedRoute = prefs.getString('last_pending_bill_route_id');
      final savedShop = prefs.getString('last_pending_bill_shop_id');

      if (mounted) {
        setState(() {
          if (_selectedRouteId == null && savedRoute != null && savedRoute.isNotEmpty) {
            _selectedRouteId = savedRoute;
            lastUsedRouteId = savedRoute;
          }
          if (_selectedShopId == null && savedShop != null && savedShop.isNotEmpty) {
            _selectedShopId = savedShop;
            lastUsedShopId = savedShop;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _persistDefaults(String routeId, String shopId) async {
    lastUsedRouteId = routeId;
    lastUsedShopId = shopId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_pending_bill_route_id', routeId);
      await prefs.setString('last_pending_bill_shop_id', shopId);
    } catch (_) {}
  }

  @override
  void dispose() {
    _billNoController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickInvoiceDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'SELECT INVOICE DATE',
    );
    if (picked != null) {
      setState(() => _invoiceDate = picked);
    }
  }

  Future<void> _pickDeliveryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deliveryDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'SELECT DELIVERY DATE',
    );
    if (picked != null) {
      setState(() => _deliveryDate = picked);
    }
  }

  Future<void> _extractDetailsFromPhoto(String base64Photo) async {
    setState(() {
      _isExtracting = true;
      _ocrStatusText = 'Extracting bill details...';
    });

    try {
      final provider = context.read<CollectionProvider>();
      final candidateShops = (_selectedRouteId != null && _selectedRouteId!.isNotEmpty)
          ? provider.getShopsForRoute(_selectedRouteId!)
          : provider.shops;

      final result = await BillOcrService.processBillImage(
        base64Image: base64Photo,
        candidateShops: candidateShops,
      );

      if (mounted) {
        setState(() {
          _isExtracting = false;
          _ocrStatusText = null;

          if (result.success) {
            // Bill Number
            if (result.billNumber != null && result.billNumber!.isNotEmpty) {
              _billNoController.text = result.billNumber!;
            }

            // Dates: Invoice Date & Delivery Date
            if (result.billDate != null) {
              _invoiceDate = result.billDate;
              _deliveryDate ??= result.billDate;
            }

            // Amount
            if (result.amount != null && result.amount! > 0) {
              _amountController.text = result.amount!.toStringAsFixed(0);
            }

            // Extracted English Party Name
            if (result.extractedPartyName != null && result.extractedPartyName!.isNotEmpty) {
              _extractedPartyRawName = result.extractedPartyName;
            }

            // Matched Marathi Shop from selected route
            if (result.matchedShop != null) {
              _selectedShopId = result.matchedShop!.id;
              _matchedShopResult = ShopMatchResult(
                shop: result.matchedShop!,
                score: result.matchScore,
                matchedExplanation: result.matchExplanation ?? '',
              );
              if (_selectedRouteId == null || _selectedRouteId!.isEmpty) {
                _selectedRouteId = result.matchedShop!.routeId;
              }
            }
          }
        });

        if (result.hasAnyExtractedField) {
          QuickAlert.success(context, 'Details extracted from bill. Please verify.');
        } else if (result.errorMessage != null) {
          QuickAlert.info(context, result.errorMessage!);
        }
      }
    } catch (e) {
      debugPrint('Extraction error: $e');
      if (mounted) {
        setState(() {
          _isExtracting = false;
          _ocrStatusText = null;
        });
      }
    }
  }

  Future<void> _captureBillPhoto() async {
    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const InAppBillCameraScreen(),
          fullscreenDialog: true,
        ),
      );

      if (result != null && mounted) {
        String? firstNewPhoto;
        setState(() {
          if (result is List<String> && result.isNotEmpty) {
            _photosBase64.addAll(result);
            firstNewPhoto = result.first;
          } else if (result is String && result.isNotEmpty) {
            _photosBase64.add(result);
            firstNewPhoto = result;
          }
        });

        if (firstNewPhoto != null) {
          await _extractDetailsFromPhoto(firstNewPhoto!);
        }
      }
    } catch (e) {
      debugPrint('Error capturing bill photo: $e');
      if (mounted) {
        QuickAlert.error(context, 'Could not open camera: $e');
      }
    }
  }

  Future<void> _pickGalleryPhoto() async {
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 82,
      );
      if (picked != null && mounted) {
        final bytes = await picked.readAsBytes();
        final b64 = base64Encode(bytes);
        setState(() {
          _photosBase64.add(b64);
        });
        await _extractDetailsFromPhoto(b64);
      }
    } catch (e) {
      debugPrint('Gallery pick error: $e');
    }
  }

  Future<void> _showOcrSettingsDialog() async {
    final existingKey = await BillOcrService.getApiKey() ?? '';
    final controller = TextEditingController(text: existingKey);
    bool obscure = true;

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.auto_awesome, color: AppTheme.primary, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Bill Scanner & AI Setup',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Fast on-device scanner runs automatically without internet.\nOptionally add a Google Gemini API Key for instant 1-second cloud AI extraction.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'Gemini API Key (Optional)',
                    hintText: 'AIzaSy...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, size: 18),
                          onPressed: () => setModalState(() => obscure = !obscure),
                        ),
                        if (controller.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setModalState(() => controller.clear()),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (existingKey.isNotEmpty) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            await BillOcrService.saveApiKey('');
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              QuickAlert.info(context, 'AI Key removed. Fast on-device scanner active.');
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.error,
                            side: const BorderSide(color: AppTheme.error),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Clear Key'),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.save, size: 18),
                        label: const Text('Save & Apply', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          final key = controller.text.trim();
                          await BillOcrService.saveApiKey(key);
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            if (key.isNotEmpty) {
                              QuickAlert.success(context, 'AI Key saved! Scans will use Google Gemini Vision.');
                            } else {
                              QuickAlert.info(context, 'Using fast on-device scanner.');
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Searchable Outlet Picker Dialog / BottomSheet
  void _openSearchableShopPicker(List<ShopModel> shops) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = shops.where((s) {
              if (query.isEmpty) return true;
              final q = query.toLowerCase();
              return MarathiSearchHelper.matches(s.name, q) ||
                  s.mobileNumber.contains(q) ||
                  MarathiSearchHelper.matches(s.address, q);
            }).toList();

            return Padding(
              padding: EdgeInsets.only(
                top: 16,
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.65,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Select Outlet / Shop',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search outlet by name, phone...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      onChanged: (val) {
                        setModalState(() => query = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.storefront_outlined, size: 40, color: Colors.blueGrey.shade300),
                                  const SizedBox(height: 8),
                                  Text(
                                    query.isEmpty
                                        ? 'No stores in this beat'
                                        : 'No stores match "$query"',
                                    style: TextStyle(color: Colors.blueGrey.shade600),
                                  ),
                                  const SizedBox(height: 10),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.add, size: 16),
                                    label: const Text('Add New Store'),
                                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                                    onPressed: () {
                                      Navigator.pop(ctx);
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
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (context, idx) {
                                final s = filtered[idx];
                                final isSelected = s.id == _selectedShopId;
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  leading: CircleAvatar(
                                    backgroundColor: isSelected ? AppTheme.primary : Colors.grey.shade200,
                                    foregroundColor: isSelected ? Colors.white : Colors.blueGrey.shade800,
                                    child: Text(s.name.isNotEmpty ? s.name[0].toUpperCase() : 'S'),
                                  ),
                                  title: Text(
                                    s.name,
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                      color: isSelected ? AppTheme.primary : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${s.mobileNumber} • ${s.address}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                                  ),
                                  trailing: isSelected
                                      ? const Icon(Icons.check_circle, color: AppTheme.primary)
                                      : null,
                                  onTap: () {
                                    setState(() {
                                      _selectedShopId = s.id;
                                    });
                                    if (_selectedRouteId != null) {
                                      _persistDefaults(_selectedRouteId!, s.id);
                                    }
                                    Navigator.pop(ctx);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _savePendingBill() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedRouteId == null || _selectedRouteId!.isEmpty) {
      QuickAlert.error(context, 'Please select a route beat');
      return;
    }

    if (_selectedShopId == null || _selectedShopId!.isEmpty) {
      QuickAlert.error(context, 'Please select an outlet / shop');
      return;
    }

    if (_invoiceDate == null) {
      QuickAlert.error(context, 'Please select Invoice Date');
      return;
    }

    if (_deliveryDate == null) {
      QuickAlert.error(context, 'Please select Delivery Date');
      return;
    }

    final billNo = _billNoController.text.trim();
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (amount <= 0) {
      QuickAlert.error(context, 'Please enter a valid bill amount');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final provider = context.read<CollectionProvider>();
      final shop = provider.getShopById(_selectedShopId!);
      final route = provider.routes.firstWhere(
        (r) => r.id == _selectedRouteId,
        orElse: () => provider.routes.first,
      );

      final newPendingBill = PendingBillModel(
        id: _uuid.v4(),
        businessName: _selectedBusiness,
        routeId: route.id,
        routeName: route.name,
        shopId: shop?.id ?? _selectedShopId!,
        shopName: shop?.name ?? 'Unknown Outlet',
        invoiceDate: _invoiceDate!,
        deliveryDate: _deliveryDate!,
        billNumber: billNo,
        totalAmount: amount,
        collectedAmount: 0.0,
        photoBase64: _photosBase64.isNotEmpty ? _photosBase64.first : null,
        photosBase64: _photosBase64,
        status: 'pending',
        createdAt: DateTime.now(),
      );

      provider.addPendingBill(newPendingBill);
      _persistDefaults(route.id, shop?.id ?? _selectedShopId!);

      if (mounted) {
        QuickAlert.success(context, 'Bill No: $billNo (₹${amount.toStringAsFixed(0)}) saved!');
        Navigator.pop(context, newPendingBill);
      }
    } catch (e) {
      if (mounted) {
        QuickAlert.error(context, 'Error saving pending bill: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CollectionProvider>();
    final routes = provider.routes;

    // Set initial route if none selected
    if (_selectedRouteId == null && routes.isNotEmpty) {
      if (lastUsedRouteId != null && routes.any((r) => r.id == lastUsedRouteId)) {
        _selectedRouteId = lastUsedRouteId;
      } else {
        _selectedRouteId = routes.first.id;
      }
    }

    final shopsInRoute = provider.getShopsForRoute(_selectedRouteId ?? '');
    if (_selectedShopId == null && lastUsedShopId != null) {
      if (shopsInRoute.any((s) => s.id == lastUsedShopId)) {
        _selectedShopId = lastUsedShopId;
      }
    }
    if (_selectedShopId != null && !shopsInRoute.any((s) => s.id == _selectedShopId)) {
      _selectedShopId = null;
    }

    final selectedShop = _selectedShopId != null ? provider.getShopById(_selectedShopId!) : null;

    final isPurva = _selectedBusiness == 'Purva Enterprises';
    final firmPrimaryColor = isPurva ? AppTheme.purvaPrimary : AppTheme.manasPrimary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Bill'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'View Pending Bills',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PendingBillsListScreen()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. FIRM SELECTOR (Purva Enterprises / Manas Sales)
              const Text(
                '1. SELECT FIRM',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: Colors.blueGrey,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedBusiness = 'Purva Enterprises';
                            if (_selectedRouteId == null && lastUsedRouteId != null) {
                              _selectedRouteId = lastUsedRouteId;
                            }
                            if (_selectedShopId == null && lastUsedShopId != null) {
                              _selectedShopId = lastUsedShopId;
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isPurva ? AppTheme.purvaPrimary : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'Purva Enterprises',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isPurva ? Colors.white : AppTheme.purvaText,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedBusiness = 'Manas Sales';
                            if (_selectedRouteId == null && lastUsedRouteId != null) {
                              _selectedRouteId = lastUsedRouteId;
                            }
                            if (_selectedShopId == null && lastUsedShopId != null) {
                              _selectedShopId = lastUsedShopId;
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: !isPurva ? AppTheme.manasPrimary : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'Manas Sales',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: !isPurva ? Colors.white : AppTheme.manasText,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 2. ROUTE SELECTOR
              const Text(
                '2. SELECT ROUTE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: Colors.blueGrey,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedRouteId,
                    hint: const Text('Choose Beat Route'),
                    items: routes.map((r) {
                      final count = provider.getShopsForRoute(r.id).length;
                      return DropdownMenuItem<String>(
                        value: r.id,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              r.name,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            Text(
                              '$count stores',
                              style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedRouteId = val;
                        _selectedShopId = null; // reset outlet on route change
                        if (val != null) {
                          lastUsedRouteId = val;
                          lastUsedShopId = null;
                        }
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // 3. BILL PHOTO (CAPTURE & AUTO EXTRACT)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        '3. BILL PHOTO (${_photosBase64.length})',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: Colors.blueGrey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: _showOcrSettingsDialog,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.auto_awesome, size: 12, color: AppTheme.primary),
                              SizedBox(width: 3),
                              Text(
                                'AI Setup',
                                style: TextStyle(fontSize: 10.5, color: AppTheme.primary, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_photosBase64.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_sweep_outlined, size: 16, color: AppTheme.error),
                      label: const Text('Clear', style: TextStyle(color: AppTheme.error, fontSize: 12)),
                      onPressed: () => setState(() {
                        _photosBase64.clear();
                        _extractedPartyRawName = null;
                        _matchedShopResult = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              if (_photosBase64.isEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.camera_alt_rounded, size: 18),
                              label: const Text(
                                'Take Photo',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F172A),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: _captureBillPhoto,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.photo_library_outlined, size: 18),
                              label: const Text(
                                'Upload File',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF0F172A),
                                side: BorderSide(color: Colors.grey.shade400),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: _pickGalleryPhoto,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Select route first, then click photo to auto-extract details',
                        style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade600),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Photo Preview & Extraction Status
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Extraction in progress indicator
                      if (_isExtracting) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2563EB)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _ocrStatusText ?? 'Extracting bill number, date, amount & party name...',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF1D4ED8), fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (_extractedPartyRawName != null || _billNoController.text.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, size: 16, color: Color(0xFF059669)),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Details extracted from bill. Review and edit any field below.',
                                  style: TextStyle(fontSize: 12, color: Color(0xFF065F46), fontWeight: FontWeight.w600),
                                ),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () {
                                  if (_photosBase64.isNotEmpty) {
                                    _extractDetailsFromPhoto(_photosBase64.first);
                                  }
                                },
                                child: const Text(
                                  'Re-scan',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Multi-photo horizontal thumbnail strip
                      SizedBox(
                        height: 100,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _photosBase64.length,
                          itemBuilder: (ctx, idx) {
                            final photo = _photosBase64[idx];
                            final bytes = _photoBytesCache.putIfAbsent(
                              photo,
                              () => ImageCompressHelper.safeBase64Decode(photo) ?? Uint8List(0),
                            );
                            return Container(
                              width: 85,
                              margin: const EdgeInsets.only(right: 10),
                              child: Stack(
                                children: [
                                  InkWell(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => FullScreenImageViewer(
                                            imagesBase64: _photosBase64,
                                            initialIndex: idx,
                                            title: 'Bill Photo Preview',
                                            subtitle: 'Photo ${idx + 1} of ${_photosBase64.length}',
                                          ),
                                        ),
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.grey.shade300),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: bytes.isNotEmpty
                                                ? Image.memory(
                                                    bytes,
                                                    width: 85,
                                                    fit: BoxFit.cover,
                                                  )
                                                : Container(
                                                    color: Colors.grey.shade200,
                                                    child: const Icon(Icons.broken_image, size: 24),
                                                  ),
                                          ),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(vertical: 2),
                                            color: const Color(0xFF0F172A),
                                            alignment: Alignment.center,
                                            child: Text(
                                              'Photo ${idx + 1}',
                                              style: const TextStyle(
                                                fontSize: 9.5,
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 2,
                                    right: 2,
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _photosBase64.removeAt(idx);
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          size: 12,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.camera_alt_outlined, size: 16),
                              label: const Text('+ Add Photo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _captureBillPhoto,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.photo_library_outlined, size: 16),
                              label: const Text('+ Add File', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _pickGalleryPhoto,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),

              // 4. OUTLET (SHOP) ACCORDING TO ROUTE (WITH SEARCH OPTION)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '4. OUTLET / SHOP NAME',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Colors.blueGrey,
                    ),
                  ),
                  InkWell(
                    onTap: () => _openSearchableShopPicker(shopsInRoute),
                    child: Row(
                      children: const [
                        Icon(Icons.search, size: 14, color: AppTheme.primary),
                        SizedBox(width: 4),
                        Text(
                          'Search Outlets',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Outlet selector tile
              InkWell(
                onTap: () => _openSearchableShopPicker(shopsInRoute),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selectedShop != null ? firmPrimaryColor : AppTheme.border,
                      width: selectedShop != null ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: firmPrimaryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Icon(Icons.storefront, color: firmPrimaryColor, size: 20),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: selectedShop != null
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        selectedShop.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      Text(
                                        '${selectedShop.mobileNumber} • ${selectedShop.address}',
                                        style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  )
                                : Text(
                                    'Tap to choose outlet (Searchable)',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.blueGrey.shade400,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                          ),
                          const Icon(Icons.arrow_drop_down, color: Colors.blueGrey),
                        ],
                      ),
                      // If party was extracted from bill, show the source info
                      if (_extractedPartyRawName != null && _extractedPartyRawName!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.amber.shade300),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.auto_awesome, size: 12, color: Color(0xFFB45309)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _matchedShopResult != null && _matchedShopResult!.matchedExplanation.isNotEmpty
                                      ? 'Matched: "$_extractedPartyRawName" (${_matchedShopResult!.matchedExplanation})'
                                      : 'Matched from bill text: "$_extractedPartyRawName"',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF92400E), fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // 5. BILL NUMBER
              const Text(
                '5. BILL NUMBER',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: Colors.blueGrey,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _billNoController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: isPurva ? 'e.g. PE-5042' : 'e.g. MS-3021',
                  prefixIcon: const Icon(Icons.receipt_outlined, size: 20),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter bill / invoice number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),

              // 6. INVOICE DATE & DELIVERY DATE
              const Text(
                '6. BILL DATES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: Colors.blueGrey,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  // Invoice Date
                  Expanded(
                    child: InkWell(
                      onTap: _pickInvoiceDate,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _invoiceDate != null ? AppTheme.primary : AppTheme.error,
                            width: _invoiceDate != null ? 1.0 : 1.2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.calendar_today_outlined, size: 14, color: AppTheme.primary),
                                SizedBox(width: 6),
                                Text(
                                  'Invoice Date *',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _invoiceDate != null
                                  ? DateFormat('dd MMM yyyy').format(_invoiceDate!)
                                  : 'Select Date',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _invoiceDate != null ? const Color(0xFF0F172A) : AppTheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Delivery Date
                  Expanded(
                    child: InkWell(
                      onTap: _pickDeliveryDate,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _deliveryDate != null ? AppTheme.secondary : AppTheme.error,
                            width: _deliveryDate != null ? 1.0 : 1.2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.local_shipping_outlined, size: 14, color: AppTheme.secondary),
                                SizedBox(width: 6),
                                Text(
                                  'Delivery Date *',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _deliveryDate != null
                                  ? DateFormat('dd MMM yyyy').format(_deliveryDate!)
                                  : 'Select Date',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _deliveryDate != null ? const Color(0xFF0F172A) : AppTheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // 7. TOTAL BILL AMOUNT
              const Text(
                '7. TOTAL BILL AMOUNT (₹)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: Colors.blueGrey,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  prefixStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.primary),
                  hintText: '0.00',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter total bill amount';
                  }
                  final parsed = double.tryParse(val.trim());
                  if (parsed == null || parsed <= 0) {
                    return 'Amount must be greater than zero';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 28),

              // SAVE BUTTON (Single, clean button)
              ElevatedButton.icon(
                icon: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_circle_outline, size: 20),
                label: Text(
                  _isSaving ? 'Saving...' : 'Save Pending Bill',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: firmPrimaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 2,
                ),
                onPressed: _isSaving ? null : _savePendingBill,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
