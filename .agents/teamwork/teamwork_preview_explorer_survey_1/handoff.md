# Codebase Architecture, Modules, & Structure Survey Report

**Agent**: `teamwork_preview_explorer_survey_1`  
**Working Directory**: `/home/aathu/daily_collection_app/.agents/teamwork/teamwork_preview_explorer_survey_1/`  
**Target Project**: `/home/aathu/daily_collection_app`  
**Date**: 2026-10-05  

---

## 1. Observation

### 1.1 Project Structure & Manifest (`pubspec.yaml`)
- **Package**: `daily_collection_app`, Flutter SDK `^3.13.2`.
- **Core Dependencies**:
  - `provider: ^6.1.5+1`: Primary reactive state management via `CollectionProvider`.
  - `shared_preferences: ^2.5.5`: Offline local persistence for routes, shops, collections, pending bills, orders, and products.
  - `firebase_core: ^4.15.0`, `cloud_firestore: ^6.10.0`, `firebase_storage: ^13.6.0`: Cloud sync and document backup with graceful offline fallback.
  - `pdf: ^3.12.0`, `printing: ^5.14.3`: PDF statement generation and godown picking reports with Marathi/Hindi Devanagari font support.
  - `excel: ^4.0.6`: Excel (`.xlsx`) multi-column ledger statements.
  - `image: ^4.3.0`, `image_picker: ^1.2.3`: Camera/gallery photo capture with client-side JPEG compression (~25-45 KB) to preserve web quota.
  - `uuid: ^4.6.0`, `intl: ^0.20.3`, `url_launcher: ^6.3.2`.
- **Assets Configured**: `assets/images/` containing `qr_purva.png`, `qr_manas.png`.

### 1.2 Codebase Module Inventory & Structure
```
lib/
├── firebase_options.dart                 # Firebase Web configuration options
├── main.dart                             # Entry point: Firebase init (safe try-catch), MultiProvider, MaterialApp
├── models/
│   ├── bill_summary.dart                 # Aggregated bill entity (billTotal, totalCollected, balanceDue, collections)
│   ├── collection_model.dart             # Core collection transaction receipt model (includes bankName, chequeNumber)
│   ├── order_model.dart                  # CatalogProduct, OrderItem, and SalesOrderModel
│   ├── payment_mode.dart                 # Enum: cash, upi, cheque, netBanking with icon/label mapping
│   ├── pending_bill_model.dart           # Pending invoice entity (deliveryDate, invoiceDate, photoBase64, status)
│   ├── route_model.dart                  # Beat route entity with sequential priority ordering
│   └── shop_model.dart                   # Retailer outlet entity associated with routeId
├── providers/
│   └── collection_provider.dart          # Central ChangeNotifier holding app state, filters, calculations, and CRUD
├── screens/
│   ├── main_navigation_shell.dart        # 4-tab NavigationBar: Overview, Orders, Ledger, Outlets
│   ├── home_dashboard_screen.dart        # Dashboard metrics, payment breakdown bottom sheets, quick triggers
│   ├── routes_shops_screen.dart          # Beat route selection, shop list, phone calling, search, CRUD
│   ├── add_route_dialog.dart             # Route create & edit dialog with priority sequencing
│   ├── add_shop_screen.dart              # Outlet registration and editing form
│   ├── make_collection_screen.dart       # Primary payment collection UI with installment history & bank routing
│   ├── record_collection_screen.dart     # Direct collection recording alternative
│   ├── pending_bills_list_screen.dart    # Pending bills browser with search, route filter, photo thumbnail & zoom
│   ├── add_pending_bill_screen.dart      # Pending bill entry with camera/gallery bill photo upload
│   ├── collections_list_screen.dart      # Daily ledger & invoice summary with date picker & WhatsApp report
│   ├── collection_details_dialog.dart    # Transaction receipt dialog with delete and re-collection
│   ├── orders_screen.dart                # Beat-based order booking (2 tabs: New Order & Booked Orders)
│   ├── statement_screen.dart             # Date/Firm/Mode filtered statement export to Excel & PDF
│   ├── send_reminder_dialog.dart         # WhatsApp payment reminder template generator
│   ├── firebase_config_dialog.dart       # Manual cloud sync settings modal
│   └── placeholder_screen.dart           # Fallback view
├── services/
│   ├── storage_service.dart              # SharedPreferences CRUD with quota protection (trims older photos on error)
│   ├── sample_data_service.dart          # Initial sample data for routes, shops, collections, and pending bills
│   ├── firebase_service.dart             # Cloud Firestore & Storage connector with graceful offline degradation
│   ├── order_catalog_service.dart        # Product catalog mapped to Purva & Manas, companies, and custom products
│   └── godown_billing_pdf_service.dart   # Consolidated godown picking & beat billing PDF generator
├── utils/
│   ├── currency_formatter.dart           # INR (₹) Indian numbering formatting
│   ├── theme.dart                        # Material 3 styling + distinct palettes for Purva vs Manas
│   ├── image_compress_helper.dart        # Downscaling to max 650px JPEG @ 60% quality, safeBase64Decode
│   └── file_download/                    # Conditional export (web Blob anchor download vs desktop/mobile stub)
│       ├── file_download.dart
│       ├── file_download_stub.dart
│       └── file_download_web.dart
└── widgets/
    ├── firm_info_dialog.dart             # Purva & Manas corporate modal with companies, banks, and clipboard copy
    ├── payment_qr_dialog.dart            # High-resolution UPI QR display with firm switch & UPI ID copy
    ├── fullscreen_image_viewer.dart      # InteractiveViewer with pinch/scroll zoom (0.5x to 6.0x) & pan
    └── add_product_dialog.dart           # Custom SKU master addition modal
```

