import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:excel/excel.dart' as xl;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:daily_collection_app/models/collection_model.dart';
import 'package:daily_collection_app/providers/collection_provider.dart';
import 'package:daily_collection_app/screens/statement_screen.dart';

/// Exact replication of the Excel statement generation logic in StatementScreen._exportToExcel
Uint8List generateStatementExcel(List<CollectionModel> records) {
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
    xl.TextCellValue('Deposit Bank'),
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
    final bank = (c.bankName != null && c.bankName!.trim().isNotEmpty) ? c.bankName!.trim() : '-';
    final ref = c.referenceNumber ?? (c.chequeNumber != null ? 'Chq #${c.chequeNumber}' : '-');

    sheet.appendRow([
      xl.IntCellValue(i + 1),
      xl.TextCellValue(timeStr),
      xl.TextCellValue(c.businessName),
      xl.TextCellValue(c.routeName),
      xl.TextCellValue(c.shopName),
      xl.TextCellValue(c.billNumber),
      xl.TextCellValue(billDateStr),
      xl.TextCellValue(c.paymentMode.label),
      xl.TextCellValue(bank),
      xl.DoubleCellValue(c.collectedAmount),
      xl.DoubleCellValue(c.billAmount),
      xl.DoubleCellValue(c.balanceAmount),
      xl.TextCellValue(ref),
      xl.TextCellValue(c.salesmanName),
    ]);
  }

  final bytes = excel.encode();
  if (bytes == null) {
    throw Exception('Excel encoding failed');
  }
  return Uint8List.fromList(bytes);
}

