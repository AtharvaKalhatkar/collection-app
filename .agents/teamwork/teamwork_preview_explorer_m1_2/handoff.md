# Handoff Report: StatementScreen Filtering Architecture & Implementation Design

**Agent**: `teamwork_preview_explorer_m1_2`  
**Working Directory**: `/home/aathu/daily_collection_app/.agents/teamwork/teamwork_preview_explorer_m1_2/`  
**Project Root**: `/home/aathu/daily_collection_app`  
**Timestamp**: 2026-10-05T15:10:00Z  
**Parent Orchestrator**: `9c4f8811-06ec-42bc-922e-c45e8b7754dc`  
**Milestone**: Milestone 1 (M1) — StatementScreen Filtering Architecture

---

## 1. Observation

Direct code examination of `lib/screens/statement_screen.dart`, `lib/providers/collection_provider.dart`, `lib/models/collection_model.dart`, `lib/models/route_model.dart`, and `lib/models/shop_model.dart` reveals the following exact findings:

### 1.1 Current State of `StatementScreen` (`lib/screens/statement_screen.dart`)
- **State variables (lines 31–37)**:
  ```dart
  class _StatementScreenState extends State<StatementScreen> {
    String? _selectedBusiness; // null means 'All'
    DateTime _selectedDate = DateTime.now();
    bool _filterByDate = true;
    PaymentMode? _selectedMode; // null means 'All Modes'
    bool _isExporting = false;
  ```
- **Single-Day Date Picker (lines 45–59)**:
  ```dart
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
  ```
  `_filterByDate` is initialized to `true` and always set to `true` in `_pickDate()`. There is no UI button or trigger allowing the user to reset to "All Dates" (`_filterByDate = false`). Furthermore, only a single date is selectable; no date range (`DateTimeRange`) is supported.
- **Current Filter Logic (lines 61–84)**:
  ```dart
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
  ```
- **Absence of Route and Outlet Controls (lines 565–746)**:
  The filter bar only contains:
  1. Firm Selector segmented tab (`ALL FIRMS`, `PURVA`, `MANAS` at lines 573–659)
  2. Date Selector pill (`_pickDate` at lines 666–699) and Payment Mode Dropdown (`_selectedMode` at lines 703–742)
  There is **zero** UI control or state variable for route filtering or outlet/shop filtering.

### 1.2 Excel Export Flow (`_exportToExcel`, lines 100–189)
- Receives `records: List<CollectionModel>` directly from `_getFilteredCollections(provider)`.
- Header row (lines 108–123) includes:
  `'S.No'`, `'Date & Time'`, `'Firm Name'`, `'Route'`, `'Outlet / Shop Name'`, `'Bill Number'`, `'Bill Date'`, `'Payment Mode'`, `'Deposit Bank'`, `'Collected Amount (INR)'`, `'Total Bill Amount (INR)'`, `'Pending Balance (INR)'`, `'Payment Reference / Cheque'`, `'Salesman'`.
- Columns 3, 4, and 8 populate `c.routeName`, `c.shopName`, and `bank` (`c.bankName` or `'-'`).
- Filename generation (lines 153–156):
  ```dart
  final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
  final firmTag = _selectedBusiness?.replaceAll(' ', '_') ?? 'All_Firms';
  final modeTag = _selectedMode?.name ?? 'All_Modes';
  final fileName = 'Collection_Statement_${firmTag}_${modeTag}_$dateStr.xlsx';
  ```
  When date range or "All Dates" is introduced, `dateStr` currently references single-day `_selectedDate`.

### 1.3 PDF Export Flow (`_exportToPdf`, lines 192–343)
- Receives `records: List<CollectionModel>` and `provider: CollectionProvider`.
- Header subtitle (lines 202, 237–239):
  `final dateStr = _filterByDate ? DateFormat('dd MMM yyyy').format(_selectedDate) : 'All Dates';`
  Displays `Date: $dateStr`, `Mode: $modeTitle`, `Officer: ${provider.salesmanName}`.
- Table headers (line 292):
  `headers: ['#', 'Outlet / Shop', 'Firm', 'Route', 'Bill #', 'Mode', 'Deposit Bank', 'Collected', 'Balance']`
  Deposit Bank is at column index 6.