### 1.3 Dual-Firm Tracking Architecture (Purva Enterprises & Manas Sales)
- **Data Isolation**:
  - `CollectionModel.businessName`, `PendingBillModel.businessName`, `SalesOrderModel.firm`, and `CatalogProduct.firm` explicitly store the business entity string.
  - `CollectionProvider` provides dedicated calculation methods:
    * `getTotalCollectionForBusiness(String business, {DateTime? forDate})`
    * `getBillsCountForBusiness(String business, {DateTime? forDate})`
    * `getPendingBalanceForBusiness(String business)`
    * `getCashForBusiness(String business, {DateTime? forDate})`
    * `getDigitalForBusiness(String business, {DateTime? forDate})`
- **Catalog & Product Segregation**:
  - `OrderCatalogService.companiesByFirm`:
    * **Purva Enterprises**: Wipro, Fena, Funfood, Imami
    * **Manas Sales**: Racket, Imami, Dabar, Cadbury, Gowardhan
- **Banking & Collection Modes**:
  - Defined in `FirmInfoDialog`, `PaymentQrDialog`, and `MakeCollectionScreen._getBanksForSelection`:
    * **Purva Enterprises**: Union Bank of India (UPI, Net Banking, Cheque), RSBL (Net Banking, Cheque); UPI ID `8459671694@okbizaxis`.
    * **Manas Sales**: Central Bank of India (UPI, Net Banking, Cheque); UPI ID `9309862465@okbizaxis`.
  - In `MakeCollectionScreen`, selecting the firm dynamically alters the available bank dropdown options.
- **Theming & Visual Distinctiveness**:
  - `AppTheme.purvaPrimary`: Royal Navy Blue (`0xFF1E3A8A`).
  - `AppTheme.manasPrimary`: Deep Forest Teal (`0xFF0F766E`).
  - Helper methods `getBusinessColor`, `getBusinessLightColor`, `getBusinessBorderColor` ensure visual clarity across dashboards, cards, and receipts.

### 1.4 Route & Outlet Models, Priority Ordering, Search & Storage
- **Route Model (`RouteModel`)**:
  - Contains `id`, `name`, `description`, `priority` (integer 1..N), `createdAt`.
  - Strictly sorted in ascending priority order in `CollectionProvider.routes`.
  - Reordering capabilities: `moveRouteUp`, `moveRouteDown`, `setRouteOrder`, `reorderRoutes`, `updateRoutePriority`.
  - Cascades: Renaming a route in `updateRoute` automatically cascades the new `routeName` across all associated shops and persists to both local storage and cloud.
