import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/collection_model.dart';
import '../models/shop_model.dart';
import '../models/bill_summary.dart';
import '../providers/collection_provider.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';
import '../utils/image_compress_helper.dart';
import 'add_shop_screen.dart';
import '../widgets/fullscreen_image_viewer.dart';

class RecordCollectionScreen extends StatefulWidget {
  final String? initialShopId;
  final String? initialBillNumber;
  final double? initialBillTotal;
  final double? initialBalanceDue;
  final String? initialBusiness;
  final bool isFollowUp;

  const RecordCollectionScreen({
    super.key,
    this.initialShopId,
    this.initialBillNumber,
    this.initialBillTotal,
    this.initialBalanceDue,
    this.initialBusiness,
    this.isFollowUp = false,
  });

  @override
  State<RecordCollectionScreen> createState() => _RecordCollectionScreenState();
}

class _RecordCollectionScreenState extends State<RecordCollectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();
  final _picker = ImagePicker();

  String? _selectedShopId;
  String _selectedBusiness = 'Purva Enterprises';
  final _billNoController = TextEditingController();
  final _billAmountController = TextEditingController();
  final _collectedAmountController = TextEditingController();
  PaymentMode _selectedMode = PaymentMode.cash;

  // Custom Bill Date & Collection Date (Default to Today)
  DateTime _billDate = DateTime.now();
  DateTime _collectionDate = DateTime.now();

  // Additional fields
  final _chequeNoController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _refNoController = TextEditingController();
  final _remarksController = TextEditingController();

  String? _photoBase64;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedShopId = widget.initialShopId;
    if (widget.initialBusiness != null) {
      _selectedBusiness = widget.initialBusiness!;
    }
    if (widget.initialBillNumber != null) {
      _billNoController.text = widget.initialBillNumber!;
    }
    if (widget.initialBillTotal != null && widget.initialBillTotal! > 0) {
      _billAmountController.text = widget.initialBillTotal!.toStringAsFixed(0);
    }
    if (widget.initialBalanceDue != null && widget.initialBalanceDue! > 0) {
      _collectedAmountController.text = widget.initialBalanceDue!.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _billNoController.dispose();
    _billAmountController.dispose();
    _collectedAmountController.dispose();
    _chequeNoController.dispose();
    _bankNameController.dispose();
    _refNoController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  double get _billAmount => double.tryParse(_billAmountController.text.trim()) ?? 0.0;
  double get _collectedAmount => double.tryParse(_collectedAmountController.text.trim()) ?? 0.0;

  BillSummary? _getExistingBill(CollectionProvider provider) {
    if (_selectedShopId == null || _billNoController.text.trim().isEmpty) return null;
    return provider.getBillSummary(_selectedShopId!, _billNoController.text.trim());
  }

  void _applyFullPayment(CollectionProvider provider) {
    final existing = _getExistingBill(provider);
    if (existing != null && existing.balanceDue > 0) {
      setState(() {
        _collectedAmountController.text = existing.balanceDue.toStringAsFixed(0);
      });
    } else if (_billAmountController.text.isNotEmpty) {
      setState(() {
        _collectedAmountController.text = _billAmountController.text;
      });
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _pickDate({required bool isBillDate}) async {
    final initial = isBillDate ? _billDate : _collectionDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: isBillDate ? 'SELECT INVOICE / BILL DATE' : 'SELECT COLLECTION DATE',
      confirmText: 'SELECT',
    );
    if (picked != null) {
      setState(() {
        if (isBillDate) {
          _billDate = picked;
        } else {
          _collectionDate = picked;
        }
      });
    }
  }

  Widget _buildDateTile({
    required String title,
    required String subtitle,
    required DateTime date,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isToday = _isSameDay(date, DateTime.now());
    final dateStr = DateFormat('dd MMM yyyy').format(date);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isToday ? AppTheme.border : AppTheme.primary,
            width: isToday ? 1.0 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: isToday ? Colors.blueGrey.shade600 : AppTheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isToday ? Colors.blueGrey.shade700 : AppTheme.primary,
                    ),
                  ),
                ),
                if (isToday)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: AppTheme.secondary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Today',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.secondary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              dateStr,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: Colors.blueGrey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source, {CameraDevice preferredCameraDevice = CameraDevice.rear}) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        preferredCameraDevice: preferredCameraDevice,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 50,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        if (mounted) {
          setState(() {
            _photoBase64 = ImageCompressHelper.compressToBase64(bytes);
          });
        }
      }
    } catch (e) {
      debugPrint('Camera error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.flip_camera_android, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Direct camera error detected. Opening device camera app with back camera...',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFD97706),
            duration: const Duration(seconds: 4),
          ),
        );

        // Fallback: automatically open device camera chooser so camera still opens after error!
        try {
          final fallback = await _picker.pickImage(
            source: ImageSource.gallery,
            maxWidth: 800,
            maxHeight: 800,
            imageQuality: 50,
          );
          if (fallback != null) {
            final bytes = await fallback.readAsBytes();
            if (mounted) {
              setState(() {
                _photoBase64 = ImageCompressHelper.compressToBase64(bytes);
              });
            }
          }
        } catch (fallbackError) {
          debugPrint('Fallback picker error: $fallbackError');
        }
      }
    }
  }

  Future<void> _openCamera() async {
    await _pickImage(ImageSource.camera, preferredCameraDevice: CameraDevice.rear);
  }

  Future<void> _openGallery() async {
    await _pickImage(ImageSource.gallery);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedShopId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a customer / store')),
      );
      return;
    }

    final provider = context.read<CollectionProvider>();
    final shop = provider.getShopById(_selectedShopId!);
    if (shop == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected store not found')),
      );
      return;
    }

    final billAmt = _billAmount;
    final collAmt = _collectedAmount;

    if (collAmt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Collected amount must be greater than zero')),
      );
      return;
    }

    final billNo = _billNoController.text.trim();
    final existingBill = provider.getBillSummary(shop.id, billNo);
    final priorCollected = existingBill?.totalCollected ?? 0.0;
    final effectiveBillTotal = existingBill != null && existingBill.billTotal > billAmt ? existingBill.billTotal : billAmt;
    final remainingBeforeThis = (effectiveBillTotal - priorCollected) > 0 ? (effectiveBillTotal - priorCollected) : effectiveBillTotal;

    if (existingBill != null && collAmt > (remainingBeforeThis + 0.01)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Collected amount (${CurrencyFormatter.format(collAmt)}) cannot exceed remaining balance of ${CurrencyFormatter.format(remainingBeforeThis)}'),
        ),
      );
      return;
    } else if (existingBill == null && collAmt > billAmt) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Collected amount cannot exceed the total invoice amount')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final newTotalCollected = priorCollected + collAmt;
      final remainingAfter = (effectiveBillTotal - newTotalCollected) > 0 ? (effectiveBillTotal - newTotalCollected) : 0.0;

      final collection = CollectionModel(
        id: _uuid.v4(),
        businessName: _selectedBusiness,
        shopId: shop.id,
        shopName: shop.name,
        routeId: shop.routeId,
        routeName: shop.routeName,
        billNumber: billNo,
        billAmount: effectiveBillTotal,
        collectedAmount: collAmt,
        balanceRemaining: remainingAfter,
        paymentMode: _selectedMode,
        photoBase64: remainingAfter <= 0.001 ? null : _photoBase64,
        chequeNumber: _selectedMode == PaymentMode.cheque ? _chequeNoController.text.trim() : null,
        bankName: _selectedMode == PaymentMode.cheque ? _bankNameController.text.trim() : null,
        referenceNumber: (_selectedMode == PaymentMode.upi || _selectedMode == PaymentMode.netBanking)
            ? _refNoController.text.trim()
            : null,
        remarks: _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
        salesmanName: provider.salesmanName,
        collectedAt: _collectionDate,
        billDate: _billDate,
      );

      await provider.addCollection(collection);

      if (mounted) {
        final isFullySettled = remainingAfter <= 0;
        final msg = isFullySettled
            ? '${CurrencyFormatter.format(collAmt)} recorded. Invoice $billNo is now fully PAID (100% complete)!'
            : '${CurrencyFormatter.format(collAmt)} recorded for ${shop.name}. Remaining Balance: ${CurrencyFormatter.format(remainingAfter)} (PENDING)';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: isFullySettled ? AppTheme.cashColor : AppTheme.chequeColor,
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save payment record: $e'),
            backgroundColor: AppTheme.balanceDueColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CollectionProvider>();
    final shops = provider.shops;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Payment Entry'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Follow-up Banner if opened for balance collection
              if (widget.isFollowUp)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.chequeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.chequeColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.history_outlined, color: AppTheme.chequeColor, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Clearing Due Balance: Invoice #${widget.initialBillNumber ?? ""}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                            ),
                            Text(
                              'Remaining Pending Balance: ${CurrencyFormatter.format(widget.initialBalanceDue ?? 0)}',
                              style: const TextStyle(fontSize: 12, color: AppTheme.chequeColor, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // Distributor Entity Selector - High Visibility Dual Firm Cards
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'DISTRIBUTOR FIRM',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 0.8,
                              color: Colors.blueGrey,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.getBusinessLightColor(_selectedBusiness),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppTheme.getBusinessBorderColor(_selectedBusiness)),
                            ),
                            child: Text(
                              _selectedBusiness.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.getBusinessTextColor(_selectedBusiness),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          // PURVA ENTERPRISES CARD
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                setState(() => _selectedBusiness = 'Purva Enterprises');
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: _selectedBusiness == 'Purva Enterprises'
                                      ? AppTheme.purvaLight
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _selectedBusiness == 'Purva Enterprises'
                                        ? AppTheme.purvaPrimary
                                        : AppTheme.border,
                                    width: _selectedBusiness == 'Purva Enterprises' ? 2 : 1,
                                  ),
                                  boxShadow: _selectedBusiness == 'Purva Enterprises'
                                      ? [
                                          BoxShadow(
                                            color: AppTheme.purvaPrimary.withValues(alpha: 0.12),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          )
                                        ]
                                      : null,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: _selectedBusiness == 'Purva Enterprises'
                                                ? AppTheme.purvaPrimary
                                                : Colors.blueGrey.shade100,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Icon(
                                            Icons.corporate_fare,
                                            size: 16,
                                            color: _selectedBusiness == 'Purva Enterprises'
                                                ? Colors.white
                                                : Colors.blueGrey.shade700,
                                          ),
                                        ),
                                        Icon(
                                          _selectedBusiness == 'Purva Enterprises'
                                              ? Icons.check_circle
                                              : Icons.radio_button_unchecked,
                                          size: 18,
                                          color: _selectedBusiness == 'Purva Enterprises'
                                              ? AppTheme.purvaPrimary
                                              : Colors.blueGrey.shade300,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Purva Enterprises',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: _selectedBusiness == 'Purva Enterprises'
                                            ? AppTheme.purvaText
                                            : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Navy Palette',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.blueGrey.shade600,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // MANAS SALES CARD
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                setState(() => _selectedBusiness = 'Manas Sales');
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: _selectedBusiness == 'Manas Sales'
                                      ? AppTheme.manasLight
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _selectedBusiness == 'Manas Sales'
                                        ? AppTheme.manasPrimary
                                        : AppTheme.border,
                                    width: _selectedBusiness == 'Manas Sales' ? 2 : 1,
                                  ),
                                  boxShadow: _selectedBusiness == 'Manas Sales'
                                      ? [
                                          BoxShadow(
                                            color: AppTheme.manasPrimary.withValues(alpha: 0.12),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          )
                                        ]
                                      : null,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: _selectedBusiness == 'Manas Sales'
                                                ? AppTheme.manasPrimary
                                                : Colors.blueGrey.shade100,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Icon(
                                            Icons.storefront,
                                            size: 16,
                                            color: _selectedBusiness == 'Manas Sales'
                                                ? Colors.white
                                                : Colors.blueGrey.shade700,
                                          ),
                                        ),
                                        Icon(
                                          _selectedBusiness == 'Manas Sales'
                                              ? Icons.check_circle
                                              : Icons.radio_button_unchecked,
                                          size: 18,
                                          color: _selectedBusiness == 'Manas Sales'
                                              ? AppTheme.manasPrimary
                                              : Colors.blueGrey.shade300,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Manas Sales',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: _selectedBusiness == 'Manas Sales'
                                            ? AppTheme.manasText
                                            : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Teal Palette',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.blueGrey.shade600,
                                        fontWeight: FontWeight.w500,
                                      ),
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
              ),
              const SizedBox(height: 12),

              // Store Selector
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'STORE / CUSTOMER',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              letterSpacing: 0.8,
                              color: Colors.blueGrey,
                            ),
                          ),
                          InkWell(
                            onTap: () async {
                              final newShop = await Navigator.push<ShopModel>(
                                context,
                                MaterialPageRoute(builder: (_) => const AddShopScreen()),
                              );
                              if (newShop != null) {
                                setState(() {
                                  _selectedShopId = newShop.id;
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.secondary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.add_business_outlined, size: 14, color: AppTheme.secondary),
                                  SizedBox(width: 4),
                                  Text(
                                    '+ Add New Store',
                                    style: TextStyle(
                                      color: AppTheme.secondary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (shops.isEmpty)
                        const Text(
                          'No stores available. Please add a store first.',
                          style: TextStyle(color: AppTheme.balanceDueColor),
                        )
                      else
                        DropdownButtonFormField<String>(
                          key: ValueKey(_selectedShopId),
                          initialValue: _selectedShopId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.storefront_outlined, size: 20),
                            labelText: 'Store Name',
                            hintText: 'Select store (e.g. ATA Kirana)',
                          ),
                          items: shops.map((s) {
                            return DropdownMenuItem<String>(
                              value: s.id,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      s.name,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Text(
                                    s.routeName,
                                    style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedShopId = val;
                            });
                          },
                          validator: (val) => val == null ? 'Please select a store' : null,
                        ),

                      // If this shop has pending bills, show them so Akash can tap to settle with 1 click!
                      if (_selectedShopId != null) ...[
                        Builder(
                          builder: (context) {
                            final pendingBills = provider.getPendingBills(forShopId: _selectedShopId);
                            if (pendingBills.isEmpty) return const SizedBox.shrink();
                            return Container(
                              margin: const EdgeInsets.only(top: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFDE68A)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.pending_actions_outlined, size: 16, color: Color(0xFFD97706)),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Pending Invoices for this Store (${pendingBills.length}):',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF92400E),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ...pendingBills.map((b) {
                                    final isThisSelected = _billNoController.text.trim().toLowerCase() ==
                                        b.billNumber.trim().toLowerCase();
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isThisSelected ? const Color(0xFFFEF3C7) : Colors.white,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isThisSelected ? const Color(0xFFD97706) : AppTheme.border,
                                          width: isThisSelected ? 1.5 : 1.0,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(
                                                      'Bill #${b.billNumber}',
                                                      style: const TextStyle(
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.bold,
                                                        color: Color(0xFF0F172A),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                      decoration: BoxDecoration(
                                                        color: AppTheme.getBusinessLightColor(b.businessName),
                                                        borderRadius: BorderRadius.circular(4),
                                                        border: Border.all(color: AppTheme.getBusinessBorderColor(b.businessName), width: 0.8),
                                                      ),
                                                      child: Text(
                                                        b.businessName == 'Purva Enterprises' ? 'PURVA' : (b.businessName == 'Manas Sales' ? 'MANAS' : b.businessName),
                                                        style: TextStyle(
                                                          fontSize: 9,
                                                          color: AppTheme.getBusinessTextColor(b.businessName),
                                                          fontWeight: FontWeight.w800,
                                                          letterSpacing: 0.3,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Billed: ${CurrencyFormatter.format(b.billTotal)}  •  Paid: ${CurrencyFormatter.format(b.totalCollected)}',
                                                  style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600),
                                                ),
                                                Text(
                                                  'Due Balance: ${CurrencyFormatter.format(b.balanceDue)}',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppTheme.balanceDueColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  isThisSelected ? const Color(0xFF0F172A) : const Color(0xFFD97706),
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              minimumSize: Size.zero,
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              elevation: 0,
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                _billNoController.text = b.billNumber;
                                                _billAmountController.text = b.billTotal.toStringAsFixed(0);
                                                _collectedAmountController.text = b.balanceDue.toStringAsFixed(0);
                                                _selectedBusiness = b.businessName;
                                                _billDate = b.billDate;
                                              });
                                            },
                                            child: Text(
                                              isThisSelected ? 'Selected' : 'Pay Balance',
                                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Date Selection Card: Bill Date & Collection Date (Defaults to Today, customizable)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.calendar_month_outlined, size: 16, color: AppTheme.primary),
                              SizedBox(width: 6),
                              Text(
                                'BILL & COLLECTION DATES',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  letterSpacing: 0.8,
                                  color: Colors.blueGrey,
                                ),
                              ),
                            ],
                          ),
                          if (!_isSameDay(_billDate, DateTime.now()) || !_isSameDay(_collectionDate, DateTime.now()))
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _billDate = DateTime.now();
                                  _collectionDate = DateTime.now();
                                });
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                child: Row(
                                  children: const [
                                    Icon(Icons.restart_alt, size: 13, color: AppTheme.secondary),
                                    SizedBox(width: 3),
                                    Text(
                                      'Reset to Today',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.secondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            Text(
                              'Default: Today',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blueGrey.shade500,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDateTile(
                              title: 'Bill / Invoice Date',
                              subtitle: !_isSameDay(_billDate, DateTime.now()) ? 'Custom Bill Date' : 'Tap to change (e.g. 17th)',
                              date: _billDate,
                              icon: Icons.receipt_long_outlined,
                              onTap: () => _pickDate(isBillDate: true),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildDateTile(
                              title: 'Collection Date',
                              subtitle: !_isSameDay(_collectionDate, DateTime.now()) ? 'Custom Payment Date' : 'Tap to change (e.g. 20th)',
                              date: _collectionDate,
                              icon: Icons.event_available_outlined,
                              onTap: () => _pickDate(isBillDate: false),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Invoice Details with Partial Payment Computation
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'INVOICE & COLLECTION AMOUNTS',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          letterSpacing: 0.8,
                          color: Colors.blueGrey,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _billNoController,
                        decoration: const InputDecoration(
                          labelText: 'Invoice / Bill Number *',
                          hintText: 'e.g. PE-4081',
                          prefixIcon: Icon(Icons.receipt_outlined, size: 20),
                        ),
                        onChanged: (val) => setState(() {}),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter invoice number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Bill Total Amount
                      TextFormField(
                        controller: _billAmountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Total Bill Amount (₹) *',
                          hintText: 'e.g. 40000',
                          prefixIcon: const Icon(Icons.currency_rupee, size: 18),
                          suffixIcon: TextButton(
                            onPressed: () => _applyFullPayment(provider),
                            child: const Text('Full / Due', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ),
                        onChanged: (val) => setState(() {}),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter total bill amount';
                          }
                          final num = double.tryParse(val.trim());
                          if (num == null || num <= 0) {
                            return 'Enter a valid amount';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Collected Amount
                      TextFormField(
                        controller: _collectedAmountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          labelText: 'Collected Amount Today (₹) *',
                          hintText: 'e.g. 10000 or 30000',
                          prefixIcon: Icon(Icons.payments_outlined, color: AppTheme.cashColor, size: 20),
                        ),
                        onChanged: (val) => setState(() {}),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter collected amount';
                          }
                          final num = double.tryParse(val.trim());
                          if (num == null || num <= 0) {
                            return 'Enter a valid amount';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Real-time Balance Status Card
                      Builder(
                        builder: (context) {
                          final existing = _getExistingBill(provider);
                          final priorPaid = existing?.totalCollected ?? 0.0;
                          final effectiveTotal = existing != null && existing.billTotal > _billAmount
                              ? existing.billTotal
                              : _billAmount;
                          final currentEntry = _collectedAmount;
                          final totalPaidAfter = priorPaid + currentEntry;
                          final remainingAfter = (effectiveTotal - totalPaidAfter) > 0
                              ? (effectiveTotal - totalPaidAfter)
                              : 0.0;
                          final isPaid100 = effectiveTotal > 0 && remainingAfter <= 0 && currentEntry > 0;

                          if (effectiveTotal <= 0 && currentEntry <= 0) {
                            return const SizedBox.shrink();
                          }

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isPaid100
                                  ? AppTheme.cashColor.withValues(alpha: 0.08)
                                  : AppTheme.chequeColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isPaid100
                                    ? AppTheme.cashColor.withValues(alpha: 0.3)
                                    : AppTheme.chequeColor.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          isPaid100 ? Icons.check_circle_outline : Icons.pending_outlined,
                                          size: 18,
                                          color: isPaid100 ? AppTheme.cashColor : AppTheme.chequeColor,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          isPaid100 ? '100% Fully Settled' : 'Partial / Pending Invoice',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            color: isPaid100 ? AppTheme.cashColor : AppTheme.chequeColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isPaid100 ? AppTheme.cashColor : AppTheme.chequeColor,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isPaid100 ? 'STATUS: PAID' : 'STATUS: PENDING',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 16),
                                if (priorPaid > 0) ...[
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Previously Paid on this Bill:',
                                          style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700)),
                                      Text(CurrencyFormatter.format(priorPaid),
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                ],
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Collecting Now Today:',
                                        style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700)),
                                    Text(CurrencyFormatter.format(currentEntry),
                                        style: const TextStyle(
                                            fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      isPaid100 ? 'Remaining Balance:' : 'Pending Balance Due:',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isPaid100 ? AppTheme.cashColor : AppTheme.balanceDueColor,
                                      ),
                                    ),
                                    Text(
                                      isPaid100 ? '₹0.00 (Cleared)' : CurrencyFormatter.format(remainingAfter),
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        color: isPaid100 ? AppTheme.cashColor : AppTheme.balanceDueColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Payment Mode Selection Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PAYMENT METHOD',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          letterSpacing: 0.8,
                          color: Colors.blueGrey,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: PaymentMode.values.map((mode) {
                          final isSelected = _selectedMode == mode;
                          Color chipColor;
                          switch (mode) {
                            case PaymentMode.cash:
                              chipColor = AppTheme.cashColor;
                              break;
                            case PaymentMode.upi:
                              chipColor = AppTheme.upiColor;
                              break;
                            case PaymentMode.cheque:
                              chipColor = AppTheme.chequeColor;
                              break;
                            case PaymentMode.netBanking:
                              chipColor = AppTheme.netBankingColor;
                              break;
                          }

                          return ChoiceChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  mode.icon,
                                  size: 16,
                                  color: isSelected ? Colors.white : Colors.blueGrey.shade800,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  mode.label,
                                  style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: isSelected ? Colors.white : Colors.blueGrey.shade900,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            selected: isSelected,
                            selectedColor: chipColor,
                            backgroundColor: Colors.grey.shade100,
                            onSelected: (val) {
                              if (val) setState(() => _selectedMode = mode);
                            },
                          );
                        }).toList(),
                      ),

                      // Conditional Cheque Fields
                      if (_selectedMode == PaymentMode.cheque) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _chequeNoController,
                          decoration: const InputDecoration(
                            labelText: 'Cheque Number *',
                            hintText: 'e.g. 402911',
                            prefixIcon: Icon(Icons.numbers_outlined, size: 20),
                          ),
                          validator: (val) {
                            if (_selectedMode == PaymentMode.cheque && (val == null || val.trim().isEmpty)) {
                              return 'Please enter cheque number';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _bankNameController,
                          decoration: const InputDecoration(
                            labelText: 'Bank Name *',
                            hintText: 'e.g. HDFC Bank, SBI',
                            prefixIcon: Icon(Icons.account_balance_outlined, size: 20),
                          ),
                          validator: (val) {
                            if (_selectedMode == PaymentMode.cheque && (val == null || val.trim().isEmpty)) {
                              return 'Please enter bank name';
                            }
                            return null;
                          },
                        ),
                      ],

                      // Conditional UPI / Netbanking Reference
                      if (_selectedMode == PaymentMode.upi || _selectedMode == PaymentMode.netBanking) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _refNoController,
                          decoration: InputDecoration(
                            labelText: _selectedMode == PaymentMode.upi
                                ? 'UPI UTR / Transaction Reference (Optional)'
                                : 'NEFT / RTGS Reference Number (Optional)',
                            hintText: 'e.g. 308192837192',
                            prefixIcon: const Icon(Icons.tag_outlined, size: 20),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Document / Photo Proof
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'INVOICE / RECEIPT DOCUMENT',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              letterSpacing: 0.8,
                              color: Colors.blueGrey,
                            ),
                          ),
                          if (_photoBase64 != null)
                            TextButton.icon(
                              icon: const Icon(Icons.delete_outline, size: 16, color: AppTheme.balanceDueColor),
                              label: const Text('Remove', style: TextStyle(color: AppTheme.balanceDueColor, fontSize: 12)),
                              onPressed: () => setState(() => _photoBase64 = null),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_photoBase64 == null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.camera_alt_rounded, size: 18),
                                      label: const Text(
                                        'Open Camera',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF0F172A),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 13),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        elevation: 1,
                                      ),
                                      onPressed: _openCamera,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                                      label: const Text(
                                        'From Gallery',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppTheme.primary,
                                        padding: const EdgeInsets.symmetric(vertical: 13),
                                        side: const BorderSide(color: AppTheme.primary, width: 1.2),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: _openGallery,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Center(
                                child: Text(
                                  'Tap camera to shoot directly, or gallery for saved photos',
                                  style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => FullScreenImageViewer(
                                      imageBase64: _photoBase64!,
                                      title: 'Invoice Photo Preview',
                                      subtitle: _billNoController.text.isNotEmpty ? 'Bill #${_billNoController.text}' : null,
                                    ),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                children: [
                                  Builder(
                                    builder: (ctx) {
                                      final bytes = ImageCompressHelper.safeBase64Decode(_photoBase64);
                                      if (bytes == null) {
                                        return Container(
                                          height: 120,
                                          color: Colors.grey.shade200,
                                          child: const Center(
                                            child: Icon(Icons.broken_image, size: 36, color: Colors.blueGrey),
                                          ),
                                        );
                                      }
                                      return ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.memory(
                                          bytes,
                                          height: 160,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                        ),
                                      );
                                    },
                                  ),
                                  Positioned(
                                    bottom: 8,
                                    left: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.75),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: const [
                                          Icon(Icons.zoom_in, size: 14, color: Colors.white),
                                          SizedBox(width: 4),
                                          Text(
                                            'Tap to Zoom & Verify',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.camera_alt_outlined, size: 16),
                                    label: const Text('Retake (Camera)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 9),
                                      side: BorderSide(color: Colors.grey.shade400),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: _openCamera,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.photo_library_outlined, size: 16),
                                    label: const Text('Change (Gallery)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 9),
                                      side: BorderSide(color: Colors.grey.shade400),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: _openGallery,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Remarks
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextFormField(
                    controller: _remarksController,
                    decoration: const InputDecoration(
                      labelText: 'Collection Notes / Remarks (Optional)',
                      hintText: 'e.g. Balance promised next week',
                      prefixIcon: Icon(Icons.notes_outlined, size: 20),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Submit Save Button
              ElevatedButton.icon(
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 20),
                label: Text(
                  _isSaving ? 'Saving Record...' : 'Confirm & Save Entry',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isSaving ? null : _submit,
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
