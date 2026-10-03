import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/order_model.dart';
import '../utils/file_download/file_download.dart';

class GodownBillingPdfService {
  /// Generates a consolidated PDF for godown picking and billing staff.
  static Future<Uint8List> generateGodownBillingPdf({
    required List<SalesOrderModel> orders,
    required String salesmanName,
    String? firmFilter,
    DateTime? reportDate,
  }) async {
    final devanagariFont = await PdfGoogleFonts.notoSansDevanagariRegular();
    final devanagariBoldFont = await PdfGoogleFonts.notoSansDevanagariBold();

    final baseStyle = pw.TextStyle(font: devanagariFont, fontSize: 8.5);
    final boldStyle = pw.TextStyle(font: devanagariBoldFont, fontSize: 8.5, fontWeight: pw.FontWeight.bold);
    final titleStyle = pw.TextStyle(font: devanagariBoldFont, fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900);
    final subTitleStyle = pw.TextStyle(font: devanagariBoldFont, fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo800);
    final headerStyle = pw.TextStyle(font: devanagariBoldFont, fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white);

    final date = reportDate ?? DateTime.now();
    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(date);
    final filterTag = (firmFilter == null || firmFilter == 'All') ? 'Purva Enterprises & Manas Sales' : firmFilter;

    final totalOrdersCount = orders.length;
    final grandTotalAmount = orders.fold<double>(0.0, (s, o) => s + o.totalAmount);
    final totalUnitsCount = orders.fold<int>(0.0.toInt(), (s, o) => s + o.items.fold<int>(0, (si, i) => si + i.quantity));

    // Consolidate items across all orders for Master Picking List
    final Map<String, _ConsolidatedPickingItem> pickingMap = {};
    for (final order in orders) {
      for (final item in order.items) {
        final key = '${item.productId}_${item.unit}';
        if (pickingMap.containsKey(key)) {
          pickingMap[key]!.totalQuantity += item.quantity;
          pickingMap[key]!.totalAmount += item.subtotal;
          if (!pickingMap[key]!.shopNames.contains(order.shopName)) {
            pickingMap[key]!.shopNames.add(order.shopName);
          }
        } else {
          pickingMap[key] = _ConsolidatedPickingItem(
            productId: item.productId,
            productName: item.productName,
            company: item.company,
            category: item.category,
            packing: item.packing,
            unit: item.unit,
            totalQuantity: item.quantity,
            totalAmount: item.subtotal,
            shopNames: [order.shopName],
          );
        }
      }
    }

    final consolidatedList = pickingMap.values.toList()
      ..sort((a, b) {
        final comp = a.company.compareTo(b.company);
        if (comp != 0) return comp;
        return a.productName.compareTo(b.productName);
      });

    // Group orders by route beat
    final Map<String, List<SalesOrderModel>> routeGroups = {};
    for (final order in orders) {
      final rName = order.routeName.isNotEmpty ? order.routeName : 'General Beat';
      routeGroups.putIfAbsent(rName, () => []).add(order);
    }

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        build: (pw.Context context) {
          return [
            // Top Document Header
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.indigo50,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.indigo300, width: 1),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(filterTag.toUpperCase(), style: titleStyle),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'ORDER DISPATCH SHEET (ऑर्डर डिस्पॅच यादी)',
                        style: subTitleStyle,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text('Booked By Salesman: $salesmanName', style: boldStyle),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Date: $dateStr', style: baseStyle),
                      pw.SizedBox(height: 3),
                      pw.Text('Total Bookings: $totalOrdersCount Orders', style: boldStyle),
                      pw.Text('Total Value: INR ${grandTotalAmount.toStringAsFixed(0)}', style: pw.TextStyle(font: devanagariBoldFont, fontSize: 10, color: PdfColors.indigo900, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // Summary Metrics Row
            pw.Row(
              children: [
                _metricBox(
                  title: 'TOTAL ORDERS',
                  value: '$totalOrdersCount',
                  color: PdfColors.indigo900,
                  fontBold: devanagariBoldFont,
                  fontRegular: devanagariFont,
                ),
                pw.SizedBox(width: 8),
                _metricBox(
                  title: 'TOTAL SKUs',
                  value: '${consolidatedList.length} items',
                  color: PdfColors.blue800,
                  fontBold: devanagariBoldFont,
                  fontRegular: devanagariFont,
                ),
                pw.SizedBox(width: 8),
                _metricBox(
                  title: 'TOTAL UNITS',
                  value: '$totalUnitsCount',
                  color: PdfColors.teal800,
                  fontBold: devanagariBoldFont,
                  fontRegular: devanagariFont,
                ),
                pw.SizedBox(width: 8),
                _metricBox(
                  title: 'EST. VALUE',
                  value: 'INR ${grandTotalAmount.toStringAsFixed(0)}',
                  color: PdfColors.indigo900,
                  fontBold: devanagariBoldFont,
                  fontRegular: devanagariFont,
                ),
              ],
            ),
            pw.SizedBox(height: 14),

            // SECTION 1: MASTER PICKING LIST
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: const pw.BoxDecoration(
                color: PdfColors.indigo900,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '1. ITEM SUMMARY (एकत्रित माल यादी)',
                    style: headerStyle,
                  ),
                  pw.Text(
                    'Total items across all orders',
                    style: pw.TextStyle(font: devanagariFont, fontSize: 7.5, color: PdfColors.white),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 6),

            if (consolidatedList.isEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.all(12),
                child: pw.Center(
                  child: pw.Text('No orders booked yet.', style: baseStyle),
                ),
              )
            else
              pw.TableHelper.fromTextArray(
                headers: ['#', 'Product Name', 'Company', 'Packing', 'Total Qty', 'Unit', 'Shops Count', 'Est. Total'],
                headerStyle: headerStyle,
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                cellStyle: baseStyle,
                cellAlignment: pw.Alignment.centerLeft,
                headerAlignment: pw.Alignment.centerLeft,
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
                data: List.generate(consolidatedList.length, (idx) {
                  final item = consolidatedList[idx];
                  return [
                    '${idx + 1}',
                    item.productName,
                    item.company,
                    item.packing,
                    '${item.totalQuantity}',
                    item.unit,
                    '${item.shopNames.length} shops',
                    'INR ${item.totalAmount.toStringAsFixed(0)}',
                  ];
                }),
              ),

            pw.SizedBox(height: 16),

            // SECTION 2: ROUTE & SHOP ORDERS BREAKDOWN
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: const pw.BoxDecoration(
                color: PdfColors.indigo900,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '2. ROUTE & SHOP ORDERS (रूटनिहाय ऑर्डर्स)',
                    style: headerStyle,
                  ),
                  pw.Text(
                    'Organized by route beat for dispatch',
                    style: pw.TextStyle(font: devanagariFont, fontSize: 7.5, color: PdfColors.white),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),

            ...routeGroups.entries.expand((rEntry) {
              final rName = rEntry.key;
              final rOrders = rEntry.value;
              final rUnits = rOrders.fold<int>(0, (s, o) => s + o.totalQuantity);
              final rTotal = rOrders.fold<double>(0.0, (s, o) => s + o.totalAmount);

              return [
                // Route Group Header Banner
                pw.Container(
                  margin: const pw.EdgeInsets.only(top: 6, bottom: 6),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.indigo100,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    border: pw.Border.all(color: PdfColors.indigo300, width: 0.8),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('ROUTE: $rName', style: pw.TextStyle(font: devanagariBoldFont, fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                      pw.Text('${rOrders.length} Orders • $rUnits units • INR ${rTotal.toStringAsFixed(0)}', style: pw.TextStyle(font: devanagariBoldFont, fontSize: 8.5, color: PdfColors.indigo900, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),

                // Orders under this route
                ...rOrders.map((order) {
                  final timeStr = DateFormat('hh:mm a').format(order.orderDate);

                  return pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 8),
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                      border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Order Sub-header
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Expanded(
                              child: pw.Row(
                                children: [
                                  pw.Container(
                                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: const pw.BoxDecoration(
                                      color: PdfColors.indigo700,
                                      borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                                    ),
                                    child: pw.Text(order.orderNumber, style: pw.TextStyle(font: devanagariBoldFont, fontSize: 8, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
                                  ),
                                  pw.SizedBox(width: 8),
                                  pw.Text(
                                    order.shopName,
                                    style: pw.TextStyle(font: devanagariBoldFont, fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                                  ),
                                ],
                              ),
                            ),
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.end,
                              children: [
                                pw.Text(order.businessName, style: boldStyle),
                                pw.Text('Time: $timeStr', style: pw.TextStyle(font: devanagariFont, fontSize: 7.5, color: PdfColors.grey700)),
                              ],
                            ),
                          ],
                        ),
                        if (order.notes != null && order.notes!.isNotEmpty) ...[
                          pw.SizedBox(height: 3),
                          pw.Text('Note: ${order.notes}', style: pw.TextStyle(font: devanagariFont, fontSize: 7.5, color: PdfColors.orange900, fontStyle: pw.FontStyle.italic)),
                        ],
                        pw.SizedBox(height: 6),

                        // Items table
                        pw.TableHelper.fromTextArray(
                          headers: ['#', 'Item Description', 'Packing', 'Qty', 'Unit', 'Rate', 'Total'],
                          headerStyle: pw.TextStyle(font: devanagariBoldFont, fontSize: 7.5, color: PdfColors.white, fontWeight: pw.FontWeight.bold),
                          headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo800),
                          cellStyle: pw.TextStyle(font: devanagariFont, fontSize: 7.5),
                          cellAlignment: pw.Alignment.centerLeft,
                          headerAlignment: pw.Alignment.centerLeft,
                          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2.5),
                          data: List.generate(order.items.length, (iIdx) {
                            final item = order.items[iIdx];
                            return [
                              '${iIdx + 1}',
                              item.productName,
                              item.packing,
                              '${item.quantity}',
                              item.unit,
                              'INR ${item.rate.toStringAsFixed(0)}',
                              'INR ${item.subtotal.toStringAsFixed(0)}',
                            ];
                          }),
                        ),
                        pw.SizedBox(height: 4),

                        // Subtotal row
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Total Items: ${order.items.length} (${order.totalQuantity} units)', style: pw.TextStyle(font: devanagariFont, fontSize: 8, color: PdfColors.grey700)),
                            pw.Text(
                              'Shop Total: INR ${order.totalAmount.toStringAsFixed(0)}',
                              style: pw.TextStyle(font: devanagariBoldFont, fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ];
            }),

            pw.SizedBox(height: 12),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Generated via Daily Collection Pro on ${DateFormat('dd-MM-yyyy hh:mm a').format(DateTime.now())}',
                style: pw.TextStyle(font: devanagariFont, fontSize: 7.5, color: PdfColors.grey600),
              ),
            ),
          ];
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _metricBox({
    required String title,
    required String value,
    required PdfColor color,
    required pw.Font fontBold,
    required pw.Font fontRegular,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(font: fontBold, fontSize: 7, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              value,
              style: pw.TextStyle(font: fontBold, fontSize: 10, color: color, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  /// Triggers PDF preview, print, or download across mobile, web, and desktop
  static Future<void> previewOrSharePdf(
    BuildContext context, {
    required List<SalesOrderModel> orders,
    required String salesmanName,
    String? firmFilter,
    DateTime? reportDate,
  }) async {
    try {
      final bytes = await generateGodownBillingPdf(
        orders: orders,
        salesmanName: salesmanName,
        firmFilter: firmFilter,
        reportDate: reportDate,
      );

      final dateTag = DateFormat('dd-MM-yyyy').format(reportDate ?? DateTime.now());
      final firmTag = (firmFilter == null || firmFilter == 'All') ? 'All_Firms' : firmFilter.replaceAll(' ', '_');
      final fileName = '${dateTag}_Orders_$firmTag.pdf';

      if (kIsWeb) {
        // Also provide instant download for web browsers
        await downloadFile(
          bytes: bytes,
          fileName: fileName,
          mimeType: 'application/pdf',
        );
      }

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes,
        name: fileName,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating Godown Billing PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _ConsolidatedPickingItem {
  final String productId;
  final String productName;
  final String company;
  final String category;
  final String packing;
  final String unit;
  int totalQuantity;
  double totalAmount;
  final List<String> shopNames;

  _ConsolidatedPickingItem({
    required this.productId,
    required this.productName,
    required this.company,
    required this.category,
    required this.packing,
    required this.unit,
    required this.totalQuantity,
    required this.totalAmount,
    required this.shopNames,
  });
}