- Filename (lines 329–333):
  `name: 'Collection_Statement_$dateTag.pdf'` where `dateTag = DateFormat('yyyy-MM-dd').format(_selectedDate)`.

### 1.4 Data Model Capabilities (`lib/models/collection_model.dart`)
- `CollectionModel` contains:
  - `routeId: String` (line 8)
  - `routeName: String` (line 9)
  - `shopId: String` (line 6)
  - `shopName: String` (line 7)
  - `businessName: String` (line 5)
  - `collectedAt: DateTime` (line 23)
  - `bankName: String?` (line 19)
- All required filter keys are native, non-null properties on `CollectionModel`.

### 1.5 Provider Capabilities (`lib/providers/collection_provider.dart`)
- `provider.routes`: Returns `List<RouteModel>` sorted by priority (lines 38–42).
- `provider.shops`: Returns `List<ShopModel>` (line 43).
- `provider.getShopsForRoute(String routeId)`: Returns `List<ShopModel>` where `s.routeId == routeId` (lines 602–604).
- `provider.collections`: Returns all loaded collections (line 44).

---

## 2. Logic Chain

1. **R2 Requirement Alignment**:
   - Requirement R2 mandates statement filtering by `(date range, route, outlet, firm)`.
   - Current `StatementScreen` only filters by `(single date, firm, payment mode)`.
   - To achieve full compliance without regressing existing features, `StatementScreen` must add:
     - Date Range Picker with "All Dates" clear option
     - Route Filter Dropdown populated from `CollectionProvider.routes`
     - Outlet/Shop Filter (reactive dropdown + quick search)
     - Preserving existing firm selector and payment mode dropdown.

2. **Date Range Precision & Edge Case Handling**:
   - `showDateRangePicker` returns start and end dates with `00:00:00.000` timestamps.
   - Transactions recorded on `_endDate` occur throughout the day (`10:00`, `15:30`, etc.).
   - A naive `isBefore(_endDate)` check would erroneously drop all collections made on the final day.
   - Therefore, the boundary check must normalize to full calendar days:
     `startOfDay = DateTime(_startDate.year, _startDate.month, _startDate.day, 0, 0, 0)`
     `endOfDay = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59, 999)`
     or check: `collectedDate.isBefore(startOfDay) || collectedDate.isAfter(endOfDay)`.
   - For single-day selection, `_startDate == _endDate`, correctly matching that single day.
   - For "All Dates", `_filterByDate = false` bypasses the date check entirely.

3. **Route & Outlet Reactive Synchronization**:
   - Outlets are structurally grouped by beat route (`shop.routeId`).
   - When a route is selected (`_selectedRouteId != null`), the outlet dropdown must only present shops belonging to that route via `provider.getShopsForRoute(_selectedRouteId)`.
   - If the user changes or clears the route, any previously selected outlet that does not belong to the newly selected route must be cleared (`_selectedShopId = null`) to avoid impossible filter states and dropdown value assertion failures.
   - Providing a fallback `currentShopId` guard guarantees zero runtime exceptions in Flutter's `DropdownButton`.

4. **Dropdown Deprecation Immunity**:
   - Flutter SDK 3.33+ deprecated `DropdownButtonFormField.value` in favor of `initialValue`.
   - In contrast, standard `DropdownButton<T>` wrapped inside a decorated `Container` (the exact pattern already used in `StatementScreen:705-740` for Payment Mode) uses `value:` natively without any deprecation warnings.
   - Using this pattern for Route and Outlet dropdowns guarantees 0 analyzer warnings and seamless reactive state updates on `setState()`.

5. **Data Flow Integrity**:
   - `_getFilteredCollections(provider)` is the single source of truth for:
     1. Financial Summary Card (`totalCollected`, `totalBilled`, `totalDue`, receipt count)
     2. Transaction ListView
     3. Statement Preview Dialog (`_showStatementPreview`)
     4. Excel Export (`_exportToExcel`)
     5. PDF Generation & Print (`_exportToPdf`)
   - Filtering in `_getFilteredCollections` automatically propagates to all 5 destinations without duplicate filtering code.
   - File naming and document header subtitles in Excel and PDF must be updated to format date ranges (`yyyy-MM-dd_to_yyyy-MM-dd` or `All_Dates`) and reflect active Route/Outlet filters.

