class ParsedBillFields {
  final String? billNumber;
  final DateTime? billDate;
  final double? amount;
  final String? partyName;
  final String rawText;

  const ParsedBillFields({
    this.billNumber,
    this.billDate,
    this.amount,
    this.partyName,
    required this.rawText,
  });

  @override
  String toString() {
    return 'ParsedBillFields(billNo: $billNumber, date: $billDate, amount: $amount, party: $partyName)';
  }
}

class BillTextParser {
  // Regex patterns for bill / invoice number
  static final List<RegExp> _invoiceNoPatterns = [
    // 1. Explicit headers: e.g. "Invoice No: PE-2024-0891", "Bill No. : 12345", "Inv # : MS/8421"
    RegExp(
      r'(?:invoice\s*(?:no|num|number)?|inv\s*(?:no|num)?|bill\s*(?:no|num)?|tax\s*inv|memo\s*(?:no)?)[\s.:#№\-_/]*([A-Za-z0-9]+(?:[\-_/][A-Za-z0-9]+)*)',
      caseSensitive: false,
    ),
    // 2. Standard wholesaler prefix patterns: PE-2024-0891, PE/24-25/1234, MS-5678, INV-104, etc.
    RegExp(
      r'\b((?:PE|MS|PI|INV|BILL|PU|MN)[\s\-_/:]+[0-9A-Za-z]+(?:[\-_/][0-9A-Za-z]+)*)\b',
      caseSensitive: false,
    ),
    RegExp(r'\b((?:PE|MS|PI)[0-9]{3,8})\b', caseSensitive: false),
    // 3. Serial / reference number: No: 12345
    RegExp(r'\b(?:no|sr\s*no|serial\s*no)[\s.:#№\-_/]+([0-9]{3,8})\b', caseSensitive: false),
  ];

  // Regex patterns for standalone invoice label (without number on same line)
  static final RegExp _standaloneInvoiceLabel = RegExp(
    r'^(?:invoice\s*(?:no|num|number)?|inv\s*(?:no|num)?|bill\s*(?:no|num)?|tax\s*inv|bill\s*#|memo\s*no)[\s.:#№\-_/]*$',
    caseSensitive: false,
  );

  // Regex patterns for dates
  static final List<RegExp> _datePatterns = [
    // DD/MM/YYYY or DD-MM-YYYY or DD.MM.YYYY
    RegExp(r'\b([0-3]?[0-9])[\/\-\.]([0-1]?[0-9])[\/\-\.](20[2-3][0-9]|[2-3][0-9])\b'),
    // YYYY-MM-DD or YYYY/MM/DD
    RegExp(r'\b(20[2-3][0-9])[\/\-\.]([0-1]?[0-9])[\/\-\.]([0-3]?[0-9])\b'),
    // DD Mon YYYY (e.g. 17 Oct 2026 or 17-Oct-2026)
    RegExp(
      r'\b([0-3]?[0-9])[\s\-_/\.](Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*[\s\-_/\.](20[2-3][0-9]|[2-3][0-9])\b',
      caseSensitive: false,
    ),
  ];

  // Regex pattern for standalone date label
  static final RegExp _standaloneDateLabel = RegExp(
    r'^(?:date|dated|dt|inv\s*date|bill\s*date)[\s.:#\-_/]*$',
    caseSensitive: false,
  );

