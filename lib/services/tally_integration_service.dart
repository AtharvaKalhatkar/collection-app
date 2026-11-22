import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as xl;
import 'package:xml/xml.dart' as xml;
import 'package:uuid/uuid.dart';

import '../models/collection_model.dart';
import '../models/order_model.dart';
import '../models/pending_bill_model.dart';
import '../models/shop_model.dart';
import '../models/route_model.dart';
import '../utils/file_download/file_download.dart';

/// Result summary for Tally data import
class TallyImportResult {
  final List<PendingBillModel> importedBills;
  final List<ShopModel> newShops;
  final double totalAmount;
  final List<String> warnings;
  final bool success;
  final String message;

  const TallyImportResult({
    required this.importedBills,
    required this.newShops,
    required this.totalAmount,
    this.warnings = const [],
    required this.success,
    required this.message,
  });
}

/// Service implementing standard Tally XML (Tally Prime / ERP 9) and Tally Prime Excel
/// specifications for seamless two-way integration.
class TallyIntegrationService {
  static const _uuid = Uuid();

  /// Escape XML special characters
  static String xmlEscape(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Format Date for Tally XML: YYYYMMDD
  static String formatTallyDate(DateTime date) {
    return DateFormat('yyyyMMdd').format(date);
  }

  /// Format Display Date for Tally: DD-MMM-YYYY
  static String formatDisplayDate(DateTime date) {
    return DateFormat('dd-MMM-yyyy').format(date);
  }

  // ===========================================================================
  // 1. EXPORT: Collections -> Tally XML (Receipt Vouchers)
  // ===========================================================================
  /// Generates Tally XML containing Receipt vouchers for field collections.
  /// Tally Structure:
  /// - Envelope / Header (Import Data)
  /// - Voucher Type: Receipt
  /// - Party Ledger (Sundry Debtors) -> Credit (Positive in Tally tag, deemed positive: No)
  /// - Cash / Bank Ledger -> Debit (Negative in Tally tag, deemed positive: Yes)
  /// - Bill Allocations against reference bill number
  static String generateReceiptsXml({
    required List<CollectionModel> collections,
    required String companyName,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="utf-8"?>');
    buffer.writeln('<ENVELOPE>');
    buffer.writeln('  <HEADER>');
    buffer.writeln('    <TALLYREQUEST>Import Data</TALLYREQUEST>');
    buffer.writeln('  </HEADER>');
    buffer.writeln('  <BODY>');
    buffer.writeln('    <DATA>');

    for (final col in collections) {
      final tallyDate = formatTallyDate(col.collectedAt);
      final voucherNo = xmlEscape(col.id.length > 16 ? col.id.substring(0, 16) : col.id);
      final partyName = xmlEscape(col.shopName.trim());
      final billNo = xmlEscape(col.billNumber.trim());
      final amount = col.collectedAmount;
      final amountStr = amount.toStringAsFixed(2);

      // Determine Bank / Cash ledger name
      String debitLedger;
      if (col.paymentMode == PaymentMode.cash) {
        debitLedger = 'Cash';
      } else if (col.bankName != null && col.bankName!.trim().isNotEmpty) {
        debitLedger = col.bankName!.trim();
      } else {
        debitLedger = col.businessName == 'Purva Enterprises' ? 'Union Bank' : 'CC Bank';
      }
      final cleanDebitLedger = xmlEscape(debitLedger);

      // Narration
      final narrationParts = <String>[
        'Collected by ${col.salesmanName}',
        'Mode: ${col.paymentMode.displayName}',
        'Bill: ${col.billNumber}',
      ];
      if (col.referenceNumber != null && col.referenceNumber!.isNotEmpty) {
        narrationParts.add('Ref: ${col.referenceNumber}');
      }
      if (col.chequeNumber != null && col.chequeNumber!.isNotEmpty) {
        narrationParts.add('Chq: ${col.chequeNumber}');
      }
      if (col.remarks != null && col.remarks!.isNotEmpty) {
        narrationParts.add('Remarks: ${col.remarks}');
      }
      final narration = xmlEscape(narrationParts.join(' | '));

      buffer.writeln('      <TALLYMESSAGE xmlns:UDF="TallyUDF">');
      buffer.writeln('        <VOUCHER VCHTYPE="Receipt" ACTION="Create" OBJVIEW="Accounting Voucher View">');
      buffer.writeln('          <DATE>$tallyDate</DATE>');
      buffer.writeln('          <EFFECTIVEDATE>$tallyDate</EFFECTIVEDATE>');
      buffer.writeln('          <VOUCHERTYPENAME>Receipt</VOUCHERTYPENAME>');
      buffer.writeln('          <VOUCHERNUMBER>$voucherNo</VOUCHERNUMBER>');
      buffer.writeln('          <PARTYLEDGERNAME>$partyName</PARTYLEDGERNAME>');
      buffer.writeln('          <PERSISTEDVIEW>Accounting Voucher View</PERSISTEDVIEW>');
      buffer.writeln('          <NARRATION>$narration</NARRATION>');

      // 1. Party Ledger Entry (CREDIT - Sundry Debtors)
      buffer.writeln('          <ALLLEDGERENTRIES.LIST>');
      buffer.writeln('            <LEDGERNAME>$partyName</LEDGERNAME>');
      buffer.writeln('            <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>');
      buffer.writeln('            <AMOUNT>$amountStr</AMOUNT>');
      if (billNo.isNotEmpty) {
        buffer.writeln('            <BILLALLOCATIONS.LIST>');
        buffer.writeln('              <NAME>$billNo</NAME>');
        buffer.writeln('              <BILLTYPE>Agst Ref</BILLTYPE>');
        buffer.writeln('              <AMOUNT>$amountStr</AMOUNT>');
        buffer.writeln('            </BILLALLOCATIONS.LIST>');
      }
      buffer.writeln('          </ALLLEDGERENTRIES.LIST>');

      // 2. Bank / Cash Ledger Entry (DEBIT - Cash / Bank)
      buffer.writeln('          <ALLLEDGERENTRIES.LIST>');
      buffer.writeln('            <LEDGERNAME>$cleanDebitLedger</LEDGERNAME>');
      buffer.writeln('            <ISDEEMEDPOSITIVE>Yes</ISDEEMEDPOSITIVE>');
      buffer.writeln('            <AMOUNT>-$amountStr</AMOUNT>');
      buffer.writeln('          </ALLLEDGERENTRIES.LIST>');

      buffer.writeln('        </VOUCHER>');
      buffer.writeln('      </TALLYMESSAGE>');
    }

    buffer.writeln('    </DATA>');
    buffer.writeln('  </BODY>');
    buffer.writeln('</ENVELOPE>');
    return buffer.toString();
  }

  /// Download Collections as Tally XML
  static Future<void> exportCollectionsToTallyXml({
    required List<CollectionModel> collections,
    required String companyName,
  }) async {
    final xmlContent = generateReceiptsXml(
      collections: collections,
      companyName: companyName,
    );
    final bytes = utf8.encode(xmlContent);
    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final cleanCompany = companyName.replaceAll(RegExp(r'\s+'), '_');
    final fileName = 'Tally_Receipts_${cleanCompany}_$timestamp.xml';

    await downloadFile(
      bytes: bytes,
      fileName: fileName,
      mimeType: 'application/xml',
    );
  }

  // ===========================================================================
  // 2. EXPORT: Booked Orders -> Tally XML (Sales Order Vouchers)
  // ===========================================================================
  /// Generates Tally XML containing Sales Order vouchers for field booked store orders.
  static String generateSalesOrdersXml({
    required List<SalesOrderModel> orders,
    required String companyName,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="utf-8"?>');
    buffer.writeln('<ENVELOPE>');
    buffer.writeln('  <HEADER>');
    buffer.writeln('    <TALLYREQUEST>Import Data</TALLYREQUEST>');
    buffer.writeln('  </HEADER>');
    buffer.writeln('  <BODY>');
    buffer.writeln('    <DATA>');

    for (final ord in orders) {
      final tallyDate = formatTallyDate(ord.orderDate);
      final voucherNo = xmlEscape(ord.orderNumber);
      final partyName = xmlEscape(ord.shopName.trim());
      final totalStr = ord.totalAmount.toStringAsFixed(2);
      final narration = xmlEscape(
        'Booked by: ${ord.salesmanName} | Route: ${ord.routeName}${ord.notes != null && ord.notes!.isNotEmpty ? " | Notes: ${ord.notes}" : ""}',
      );

      buffer.writeln('      <TALLYMESSAGE xmlns:UDF="TallyUDF">');
      buffer.writeln('        <VOUCHER VCHTYPE="Sales Order" ACTION="Create" OBJVIEW="Invoice Voucher View">');
      buffer.writeln('          <DATE>$tallyDate</DATE>');
      buffer.writeln('          <EFFECTIVEDATE>$tallyDate</EFFECTIVEDATE>');
      buffer.writeln('          <VOUCHERTYPENAME>Sales Order</VOUCHERTYPENAME>');
      buffer.writeln('          <VOUCHERNUMBER>$voucherNo</VOUCHERNUMBER>');
      buffer.writeln('          <PARTYLEDGERNAME>$partyName</PARTYLEDGERNAME>');
      buffer.writeln('          <PERSISTEDVIEW>Invoice Voucher View</PERSISTEDVIEW>');
      buffer.writeln('          <NARRATION>$narration</NARRATION>');

      // Party Debit Entry
      buffer.writeln('          <ALLLEDGERENTRIES.LIST>');
      buffer.writeln('            <LEDGERNAME>$partyName</LEDGERNAME>');
      buffer.writeln('            <ISDEEMEDPOSITIVE>Yes</ISDEEMEDPOSITIVE>');
      buffer.writeln('            <AMOUNT>-$totalStr</AMOUNT>');
      buffer.writeln('          </ALLLEDGERENTRIES.LIST>');

      // Inventory entries
      for (final it in ord.items) {
        final itemName = xmlEscape(it.productName.trim());
        final itemRate = it.rate.toStringAsFixed(2);
        final itemSubtotal = it.subtotal.toStringAsFixed(2);
        final qtyStr = it.cases > 0
            ? '${it.cases} Cs${it.units > 0 ? " ${it.units} Nos" : ""}'
            : '${it.units} Nos';

        buffer.writeln('          <ALLINVENTORYENTRIES.LIST>');
        buffer.writeln('            <STOCKITEMNAME>$itemName</STOCKITEMNAME>');
        buffer.writeln('            <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>');
        buffer.writeln('            <RATE>$itemRate/Cs</RATE>');
        buffer.writeln('            <AMOUNT>$itemSubtotal</AMOUNT>');
        buffer.writeln('            <ACTUALQTY> $qtyStr</ACTUALQTY>');
        buffer.writeln('            <BILLEDQTY> $qtyStr</BILLEDQTY>');
        buffer.writeln('            <ACCOUNTINGALLOCATIONS.LIST>');
        buffer.writeln('              <LEDGERNAME>Sales Account</LEDGERNAME>');
        buffer.writeln('              <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>');
        buffer.writeln('              <AMOUNT>$itemSubtotal</AMOUNT>');
        buffer.writeln('            </ACCOUNTINGALLOCATIONS.LIST>');
        buffer.writeln('          </ALLINVENTORYENTRIES.LIST>');
      }

      buffer.writeln('        </VOUCHER>');
      buffer.writeln('      </TALLYMESSAGE>');
    }

    buffer.writeln('    </DATA>');
    buffer.writeln('  </BODY>');
    buffer.writeln('</ENVELOPE>');
    return buffer.toString();
  }

  /// Download Booked Orders as Tally XML
  static Future<void> exportSalesOrdersToTallyXml({
    required List<SalesOrderModel> orders,
    required String companyName,
  }) async {
    final xmlContent = generateSalesOrdersXml(
      orders: orders,
      companyName: companyName,
    );
    final bytes = utf8.encode(xmlContent);
    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final cleanCompany = companyName.replaceAll(RegExp(r'\s+'), '_');
    final fileName = 'Tally_SalesOrders_${cleanCompany}_$timestamp.xml';

    await downloadFile(
      bytes: bytes,
      fileName: fileName,
      mimeType: 'application/xml',
    );
  }

  // ===========================================================================
  // 3. EXPORT: Outlets / Shops -> Tally XML (Ledger Masters)
  // ===========================================================================
  /// Generates Tally XML for Outlets under 'Sundry Debtors' group with route & contact details.
  static String generateOutletsLedgerXml({
    required List<ShopModel> shops,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="utf-8"?>');
    buffer.writeln('<ENVELOPE>');
    buffer.writeln('  <HEADER>');
    buffer.writeln('    <TALLYREQUEST>Import Data</TALLYREQUEST>');
    buffer.writeln('  </HEADER>');
    buffer.writeln('  <BODY>');
    buffer.writeln('    <DATA>');

    for (final s in shops) {
      final name = xmlEscape(s.name.trim());
      final phone = xmlEscape(s.mobileNumber.trim());
      final address = xmlEscape('${s.address.trim()}${s.routeName.isNotEmpty ? " [Route: ${s.routeName}]" : ""}');

      buffer.writeln('      <TALLYMESSAGE xmlns:UDF="TallyUDF">');
      buffer.writeln('        <LEDGER NAME="$name" ACTION="Create">');
      buffer.writeln('          <NAME>$name</NAME>');
      buffer.writeln('          <PARENT>Sundry Debtors</PARENT>');
      buffer.writeln('          <ISBILLWISEON>Yes</ISBILLWISEON>');
      buffer.writeln('          <AFFECTSSTOCK>No</AFFECTSSTOCK>');
      buffer.writeln('          <COUNTRYNAME>India</COUNTRYNAME>');
      buffer.writeln('          <STATENAME>Maharashtra</STATENAME>');
      if (phone.isNotEmpty) {
        buffer.writeln('          <LEDGERPHONE>$phone</LEDGERPHONE>');
      }
      if (address.isNotEmpty) {
        buffer.writeln('          <ADDRESS.LIST>');
        buffer.writeln('            <ADDRESS>$address</ADDRESS>');
        buffer.writeln('          </ADDRESS.LIST>');
      }
      buffer.writeln('        </LEDGER>');
      buffer.writeln('      </TALLYMESSAGE>');
    }

    buffer.writeln('    </DATA>');
    buffer.writeln('  </BODY>');
    buffer.writeln('</ENVELOPE>');
    return buffer.toString();
  }

  /// Download Outlets as Tally XML
  static Future<void> exportOutletsToTallyXml({
    required List<ShopModel> shops,
  }) async {
    final xmlContent = generateOutletsLedgerXml(shops: shops);
    final bytes = utf8.encode(xmlContent);
    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final fileName = 'Tally_Ledgers_SundryDebtors_$timestamp.xml';

    await downloadFile(
      bytes: bytes,
      fileName: fileName,
      mimeType: 'application/xml',
    );
  }

  // ===========================================================================
  // 4. EXPORT: Collections -> Tally Prime Excel Import Template
  // ===========================================================================
  /// Exports collections in Tally Prime Release 4+ Excel import template.
  static Future<void> exportCollectionsToTallyExcel({
    required List<CollectionModel> collections,
    required String companyName,
  }) async {
    final excel = xl.Excel.createExcel();
    final sheet = excel['Receipt_Vouchers'];
    excel.setDefaultSheet('Receipt_Vouchers');

    // Header Styles
    final headerStyle = xl.CellStyle(
      bold: true,
      fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: xl.ExcelColor.fromHexString('#0F172A'),
      horizontalAlign: xl.HorizontalAlign.Center,
      verticalAlign: xl.VerticalAlign.Center,
    );

    final headers = [
      'Date (DD-MM-YYYY)',
      'Voucher Type',
      'Voucher Number',
      'Party / Customer Name',
      'Bank / Cash Ledger',
      'Amount (₹)',
      'Payment Mode',
      'Bill Number',
      'Reference / Cheque No',
      'Collected By',
      'Firm Name',
      'Narration',
    ];

    for (int col = 0; col < headers.length; col++) {
      final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
      cell.value = xl.TextCellValue(headers[col]);
      cell.cellStyle = headerStyle;
    }

    for (int row = 0; row < collections.length; row++) {
      final c = collections[row];
      final rowIndex = row + 1;

      String debitLedger;
      if (c.paymentMode == PaymentMode.cash) {
        debitLedger = 'Cash';
      } else if (c.bankName != null && c.bankName!.trim().isNotEmpty) {
        debitLedger = c.bankName!.trim();
      } else {
        debitLedger = c.businessName == 'Purva Enterprises' ? 'Union Bank' : 'CC Bank';
      }

      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value =
          xl.TextCellValue(DateFormat('dd-MM-yyyy').format(c.collectedAt));
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex)).value =
          xl.TextCellValue('Receipt');
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex)).value =
          xl.TextCellValue(c.id.length > 12 ? c.id.substring(0, 12) : c.id);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex)).value =
          xl.TextCellValue(c.shopName);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex)).value =
          xl.TextCellValue(debitLedger);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex)).value =
          xl.DoubleCellValue(c.collectedAmount);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex)).value =
          xl.TextCellValue(c.paymentMode.displayName);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIndex)).value =
          xl.TextCellValue(c.billNumber);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIndex)).value =
          xl.TextCellValue(c.referenceNumber ?? c.chequeNumber ?? '');
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: rowIndex)).value =
          xl.TextCellValue(c.salesmanName);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: rowIndex)).value =
          xl.TextCellValue(c.businessName);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: rowIndex)).value =
          xl.TextCellValue('Field collection via ${c.paymentMode.displayName} by ${c.salesmanName}');
    }

    final bytes = excel.save();
    if (bytes != null) {
      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final cleanCompany = companyName.replaceAll(RegExp(r'\s+'), '_');
      await downloadFile(
        bytes: bytes,
        fileName: 'TallyPrime_Receipts_${cleanCompany}_$timestamp.xlsx',
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    }
  }

  // ===========================================================================
  // 5. IMPORT: Pending Bills from Tally XML
  // ===========================================================================
  /// Parses standard Tally XML (Bills Outstanding or Sales Vouchers) into PendingBillModel list.
  static TallyImportResult parsePendingBillsFromTallyXml({
    required String xmlContent,
    required List<RouteModel> existingRoutes,
    required List<ShopModel> existingShops,
    required String defaultFirm,
    String? fallbackRouteId,
  }) {
    final warnings = <String>[];
    final importedBills = <PendingBillModel>[];
    final newShops = <ShopModel>[];

    // Find default fallback route
    RouteModel defaultRoute = existingRoutes.isNotEmpty
        ? existingRoutes.first
        : RouteModel(id: 'r_general', name: 'General Route');
    if (fallbackRouteId != null && fallbackRouteId.isNotEmpty) {
      final found = existingRoutes.where((r) => r.id == fallbackRouteId).firstOrNull;
      if (found != null) defaultRoute = found;
    }

    try {
      final document = xml.XmlDocument.parse(xmlContent);

      // 1. Look for <VOUCHER> tags (Sales Vouchers / Invoices exported from Tally)
      final vouchers = document.findAllElements('VOUCHER');
      if (vouchers.isNotEmpty) {
        for (final v in vouchers) {
          try {
            // Process Sales, Sales Order, or any bill voucher
            final dateStr = v.findElements('DATE').firstOrNull?.innerText ?? '';
            DateTime invoiceDate = DateTime.now();
            if (dateStr.length == 8) {
              final y = int.tryParse(dateStr.substring(0, 4)) ?? 2026;
              final m = int.tryParse(dateStr.substring(4, 6)) ?? 1;
              final d = int.tryParse(dateStr.substring(6, 8)) ?? 1;
              invoiceDate = DateTime(y, m, d);
            }

            final billNo = v.findElements('VOUCHERNUMBER').firstOrNull?.innerText ??
                v.findElements('REFERENCE').firstOrNull?.innerText ??
                'INV-${DateTime.now().millisecondsSinceEpoch}';

            final partyName = v.findElements('PARTYLEDGERNAME').firstOrNull?.innerText ??
                v.findElements('PARTYNAME').firstOrNull?.innerText ??
                '';

            if (partyName.trim().isEmpty) continue;

            // Extract total amount from ledger entries
            double totalAmount = 0.0;
            final ledgerEntries = v.findAllElements('ALLLEDGERENTRIES.LIST');
            for (final le in ledgerEntries) {
              final leParty = le.findElements('LEDGERNAME').firstOrNull?.innerText ?? '';
              if (leParty.toLowerCase().trim() == partyName.toLowerCase().trim()) {
                final amtStr = le.findElements('AMOUNT').firstOrNull?.innerText ?? '0';
                final amt = double.tryParse(amtStr.replaceAll(',', '').replaceAll('-', '')) ?? 0.0;
                if (amt > totalAmount) totalAmount = amt;
              }
            }

            if (totalAmount <= 0) {
              // Try inventory entries or voucher amount
              for (final inv in v.findAllElements('ALLINVENTORYENTRIES.LIST')) {
                final amtStr = inv.findElements('AMOUNT').firstOrNull?.innerText ?? '0';
                final amt = double.tryParse(amtStr.replaceAll(',', '').replaceAll('-', '')) ?? 0.0;
                totalAmount += amt;
              }
            }

            if (totalAmount <= 0) continue;

            // Find or create shop
            final cleanShopName = partyName.trim();
            ShopModel? shop = existingShops
                .where((s) => s.name.toLowerCase().trim() == cleanShopName.toLowerCase())
                .firstOrNull;

            shop ??= newShops
                .where((s) => s.name.toLowerCase().trim() == cleanShopName.toLowerCase())
                .firstOrNull;

            if (shop == null) {
              shop = ShopModel(
                id: 'shop_tally_${_uuid.v4().substring(0, 8)}',
                name: cleanShopName,
                routeId: defaultRoute.id,
                routeName: defaultRoute.name,
                mobileNumber: '',
                address: defaultRoute.name,
              );
              newShops.add(shop);
            }

            final bill = PendingBillModel(
              id: 'pb_tally_${_uuid.v4()}',
              businessName: defaultFirm,
              routeId: shop.routeId,
              routeName: shop.routeName,
              shopId: shop.id,
              shopName: shop.name,
              invoiceDate: invoiceDate,
              deliveryDate: invoiceDate.add(const Duration(days: 1)),
              billNumber: billNo.trim(),
              totalAmount: totalAmount,
              collectedAmount: 0.0,
              status: 'pending',
            );
            importedBills.add(bill);
          } catch (e) {
            warnings.add('Error parsing voucher: $e');
          }
        }
      }

      // 2. Also check for <BILL> / <BILLOUTSTANDINGS> / <BILLALLOCATION> tags (Tally Outstandings Report XML)
      if (importedBills.isEmpty) {
        final billElements = document.findAllElements('BILL').isNotEmpty
            ? document.findAllElements('BILL')
            : document.findAllElements('BILLALLOCATION');

        for (final b in billElements) {
          try {
            final billNo = b.findElements('BILLNAME').firstOrNull?.innerText ??
                b.findElements('NAME').firstOrNull?.innerText ??
                b.findElements('BILLNO').firstOrNull?.innerText ??
                '';
            final partyName = b.findElements('PARTYNAME').firstOrNull?.innerText ??
                b.findElements('LEDGERNAME').firstOrNull?.innerText ??
                '';
            final amtStr = b.findElements('CLOSINGBALANCE').firstOrNull?.innerText ??
                b.findElements('AMOUNT').firstOrNull?.innerText ??
                b.findElements('OPENINGBALANCE').firstOrNull?.innerText ??
                '0';
            final totalAmount = double.tryParse(amtStr.replaceAll(',', '').replaceAll('-', '')) ?? 0.0;

            if (billNo.isEmpty || partyName.isEmpty || totalAmount <= 0) continue;

            final dateStr = b.findElements('BILLDATE').firstOrNull?.innerText ??
                b.findElements('DATE').firstOrNull?.innerText ??
                '';
            DateTime invoiceDate = DateTime.now();
            if (dateStr.length == 8) {
              final y = int.tryParse(dateStr.substring(0, 4)) ?? 2026;
              final m = int.tryParse(dateStr.substring(4, 6)) ?? 1;
              final d = int.tryParse(dateStr.substring(6, 8)) ?? 1;
              invoiceDate = DateTime(y, m, d);
            }

            final cleanShopName = partyName.trim();
            ShopModel? shop = existingShops
                .where((s) => s.name.toLowerCase().trim() == cleanShopName.toLowerCase())
                .firstOrNull;

            shop ??= newShops
                .where((s) => s.name.toLowerCase().trim() == cleanShopName.toLowerCase())
                .firstOrNull;

            if (shop == null) {
              shop = ShopModel(
                id: 'shop_tally_${_uuid.v4().substring(0, 8)}',
                name: cleanShopName,
                routeId: defaultRoute.id,
                routeName: defaultRoute.name,
                mobileNumber: '',
                address: defaultRoute.name,
              );
              newShops.add(shop);
            }

            final pendingBill = PendingBillModel(
              id: 'pb_tally_${_uuid.v4()}',
              businessName: defaultFirm,
              routeId: shop.routeId,
              routeName: shop.routeName,
              shopId: shop.id,
              shopName: shop.name,
              invoiceDate: invoiceDate,
              deliveryDate: invoiceDate.add(const Duration(days: 1)),
              billNumber: billNo.trim(),
              totalAmount: totalAmount,
              collectedAmount: 0.0,
              status: 'pending',
            );
            importedBills.add(pendingBill);
          } catch (e) {
            warnings.add('Error parsing bill node: $e');
          }
        }
      }

      final totalSum = importedBills.fold(0.0, (sum, b) => sum + b.totalAmount);

      return TallyImportResult(
        importedBills: importedBills,
        newShops: newShops,
        totalAmount: totalSum,
        warnings: warnings,
        success: importedBills.isNotEmpty,
        message: importedBills.isNotEmpty
            ? 'Successfully parsed ${importedBills.length} pending bills from Tally XML (₹${totalSum.toStringAsFixed(2)}).'
            : 'No valid bills found in the XML file. Ensure this is a Tally Sales or Outstandings XML.',
      );
    } catch (e) {
      return TallyImportResult(
        importedBills: const [],
        newShops: const [],
        totalAmount: 0.0,
        warnings: [e.toString()],
        success: false,
        message: 'Failed to parse Tally XML: $e',
      );
    }
  }

  // ===========================================================================
  // 6. IMPORT: Pending Bills from Tally Excel / Standard Excel
  // ===========================================================================
  /// Parses Excel file exported from Tally (Bills Outstanding, Sales Register, etc.)
  static TallyImportResult parsePendingBillsFromExcel({
    required List<int> bytes,
    required List<RouteModel> existingRoutes,
    required List<ShopModel> existingShops,
    required String defaultFirm,
    String? fallbackRouteId,
  }) {
    final warnings = <String>[];
    final importedBills = <PendingBillModel>[];
    final newShops = <ShopModel>[];

    RouteModel defaultRoute = existingRoutes.isNotEmpty
        ? existingRoutes.first
        : RouteModel(id: 'r_general', name: 'General Route');
    if (fallbackRouteId != null && fallbackRouteId.isNotEmpty) {
      final found = existingRoutes.where((r) => r.id == fallbackRouteId).firstOrNull;
      if (found != null) defaultRoute = found;
    }

    try {
      final excel = xl.Excel.decodeBytes(bytes);
      final sheetName = excel.tables.keys.first;
      final table = excel.tables[sheetName];

      if (table == null || table.rows.isEmpty) {
        return const TallyImportResult(
          importedBills: [],
          newShops: [],
          totalAmount: 0.0,
          success: false,
          message: 'The selected Excel file is empty.',
        );
      }

      // Detect header row index
      int headerRowIdx = -1;
      int colDate = -1;
      int colBillNo = -1;
      int colParty = -1;
      int colAmount = -1;
      int colRoute = -1;

      for (int r = 0; r < table.rows.length && r < 15; r++) {
        final row = table.rows[r];
        for (int c = 0; c < row.length; c++) {
          final val = row[c]?.value?.toString().toLowerCase().trim() ?? '';
          if (val.contains('date') && colDate == -1) colDate = c;
          if ((val.contains('bill') || val.contains('ref') || val.contains('inv')) && colBillNo == -1) colBillNo = c;
          if ((val.contains('party') || val.contains('particulars') || val.contains('customer') || val.contains('shop') || val.contains('ledger')) && colParty == -1) colParty = c;
          if ((val.contains('amount') || val.contains('balance') || val.contains('pending') || val.contains('debit') || val.contains('total')) && colAmount == -1) colAmount = c;
          if ((val.contains('route') || val.contains('area') || val.contains('beat')) && colRoute == -1) colRoute = c;
        }

        // If we found at least party, amount and (billNo or date), this is our header
        if (colParty != -1 && colAmount != -1 && (colBillNo != -1 || colDate != -1)) {
          headerRowIdx = r;
          break;
        }
      }

      if (headerRowIdx == -1) {
        // Fallback default column indexes if no header names matched
        colDate = 0;
        colBillNo = 1;
        colParty = 2;
        colAmount = 3;
        headerRowIdx = 0;
      }

      for (int r = headerRowIdx + 1; r < table.rows.length; r++) {
        final row = table.rows[r];
        if (row.isEmpty) continue;

        final rawParty = colParty < row.length ? row[colParty]?.value?.toString().trim() ?? '' : '';
        if (rawParty.isEmpty || rawParty.toLowerCase().contains('total')) continue;

        // Extract amount
        final rawAmount = colAmount < row.length ? row[colAmount]?.value?.toString().trim() ?? '' : '';
        final cleanAmtStr = rawAmount.replaceAll(RegExp(r'[^\d.]'), '');
        final totalAmount = double.tryParse(cleanAmtStr) ?? 0.0;
        if (totalAmount <= 0) continue;

        // Extract bill number
        var billNo = colBillNo < row.length ? row[colBillNo]?.value?.toString().trim() ?? '' : '';
        if (billNo.isEmpty) {
          billNo = 'BILL-${DateTime.now().millisecondsSinceEpoch % 100000 + r}';
        }

        // Extract Date
        DateTime invoiceDate = DateTime.now();
        if (colDate < row.length && row[colDate]?.value != null) {
          final rawDate = row[colDate]?.value?.toString().trim() ?? '';
          try {
            if (rawDate.contains('-')) {
              final parts = rawDate.split('-');
              if (parts.length == 3) {
                if (parts[0].length == 4) {
                  invoiceDate = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
                } else {
                  invoiceDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
                }
              }
            } else if (rawDate.contains('/')) {
              final parts = rawDate.split('/');
              if (parts.length == 3) {
                invoiceDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
              }
            }
          } catch (_) {}
        }

        // Determine Route
        RouteModel chosenRoute = defaultRoute;
        if (colRoute != -1 && colRoute < row.length) {
          final routeNameFromRow = row[colRoute]?.value?.toString().trim() ?? '';
          if (routeNameFromRow.isNotEmpty) {
            final matched = existingRoutes
                .where((rt) => rt.name.toLowerCase().trim() == routeNameFromRow.toLowerCase())
                .firstOrNull;
            if (matched != null) chosenRoute = matched;
          }
        }

        // Find or create shop
        final cleanShopName = rawParty.trim();
        ShopModel? shop = existingShops
            .where((s) => s.name.toLowerCase().trim() == cleanShopName.toLowerCase())
            .firstOrNull;

        shop ??= newShops
            .where((s) => s.name.toLowerCase().trim() == cleanShopName.toLowerCase())
            .firstOrNull;

        if (shop == null) {
          shop = ShopModel(
            id: 'shop_tally_${_uuid.v4().substring(0, 8)}',
            name: cleanShopName,
            routeId: chosenRoute.id,
            routeName: chosenRoute.name,
            mobileNumber: '',
            address: chosenRoute.name,
          );
          newShops.add(shop);
        }

        final pendingBill = PendingBillModel(
          id: 'pb_tally_${_uuid.v4()}',
          businessName: defaultFirm,
          routeId: shop.routeId,
          routeName: shop.routeName,
          shopId: shop.id,
          shopName: shop.name,
          invoiceDate: invoiceDate,
          deliveryDate: invoiceDate.add(const Duration(days: 1)),
          billNumber: billNo.trim(),
          totalAmount: totalAmount,
          collectedAmount: 0.0,
          status: 'pending',
        );
        importedBills.add(pendingBill);
      }

      final totalSum = importedBills.fold(0.0, (sum, b) => sum + b.totalAmount);

      return TallyImportResult(
        importedBills: importedBills,
        newShops: newShops,
        totalAmount: totalSum,
        warnings: warnings,
        success: importedBills.isNotEmpty,
        message: importedBills.isNotEmpty
            ? 'Successfully imported ${importedBills.length} pending bills from Excel (₹${totalSum.toStringAsFixed(2)}).'
            : 'No valid rows found in the Excel file.',
      );
    } catch (e) {
      return TallyImportResult(
        importedBills: const [],
        newShops: const [],
        totalAmount: 0.0,
        warnings: [e.toString()],
        success: false,
        message: 'Failed to read Tally Excel file: $e',
      );
    }
  }

  // ===========================================================================
  // 7. DOWNLOAD SAMPLE TALLY IMPORT TEMPLATES
  // ===========================================================================
  /// Download a sample Tally Excel file that users can fill and import directly
  static Future<void> downloadSamplePendingBillsExcel() async {
    final excel = xl.Excel.createExcel();
    final sheet = excel['Pending_Bills_Template'];
    excel.setDefaultSheet('Pending_Bills_Template');

    final headerStyle = xl.CellStyle(
      bold: true,
      fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: xl.ExcelColor.fromHexString('#1E3A8A'),
      horizontalAlign: xl.HorizontalAlign.Center,
      verticalAlign: xl.VerticalAlign.Center,
    );

    final headers = [
      'Date (DD-MM-YYYY)',
      'Bill / Ref Number',
      'Party Name / Shop Name',
      'Pending Amount (₹)',
      'Route Name (Optional)',
      'Firm Name (Purva Enterprises / Manas Sales)',
    ];

    for (int col = 0; col < headers.length; col++) {
      final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
      cell.value = xl.TextCellValue(headers[col]);
      cell.cellStyle = headerStyle;
    }

    final sampleRows = [
      ['22-11-2026', 'INV-1001', 'G R Mart', 4500.0, 'Kharabwadi Mahalunge', 'Purva Enterprises'],
      ['22-11-2026', 'INV-1002', 'B G Mart', 3200.0, 'Kharabwadi Mahalunge', 'Purva Enterprises'],
      ['21-11-2026', 'INV-1003', 'Sai Krupa Super Market', 5800.0, 'Chakan Industrial', 'Purva Enterprises'],
      ['20-11-2026', 'INV-1004', 'Mahesh Traders', 2750.0, 'Talegaon Dabhade', 'Manas Sales'],
    ];

    for (int r = 0; r < sampleRows.length; r++) {
      final row = sampleRows[r];
      final rowIndex = r + 1;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value = xl.TextCellValue(row[0] as String);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex)).value = xl.TextCellValue(row[1] as String);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex)).value = xl.TextCellValue(row[2] as String);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex)).value = xl.DoubleCellValue(row[3] as double);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex)).value = xl.TextCellValue(row[4] as String);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex)).value = xl.TextCellValue(row[5] as String);
    }

    final bytes = excel.save();
    if (bytes != null) {
      await downloadFile(
        bytes: bytes,
        fileName: 'Tally_Pending_Bills_Sample_Template.xlsx',
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    }
  }

  /// Download a sample Tally XML file
  static Future<void> downloadSamplePendingBillsXml() async {
    final sampleXml = '''<?xml version="1.0" encoding="utf-8"?>
<ENVELOPE>
  <HEADER>
    <TALLYREQUEST>Import Data</TALLYREQUEST>
  </HEADER>
  <BODY>
    <DATA>
      <TALLYMESSAGE xmlns:UDF="TallyUDF">
        <VOUCHER VCHTYPE="Sales" ACTION="Create">
          <DATE>20261122</DATE>
          <VOUCHERTYPENAME>Sales</VOUCHERTYPENAME>
          <VOUCHERNUMBER>INV-1001</VOUCHERNUMBER>
          <PARTYLEDGERNAME>G R Mart</PARTYLEDGERNAME>
          <ALLLEDGERENTRIES.LIST>
            <LEDGERNAME>G R Mart</LEDGERNAME>
            <ISDEEMEDPOSITIVE>Yes</ISDEEMEDPOSITIVE>
            <AMOUNT>-4500.00</AMOUNT>
          </ALLLEDGERENTRIES.LIST>
          <ALLLEDGERENTRIES.LIST>
            <LEDGERNAME>Sales Account</LEDGERNAME>
            <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>
            <AMOUNT>4500.00</AMOUNT>
          </ALLLEDGERENTRIES.LIST>
        </VOUCHER>
      </TALLYMESSAGE>
      <TALLYMESSAGE xmlns:UDF="TallyUDF">
        <VOUCHER VCHTYPE="Sales" ACTION="Create">
          <DATE>20261122</DATE>
          <VOUCHERTYPENAME>Sales</VOUCHERTYPENAME>
          <VOUCHERNUMBER>INV-1002</VOUCHERNUMBER>
          <PARTYLEDGERNAME>B G Mart</PARTYLEDGERNAME>
          <ALLLEDGERENTRIES.LIST>
            <LEDGERNAME>B G Mart</LEDGERNAME>
            <ISDEEMEDPOSITIVE>Yes</ISDEEMEDPOSITIVE>
            <AMOUNT>-3200.00</AMOUNT>
          </ALLLEDGERENTRIES.LIST>
          <ALLLEDGERENTRIES.LIST>
            <LEDGERNAME>Sales Account</LEDGERNAME>
            <ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>
            <AMOUNT>3200.00</AMOUNT>
          </ALLLEDGERENTRIES.LIST>
        </VOUCHER>
      </TALLYMESSAGE>
    </DATA>
  </BODY>
</ENVELOPE>''';

    final bytes = utf8.encode(sampleXml);
    await downloadFile(
      bytes: bytes,
      fileName: 'Tally_Sample_Sales_Bills.xml',
      mimeType: 'application/xml',
    );
  }
}