---

## 3. Caveats

1. **Read-Only Explorer Mandate**: Per Teamwork protocol, this report presents the complete design and exact diff specifications. The code modifications in `lib/screens/statement_screen.dart` will be applied by the implementer agent.
2. **Shop Name Fallback for Custom/Historic Outlets**: If a collection was recorded with a historical shop ID that was subsequently deleted from `provider.shops`, the collection's `shopName` remains intact in `CollectionModel`. The search query filter safely searches `c.shopName` directly so historical collections remain searchable even if the shop entity is absent.
3. **No External Package Additions**: All functionality uses existing project dependencies (`intl`, `excel`, `pdf`, `printing`, `provider`). No changes to `pubspec.yaml` are needed.

---

## 4. Conclusion & Concrete Implementation Proposal

### 4.1 State & Initialization Design

Add constructor parameters, state variables, and initialization in `lib/screens/statement_screen.dart`:

```dart
class StatementScreen extends StatefulWidget {
  final String? initialBusiness;
  final PaymentMode? initialMode;
  final String? initialRouteId;
  final String? initialShopId;
  final DateTime? initialDate;
  final DateTimeRange? initialDateRange;

  const StatementScreen({
    super.key,
    this.initialBusiness,
    this.initialMode,
    this.initialRouteId,
    this.initialShopId,
    this.initialDate,
    this.initialDateRange,
  });

  @override
  State<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends State<StatementScreen> {
  String? _selectedBusiness; // null means 'All'
  DateTime? _startDate;
  DateTime? _endDate;
  bool _filterByDate = true;
  String? _selectedRouteId; // null means 'All Routes'
  String? _selectedShopId; // null means 'All Outlets'
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  PaymentMode? _selectedMode; // null means 'All Modes'
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _selectedBusiness = widget.initialBusiness;
    _selectedMode = widget.initialMode;
    _selectedRouteId = widget.initialRouteId;
    _selectedShopId = widget.initialShopId;

    if (widget.initialDateRange != null) {
      _startDate = widget.initialDateRange!.start;
      _endDate = widget.initialDateRange!.end;
      _filterByDate = true;
    } else if (widget.initialDate != null) {
      _startDate = widget.initialDate;
      _endDate = widget.initialDate;
      _filterByDate = true;
    } else {
      final now = DateTime.now();
      _startDate = DateTime(now.year, now.month, now.day);
      _endDate = DateTime(now.year, now.month, now.day);
      _filterByDate = true;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
```

### 4.2 Helper Methods for Date & Filter Reset

```dart
  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initialRange = (_startDate != null && _endDate != null)
        ? DateTimeRange(start: _startDate!, end: _endDate!)
        : DateTimeRange(start: now, end: now);

    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initialRange,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: 'SELECT STATEMENT DATE RANGE',
      saveText: 'APPLY',
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _filterByDate = true;
      });
    }
  }

  // Preserved for backward compatibility
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: 'SELECT STATEMENT DATE',
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        _endDate = picked;
        _filterByDate = true;
      });
    }
  }

  String _getDateRangeDisplay() {
    if (!_filterByDate || _startDate == null || _endDate == null) {
      return 'All Dates';
    }
    final sameDay = _startDate!.year == _endDate!.year &&
        _startDate!.month == _endDate!.month &&
        _startDate!.day == _endDate!.day;
    if (sameDay) {
      return DateFormat('dd MMM yyyy').format(_startDate!);
    }
    return '${DateFormat('dd MMM').format(_startDate!)} - ${DateFormat('dd MMM yyyy').format(_endDate!)}';
  }

  bool get _hasActiveFilters {
    final now = DateTime.now();
    final isToday = _startDate != null &&
        _endDate != null &&
        _startDate!.year == now.year &&
        _startDate!.month == now.month &&
        _startDate!.day == now.day &&
        _endDate!.year == now.year &&
        _endDate!.month == now.month &&
        _endDate!.day == now.day;

    return _selectedBusiness != null ||
        !_filterByDate ||
        !isToday ||
        _selectedRouteId != null ||
        _selectedShopId != null ||
        _selectedMode != null ||
        _searchQuery.isNotEmpty;
  }

  void _resetFilters() {
    final now = DateTime.now();
    setState(() {
      _selectedBusiness = null;
      _startDate = DateTime(now.year, now.month, now.day);
      _endDate = DateTime(now.year, now.month, now.day);
      _filterByDate = true;
      _selectedRouteId = null;
      _selectedShopId = null;
      _selectedMode = null;
      _searchQuery = '';
      _searchController.clear();
    });
  }
```

