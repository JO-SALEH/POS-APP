# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/); versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [2.2.1] — 2026-11-22

### Fixed
- **Returns ignored the invoice discount / tax**: the phone refunded the full line price while the PC refunds what was really paid. The refund (preview, record, shift cash) now uses the same share as the PC.
- **Credit sales**: a return of a credit sale now says so (the return screen and the confirmation name the customer and the amount deducted from the account) and lowers the customer's balance on the phone right away; a credit sale raises it right away. The PC's figure replaces both on the next refresh.
- The part a customer paid at the counter of a credit sale (`received`) is now sent to the PC, which used to book the whole invoice as debt. (Needs the matching PC program.)

## [2.2.0] — 2026-11-22

### Fixed
- **A deleted purchase order came back after Refresh.** The PC keeps offering an order for the whole session, so the phone downloaded it again. The phone now remembers deleted (and trimmed) orders on disk and never fetches them again; a delete that happens while a refresh is running is no longer undone by it.
- Sales with no lines were counted as "unsent" forever, which kept the app from contacting the PC; they are no longer counted.
- An invoice or return the PC refuses is no longer re-sent every 30 s: automatic rounds stop after 3 refusals (until restart or *Sync now*).
- The "phone connected" signal is now also sent when there is nothing to push.
- A customer row without a balance no longer aborts the whole catalog refresh.

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
