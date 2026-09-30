import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/payment_mode.dart';
import '../models/pending_bill_model.dart';
import '../providers/collection_provider.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';
import 'add_pending_bill_screen.dart';

class MakeCollectionScreen extends StatefulWidget {
  final String? initialPendingBillId;
  final String? initialBusiness;
  final String? initialRouteId;

  const MakeCollectionScreen({
    super.key,
    this.initialPendingBillId,
    this.initialBusiness,
    this.initialRouteId,
  });

  @override
  State<MakeCollectionScreen> createState() => _MakeCollectionScreenState();
}

class _MakeCollectionScreenState extends State<MakeCollectionScreen> {
  final _formKey = GlobalKey<FormState>();

  String _selectedBusiness = 'Purva Enterprises';
  String? _selectedRouteId;
  String? _selectedPendingBillId;

  // Collection Date (DEFAULTS TO TODAY)
  DateTime _collectionDate = DateTime.now();

  final _collectedAmountController = TextEditingController();
  PaymentMode _selectedMode = PaymentMode.cash;

  // Optional quick payment details
  final _chequeNoController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _refNoController = TextEditingController();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialBusiness != null) {
      _selectedBusiness = widget.initialBusiness!;
    }
    _selectedRouteId = widget.initialRouteId;
    _selectedPendingBillId = widget.initialPendingBillId;
  }

  @override
  void dispose() {
    _collectedAmountController.dispose();
    _chequeNoController.dispose();
    _bankNameController.dispose();
    _refNoController.dispose();
    super.dispose();
  }

  Future<void> _pickCollectionDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _collectionDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'SELECT COLLECTION DATE',
    );
    if (picked != null) {
      setState(() => _collectionDate = picked);
    }
  }

  // Searchable Pending Bill Picker
  void _openSearchablePendingBillPicker(List<PendingBillModel> bills) {
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
            final filtered = bills.where((b) {
              if (query.isEmpty) return true;
              final q = query.toLowerCase();
              return b.billNumber.toLowerCase().contains(q) ||
                  b.shopName.toLowerCase().contains(q) ||
                  b.routeName.toLowerCase().contains(q);
            }).toList();

            return Padding(
              padding: EdgeInsets.only(
                top: 16,
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Select Bill',
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
                        hintText: 'Search bill, outlet...',
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
                                  Icon(Icons.receipt_long_outlined, size: 40, color: Colors.blueGrey.shade300),
                                  const SizedBox(height: 8),
                                  Text(
                                    query.isEmpty
                                        ? 'No pending bills found for this route'
                                        : 'No bills match "$query"',
                                    style: TextStyle(color: Colors.blueGrey.shade600),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.add, size: 16),
                                    label: const Text('Add New Bill'),
                                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => AddPendingBillScreen(initialRouteId: _selectedRouteId),
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
                                final b = filtered[idx];
                                final isSelected = b.id == _selectedPendingBillId;
                                final invDateStr = DateFormat('dd MMM').format(b.invoiceDate);
                                final delDateStr = DateFormat('dd MMM').format(b.deliveryDate);

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  leading: Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppTheme.primary
                                          : const Color(0xFFD97706).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        Icons.receipt_outlined,
                                        color: isSelected ? Colors.white : const Color(0xFFD97706),
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          b.shopName,
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                        ),
                                      ),
                                      Text(
                                        CurrencyFormatter.format(b.balanceDue),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          color: AppTheme.balanceDueColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 3.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Bill #${b.billNumber} • Inv: $invDateStr • Del: $delDateStr',
                                          style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700),
                                        ),
                                        Text(
                                          'Total: ${CurrencyFormatter.format(b.totalAmount)}',
                                          style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade500),
                                        ),
                                      ],
                                    ),
                                  ),
                                  trailing: isSelected
                                      ? const Icon(Icons.check_circle, color: AppTheme.primary)
                                      : null,
                                  onTap: () {
                                    setState(() {
                                      _selectedPendingBillId = b.id;
                                      _collectedAmountController.text = b.balanceDue.toStringAsFixed(0);
                                    });
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

  Future<void> _saveCollection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedPendingBillId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a pending bill to collect against'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    final provider = context.read<CollectionProvider>();
    final pendingBill = provider.getPendingBillById(_selectedPendingBillId!);
    if (pendingBill == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected bill could not be found'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    final amount = double.tryParse(_collectedAmountController.text.trim()) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid collected amount'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    if (amount > pendingBill.balanceDue + 1.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Amount exceeds pending balance (${CurrencyFormatter.format(pendingBill.balanceDue)})'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await provider.recordCollectionForPendingBill(
        pendingBill: pendingBill,
        collectedAmount: amount,
        paymentMode: _selectedMode,
        collectionDate: _collectionDate,
        chequeNumber: _selectedMode == PaymentMode.cheque ? _chequeNoController.text.trim() : null,
        bankName: _selectedMode == PaymentMode.cheque ? _bankNameController.text.trim() : null,
        referenceNumber: _selectedMode == PaymentMode.upi || _selectedMode == PaymentMode.netBanking
            ? _refNoController.text.trim()
            : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Collected ${CurrencyFormatter.format(amount)} from ${pendingBill.shopName} via ${_selectedMode.label}!',
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving collection: $e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CollectionProvider>();
    final routes = provider.routes;

    if (_selectedRouteId == null && routes.isNotEmpty) {
      _selectedRouteId = routes.first.id;
    }

    final pendingBills = provider.getPendingBillsForRoute(
      _selectedRouteId ?? '',
      businessName: _selectedBusiness,
    );

    final selectedBill = _selectedPendingBillId != null
        ? provider.getPendingBillById(_selectedPendingBillId!)
        : null;

    final isPurva = _selectedBusiness == 'Purva Enterprises';
    final firmPrimaryColor = isPurva ? AppTheme.purvaPrimary : AppTheme.manasPrimary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collect'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
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
                '1. SELECT FIRM / COMPANY',
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
                            _selectedPendingBillId = null;
                            _collectedAmountController.clear();
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
                              'Purva',
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
                            _selectedPendingBillId = null;
                            _collectedAmountController.clear();
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
                              'Manas',
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
                '2. SELECT ROUTE (BEAT)',
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
                    hint: const Text('Select Route'),
                    items: routes.map((r) {
                      final billsCount = provider.getPendingBillsForRoute(r.id, businessName: _selectedBusiness).length;
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
                              '$billsCount pending bills',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: billsCount > 0 ? const Color(0xFFD97706) : Colors.blueGrey.shade500,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedRouteId = val;
                        _selectedPendingBillId = null;
                        _collectedAmountController.clear();
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // 3. PENDING BILL DROPDOWN (WITH SEARCH OPTION)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '3. SELECT PENDING BILL',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Colors.blueGrey,
                    ),
                  ),
                  InkWell(
                    onTap: () => _openSearchablePendingBillPicker(pendingBills),
                    child: Row(
                      children: const [
                        Icon(Icons.search, size: 14, color: AppTheme.primary),
                        SizedBox(width: 4),
                        Text(
                          'Search Bills',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Pending bill picker tile
              InkWell(
                onTap: () => _openSearchablePendingBillPicker(pendingBills),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selectedBill != null ? firmPrimaryColor : AppTheme.border,
                      width: selectedBill != null ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: selectedBill != null
                              ? const Color(0xFFD97706).withValues(alpha: 0.12)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.receipt_long_outlined,
                            color: selectedBill != null ? const Color(0xFFD97706) : Colors.blueGrey,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: selectedBill != null
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          selectedBill.shopName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                      ),
                                      Text(
                                        'Due: ${CurrencyFormatter.format(selectedBill.balanceDue)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                          color: AppTheme.balanceDueColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Bill #${selectedBill.billNumber} • Total: ${CurrencyFormatter.format(selectedBill.totalAmount)}',
                                    style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                                  ),
                                ],
                              )
                            : Text(
                                pendingBills.isEmpty
                                    ? 'No pending bills in this beat (Tap to upload)'
                                    : 'Tap to select pending bill (${pendingBills.length} available)',
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

              // 4. AUTO-LOADED BILL DETAILS FROM PREVIOUS PENDING BILL
              if (selectedBill != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'BILL DATE',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                DateFormat('dd MMM yyyy').format(selectedBill.invoiceDate),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'DELIVERY DATE',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                DateFormat('dd MMM yyyy').format(selectedBill.deliveryDate),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'TOTAL BILL AMT',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                CurrencyFormatter.format(selectedBill.totalAmount),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),

              // 5. COLLECTION DATE (DEFAULTS TO TODAY)
              const Text(
                '5. COLLECTION DATE (DEFAULT: TODAY)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: Colors.blueGrey,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickCollectionDate,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event_available_outlined, size: 20, color: AppTheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          DateFormat('EEEE, dd MMM yyyy').format(_collectionDate),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'CHANGE',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // 6. COLLECTED AMOUNT
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '6. COLLECTED AMOUNT (₹)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Colors.blueGrey,
                    ),
                  ),
                  if (selectedBill != null && selectedBill.balanceDue > 0)
                    InkWell(
                      onTap: () {
                        setState(() {
                          _collectedAmountController.text = selectedBill.balanceDue.toStringAsFixed(0);
                        });
                      },
                      child: Text(
                        'Full: ${CurrencyFormatter.format(selectedBill.balanceDue)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _collectedAmountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  prefixStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.primary),
                  hintText: '0.00',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter collected amount';
                  }
                  final parsed = double.tryParse(val.trim());
                  if (parsed == null || parsed <= 0) {
                    return 'Amount must be greater than zero';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),

              // 7. PAYMENT MODE
              const Text(
                '7. PAYMENT MODE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: Colors.blueGrey,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: PaymentMode.values.map((mode) {
                  final isSelected = _selectedMode == mode;
                  Color modeColor;
                  switch (mode) {
                    case PaymentMode.cash:
                      modeColor = AppTheme.cashColor;
                      break;
                    case PaymentMode.upi:
                      modeColor = AppTheme.upiColor;
                      break;
                    case PaymentMode.cheque:
                      modeColor = AppTheme.chequeColor;
                      break;
                    case PaymentMode.netBanking:
                      modeColor = AppTheme.netBankingColor;
                      break;
                  }

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: InkWell(
                        onTap: () => setState(() => _selectedMode = mode),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? modeColor : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? modeColor : AppTheme.border,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                mode.icon,
                                size: 18,
                                color: isSelected ? Colors.white : modeColor,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                mode.label,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: isSelected ? Colors.white : Colors.blueGrey.shade800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              // Optional details if Cheque or UPI
              if (_selectedMode == PaymentMode.cheque) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _chequeNoController,
                        decoration: InputDecoration(
                          labelText: 'Cheque Number (Optional)',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _bankNameController,
                        decoration: InputDecoration(
                          labelText: 'Bank Name (Optional)',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (_selectedMode == PaymentMode.upi || _selectedMode == PaymentMode.netBanking) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _refNoController,
                  decoration: InputDecoration(
                    labelText: 'UTR / Transaction Reference (Optional)',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
              const SizedBox(height: 28),

              // 8. DIRECT SAVE BUTTON (NO PHOTO, NO NOTES)
              ElevatedButton.icon(
                icon: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_circle_outline, size: 20),
                label: Text(
                  _isSaving ? 'Saving Collection...' : 'Direct Save Collection',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: firmPrimaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 2,
                ),
                onPressed: _isSaving ? null : _saveCollection,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