### 4.3 Concrete Filtering Logic (`_getFilteredCollections`)

```dart
  List<CollectionModel> _getFilteredCollections(CollectionProvider provider) {
    return provider.collections.where((c) {
      // 1. Date Range Filter
      if (_filterByDate && _startDate != null && _endDate != null) {
        final startOfDay = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
        final endOfDay = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59, 999);
        if (c.collectedAt.isBefore(startOfDay) || c.collectedAt.isAfter(endOfDay)) {
          return false;
        }
      }

      // 2. Firm Filter
      if (_selectedBusiness != null && _selectedBusiness != 'All') {
        if (c.businessName != _selectedBusiness) return false;
      }

      // 3. Route Filter
      if (_selectedRouteId != null && _selectedRouteId!.isNotEmpty) {
        if (c.routeId != _selectedRouteId) return false;
      }

      // 4. Outlet / Shop Filter
      if (_selectedShopId != null && _selectedShopId!.isNotEmpty) {
        if (c.shopId != _selectedShopId) return false;
      }

      // 5. Payment Mode Filter
      if (_selectedMode != null) {
        if (c.paymentMode != _selectedMode) return false;
      }

      // 6. Outlet Name, Bill #, Reference Search Filter
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase().trim();
        final matchShop = c.shopName.toLowerCase().contains(q);
        final matchBill = c.billNumber.toLowerCase().contains(q);
        final matchRoute = c.routeName.toLowerCase().contains(q);
        final matchRef = c.referenceNumber?.toLowerCase().contains(q) ?? false;
        final matchCheque = c.chequeNumber?.toLowerCase().contains(q) ?? false;
        final matchBank = c.bankName?.toLowerCase().contains(q) ?? false;
        if (!matchShop && !matchBill && !matchRoute && !matchRef && !matchCheque && !matchBank) {
          return false;
        }
      }

      return true;
    }).toList()
      ..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
  }
```

### 4.4 Flow into Exports & Preview

1. **Excel Filename & Headers (`_exportToExcel`)**:
   ```dart
   final dateStr = !_filterByDate
       ? 'All_Dates'
       : (_startDate != null && _endDate != null && _startDate == _endDate
           ? DateFormat('yyyy-MM-dd').format(_startDate!)
           : '${_startDate != null ? DateFormat('yyyy-MM-dd').format(_startDate!) : 'start'}_to_${_endDate != null ? DateFormat('yyyy-MM-dd').format(_endDate!) : 'end'}');
   final firmTag = _selectedBusiness?.replaceAll(' ', '_') ?? 'All_Firms';
   final modeTag = _selectedMode?.name ?? 'All_Modes';
   final routeTag = _selectedRouteId != null ? '_Route' : '';
   final fileName = 'Collection_Statement_${firmTag}_${modeTag}_$dateStr$routeTag.xlsx';
   ```
   Deposit Bank remains at Column Index 8: `xl.TextCellValue(bank)`.