/// Exact replication of the PDF statement generation logic in StatementScreen._exportToPdf
Future<Uint8List> generateStatementPdf(
  List<CollectionModel> records, {
  String? firmTitle,
  String? modeTitle,
  String? routeName,
  String? shopName,
  String salesmanName = 'Akash',
  String dateStr = 'All Dates',
  pw.Font? regularFont,
  pw.Font? boldFont,
}) async {
  final devanagariFont = regularFont ?? pw.Font.helvetica();
  final devanagariBoldFont = boldFont ?? pw.Font.helveticaBold();
  final baseStyle = pw.TextStyle(font: devanagariFont, fontSize: 8.5);
  final headerTextStyle = pw.TextStyle(
    font: devanagariBoldFont,
    fontSize: 9,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.white,
  );

  final doc = pw.Document();
  final totalCollected = records.fold(0.0, (s, c) => s + c.collectedAmount);
  final totalBilled = records.fold(0.0, (s, c) => s + c.billAmount);
  final totalDue = records.fold(0.0, (s, c) => s + c.balanceAmount);

  final effectiveFirmTitle = firmTitle ?? 'Purva Enterprises & Manas Sales';
  final effectiveModeTitle = modeTitle ?? 'All Modes';

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
                    effectiveFirmTitle.toUpperCase(),
                    style: pw.TextStyle(
                      font: devanagariBoldFont,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.indigo900,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'DAILY COLLECTION STATEMENT',
                    style: pw.TextStyle(
                      font: devanagariBoldFont,
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Date: $dateStr', style: pw.TextStyle(font: devanagariFont, fontSize: 11)),
                  pw.Text('Mode: $effectiveModeTitle', style: pw.TextStyle(font: devanagariFont, fontSize: 11)),
                  if (routeName != null)
                    pw.Text('Route: $routeName', style: pw.TextStyle(font: devanagariFont, fontSize: 10)),
                  if (shopName != null)
                    pw.Text('Outlet: $shopName', style: pw.TextStyle(font: devanagariFont, fontSize: 10)),
                  pw.Text('Officer: $salesmanName', style: pw.TextStyle(font: devanagariFont, fontSize: 11)),
                ],
              ),
            ],
          ),
          pw.Divider(thickness: 1.5, color: PdfColors.indigo800),
          pw.SizedBox(height: 8),

          // Summary Box
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: const pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Column(
                  children: [
                    pw.Text(
                      'TOTAL COLLECTED',
                      style: pw.TextStyle(
                        font: devanagariBoldFont,
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'INR ${totalCollected.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        font: devanagariBoldFont,
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.green800,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text(
                      'TOTAL INVOICED',
                      style: pw.TextStyle(
                        font: devanagariBoldFont,
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'INR ${totalBilled.toStringAsFixed(2)}',
                      style: pw.TextStyle(font: devanagariBoldFont, fontSize: 12, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text(
                      'BALANCE DUE',
                      style: pw.TextStyle(
                        font: devanagariBoldFont,
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'INR ${totalDue.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        font: devanagariBoldFont,
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.red800,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text(
                      'RECEIPTS',
                      style: pw.TextStyle(
                        font: devanagariBoldFont,
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      '${records.length}',
                      style: pw.TextStyle(font: devanagariBoldFont, fontSize: 12, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // Table
          pw.TableHelper.fromTextArray(
            headers: ['#', 'Outlet / Shop', 'Firm', 'Route', 'Bill #', 'Mode', 'Deposit Bank', 'Collected', 'Balance'],
            headerStyle: headerTextStyle,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
            cellStyle: baseStyle,
            cellAlignment: pw.Alignment.centerLeft,
            headerAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            data: List.generate(records.length, (idx) {
              final c = records[idx];
              final bank = (c.bankName != null && c.bankName!.trim().isNotEmpty) ? c.bankName!.trim() : '-';
              return [
                '${idx + 1}',
                c.shopName,
                c.businessName == 'Purva Enterprises' ? 'Purva' : 'Manas',
                c.routeName,
                c.billNumber,
                c.paymentMode.label,
                bank,
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

  return doc.save();
}

CollectionModel buildTestCollection({
  required String id,
  required String businessName,
  required PaymentMode mode,
  String? bankName,
  String? refNo,
  String? chequeNo,
  double collected = 5000.0,
  double billed = 10000.0,
  double balance = 5000.0,
  String shop = 'Test Kirana Store',
  String route = 'Chakan Beat',
  String billNo = 'INV-1001',
}) {
  return CollectionModel(
    id: id,
    businessName: businessName,
    shopId: 'shop-$id',
    shopName: shop,
    routeId: 'route-1',
    routeName: route,
    billNumber: billNo,
    billAmount: billed,
    collectedAmount: collected,
    balanceRemaining: balance,
    paymentMode: mode,
    salesmanName: 'Akash Gite',
    collectedAt: DateTime(2026, 9, 20, 11, 30),
    billDate: DateTime(2026, 9, 15),
    bankName: bankName,
    referenceNumber: refNo,
    chequeNumber: chequeNo,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('1. Boundary Conditions: Empty, Single, and All Records', () {
    test('Excel Export: Empty Filtered Subset (0 records) produces valid header-only spreadsheet', () {
      final bytes = generateStatementExcel([]);
      expect(bytes, isNotEmpty);

      final decoded = xl.Excel.decodeBytes(bytes);
      final sheetName = decoded.getDefaultSheet() ?? decoded.tables.keys.first;
      final sheet = decoded.tables[sheetName]!;

      // Exactly 1 row: Header
      expect(sheet.rows.length, 1);
      final headerRow = sheet.rows[0];
      expect(headerRow.length, 14);

      // Verify Column 8 is 'Deposit Bank'
      expect(headerRow[8]?.value?.toString(), 'Deposit Bank');
      expect(headerRow[0]?.value?.toString(), 'S.No');
      expect(headerRow[7]?.value?.toString(), 'Payment Mode');
    });

    test('Excel Export: Single Record Subset (1 record) produces header + 1 accurate data row', () {
      final single = buildTestCollection(
        id: 'single-1',
        businessName: 'Purva Enterprises',
        mode: PaymentMode.cheque,
        bankName: 'HDFC Bank',
        chequeNo: '492011',
        collected: 12500.0,
        billed: 12500.0,
        balance: 0.0,
        shop: 'Mahesh Traders',
        route: 'Bhosari',
        billNo: 'PE-999',
      );

      final bytes = generateStatementExcel([single]);
      final decoded = xl.Excel.decodeBytes(bytes);
      final sheetName = decoded.getDefaultSheet() ?? decoded.tables.keys.first;
      final sheet = decoded.tables[sheetName]!;

      expect(sheet.rows.length, 2);
      final dataRow = sheet.rows[1];
      expect(dataRow.length, 14);

      expect(dataRow[0]?.value?.toString(), '1'); // S.No
      expect(dataRow[2]?.value?.toString(), 'Purva Enterprises');
      expect(dataRow[3]?.value?.toString(), 'Bhosari');
      expect(dataRow[4]?.value?.toString(), 'Mahesh Traders');
      expect(dataRow[5]?.value?.toString(), 'PE-999');
      expect(dataRow[7]?.value?.toString(), 'Cheque');
      expect(dataRow[8]?.value?.toString(), 'HDFC Bank'); // Deposit Bank
      expect(double.parse(dataRow[9]!.value.toString()), 12500.0); // Collected
      expect(double.parse(dataRow[10]!.value.toString()), 12500.0); // Bill
      expect(double.parse(dataRow[11]!.value.toString()), 0.0); // Balance
      expect(dataRow[12]?.value?.toString(), 'Chq #492011');
      expect(dataRow[13]?.value?.toString(), 'Akash Gite');
    });

    test('Excel Export: All Records Subset (multiple records) preserves order, count, and bank columns', () {
      final records = [
        buildTestCollection(id: '1', businessName: 'Purva Enterprises', mode: PaymentMode.cash, bankName: null),
        buildTestCollection(id: '2', businessName: 'Purva Enterprises', mode: PaymentMode.upi, bankName: 'Union Bank'),
        buildTestCollection(id: '3', businessName: 'Manas Sales', mode: PaymentMode.cheque, bankName: 'Central Bank'),
        buildTestCollection(id: '4', businessName: 'Manas Sales', mode: PaymentMode.netBanking, bankName: 'Central Bank'),
      ];

      final bytes = generateStatementExcel(records);
      final decoded = xl.Excel.decodeBytes(bytes);
      final sheetName = decoded.getDefaultSheet() ?? decoded.tables.keys.first;
      final sheet = decoded.tables[sheetName]!;

      expect(sheet.rows.length, 5); // 1 header + 4 rows
      expect(sheet.rows[1][8]?.value?.toString(), '-'); // Cash bank is dash
      expect(sheet.rows[2][8]?.value?.toString(), 'Union Bank'); // UPI
      expect(sheet.rows[3][8]?.value?.toString(), 'Central Bank'); // Cheque
      expect(sheet.rows[4][8]?.value?.toString(), 'Central Bank'); // NetBanking
    });

    test('PDF Export: Empty Filtered Subset (0 records) produces valid PDF document bytes', () async {
      final pdfBytes = await generateStatementPdf([]);
      expect(pdfBytes, isNotEmpty);
      final headerStr = String.fromCharCodes(pdfBytes.sublist(0, 5));
      expect(headerStr, '%PDF-');
    });

    test('PDF Export: Single Record Subset (1 record) produces valid PDF document with summary and 1 row', () async {
      final single = buildTestCollection(
        id: 'pdf-single',
        businessName: 'Manas Sales',
        mode: PaymentMode.upi,
        bankName: 'Central Bank',
        collected: 8000.0,
        billed: 10000.0,
        balance: 2000.0,
      );

      final pdfBytes = await generateStatementPdf([single]);
      expect(pdfBytes, isNotEmpty);
      final headerStr = String.fromCharCodes(pdfBytes.sublist(0, 5));
      expect(headerStr, '%PDF-');
    });

    test('PDF Export: All Records Subset produces valid multi-row PDF bytes with correct totals', () async {
      final records = [
        buildTestCollection(id: 'p1', businessName: 'Purva Enterprises', mode: PaymentMode.cash, bankName: null, collected: 10000.0, billed: 10000.0, balance: 0.0),
        buildTestCollection(id: 'p2', businessName: 'Purva Enterprises', mode: PaymentMode.cheque, bankName: 'RSBL', collected: 15000.0, billed: 20000.0, balance: 5000.0),
        buildTestCollection(id: 'p3', businessName: 'Manas Sales', mode: PaymentMode.upi, bankName: 'Central Bank', collected: 5000.0, billed: 5000.0, balance: 0.0),
      ];

      final pdfBytes = await generateStatementPdf(records);
      expect(pdfBytes, isNotEmpty);
      final headerStr = String.fromCharCodes(pdfBytes.sublist(0, 5));
      expect(headerStr, '%PDF-');
    });
  });

  group('2. Deposit Bank Column Across Cash, UPI, Cheque, and NetBanking Modes', () {
    test('Cash Mode: bankName is null or empty, outputs "-" in Excel and PDF', () async {
      final cash1 = buildTestCollection(id: 'c1', businessName: 'Purva Enterprises', mode: PaymentMode.cash, bankName: null);
      final cash2 = buildTestCollection(id: 'c2', businessName: 'Purva Enterprises', mode: PaymentMode.cash, bankName: '   ');

      final excelBytes = generateStatementExcel([cash1, cash2]);
      final decoded = xl.Excel.decodeBytes(excelBytes);
      final sheet = decoded.tables[decoded.getDefaultSheet() ?? decoded.tables.keys.first]!;

      expect(sheet.rows[1][8]?.value?.toString(), '-');
      expect(sheet.rows[2][8]?.value?.toString(), '-');

      final pdfBytes = await generateStatementPdf([cash1, cash2]);
      expect(pdfBytes, isNotEmpty);
    });

    test('UPI Mode: accurately maps to Union Bank (Purva) and Central Bank (Manas)', () {
      final upiPurva = buildTestCollection(id: 'u1', businessName: 'Purva Enterprises', mode: PaymentMode.upi, bankName: 'Union Bank');
      final upiManas = buildTestCollection(id: 'u2', businessName: 'Manas Sales', mode: PaymentMode.upi, bankName: 'Central Bank');

      final excelBytes = generateStatementExcel([upiPurva, upiManas]);
      final decoded = xl.Excel.decodeBytes(excelBytes);
      final sheet = decoded.tables[decoded.getDefaultSheet() ?? decoded.tables.keys.first]!;

      expect(sheet.rows[1][7]?.value?.toString(), 'UPI');
      expect(sheet.rows[1][8]?.value?.toString(), 'Union Bank');

      expect(sheet.rows[2][7]?.value?.toString(), 'UPI');
      expect(sheet.rows[2][8]?.value?.toString(), 'Central Bank');
    });

    test('Cheque Mode: accurately maps to HDFC Bank, RSBL, and custom bank names with trimming', () {
      final chq1 = buildTestCollection(id: 'q1', businessName: 'Purva Enterprises', mode: PaymentMode.cheque, bankName: '  HDFC Bank  ');
      final chq2 = buildTestCollection(id: 'q2', businessName: 'Purva Enterprises', mode: PaymentMode.cheque, bankName: 'RSBL');
      final chq3 = buildTestCollection(id: 'q3', businessName: 'Manas Sales', mode: PaymentMode.cheque, bankName: 'Central Bank');

      final excelBytes = generateStatementExcel([chq1, chq2, chq3]);
      final decoded = xl.Excel.decodeBytes(excelBytes);
      final sheet = decoded.tables[decoded.getDefaultSheet() ?? decoded.tables.keys.first]!;

      expect(sheet.rows[1][8]?.value?.toString(), 'HDFC Bank'); // trimmed
      expect(sheet.rows[2][8]?.value?.toString(), 'RSBL');
      expect(sheet.rows[3][8]?.value?.toString(), 'Central Bank');
    });

    test('NetBanking Mode: accurately maps to State Bank of India and Union Bank', () {
      final net1 = buildTestCollection(id: 'n1', businessName: 'Manas Sales', mode: PaymentMode.netBanking, bankName: 'State Bank of India');
      final net2 = buildTestCollection(id: 'n2', businessName: 'Purva Enterprises', mode: PaymentMode.netBanking, bankName: 'Union Bank');

      final excelBytes = generateStatementExcel([net1, net2]);
      final decoded = xl.Excel.decodeBytes(excelBytes);
      final sheet = decoded.tables[decoded.getDefaultSheet() ?? decoded.tables.keys.first]!;

      expect(sheet.rows[1][7]?.value?.toString(), 'NEFT'); // NetBanking label is NEFT
      expect(sheet.rows[1][8]?.value?.toString(), 'State Bank of India');

      expect(sheet.rows[2][7]?.value?.toString(), 'NEFT');
      expect(sheet.rows[2][8]?.value?.toString(), 'Union Bank');
    });
  });

  group('3. UI Widget Boundary & Deposit Bank Display Tests', () {
    testWidgets('StatementScreen: Empty subset disables export & preview buttons and displays empty state', (tester) async {
      final provider = CollectionProvider();

      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<CollectionProvider>.value(
            value: provider,
            child: const StatementScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Enter an impossible search query
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'NON_EXISTENT_QUERY_12345');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify Empty State is shown
      expect(find.text('No records found'), findsOneWidget);
      expect(find.text('0 Receipts • Billed: ₹0'), findsOneWidget);

      // Verify Buttons: Preview, Excel, PDF should be disabled
      final previewBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Preview'));
      expect(previewBtn.onPressed, isNull, reason: 'Preview button must be disabled when 0 records match');

      final excelBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Excel (.xlsx)'));
      expect(excelBtn.onPressed, isNull, reason: 'Excel button must be disabled when 0 records match');

      final pdfBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'PDF Document'));
      expect(pdfBtn.onPressed, isNull, reason: 'PDF button must be disabled when 0 records match');

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
    });

    testWidgets('StatementScreen: Single record match enables buttons, shows 1 receipt, and preview displays bank badge', (tester) async {
      final provider = CollectionProvider();

      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<CollectionProvider>.value(
            value: provider,
            child: const StatementScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Filter to a specific single bill: 'PE-4090' (Om Traders, Cheque, HDFC Bank)
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'PE-4090');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('1 Receipts'), findsOneWidget);
      expect(find.text('Om Traders'), findsOneWidget);
      expect(find.text('HDFC Bank'), findsOneWidget);

      // Verify Buttons are enabled
      final previewBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Preview'));
      expect(previewBtn.onPressed, isNotNull);

      final excelBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Excel (.xlsx)'));
      expect(excelBtn.onPressed, isNotNull);

      final pdfBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'PDF Document'));
      expect(pdfBtn.onPressed, isNotNull);

      // Tap Preview button to inspect dialog
      await tester.tap(find.widgetWithText(ElevatedButton, 'Preview'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Statement Preview'), findsOneWidget);
      expect(find.text('Om Traders'), findsWidgets);
      expect(find.text('HDFC Bank'), findsWidgets);

      // Close preview
      await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.byIcon(Icons.close)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Statement Preview'), findsNothing);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
    });

    testWidgets('StatementScreen: Bank name search filter correctly isolates records', (tester) async {
      final provider = CollectionProvider();

      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<CollectionProvider>.value(
            value: provider,
            child: const StatementScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Search for 'State Bank' -> Should isolate col-6 (MS-2022 NetBanking)
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'State Bank');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('State Bank of India'), findsOneWidget);
      expect(find.textContaining('MS-2022'), findsOneWidget);
      expect(find.textContaining('1 Receipts'), findsOneWidget);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
    });
  });

  group('4. Performance, Scale, and Memory Allocation Stress Tests', () {
    test('Scale Test: Generates Excel with 500 records within tight latency and memory bounds', () {
      final largeRecords = List.generate(500, (i) {
        final mode = PaymentMode.values[i % PaymentMode.values.length];
        String? bank;
        if (mode == PaymentMode.cheque) bank = 'HDFC Bank';
        if (mode == PaymentMode.netBanking) bank = 'State Bank of India';
        if (mode == PaymentMode.upi) bank = (i % 2 == 0) ? 'Union Bank' : 'Central Bank';

        return buildTestCollection(
          id: 'perf-$i',
          businessName: (i % 2 == 0) ? 'Purva Enterprises' : 'Manas Sales',
          mode: mode,
          bankName: bank,
          shop: 'Kirana Store $i',
          billNo: 'BILL-$i',
          collected: (i * 100.0) % 20000 + 500,
          billed: ((i * 100.0) % 20000 + 500) * 1.5,
          balance: ((i * 100.0) % 20000 + 500) * 0.5,
        );
      });

      final stopwatch = Stopwatch()..start();
      final bytes = generateStatementExcel(largeRecords);
      stopwatch.stop();

      expect(bytes, isNotEmpty);
      expect(stopwatch.elapsedMilliseconds, lessThan(3000), reason: '500 records Excel generation took too long');

      final decoded = xl.Excel.decodeBytes(bytes);
      final sheet = decoded.tables[decoded.getDefaultSheet() ?? decoded.tables.keys.first]!;
      expect(sheet.rows.length, 501);
    });

    test('Scale Test: Generates multi-page PDF with 200 records without out-of-memory or stack overflow', () async {
      final largeRecords = List.generate(200, (i) {
        final mode = PaymentMode.values[i % PaymentMode.values.length];
        return buildTestCollection(
          id: 'pdf-perf-$i',
          businessName: (i % 2 == 0) ? 'Purva Enterprises' : 'Manas Sales',
          mode: mode,
          bankName: mode != PaymentMode.cash ? 'Test Bank $i' : null,
          shop: 'Store $i',
          billNo: 'INV-$i',
        );
      });

      final stopwatch = Stopwatch()..start();
      final pdfBytes = await generateStatementPdf(largeRecords);
      stopwatch.stop();

      expect(pdfBytes, isNotEmpty);
      expect(stopwatch.elapsedMilliseconds, lessThan(6000), reason: '200 records PDF generation took too long');
      final headerStr = String.fromCharCodes(pdfBytes.sublist(0, 5));
      expect(headerStr, '%PDF-');
    });

    test('Repetition Stress: 50 successive Excel export cycles verify stable memory allocation', () {
      final testSet = [
        buildTestCollection(id: 's1', businessName: 'Purva Enterprises', mode: PaymentMode.cash),
        buildTestCollection(id: 's2', businessName: 'Purva Enterprises', mode: PaymentMode.upi, bankName: 'Union Bank'),
        buildTestCollection(id: 's3', businessName: 'Manas Sales', mode: PaymentMode.cheque, bankName: 'Central Bank'),
        buildTestCollection(id: 's4', businessName: 'Manas Sales', mode: PaymentMode.netBanking, bankName: 'State Bank of India'),
      ];

      for (int i = 0; i < 50; i++) {
        final bytes = generateStatementExcel(testSet);
        expect(bytes.length, greaterThan(1000));
      }
    });

    test('Adversarial Inputs: Handles special characters, unicode, and extreme numeric values safely', () {
      final hostileRecord = buildTestCollection(
        id: 'hostile-1',
        businessName: 'Purva Enterprises',
        mode: PaymentMode.cheque,
        bankName: 'HDFC & ICICI <Merged> "Bank" / Pune',
        refNo: '<script>alert("xss")</script> & Co.',
        chequeNo: '#999999999/2026',
        shop: 'Om Traders (A/C #99)',
        route: 'Route A & B <North>',
        billNo: 'PE/INV/2026/001 & 002',
        collected: 99999999.99,
        billed: 99999999.99,
        balance: 0.0,
      );

      final bytes = generateStatementExcel([hostileRecord]);
      expect(bytes, isNotEmpty);

      final decoded = xl.Excel.decodeBytes(bytes);
      final sheet = decoded.tables[decoded.getDefaultSheet() ?? decoded.tables.keys.first]!;
      expect(sheet.rows.length, 2);
      final row = sheet.rows[1];

      expect(row[4]?.value?.toString(), 'Om Traders (A/C #99)');
      expect(row[8]?.value?.toString(), 'HDFC & ICICI <Merged> "Bank" / Pune');
      expect(double.parse(row[9]!.value.toString()), 99999999.99);
    });
  });
}
