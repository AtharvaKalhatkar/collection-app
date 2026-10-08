import 'package:flutter/material.dart';
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
  String? get _photoBase64 => _photosBase64.isNotEmpty ? _photosBase64.first : null;
  bool _isSaving = false;

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

  Future<void> _captureBillPhoto() async {
    try {
      final photoBase64 = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => const InAppBillCameraScreen(),
          fullscreenDialog: true,
        ),
      );

      if (photoBase64 != null && photoBase64.isNotEmpty && mounted) {
        setState(() {
          _photosBase64.add(photoBase64);
        });
        QuickAlert.success(context, 'Bill photo added');
      }
    } catch (e) {
      debugPrint('Error capturing bill photo: $e');
      if (mounted) {
        QuickAlert.error(context, 'Could not open camera: $e');
      }
    }
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
        photoBase64: _photoBase64,
        photosBase64: _photosBase64,
        status: 'pending',
        createdAt: DateTime.now(),
      );

      await provider.addPendingBill(newPendingBill);
      await _persistDefaults(route.id, shop?.id ?? _selectedShopId!);

      if (mounted) {
        QuickAlert.success(context, 'Bill #$billNo (₹${amount.toStringAsFixed(0)}) saved!');
        Navigator.pop(context);
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

              // 3. OUTLET (SHOP) ACCORDING TO ROUTE (WITH SEARCH OPTION)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '3. SELECT OUTLET / SHOP',
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
                  child: Row(
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
                ),
              ),
              const SizedBox(height: 18),

              // 4. INVOICE DATE & DELIVERY DATE (NO DEFAULT DATE)
              const Text(
                '4. BILL DATES (NO DEFAULT DATE)',
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

              // 6. TOTAL BILL AMOUNT
              const Text(
                '6. TOTAL BILL AMOUNT (₹)',
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
              const SizedBox(height: 18),

              // 7. UPLOAD BILL PHOTOS (Supports Multiple Pages / Proofs)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '7. UPLOAD BILL PHOTOS (${_photosBase64.length})',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Colors.blueGrey,
                    ),
                  ),
                  if (_photosBase64.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_sweep_outlined, size: 16, color: AppTheme.error),
                      label: const Text('Clear All', style: TextStyle(color: AppTheme.error, fontSize: 12)),
                      onPressed: () => setState(() => _photosBase64.clear()),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              if (_photosBase64.isEmpty) ...[
                // Clean Single Camera Button (Camera with Gallery in system chooser)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.camera_alt_rounded, size: 20),
                        label: const Text(
                          'Open Camera',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 1,
                        ),
                        onPressed: _captureBillPhoto,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Live bill camera with gallery inside',
                        style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade600),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Multi-photo horizontal thumbnail preview
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
                      SizedBox(
                        height: 115,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _photosBase64.length,
                          itemBuilder: (ctx, idx) {
                            final photo = _photosBase64[idx];
                            final bytes = ImageCompressHelper.safeBase64Decode(photo);
                            return Container(
                              width: 95,
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
                                            subtitle: 'Page ${idx + 1} of ${_photosBase64.length}',
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
                                            child: bytes != null
                                                ? Image.memory(
                                                    bytes,
                                                    width: 95,
                                                    fit: BoxFit.cover,
                                                  )
                                                : Container(
                                                    color: Colors.grey.shade200,
                                                    child: const Icon(Icons.broken_image, size: 24),
                                                  ),
                                          ),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(vertical: 3),
                                            color: const Color(0xFF0F172A),
                                            alignment: Alignment.center,
                                            child: Text(
                                              'Photo ${idx + 1}',
                                              style: const TextStyle(
                                                fontSize: 10,
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
                                    top: 3,
                                    right: 3,
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
                                          size: 13,
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
                      const Divider(height: 18),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.camera_alt_outlined, size: 16),
                        label: const Text('+ Add Another Photo', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          minimumSize: const Size(double.infinity, 42),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _captureBillPhoto,
                      ),
                    ],
                  ),
                ),
              ],
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
