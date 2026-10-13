# Project: Daily Collection App Quality, Verification & Release

## Architecture
- **Framework**: Flutter Web / Mobile (Material 3)
- **State Management**: Central reactive `CollectionProvider` (`ChangeNotifier`)
- **Data Layer**: Offline-first via `SharedPreferences` (`StorageService` with quota-preserving photo trimming) + Cloud Firestore backup (`FirebaseService`)
- **Business Partitioning**: Strict dual-firm separation:
  - **Purva Enterprises**: Agencies (Wipro, Fena, Funfood, Imami), Union Bank of India & RSBL, Theme Royal Navy Blue
  - **Manas Sales**: Agencies (Racket, Imami, Dabar, Cadbury, Gowardhan), Central Bank of India, Theme Forest Teal
- **Route & Beat Logic**: Sequential integer priority (1..N) ordering with cascading updates across shops and collections
- **Document & Proof Engine**: Client-side JPEG downsampling to 650px @ 60% quality (~25-45 KB), base64 padding repair and safe decoding, interactive zoom viewer (0.5x - 6.0x)
- **Reporting & Exports**: PDF generator (`Printing`/`pdf`) and Excel (.xlsx) export with explicit Deposit Bank column

## Code Layout
- `lib/models/`: Data entities (`bill_summary.dart`, `collection_model.dart`, `order_model.dart`, `payment_mode.dart`, `pending_bill_model.dart`, `route_model.dart`, `shop_model.dart`)
- `lib/providers/`: State management (`collection_provider.dart`)
- `lib/screens/`: UI views (`home_dashboard_screen.dart`, `routes_shops_screen.dart`, `make_collection_screen.dart`, `pending_bills_list_screen.dart`, `statement_screen.dart`, `orders_screen.dart`, etc.)
- `lib/services/`: Persistence, cloud, and PDF/Excel generation (`storage_service.dart`, `firebase_service.dart`, `order_catalog_service.dart`, `godown_billing_pdf_service.dart`)
- `lib/utils/`: Formatting, theme, image helpers, web file download (`image_compress_helper.dart`, `theme.dart`, `currency_formatter.dart`, `file_download/`)
- `lib/widgets/`: Reusable dialogs and components (`firm_info_dialog.dart`, `payment_qr_dialog.dart`, `fullscreen_image_viewer.dart`, `add_product_dialog.dart`)
- `test/`: Automated test suite (`widget_test.dart`, `orders_feature_test.dart`, `custom_date_and_crud_test.dart`, `dual_firm_tracking_test.dart`, `bill_tracking_test.dart`)

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Zero Deprecations & Clean Analysis | Fix 10 `DropdownButtonFormField.value` deprecations in orders_screen and add_product_dialog | M1 | Survey (Explorer 1, 2, 3) |
| 2 | Clean Headless Unit Test Environment | Suppress unmocked Firebase platform channel exception logs during testing | M1 | Survey (Explorer 2) |
| 3 | Statement Date Range & Reset Filter | Allow date range selection and toggle between date range and all dates in StatementScreen | M1 | Survey (Explorer 3) |
| 4 | Statement Route Filter | Allow filtering collection statements by Beat Route in StatementScreen | M1 | Survey (Explorer 3) |
| 5 | Statement Outlet Filter | Allow filtering collection statements by Outlet/Shop in StatementScreen | M1 | Survey (Explorer 3) |
| 6 | Statement Export Deposit Bank Integrity | Verify Excel (.xlsx) and PDF statements contain valid Deposit Bank columns | M2 | Survey (Explorer 2, 3) |
| 7 | Payment Mode & Bank Assignment Tests | Automated test suite verifying Cash, UPI, Cheque, NetBanking bank mapping | M2 | Survey (Explorer 2) |
| 8 | Document Bill Proof & Zoom Tests | Automated test suite verifying photo compression, safe base64 decoding, and zoom viewer | M2 | Survey (Explorer 2, 3) |
| 9 | Statement Filtering Automated Tests | Automated tests verifying date range, route, outlet, and firm filters in Statement export | M2 | Survey (Explorer 2, 3) |
| 10 | Regression & Core Flows Full Test Pass | Execute 100% of test suites with 0 failures | M2 | ORIGINAL_REQUEST R1/R3 |
| 11 | Static Analysis Verification | Execute `dart analyze` with 0 errors and 0 warnings | M2 | ORIGINAL_REQUEST R1 |
| 12 | Production Web Release Build | Execute `flutter build web --release --base-href /collection-app/` generating `build/web` | M2 | ORIGINAL_REQUEST R4 |
| 13 | Multi-Agent Independent Review & Audit | Independent Reviewers, Challengers, and Forensic Integrity Auditor gate check | M2 | Process Requirement |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Core Remediation & Statement Filtering Enhancement | Fix 10 deprecations, silence test channel errors, add date range, route, and outlet filters in StatementScreen | none | IN_PROGRESS |
| M2 | Test Suite Expansion, Web Release Build & Multi-Agent Verification | Comprehensive tests for exports, banks, proofs, filters; full test pass, analyze clean, release web build, review & forensic audit | M1 | PLANNED |

## Interface Contracts
### Statement Filtering Contract (`statement_screen.dart`)
- **Route Filtering**: Selected route (`RouteModel? _selectedRoute` or `String? _selectedRouteId`). When non-null, filter `filtered = filtered.where((c) => c.routeId == _selectedRouteId)`.
- **Outlet Filtering**: Selected shop or search query (`ShopModel? _selectedShop` or `String? _selectedShopQuery`). Filters collections matching shop name/ID.
- **Date Range Filtering**: `DateTimeRange? _selectedDateRange` (or `_startDate` / `_endDate`). When active, `filtered = filtered.where((c) => c.collectedAt.isAfter(_startDate.subtract(1 day)) && c.collectedAt.isBefore(_endDate.add(1 day)))`. Also support "All Dates" (`_filterByDate = false`).

### DropdownButtonFormField Contract
- Migrate `value: <stateVar>` to `initialValue: <stateVar>` with proper Key/form reset so form fields dynamically bind to values without `deprecated_member_use` warnings.