  // Regex patterns for total amount
  static final List<RegExp> _totalAmountPatterns = [
    // Priority 1: Grand Total, Net Payable, Total Payable
    RegExp(
      r'(?:grand\s*total|net\s*payable|total\s*payable|net\s*amount\s*payable|final\s*amount|bill\s*amount|net\s*total|net\s*amount)[\s.:=₹RsINR\-]*(?:₹|rs\.?|inr)?[\s]*([0-9,]+(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    ),
    // Priority 2: General total lines
    RegExp(
      r'(?:total\s*amount|total\s*rs|total\s*₹|total\s*amt|total)[\s.:=₹RsINR\-]*(?:₹|rs\.?|inr)?[\s]*([0-9,]+(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    ),
    // Priority 3: Currency prefix: ₹ 1,450.00 or Rs. 1450.00
    RegExp(r'(?:₹|rs\.?|inr)[\s.:]*([0-9,]+(?:\.[0-9]{1,2})?)', caseSensitive: false),
  ];

  // Regex pattern for standalone total label (where amount is on the next line)
  static final RegExp _standaloneTotalLabel = RegExp(
    r'^(?:grand\s*total|net\s*payable|total\s*payable|net\s*amount|final\s*amount|bill\s*amount|total\s*amount|total)[\s.:=₹RsINR\-]*$',
    caseSensitive: false,
  );

  // Regex patterns to identify customer / party name lines
  static final List<RegExp> _partyNameHeaderPatterns = [
    RegExp(r'^(?:m/s|ms|messrs|to|customer|cust|party|buyer|consignee|client|name)[\s.:#\-]+(.+)$', caseSensitive: false),
    RegExp(r'^(?:m/s\.|to\s*:)[\s]*(.+)$', caseSensitive: false),
  ];

  static final RegExp _standaloneCustomerLabel = RegExp(
    r'^(?:m/s|ms|messrs|to|customer|cust|party|buyer|consignee|client|billed\s*to)[\s.:#\-]*$',
    caseSensitive: false,
  );

  /// Parses text into structured bill fields with spatial awareness (header, footer, full text)
  static ParsedBillFields parse(
    String fullText, {
    String? headerText,
    String? footerText,
  }) {
    if (fullText.trim().isEmpty && (headerText == null || headerText.trim().isEmpty)) {
      return const ParsedBillFields(rawText: '');
    }

    final allLines = _splitLines(fullText);
    final headerLines = headerText != null && headerText.trim().isNotEmpty
        ? _splitLines(headerText)
        : allLines.take((allLines.length * 0.45).ceil().clamp(1, allLines.length)).toList();

    final footerLines = footerText != null && footerText.trim().isNotEmpty
        ? _splitLines(footerText)
        : allLines.skip((allLines.length * 0.55).floor().clamp(0, allLines.length)).toList();

    // 1. Bill Number: search header lines first (top section), then all lines
    String? billNo = _extractBillNumber(headerLines, allLines, fullText);

    // 2. Bill Date: search header lines first, then all lines
    DateTime? billDate = _extractBillDate(headerLines, allLines, fullText);

    // 3. Amount: search footer lines first (bottom section), then all lines
    double? amount = _extractTotalAmount(footerLines, allLines, fullText);

    // 4. Party / Customer Name: search header lines first
    String? partyName = _extractPartyName(headerLines, allLines, fullText);

    return ParsedBillFields(
      billNumber: billNo,
      billDate: billDate,
      amount: amount,
      partyName: partyName,
      rawText: fullText,
    );
  }

  static List<String> _splitLines(String text) {
    return text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  // ==========================================
  // INVOICE / BILL NUMBER EXTRACTION
  // ==========================================
  static String? _extractBillNumber(
    List<String> headerLines,
    List<String> allLines,
    String fullText,
  ) {
    // Phase A: Search header lines with same-line patterns and lookahead
    final headerCandidate = _findBillNumberInLineList(headerLines);
    if (headerCandidate != null) return headerCandidate;

    // Phase B: Search all lines with same-line patterns and lookahead
    final allCandidate = _findBillNumberInLineList(allLines);
    if (allCandidate != null) return allCandidate;

    // Phase C: Fallback to full text regex match
    for (final pattern in _invoiceNoPatterns) {
      final match = pattern.firstMatch(fullText);
      if (match != null && match.groupCount >= 1) {
        final candidate = match.group(1)?.trim();
        if (candidate != null && _isValidBillNumber(candidate)) {
          return _formatBillNumber(candidate);
        }
      }
    }

    return null;
  }

  static String? _findBillNumberInLineList(List<String> lines) {
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // 1. Check same-line patterns
      for (final pattern in _invoiceNoPatterns) {
        final match = pattern.firstMatch(line);
        if (match != null && match.groupCount >= 1) {
          final candidate = match.group(1)?.trim();
          if (candidate != null && _isValidBillNumber(candidate)) {
            return _formatBillNumber(candidate);
          }
        }
      }

      // 2. Spatial lookahead: Label is on line i, number is on line i+1 (or i+2)
      if (_standaloneInvoiceLabel.hasMatch(line)) {
        for (int offset = 1; offset <= 2 && (i + offset) < lines.length; offset++) {
          final nextLine = lines[i + offset].trim();
          // Extract first token or entire line
          final words = nextLine.split(RegExp(r'\s+'));
          if (words.isNotEmpty) {
            final firstWord = words.first;
            if (_isValidBillNumber(firstWord)) {
              return _formatBillNumber(firstWord);
            }
          }
        }
      }
    }
    return null;
  }

  static bool _isValidBillNumber(String s) {
    // Normalize OCR confusion for numbers
    var clean = s.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (clean.length < 2 || clean.length > 20) return false;
    // Must contain at least one digit
    if (!RegExp(r'\d').hasMatch(clean)) return false;
    // Should not be a pure 10-digit mobile number or 6-digit pin code
    if (clean.length == 10 && RegExp(r'^[6-9]\d{9}$').hasMatch(clean)) return false;
    if (clean.length == 6 && RegExp(r'^[1-9]\d{5}$').hasMatch(clean)) return false;
    // Avoid GSTIN (15 chars starting with 2 digits)
    if (clean.length == 15 && RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$').hasMatch(clean)) {
      return false;
    }
    return true;
  }

  static String _formatBillNumber(String s) {
    var clean = s.trim();
    // Normalize spaces around separators: e.g. "PE - 1024" -> "PE-1024"
    clean = clean.replaceAllMapped(RegExp(r'\s*([-_/])\s*'), (m) => m[1]!);
    // Remove trailing dots/commas
    clean = clean.replaceAll(RegExp(r'[.,;:]+$'), '');
    return clean.toUpperCase();
  }

  // ==========================================
  // INVOICE DATE EXTRACTION
  // ==========================================
  static DateTime? _extractBillDate(
    List<String> headerLines,
    List<String> allLines,
    String fullText,
  ) {
    // Phase A: Search header lines first (where invoice dates reside)
    final headerDate = _findDateInLineList(headerLines);
    if (headerDate != null) return headerDate;

    // Phase B: Search all lines
    final allDate = _findDateInLineList(allLines);
    if (allDate != null) return allDate;

    // Phase C: Full text match with OCR 'O' fix
    final cleanedFullText = _cleanOcrDateString(fullText);
    final now = DateTime.now();
    for (final pattern in _datePatterns) {
      final match = pattern.firstMatch(cleanedFullText);
      if (match != null) {
        final parsed = _parseDateMatch(match);
        if (parsed != null && parsed.year >= 2020 && parsed.year <= now.year + 2) {
          return parsed;
        }
      }
    }

    return null;
  }

  static String _cleanOcrDateString(String text) {
    return text.replaceAllMapped(
      RegExp(r'\b([0-3]?[0-9oO])[\/\-\.]([0-1]?[0-9oO])[\/\-\.](2[oO][2-3][0-9oO]|[2-3][0-9oO]|20[2-3][0-9oO])\b', caseSensitive: false),
      (m) => m[0]!.replaceAll(RegExp(r'[oO]'), '0'),
    );
  }

  static DateTime? _findDateInLineList(List<String> lines) {
    final now = DateTime.now();

    for (int i = 0; i < lines.length; i++) {
      var line = _cleanOcrDateString(lines[i]);

      // 1. Same-line date patterns
      for (final pattern in _datePatterns) {
        final match = pattern.firstMatch(line);
        if (match != null) {
          final parsed = _parseDateMatch(match);
          if (parsed != null && parsed.year >= 2020 && parsed.year <= now.year + 2) {
            return parsed;
          }
        }
      }

      // 2. Spatial lookahead: Line i has "Date:", Line i+1 has the date string
      if (_standaloneDateLabel.hasMatch(line) && (i + 1) < lines.length) {
        var nextLine = _cleanOcrDateString(lines[i + 1]);
        for (final pattern in _datePatterns) {
          final match = pattern.firstMatch(nextLine);
          if (match != null) {
            final parsed = _parseDateMatch(match);
            if (parsed != null && parsed.year >= 2020 && parsed.year <= now.year + 2) {
              return parsed;
            }
          }
        }
      }
    }
    return null;
  }

  static DateTime? _parseDateMatch(Match match) {
    try {
      final g1 = match.group(1)!;
      final g2 = match.group(2)!;
      final g3 = match.group(3)!;

      // Check if YYYY-MM-DD
      if (g1.length == 4 && int.tryParse(g1) != null) {
        final y = int.parse(g1);
        final m = int.parse(g2);
        final d = int.parse(g3);
        if (d >= 1 && d <= 31 && m >= 1 && m <= 12) {
          return DateTime(y, m, d);
        }
      }

      // Check if Month is string (e.g. Oct)
      final monthIndex = _monthNameToNumber(g2);
      if (monthIndex != null) {
        final d = int.parse(g1);
        var y = int.parse(g3);
        if (y < 100) y += 2000;
        if (d >= 1 && d <= 31) {
          return DateTime(y, monthIndex, d);
        }
      }

      // DD/MM/YYYY or DD/MM/YY
      final d = int.parse(g1);
      final m = int.parse(g2);
      var y = int.parse(g3);
      if (y < 100) y += 2000;

      if (d >= 1 && d <= 31 && m >= 1 && m <= 12) {
        return DateTime(y, m, d);
      }
    } catch (_) {}
    return null;
  }

  static int? _monthNameToNumber(String name) {
    final s = name.toLowerCase();
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    for (final entry in months.entries) {
      if (s.startsWith(entry.key)) return entry.value;
    }
    return null;
  }

  // ==========================================
  // TOTAL AMOUNT EXTRACTION
  // ==========================================
  static double? _extractTotalAmount(
    List<String> footerLines,
    List<String> allLines,
    String fullText,
  ) {
    // Phase A: Search footer lines first (bottom of bill)
    final footerAmt = _findAmountInLineList(footerLines, isFooter: true);
    if (footerAmt != null) return footerAmt;

    // Phase B: Search all lines (reversed, from bottom up)
    final allAmt = _findAmountInLineList(allLines, isFooter: false);
    if (allAmt != null) return allAmt;

    return null;
  }

  static double? _findAmountInLineList(List<String> lines, {required bool isFooter}) {
    final List<double> candidates = [];

    // Search lines from bottom to top (totals are always at the bottom)
    for (int i = lines.length - 1; i >= 0; i--) {
      final line = lines[i];
      final lower = line.toLowerCase();

      // Skip tax rate lines e.g. "CGST @ 2.5%", "SGST 9%", "HSN Code", etc.
      if (lower.contains('@') && lower.contains('%')) continue;
      if (lower.contains('round off') || lower.contains('round-off')) continue;

      // 1. Check if line has explicit Grand Total / Net Payable label
      for (final pattern in _totalAmountPatterns) {
        final matches = pattern.allMatches(line);
        for (final match in matches) {
          if (match.groupCount >= 1) {
            final amtStr = match.group(1)?.replaceAll(',', '').trim();
            if (amtStr != null) {
              final val = double.tryParse(amtStr);
              if (val != null && val >= 5.0 && val < 5000000) {
                // If the line has explicit "Grand Total" or "Net Payable", prioritize immediately!
                if (lower.contains('grand total') ||
                    lower.contains('net total') ||
                    lower.contains('net payable') ||
                    lower.contains('total payable') ||
                    lower.contains('final amount')) {
                  return val;
                }
                candidates.add(val);
              }
            }
          }
        }
      }

      // 2. Spatial lookahead: Line i has "Grand Total", line i+1 has the numeric amount
      if (_standaloneTotalLabel.hasMatch(line) && (i + 1) < lines.length) {
        final nextLine = lines[i + 1].trim();
        final numMatch = RegExp(r'(?:₹|rs\.?)?[\s]*([0-9,]+(?:\.[0-9]{1,2})?)').firstMatch(nextLine);
        if (numMatch != null && numMatch.groupCount >= 1) {
          final val = double.tryParse(numMatch.group(1)!.replaceAll(',', ''));
          if (val != null && val >= 5.0 && val < 5000000) {
            return val;
          }
        }
      }
    }

    if (candidates.isNotEmpty) {
      // In invoice footers, the Grand Total / Net Payable is typically the largest amount
      candidates.sort((a, b) => b.compareTo(a));
      return candidates.first;
    }

    return null;
  }

  // ==========================================
  // CUSTOMER / PARTY NAME EXTRACTION
  // ==========================================
  static String? _extractPartyName(
    List<String> headerLines,
    List<String> allLines,
    String fullText,
  ) {
    // 1. Search header lines for explicit customer labels
    final fromHeader = _findPartyNameInLines(headerLines);
    if (fromHeader != null) return fromHeader;

    // 2. Search all lines for explicit customer labels
    final fromAll = _findPartyNameInLines(allLines);
    if (fromAll != null) return fromAll;

    // 3. Scan lines around the top third (usually lines 2 to 12 of an invoice)
    for (int i = 0; i < allLines.length && i < 12; i++) {
      final line = allLines[i];
      final lower = line.toLowerCase();

      // Skip own firm headers, GSTIN, phone, tax invoice title, etc.
      if (_isCompanySelfHeader(line) ||
          lower.contains('tax invoice') ||
          lower.contains('gstin') ||
          lower.contains('invoice no') ||
          lower.contains('bill no') ||
          lower.contains('date:') ||
          lower.contains('fssai') ||
          lower.contains('original') ||
          lower.contains('duplicate')) {
        continue;
      }

      // Check if line looks like a retail/trader store name
      if (lower.contains('traders') ||
          lower.contains('kirana') ||
          lower.contains('stores') ||
          lower.contains('store') ||
          lower.contains('provision') ||
          lower.contains('super market') ||
          lower.contains('mart') ||
          lower.contains('general') ||
          lower.contains('enterprise') ||
          lower.contains('agency')) {
        return _cleanPartyLine(line);
      }
    }

    return null;
  }

  static String? _findPartyNameInLines(List<String> lines) {
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Same-line customer header: "M/s ABC TRADERS", "To: MAHALAXMI STORES"
      for (final pattern in _partyNameHeaderPatterns) {
        final match = pattern.firstMatch(line);
        if (match != null && match.groupCount >= 1) {
          final name = match.group(1)?.trim();
          if (name != null && name.length >= 3 && !_isCompanySelfHeader(name)) {
            return _cleanPartyLine(name);
          }
        }
      }

      // Spatial lookahead: Line i has "Billed To:" / "Customer:", Line i+1 has name
      if (_standaloneCustomerLabel.hasMatch(line) && (i + 1) < lines.length) {
        final nextLine = lines[i + 1].trim();
        if (nextLine.length >= 3 && !_isCompanySelfHeader(nextLine)) {
          return _cleanPartyLine(nextLine);
        }
      }
    }
    return null;
  }

  static String _cleanPartyLine(String s) {
    var clean = s.trim();
    // Remove trailing GSTIN or mobile if appended
    clean = clean.replaceAll(RegExp(r'\b\d{10}\b.*$'), '').trim();
    clean = clean.replaceAll(RegExp(r'gstin[:\s]*.*$', caseSensitive: false), '').trim();
    return clean;
  }

  static bool _isCompanySelfHeader(String s) {
    final lower = s.toLowerCase();
    // Exclude own distributor/agency names from being detected as party
    return lower.contains('purva enterprises') ||
        lower.contains('manas sales') ||
        lower.contains('purva') ||
        lower.contains('manas');
  }
}
