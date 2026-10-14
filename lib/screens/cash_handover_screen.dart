import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../models/cash_handover_model.dart';
import '../providers/collection_provider.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';

class CashHandoverScreen extends StatefulWidget {
  final DateTime? initialDate;
  final String? initialBusiness;

  const CashHandoverScreen({
    super.key,
    this.initialDate,
    this.initialBusiness,
  });

  @override
  State<CashHandoverScreen> createState() => _CashHandoverScreenState();
}

class _CashHandoverScreenState extends State<CashHandoverScreen> {
  late DateTime _selectedDate;
  String _selectedBusiness = 'All';
  final TextEditingController _receivedByController =
      TextEditingController(text: 'Office / Owner');
  final TextEditingController _remarksController = TextEditingController();

  final Map<int, TextEditingController> _noteControllers = {
    500: TextEditingController(text: '0'),
    200: TextEditingController(text: '0'),
    100: TextEditingController(text: '0'),
    50: TextEditingController(text: '0'),
    20: TextEditingController(text: '0'),
    10: TextEditingController(text: '0'),
  };
  final TextEditingController _coinsController = TextEditingController(text: '0');

  final Uuid _uuid = const Uuid();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _selectedBusiness = widget.initialBusiness ?? 'All';

    // Check if an existing handover was already saved for this date
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadExistingHandoverIfAny();
    });
  }

  void _loadExistingHandoverIfAny() {
    final provider = context.read<CollectionProvider>();
    final existing = provider.getLatestHandoverForDate(_selectedDate,
        business: _selectedBusiness == 'All' ? null : _selectedBusiness);
    if (existing != null) {
      setState(() {
        _noteControllers[500]?.text = existing.count500.toString();
        _noteControllers[200]?.text = existing.count200.toString();
        _noteControllers[100]?.text = existing.count100.toString();
        _noteControllers[50]?.text = existing.count50.toString();
        _noteControllers[20]?.text = existing.count20.toString();
        _noteControllers[10]?.text = existing.count10.toString();
        _coinsController.text = existing.coinsAmount.toStringAsFixed(0);
        _receivedByController.text = existing.receivedByName;
        _remarksController.text = existing.remarks ?? '';
      });
    }
  }

  @override
  void dispose() {
    _receivedByController.dispose();
    _remarksController.dispose();
    for (final c in _noteControllers.values) {
      c.dispose();
    }
    _coinsController.dispose();
    super.dispose();
  }

  int _getNoteCount(int note) {
    return int.tryParse(_noteControllers[note]?.text.trim() ?? '0') ?? 0;
  }

  void _updateNoteCount(int note, int delta) {
    final current = _getNoteCount(note);
    final updated = (current + delta).clamp(0, 9999);
    setState(() {
      _noteControllers[note]?.text = updated.toString();
    });
  }

  double _getCoinsAmount() {
    return double.tryParse(_coinsController.text.trim()) ?? 0.0;
  }

  double _calculateTotalCounted() {
    double total = 0.0;
    for (final note in [500, 200, 100, 50, 20, 10]) {
      total += note * _getNoteCount(note);
    }
    total += _getCoinsAmount();
    return total;
  }

  double _getExpectedCash(CollectionProvider provider) {
    if (_selectedBusiness == 'Purva Enterprises') {
      return provider.getCashForBusiness('Purva Enterprises', forDate: _selectedDate);
    } else if (_selectedBusiness == 'Manas Sales') {
      return provider.getCashForBusiness('Manas Sales', forDate: _selectedDate);
    } else {
      // Both firms combined for that day
      final purvaCash = provider.getCashForBusiness('Purva Enterprises', forDate: _selectedDate);
      final manasCash = provider.getCashForBusiness('Manas Sales', forDate: _selectedDate);
      return purvaCash + manasCash;
    }
  }

  void _clearAllCounts() {
    setState(() {
      for (final c in _noteControllers.values) {
        c.text = '0';
      }
      _coinsController.text = '0';
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadExistingHandoverIfAny();
    }
  }

  CashHandoverModel _buildModel(CollectionProvider provider) {
    final totalCounted = _calculateTotalCounted();
    final totalExpected = _getExpectedCash(provider);
    final variance = totalCounted - totalExpected;

    return CashHandoverModel(
      id: _uuid.v4(),
      date: _selectedDate,
      businessName: _selectedBusiness,
      salesmanName: provider.salesmanName,
      receivedByName: _receivedByController.text.trim().isNotEmpty
          ? _receivedByController.text.trim()
          : 'Office / Owner',
      count500: _getNoteCount(500),
      count200: _getNoteCount(200),
      count100: _getNoteCount(100),
      count50: _getNoteCount(50),
      count20: _getNoteCount(20),
      count10: _getNoteCount(10),
      coinsAmount: _getCoinsAmount(),
      totalCounted: totalCounted,
      totalExpected: totalExpected,
      variance: variance,
      remarks: _remarksController.text.trim().isNotEmpty ? _remarksController.text.trim() : null,
    );
  }

  Future<void> _saveHandover() async {
    final provider = context.read<CollectionProvider>();
    final handover = _buildModel(provider);

    setState(() => _isSaving = true);
    await provider.saveCashHandover(handover);
    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Cash Handover saved: ${CurrencyFormatter.format(handover.totalCounted)}',
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.secondary,
      ),
    );
  }

  Future<void> _shareOnWhatsApp() async {
    final provider = context.read<CollectionProvider>();
    final handover = _buildModel(provider);
    final text = provider.generateCashHandoverWhatsAppText(handover);

    // Also copy to clipboard for convenience
    Clipboard.setData(ClipboardData(text: text));

    final waUrl = Uri.parse('https://api.whatsapp.com/send?text=${Uri.encodeComponent(text)}');
    try {
      final launched = await launchUrl(waUrl, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        _showCopyAlert();
      }
    } catch (_) {
      if (mounted) {
        _showCopyAlert();
      }
    }
  }

  void _showCopyAlert() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Handover report copied to clipboard! Paste directly into WhatsApp.'),
        backgroundColor: AppTheme.primary,
      ),
    );
  }

  void _showHistoryModal(BuildContext context) {
    final provider = context.read<CollectionProvider>();
    final handovers = provider.cashHandovers;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          maxChildSize: 0.9,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Cash Handover History',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Past daily physical cash verification records',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                  ),
                  const Divider(height: 20),
                  Expanded(
                    child: handovers.isEmpty
                        ? Center(
                            child: Text(
                              'No saved handovers yet',
                              style: TextStyle(color: Colors.blueGrey.shade400),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: handovers.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (_, idx) {
                              final h = handovers[idx];
                              final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(h.createdAt);
                              final isMatch = h.isMatched;

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                leading: CircleAvatar(
                                  backgroundColor: isMatch
                                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                      : (h.hasShortage
                                          ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                                          : const Color(0xFF3B82F6).withValues(alpha: 0.15)),
                                  child: Icon(
                                    isMatch
                                        ? Icons.check_circle_outline
                                        : (h.hasShortage ? Icons.warning_amber_rounded : Icons.info_outline),
                                    color: isMatch
                                        ? const Color(0xFF059669)
                                        : (h.hasShortage ? const Color(0xFFDC2626) : const Color(0xFF2563EB)),
                                    size: 20,
                                  ),
                                ),
                                title: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      CurrencyFormatter.format(h.totalCounted),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isMatch ? Colors.green.shade50 : Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isMatch
                                            ? 'MATCHED'
                                            : (h.hasShortage
                                                ? '-${CurrencyFormatter.format(h.variance.abs())}'
                                                : '+${CurrencyFormatter.format(h.variance)}'),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isMatch ? Colors.green.shade800 : Colors.red.shade800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    '$dateStr • ${h.businessName}\nTo: ${h.receivedByName}',
                                    style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600),
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.share, size: 18, color: AppTheme.primary),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    final text = provider.generateCashHandoverWhatsAppText(h);
                                    Clipboard.setData(ClipboardData(text: text));
                                    launchUrl(
                                      Uri.parse('https://api.whatsapp.com/send?text=${Uri.encodeComponent(text)}'),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CollectionProvider>();
    final expectedCash = _getExpectedCash(provider);
    final totalCounted = _calculateTotalCounted();
    final variance = totalCounted - expectedCash;
    final isMatch = variance.abs() <= 0.01;
    final isShortage = variance < -0.01;
    final dateStr = DateFormat('dd MMM yyyy').format(_selectedDate);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Day Closing & Cash Counter'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Handover History',
            onPressed: () => _showHistoryModal(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reset Counts',
            onPressed: _clearAllCounts,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Filter Bar: Date & Firm Selectors
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Date Selector
                      Expanded(
                        child: InkWell(
                          onTap: _pickDate,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_month_outlined, size: 16, color: AppTheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  dateStr,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Business Filter Dropdown
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _selectedBusiness,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                              items: const [
                                DropdownMenuItem(value: 'All', child: Text('Both Firms')),
                                DropdownMenuItem(value: 'Purva Enterprises', child: Text('Purva')),
                                DropdownMenuItem(value: 'Manas Sales', child: Text('Manas')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedBusiness = val);
                                  _loadExistingHandoverIfAny();
                                }
                              },
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

            // Live Reconciliation Matcher Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isMatch
                      ? [const Color(0xFF065F46), const Color(0xFF047857)]
                      : (isShortage
                          ? [const Color(0xFF991B1B), const Color(0xFFB91C1C)]
                          : [const Color(0xFF1E40AF), const Color(0xFF2563EB)]),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: (isMatch
                            ? const Color(0xFF047857)
                            : (isShortage ? const Color(0xFFB91C1C) : const Color(0xFF2563EB)))
                        .withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'PHYSICAL CASH RECONCILIATION',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isMatch
                                  ? Icons.check_circle_rounded
                                  : (isShortage ? Icons.error_rounded : Icons.info_rounded),
                              size: 13,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isMatch ? 'PERFECT MATCH' : (isShortage ? 'SHORTAGE' : 'SURPLUS'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    CurrencyFormatter.format(totalCounted),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Target (System Cash)',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
                            ),
                            Text(
                              CurrencyFormatter.format(expectedCash),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                        Container(width: 1, height: 24, color: Colors.white.withValues(alpha: 0.2)),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Variance / Difference',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
                            ),
                            Text(
                              isMatch
                                  ? '₹0 (Exact Match)'
                                  : (isShortage
                                      ? '-${CurrencyFormatter.format(variance.abs())}'
                                      : '+${CurrencyFormatter.format(variance)}'),
                              style: TextStyle(
                                color: isMatch ? Colors.greenAccent : (isShortage ? const Color(0xFFFCA5A5) : Colors.yellowAccent),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Denomination Counter Heading
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Cash Denomination Counter',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                ),
                Text(
                  'Count physical notes in hand',
                  style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade500),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Denominations List
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  _buildNoteRow(500, const Color(0xFF065F46)),
                  const Divider(height: 1),
                  _buildNoteRow(200, const Color(0xFFC2410C)),
                  const Divider(height: 1),
                  _buildNoteRow(100, const Color(0xFF4338CA)),
                  const Divider(height: 1),
                  _buildNoteRow(50, const Color(0xFF0284C7)),
                  const Divider(height: 1),
                  _buildNoteRow(20, const Color(0xFF0D9488)),
                  const Divider(height: 1),
                  _buildNoteRow(10, const Color(0xFF78350F)),
                  const Divider(height: 1),
                  _buildCoinsRow(),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Handover Details Section
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Handover Sign-off Details',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: 'Salesman',
                            labelStyle: const TextStyle(fontSize: 12),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            prefixIcon: const Icon(Icons.person_outline, size: 18),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          controller: TextEditingController(text: provider.salesmanName),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _receivedByController,
                          decoration: InputDecoration(
                            labelText: 'Handed Over To',
                            labelStyle: const TextStyle(fontSize: 12),
                            prefixIcon: const Icon(Icons.assignment_ind_outlined, size: 18),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _remarksController,
                    decoration: InputDecoration(
                      labelText: 'Remarks / Notes (Optional)',
                      hintText: 'e.g. ₹20 coin change kept for morning bag',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      labelStyle: const TextStyle(fontSize: 12),
                      prefixIcon: const Icon(Icons.note_alt_outlined, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text(_isSaving ? 'Saving...' : 'Save Handover'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isSaving ? null : _saveHandover,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('WhatsApp Slip'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _shareOnWhatsApp,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteRow(int note, Color badgeColor) {
    final count = _getNoteCount(note);
    final subtotal = note * count;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Currency Badge
          Container(
            width: 68,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              '₹$note',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: badgeColor,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Count Controls: [-] [TextField] [+]
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStepperButton(
                icon: Icons.remove,
                onPressed: () => _updateNoteCount(note, -1),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 52,
                height: 36,
                child: TextField(
                  controller: _noteControllers[note],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 4),
              _buildStepperButton(
                icon: Icons.add,
                onPressed: () => _updateNoteCount(note, 1),
              ),
            ],
          ),

          const Spacer(),

          // Subtotal
          Text(
            CurrencyFormatter.format(subtotal.toDouble()),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: count > 0 ? const Color(0xFF0F172A) : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoinsRow() {
    final coins = _getCoinsAmount();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 68,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Text(
              'Coins',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Colors.amber.shade900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 104,
            height: 36,
            child: TextField(
              controller: _coinsController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              decoration: InputDecoration(
                prefixText: '₹ ',
                prefixStyle: TextStyle(color: Colors.blueGrey.shade600, fontSize: 13),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const Spacer(),
          Text(
            CurrencyFormatter.format(coins),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: coins > 0 ? const Color(0xFF0F172A) : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepperButton({required IconData icon, required VoidCallback onPressed}) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Icon(icon, size: 16, color: Colors.blueGrey.shade800),
      ),
    );
  }
}
