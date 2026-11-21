# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/); versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Purchase orders from the PC.** "Send to mobile" in the PC program's *Purchase orders* page hands a PDF (the selected rows, or the whole order) to the phone while the app is connected. The app downloads it on its next sync round, tells the PC it arrived and shows a notification; tapping it opens the new *Purchase orders from the PC* screen (open / share, save to the phone, delete). Requires the matching PC program (`GET /orders`, `GET /orders/<id>.pdf`, `POST /orders/<id>/ack`).
- Every request now carries `X-JO-Client: mobile`, so the PC can tell the app is connected.
- Android: `POST_NOTIFICATIONS` permission and core-library desugaring (added by `tools/patch_android.py`) for `flutter_local_notifications`.

## [2.1.0] — 2026-11-14

### Added
- New dark-gold design on every screen: wave background, rounded gold buttons, floating navigation bar, illustrated empty states.
- Expiry awareness: expired items are blocked at checkout, near-expiry items are flagged, and the *Today* page lists what expires soon (warning window is configurable).
- Reorder levels from the PC feed the low-stock list.
- Credit customers: suggestions and live balance synced from the PC.
- Returns are delivered to the PC automatically (once the original invoice is there), without double-booking.
- "Developed by JØ ROYALTY" footer and a pointer to the full JØ PHARMA desktop experience.

### Changed
- Local database upgraded to schema v5 (in-place migration from every earlier version).
- CI builds with JDK 21.

## [2.0.0] — 2026-11-14

### Added
- Renamed **JØ PHARMA MOBILE** with the JØ PHARMA emblem as app icon.
- Point-of-sale parity: pack / strip / unit selling, hold & recall, undo, credit and four payment methods, discount amount or %, tax, received / change, receipts.
- Shifts with cash count, returns, daily dashboard, manager / cashier roles, Arabic name, stock display.

## [1.1.0] — 2026-11-13

### Added
- Desktop-style import: automatic column detection, mapping screen with live preview, import modes, Arabic names.
- Products tab: multi-select, select all, delete selected / all, paging, sort, bulk price change, CSV export, extra barcodes.

### Changed
- A barcode repeated in a file is merged into one product; unnamed products import with the barcode as the name.

## [1.0.0] — 2026-11-13

First release: offline point of sale with camera scanning, product management, import from database / Excel / CSV / JSON, local-network delivery of invoices, sales history and exports, Arabic and English.