2. **PDF Header & Filename (`_exportToPdf`)**:
   ```dart
   final dateStr = _getDateRangeDisplay();
   final routeName = _selectedRouteId != null
       ? (provider.routes.where((r) => r.id == _selectedRouteId).firstOrNull?.name ?? 'Route')
       : null;
   final shopName = _selectedShopId != null
       ? (provider.shops.where((s) => s.id == _selectedShopId).firstOrNull?.name ?? 'Outlet')
       : null;
   ```
   In PDF header:
   ```dart
   pw.Column(
     crossAxisAlignment: pw.CrossAxisAlignment.end,
     children: [
       pw.Text('Date: $dateStr', style: pw.TextStyle(font: devanagariFont, fontSize: 11)),
       pw.Text('Mode: $modeTitle', style: pw.TextStyle(font: devanagariFont, fontSize: 11)),
       if (routeName != null)
         pw.Text('Route: $routeName', style: pw.TextStyle(font: devanagariFont, fontSize: 10)),
       if (shopName != null)
         pw.Text('Outlet: $shopName', style: pw.TextStyle(font: devanagariFont, fontSize: 10)),
       pw.Text('Officer: ${provider.salesmanName}', style: pw.TextStyle(font: devanagariFont, fontSize: 11)),
     ],
   ),
   ```
   Filename:
   ```dart
   final dateTag = !_filterByDate
       ? 'All_Dates'
       : (_startDate != null && _endDate != null && _startDate == _endDate
           ? DateFormat('yyyy-MM-dd').format(_startDate!)
           : '${_startDate != null ? DateFormat('yyyy-MM-dd').format(_startDate!) : 'start'}_to_${_endDate != null ? DateFormat('yyyy-MM-dd').format(_endDate!) : 'end'}');
   name: 'Collection_Statement_$dateTag.pdf',
   ```

3. **Statement Preview (`_showStatementPreview`)**:
   Uses `_getDateRangeDisplay()` and dynamically lists `routeName` and `shopName` in the preview header if filtered.

### 4.5 Enhanced UI Control Bar in `build()`

Replace lines 664–746 with the 3-section control layout:

```dart
// Row 2: Date Range Selector & Payment Mode
Row(
  children: [
    // Date Range Selector
    Expanded(
      flex: 6,
      child: InkWell(
        onTap: _pickDateRange,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _filterByDate ? AppTheme.primary.withValues(alpha: 0.05) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _filterByDate ? AppTheme.primary : AppTheme.border,
              width: _filterByDate ? 1.2 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.date_range_outlined,
                size: 16,
                color: _filterByDate ? AppTheme.primary : Colors.blueGrey,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _getDateRangeDisplay(),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: _filterByDate ? AppTheme.primary : Colors.blueGrey.shade800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_filterByDate)
                InkWell(
                  onTap: () => setState(() => _filterByDate = false),
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(2.0),
                    child: Icon(Icons.close, size: 14, color: Colors.blueGrey),
                  ),
                )
              else
                const Icon(Icons.arrow_drop_down, size: 18, color: Colors.blueGrey),
            ],
          ),
        ),
      ),
    ),
    const SizedBox(width: 8),

    // Payment Mode Dropdown
    Expanded(
      flex: 5,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _selectedMode != null ? AppTheme.primary : AppTheme.border,
            width: _selectedMode != null ? 1.2 : 1.0,
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<PaymentMode?>(
            isExpanded: true,
            value: _selectedMode,
            hint: const Text('All Modes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            items: [
              const DropdownMenuItem<PaymentMode?>(
                value: null,
                child: Text('All Modes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
            onChanged: (val) => setState(() => _selectedMode = val),
          ),
        ),
      ),
    ),
  ],
),
const SizedBox(height: 8),

// Row 3: Route Dropdown & Outlet Dropdown (Reactive)
Row(
  children: [
    // Route Filter Dropdown
    Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _selectedRouteId != null ? AppTheme.primary : AppTheme.border,
            width: _selectedRouteId != null ? 1.2 : 1.0,
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            isExpanded: true,
            value: _selectedRouteId,
            hint: const Row(
              children: [
                Icon(Icons.alt_route, size: 15, color: Colors.blueGrey),
                SizedBox(width: 6),
                Text('All Routes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Row(
                  children: [
                    Icon(Icons.alt_route, size: 15, color: Colors.blueGrey),
                    SizedBox(width: 6),
                    Text('All Routes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              ...provider.routes.map((r) {
                return DropdownMenuItem<String?>(
                  value: r.id,
                  child: Text(
                    r.name,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
            ],
            onChanged: (val) {
              setState(() {
                _selectedRouteId = val;
                if (_selectedShopId != null && val != null) {
                  final shopsInRoute = provider.getShopsForRoute(val);
                  if (!shopsInRoute.any((s) => s.id == _selectedShopId)) {
                    _selectedShopId = null;
                  }
                }
              });
            },
          ),
        ),
      ),
    ),
    const SizedBox(width: 8),

    // Outlet Filter Dropdown (Reactive to selected route)
    Expanded(
      child: Builder(
        builder: (context) {
          final availableShops = _selectedRouteId != null && _selectedRouteId!.isNotEmpty
              ? provider.getShopsForRoute(_selectedRouteId!)
              : provider.shops;

          final effectiveShopId = availableShops.any((s) => s.id == _selectedShopId)
              ? _selectedShopId
              : null;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: effectiveShopId != null ? AppTheme.primary : AppTheme.border,
                width: effectiveShopId != null ? 1.2 : 1.0,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: effectiveShopId,
                hint: const Row(
                  children: [
                    Icon(Icons.storefront_outlined, size: 15, color: Colors.blueGrey),
                    SizedBox(width: 6),
                    Text('All Outlets', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Row(
                      children: [
                        Icon(Icons.storefront_outlined, size: 15, color: Colors.blueGrey),
                        SizedBox(width: 6),
                        Text('All Outlets', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  ...availableShops.map((s) {
                    return DropdownMenuItem<String?>(
                      value: s.id,
                      child: Text(
                        s.name,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }),
                ],
                onChanged: (val) => setState(() => _selectedShopId = val),
              ),
            ),
          );
        },
      ),
    ),
  ],
),
const SizedBox(height: 8),

// Row 4: Search Bar & Reset Filters Button
Row(
  children: [
    Expanded(
      child: SizedBox(
        height: 38,
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search outlet, bill #, reference...',
            hintStyle: const TextStyle(fontSize: 12),
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
          ),
          onChanged: (val) => setState(() => _searchQuery = val),
        ),
      ),
    ),
    if (_hasActiveFilters) ...[
      const SizedBox(width: 8),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          minimumSize: const Size(0, 38),
          foregroundColor: AppTheme.error,
          side: const BorderSide(color: AppTheme.error, width: 0.8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: const Icon(Icons.filter_alt_off, size: 15),
        label: const Text('Reset', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
        onPressed: _resetFilters,
      ),
    ],
  ],
),
```

