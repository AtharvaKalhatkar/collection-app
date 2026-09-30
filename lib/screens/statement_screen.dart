import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:excel/excel.dart' as xl;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/collection_model.dart';
import '../models/payment_mode.dart';
import '../providers/collection_provider.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';
import '../utils/file_download/file_download.dart';
import 'collection_details_dialog.dart';

class StatementScreen extends StatefulWidget {
  final String? initialBusiness;
  final PaymentMode? initialMode;

  const StatementScreen({
    super.key,
    this.initialBusiness,
    this.initialMode,
  });

  @override
  State<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends State<StatementScreen> {
  String? _selectedBusiness; // null means 'All'
  DateTime _selectedDate = DateTime.now();
  bool _filterByDate = true;
  PaymentMode? _selectedMode; // null means 'All Modes'
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _selectedBusiness = widget.initialBusiness;
    _selectedMode = widget.initialMode;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: 'SELECT STATEMENT DATE',
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _filterByDate = true;
      });
    }
  }

  List<CollectionModel> _getFilteredCollections(CollectionProvider provider) {
    return provider.collections.where((c) {
      // Date filter
      if (_filterByDate) {
        final sameDay = c.collectedAt.year == _selectedDate.year &&
            c.collectedAt.month == _selectedDate.month &&
            c.collectedAt.day == _selectedDate.day;
        if (!sameDay) return false;
      }

      // Firm filter
      if (_selectedBusiness != null && _selectedBusiness != 'All') {
        if (c.businessName != _selectedBusiness) return false;
      }

      // Mode filter
      if (_selectedMode != null) {
        if (c.paymentMode != _selectedMode) return false;
      }

      return true;
    }).toList()
      ..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
  }

  Color _getModeColor(PaymentMode mode) {
    switch (mode) {
      case PaymentMode.cash:
        return AppTheme.cashColor;
      case PaymentMode.upi:
        return AppTheme.upiColor;
      case PaymentMode.cheque:
        return AppTheme.chequeColor;
      case PaymentMode.netBanking:
        return AppTheme.netBankingColor;
    }
  }

  // --- EXCEL (.xlsx) EXPORT ---
  Future<void> _exportToExcel(List<CollectionModel> records) async {
    setState(() => _isExporting = true);
    try {
      final excel = xl.Excel.createExcel();
      final sheetName = excel.getDefaultSheet() ?? 'Statement';
      final sheet = excel[sheetName];

      // Header row
      sheet.appendRow([
        xl.TextCellValue('S.No'),
        xl.TextCellValue('Date & Time'),
        xl.TextCellValue('Firm Name'),
        xl.TextCellValue('Route'),
        xl.TextCellValue('Outlet / Shop Name'),
        xl.TextCellValue('Bill Number'),
        xl.TextCellValue('Bill Date'),
        xl.TextCellValue('Payment Mode'),
        xl.TextCellValue('Collected Amount (INR)'),
        xl.TextCellValue('Total Bill Amount (INR)'),
        xl.TextCellValue('Pending Balance (INR)'),
        xl.TextCellValue('Payment Reference / Cheque'),
        xl.TextCellValue('Salesman'),
      ]);

      // Data rows
      for (int i = 0; i < records.length; i++) {
        final c = records[i];
        final timeStr = DateFormat('dd-MM-yyyy hh:mm a').format(c.collectedAt);
        final billDateStr = DateFormat('dd-MM-yyyy').format(c.billDate);
        final ref = c.referenceNumber ?? (c.chequeNumber != null ? 'Chq #${c.chequeNumber} (${c.bankName ?? ''})' : '-');

        sheet.appendRow([
          xl.IntCellValue(i + 1),
          xl.TextCellValue(timeStr),
          xl.TextCellValue(c.businessName),
          xl.TextCellValue(c.routeName),
          xl.TextCellValue(c.shopName),
          xl.TextCellValue(c.billNumber),
          xl.TextCellValue(billDateStr),
          xl.TextCellValue(c.paymentMode.label),
          xl.DoubleCellValue(c.collectedAmount),
          xl.DoubleCellValue(c.billAmount),
          xl.DoubleCellValue(c.balanceAmount),
          xl.TextCellValue(ref),
          xl.TextCellValue(c.salesmanName),
        ]);
      }

      final bytes = excel.encode();
      if (bytes != null) {
        final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
        final firmTag = _selectedBusiness?.replaceAll(' ', '_') ?? 'All_Firms';
        final modeTag = _selectedMode?.name ?? 'All_Modes';
        final fileName = 'Collection_Statement_${firmTag}_${modeTag}_$dateStr.xlsx';

        await downloadFile(
          bytes: bytes,
          fileName: fileName,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.table_view_outlined, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Excel file "$fileName" ready and downloaded!')),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating Excel: $e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // --- PDF EXPORT ---
  Future<void> _exportToPdf(List<CollectionModel> records, CollectionProvider provider) async {
    setState(() => _isExporting = true);
    try {
      final devanagariFont = await PdfGoogleFonts.notoSansDevanagariRegular();
      final devanagariBoldFont = await PdfGoogleFonts.notoSansDevanagariBold();
      final baseStyle = pw.TextStyle(font: devanagariFont, fontSize: 8.5);

      final headerTextStyle = pw.TextStyle(font: devanagariBoldFont, fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white);

      final doc = pw.Document();
      final dateStr = _filterByDate ? DateFormat('dd MMM yyyy').format(_selectedDate) : 'All Dates';
      final totalCollected = records.fold(0.0, (s, c) => s + c.collectedAmount);
      final totalBilled = records.fold(0.0, (s, c) => s + c.billAmount);
      final totalDue = records.fold(0.0, (s, c) => s + c.balanceAmount);

      final firmTitle = _selectedBusiness ?? 'Purva Enterprises & Manas Sales';
      final modeTitle = _selectedMode?.label ?? 'All Payment Modes';

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context context) {
            return [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        firmTitle.toUpperCase(),
                        style: pw.TextStyle(font: devanagariBoldFont, fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'DAILY COLLECTION STATEMENT',
                        style: pw.TextStyle(font: devanagariBoldFont, fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Date: $dateStr', style: pw.TextStyle(font: devanagariFont, fontSize: 11)),
                      pw.Text('Mode: $modeTitle', style: pw.TextStyle(font: devanagariFont, fontSize: 11)),
                      pw.Text('Officer: ${provider.salesmanName}', style: pw.TextStyle(font: devanagariFont, fontSize: 11)),
                    ],
                  ),
                ],
              ),
              pw.Divider(thickness: 1.5, color: PdfColors.indigo800),
              pw.SizedBox(height: 8),

              // Summary Box
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    pw.Column(
                      children: [
                        pw.Text('TOTAL COLLECTED', style: pw.TextStyle(font: devanagariBoldFont, fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                        pw.SizedBox(height: 2),
                        pw.Text('INR ${totalCollected.toStringAsFixed(2)}', style: pw.TextStyle(font: devanagariBoldFont, fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
                      ],
                    ),
                    pw.Column(
                      children: [
                        pw.Text('TOTAL INVOICED', style: pw.TextStyle(font: devanagariBoldFont, fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                        pw.SizedBox(height: 2),
                        pw.Text('INR ${totalBilled.toStringAsFixed(2)}', style: pw.TextStyle(font: devanagariBoldFont, fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                    pw.Column(
                      children: [
                        pw.Text('BALANCE DUE', style: pw.TextStyle(font: devanagariBoldFont, fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                        pw.SizedBox(height: 2),
                        pw.Text('INR ${totalDue.toStringAsFixed(2)}', style: pw.TextStyle(font: devanagariBoldFont, fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
                      ],
                    ),
                    pw.Column(
                      children: [
                        pw.Text('RECEIPTS', style: pw.TextStyle(font: devanagariBoldFont, fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                        pw.SizedBox(height: 2),
                        pw.Text('${records.length}', style: pw.TextStyle(font: devanagariBoldFont, fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),

              // Table
              pw.TableHelper.fromTextArray(
                headers: ['#', 'Outlet / Shop', 'Firm', 'Route', 'Bill #', 'Mode', 'Collected', 'Balance'],
                headerStyle: headerTextStyle,
                headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
                cellStyle: baseStyle,
                cellAlignment: pw.Alignment.centerLeft,
                headerAlignment: pw.Alignment.centerLeft,
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                data: List.generate(records.length, (idx) {
                  final c = records[idx];
                  return [
                    '${idx + 1}',
                    c.shopName,
                    c.businessName == 'Purva Enterprises' ? 'Purva' : 'Manas',
                    c.routeName,
                    c.billNumber,
                    c.paymentMode.label,
                    'INR ${c.collectedAmount.toStringAsFixed(0)}',
                    c.balanceAmount > 0 ? 'INR ${c.balanceAmount.toStringAsFixed(0)}' : 'Settled',
                  ];
                }),
              ),
              pw.SizedBox(height: 16),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  'Generated via Daily Collection Pro on ${DateFormat('dd-MM-yyyy hh:mm a').format(DateTime.now())}',
                  style: pw.TextStyle(font: devanagariFont, fontSize: 8, color: PdfColors.grey600),
                ),
              ),
            ];
          },
        ),
      );

      final pdfBytes = await doc.save();
      final dateTag = DateFormat('yyyy-MM-dd').format(_selectedDate);
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: 'Collection_Statement_$dateTag.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating PDF: $e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showStatementPreview(List<CollectionModel> records, CollectionProvider provider) {
    final dateStr = _filterByDate ? DateFormat('dd MMM yyyy').format(_selectedDate) : 'All Dates';
    final totalCollected = records.fold(0.0, (s, c) => s + c.collectedAmount);
    final totalBilled = records.fold(0.0, (s, c) => s + c.billAmount);
    final totalDue = records.fold(0.0, (s, c) => s + c.balanceAmount);

    final firmTitle = _selectedBusiness ?? 'Purva Enterprises & Manas Sales';
    final modeTitle = _selectedMode?.label ?? 'All Payment Modes';

    showDialog(
      context: context,
      useSafeArea: false,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Statement Preview'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                firmTitle.toUpperCase(),
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'DAILY COLLECTION STATEMENT',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Date: $dateStr', style: const TextStyle(fontSize: 11)),
                            Text('Mode: $modeTitle', style: const TextStyle(fontSize: 11)),
                            Text('Officer: ${provider.salesmanName}', style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                    const Divider(thickness: 1.5, color: Colors.indigo),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              Text('TOTAL COLLECTED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                              const SizedBox(height: 2),
                              Text('INR ${totalCollected.toStringAsFixed(2)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                            ],
                          ),
                          Column(
                            children: [
                              Text('TOTAL INVOICED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                              const SizedBox(height: 2),
                              Text('INR ${totalBilled.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Column(
                            children: [
                              Text('BALANCE DUE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                              const SizedBox(height: 2),
                              Text('INR ${totalDue.toStringAsFixed(2)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                            ],
                          ),
                          Column(
                            children: [
                              Text('RECEIPTS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                              const SizedBox(height: 2),
                              Text('${records.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final c = records[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.shopName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text('${c.businessName == 'Purva Enterprises' ? 'Purva' : 'Manas'} • ${c.routeName}', style: const TextStyle(fontSize: 11)),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Bill: ${c.billNumber}', style: const TextStyle(fontSize: 12)),
                                  Text(c.paymentMode.label, style: const TextStyle(fontSize: 11)),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('INR ${c.collectedAmount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text(
                                    c.balanceAmount > 0 ? 'Due: INR ${c.balanceAmount.toStringAsFixed(0)}' : 'Settled',
                                    style: TextStyle(fontSize: 11, color: c.balanceAmount > 0 ? Colors.red : Colors.green),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Generated via Daily Collection Pro on ${DateFormat('dd-MM-yyyy hh:mm a').format(DateTime.now())}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CollectionProvider>();
    final filteredRecords = _getFilteredCollections(provider);

    final totalCollected = filteredRecords.fold(0.0, (s, c) => s + c.collectedAmount);
    final totalBilled = filteredRecords.fold(0.0, (s, c) => s + c.billAmount);
    final totalBalance = filteredRecords.fold(0.0, (s, c) => s + c.balanceAmount);

    final isPurva = _selectedBusiness == 'Purva Enterprises';
    final isManas = _selectedBusiness == 'Manas Sales';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statement'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined, size: 20),
            tooltip: 'Select Date',
            onPressed: _pickDate,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Bar
          Container(
            padding: const EdgeInsets.all(12.0),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. FIRM SELECTOR (Purva / Manas / All)
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      // All Firms
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _selectedBusiness = null),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: _selectedBusiness == null ? AppTheme.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                'ALL FIRMS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: _selectedBusiness == null ? Colors.white : Colors.blueGrey.shade800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Purva Enterprises
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _selectedBusiness = 'Purva Enterprises'),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: isPurva ? AppTheme.purvaPrimary : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                'PURVA',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: isPurva ? Colors.white : AppTheme.purvaText,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Manas Sales
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _selectedBusiness = 'Manas Sales'),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: isManas ? AppTheme.manasPrimary : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                'MANAS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: isManas ? Colors.white : AppTheme.manasText,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // 2. DATE SELECTOR & 3. PAYMENT MODE DROPDOWN ROW
                Row(
                  children: [
                    // Date Selector
                    Expanded(
                      flex: 5,
                      child: InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.event, size: 16, color: AppTheme.primary),
                                  const SizedBox(width: 6),
                                  Text(
                                    _filterByDate
                                        ? DateFormat('dd MMM yyyy').format(_selectedDate)
                                        : 'All Dates',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                  ),
                                ],
                              ),
                              const Icon(Icons.arrow_drop_down, size: 18, color: Colors.blueGrey),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Payment Mode Dropdown
                    Expanded(
                      flex: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<PaymentMode?>(
                            isExpanded: true,
                            value: _selectedMode,
                            hint: const Text('All Modes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            items: [
                              const DropdownMenuItem<PaymentMode?>(
                                value: null,
                                child: Text('All Payment Modes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                              ...PaymentMode.values.map((mode) {
                                return DropdownMenuItem<PaymentMode?>(
                                  value: mode,
                                  child: Row(
                                    children: [
                                      Icon(mode.icon, size: 15, color: _getModeColor(mode)),
                                      const SizedBox(width: 6),
                                      Text(mode.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                );
                              }),
                            ],
                            onChanged: (val) {
                              setState(() => _selectedMode = val);
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
          const Divider(height: 1),

          // Financial Summary Card for Statement
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.grey.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedMode != null
                          ? 'TOTAL ${_selectedMode!.label.toUpperCase()}'
                          : 'NET COLLECTED',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      CurrencyFormatter.format(totalCollected),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: _selectedMode != null ? _getModeColor(_selectedMode!) : AppTheme.primary,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${filteredRecords.length} Receipts • Billed: ${CurrencyFormatter.format(totalBilled)}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                        ),
                        if (totalBalance > 0)
                          Text(
                            'Due: ${CurrencyFormatter.format(totalBalance)}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.balanceDueColor),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Download Action Buttons Bar (Preview, Excel, PDF)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                // Preview Button
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.image_outlined, size: 16),
                    label: const Text('Preview', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      elevation: 1,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: filteredRecords.isEmpty
                        ? null
                        : () => _showStatementPreview(filteredRecords, provider),
                  ),
                ),
                const SizedBox(width: 8),

                // Excel Export Button
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.table_view, size: 16),
                    label: const Text('Excel (.xlsx)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF107C41), // Excel green
                      foregroundColor: Colors.white,
                      elevation: 1,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _isExporting || filteredRecords.isEmpty
                        ? null
                        : () => _exportToExcel(filteredRecords),
                  ),
                ),
                const SizedBox(width: 8),

                // PDF Export Button
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: const Text('PDF Document', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626), // PDF red
                      foregroundColor: Colors.white,
                      elevation: 1,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _isExporting || filteredRecords.isEmpty
                        ? null
                        : () => _exportToPdf(filteredRecords, provider),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // List of Statement Bills / Collections
          Expanded(
            child: filteredRecords.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.description_outlined, size: 48, color: Colors.blueGrey.shade300),
                        const SizedBox(height: 12),
                        Text(
                          'No collections recorded for this selection',
                          style: TextStyle(fontSize: 14, color: Colors.blueGrey.shade600),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filteredRecords.length,
                    itemBuilder: (context, index) {
                      final item = filteredRecords[index];
                      final modeColor = _getModeColor(item.paymentMode);
                      final timeStr = DateFormat('hh:mm a').format(item.collectedAt);
                      final isPartial = item.isPartial;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => CollectionDetailsDialog(collection: item),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: modeColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Icon(item.paymentMode.icon, size: 20, color: modeColor),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.shopName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: Color(0xFF0F172A),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: AppTheme.getBusinessLightColor(item.businessName),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: AppTheme.getBusinessBorderColor(item.businessName), width: 0.8),
                                            ),
                                            child: Text(
                                              item.businessName == 'Purva Enterprises' ? 'PURVA' : 'MANAS',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                                color: AppTheme.getBusinessTextColor(item.businessName),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Bill: ${item.billNumber}',
                                            style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700, fontWeight: FontWeight.w500),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Text(
                                            '${item.routeName} • $timeStr',
                                            style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade400),
                                          ),
                                          if (isPartial) ...[
                                            const SizedBox(width: 6),
                                            Text(
                                              'Due: ${CurrencyFormatter.format(item.balanceAmount)}',
                                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.balanceDueColor),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      CurrencyFormatter.format(item.collectedAmount),
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: modeColor),
                                    ),
                                    const SizedBox(height: 2),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: modeColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        item.paymentMode.label,
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: modeColor),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