- **Outlet Model (`ShopModel`)**:
  - Contains `id`, `name`, `routeId`, `routeName`, `mobileNumber`, `address`, `ownerName`, `createdAt`.
  - Deleting/updating shops cascades to collection records.
- **Search Capabilities**:
  - Multi-attribute search in `RoutesShopsScreen` (shop name, mobile number, address).
  - Multi-attribute search in `CollectionProvider.getFilteredCollections` (shop name, bill number, route name).
  - Searchable modal bottom sheet picker in `MakeCollectionScreen` (bill number, shop name, route name).
  - Search in `CollectionsListScreen` and `PendingBillsListScreen`.
- **Storage Resilience**:
  - SharedPreferences as the single local source of truth.
  - Fail-safe quota mechanism: If browser localStorage fills up when saving collections or pending bills, older records have their base64 photo payloads pruned while retaining recent 15 records, preventing unhandled exceptions.

### 1.5 Web Configuration & Build Setup
- **`web/index.html`**:
  - Contains `<base href="$FLUTTER_BASE_HREF">` on line 4.
  - Includes PWA metadata, manifest link, install banner prompt, and service worker registration.
  - Flutter bootstrap loader: `<script src="flutter_bootstrap.js" async></script>`.
- **File Download Mechanism**:
  - Uses `dart:html` Blob URL and `AnchorElement.click()` in `lib/utils/file_download/file_download_web.dart`.
- **Build Verification**:
  - Running `flutter build web --release --base-href /collection-app/` succeeds (`Exit Code 0`, built in 177.8s).
  - Inspection of `build/web/index.html` confirms line 4 transformed correctly to `<base href="/collection-app/">`.

### 1.6 Static Analysis & Test Suite Findings
- **Automated Tests**:
  - Command: `flutter test`
  - Output: **22 passing tests out of 22 (100% pass rate)**.
  - Covered files:
    1. `test/widget_test.dart` (Smoke test & navigation to Pending Bills)
    2. `test/dual_firm_tracking_test.dart` (Purva vs Manas calculation, per-firm filter isolation)
    3. `test/bill_tracking_test.dart` (Pending vs paid, partial balance calculation, subsequent clearance)
    4. `test/custom_date_and_crud_test.dart` (Separate bill date vs collection date, cascading updates, route priority ordering)
    5. `test/orders_feature_test.dart` (Catalog companies/categories, custom SKU additions, units, sales order serialization)
- **Static Analysis (`dart analyze`)**:
  - Errors: **0**
  - Warnings: **0**
  - Infos / Deprecations: **10** (All `deprecated_member_use`: `value` is deprecated in `DropdownButtonFormField`, recommending `initialValue`).
    * `lib/screens/orders_screen.dart`: Lines 374, 1028, 1048, 1085, 1126, 1164, 1198.
    * `lib/widgets/add_product_dialog.dart`: Lines 307, 365, 432.
  - Wasm Dry Run Note: Package `image: ^4.3.0` contains `avoid_double_and_int_checks` lint violations under Wasm compilation, and `file_download_web.dart` uses `dart:html`. Flutter's JS fallback compiler (`dart2js`) succeeds cleanly for web release.

---

## 2. Logic Chain

1. **Requirement R1 Mapping (Automated Test Execution & Static Analysis)**:
   - Direct inspection and execution of the test suite (`flutter test`) verified 22/22 unit and widget tests pass.
   - Running `dart analyze` confirmed 0 errors and 0 warnings.
   - Identified 10 deprecation `info` notices on `DropdownButtonFormField.value` that can be migrated to `initialValue` during bug remediation.