---

## 5. Verification Method

### 5.1 Static Analysis & Deprecation Verification
Execute `dart analyze` to confirm no compilation issues or deprecation warnings:
```bash
dart analyze
```
*Expected Result*: 0 warnings in `statement_screen.dart`.

### 5.2 Automated Widget Tests
Create a dedicated test file `test/statement_filtering_test.dart` verifying all 5 filter dimensions:
1. **Date Range & All Dates**:
   - Verify initial load filters by today's date.
   - Tap date clear icon (`Icons.close`) -> verify `_filterByDate == false`, displaying collections across all dates.
2. **Route Filter**:
   - Select a Route from the Route dropdown -> verify only collections with matching `routeId` are visible.
   - Verify Outlet dropdown is populated strictly with shops where `shop.routeId == selectedRouteId`.
3. **Outlet Filter**:
   - Select an Outlet from the Outlet dropdown -> verify only collections for that specific `shopId` are rendered.
4. **Firm & Payment Mode**:
   - Switch firm to `Purva Enterprises` / `Manas Sales` -> verify collections match `businessName`.
   - Select `Cash` / `UPI` / `Cheque` -> verify collections match `paymentMode`.
5. **Search Query**:
   - Enter a query into the search bar -> verify filtering matches `shopName` or `billNumber`.
6. **Reset Filters**:
   - Tap `Reset` button -> verify all filter state variables return to default.

Run all tests:
```bash
flutter test
```
*Expected Result*: 100% test pass with zero failures.

### 5.3 Web Production Build
Verify compilation and tree-shaking for web release:
```bash
flutter build web --release --base-href /collection-app/
```
*Expected Result*: Clean build generating artifacts in `build/web` without errors.

### 5.4 Invalidation Conditions
The design is invalidated if:
- Selecting a route does not filter collections or fails to constrain the outlet dropdown.
- Selecting a date range excludes records on the end date due to midnight timestamp mismatch.
- Flutter analyzer emits deprecations for dropdown properties.
- Excel or PDF export excludes any of the active filter records or fails to include the Deposit Bank column.