2. **Requirement R2 Mapping (Core User Flow & Module Verification)**:
   - **Overview Dashboard & Firm Info**: Implemented in `HomeDashboardScreen`, `FirmInfoDialog`, and `PaymentQrDialog`. Tested in `widget_test.dart` and `dual_firm_tracking_test.dart`.
   - **Outlets & Routes**: Implemented in `RoutesShopsScreen`, `AddRouteDialog`, and `AddShopScreen`. Priority sequencing logic is enforced in `CollectionProvider.routes` and verified in `custom_date_and_crud_test.dart`.
   - **Pending Bills & Document Proof**: Implemented in `PendingBillsListScreen`, `AddPendingBillScreen`, `FullScreenImageViewer`, and `ImageCompressHelper`. Safe compression to JPEG prevents web memory and storage quota overflow.
   - **Make Collection & Installment History**: Implemented in `MakeCollectionScreen`. Supports single & partial payments, prior installment breakdowns (lines 902-964), remaining balance recalculation, and bank routing per firm. Verified in `bill_tracking_test.dart`.
   - **Statement & Export Engine**: Implemented in `StatementScreen`. Multi-format export (PDF via `Printing`/`pdf` and Excel via `excel`) contains the designated 'Deposit Bank' column. Web downloads utilize Blob anchor clicks.
   - **Order Booking & Dispatch**: Implemented in `OrdersScreen`, `OrderCatalogService`, `AddProductDialog`, and `GodownBillingPdfService`. Supports packaging units (Pcs, Outer, Box, Nodes), custom product additions, and godown picking reports. Verified in `orders_feature_test.dart`.

3. **Requirement R3 Mapping (Targeted Bug Remediation & Regression Testing)**:
   - Identified clean code separation without structural bugs in existing logic.
   - Minor deprecation cleanup target (`DropdownButtonFormField.value` -> `initialValue`).
   - All existing business rules (dual-firm segregation, sequential route ordering, bill photo preservation) are safeguarded with regression tests in `test/`.

4. **Requirement R4 Mapping (Production Web Build & Deployment Validation)**:
   - Validated that `web/index.html` has `<base href="$FLUTTER_BASE_HREF">`.
   - Executed `flutter build web --release --base-href /collection-app/` and inspected the output artifacts in `build/web/`.
   - Verified that tree-shaking operated correctly on icon fonts and that the resulting `build/web/index.html` accurately contains `<base href="/collection-app/">`.

---

## 3. Caveats

1. **Firebase Network Channel during Unit Tests**:
   - In offline/unit test execution environments without native platform channels initialized, `FirebaseService.init()` logs `PlatformException(channel-error)`. The provider gracefully absorbs this error and falls back 100% to local `SharedPreferences` cache without failing tests.
2. **WebAssembly vs JavaScript Web Compilation**:
   - The project currently relies on `dart:html` in `file_download_web.dart` and `image: 4.3.0`. The default release command `flutter build web --release` emits standard JavaScript (via dart2js), which succeeds completely. However, if building with `--wasm`, `dart:html` would need migration to `package:web`.
3. **Deprecations (Informational)**:
   - The 10 `info` items from `dart analyze` do not break builds or fail tests, but represent Flutter 3.33+ deprecations.

---

## 4. Conclusion

The `daily_collection_app` codebase is architecturally sound, thoroughly organized, and demonstrates strong separation of concerns across models, providers, services, and UI screens. 

- **Dual-firm tracking** is rigorously implemented across Purva Enterprises and Manas Sales with distinct company catalogs, dedicated bank accounts (Union Bank/RSBL vs Central Bank), independent UPI QR codes, and per-firm financial metrics.
- **Route & Outlet management** correctly enforces sequential integer priority ordering (1..N) with cascading name updates.
- **Collection workflows** reliably handle partial payments, recalculate remaining balance due, display installment histories, and store bill photos with JPEG downscaling.
- **Exports** in both PDF and Excel formats include all critical fields including the Deposit Bank column.
- **Web release builds** compile cleanly with `--base-href /collection-app/`, properly populating `<base href>`.

---

## 5. Verification Method

To independently verify these architectural findings, run the following commands from `/home/aathu/daily_collection_app`:

1. **Verify Automated Test Suite**:
   ```bash
   flutter test
   ```
   *Expected outcome*: 22/22 tests passing with 0 failures.

2. **Verify Static Analysis**:
   ```bash
   dart analyze
   ```
   *Expected outcome*: 0 errors, 0 warnings (10 informational deprecation notes).

3. **Verify Web Production Build & Base-Href**:
   ```bash
   flutter build web --release --base-href /collection-app/
   grep -n '<base href' build/web/index.html
   ```
   *Expected outcome*: Build succeeds with Exit Code 0, and line 4 of `build/web/index.html` displays `<base href="/collection-app/">`.
