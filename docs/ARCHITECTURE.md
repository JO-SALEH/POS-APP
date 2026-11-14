# Architecture

JØ PHARMA MOBILE is a single Flutter app with an offline SQLite database. Nothing needs a server; the optional link to the JØ PHARMA program on the PC is a plain HTTP exchange on the local network.

## Layers

| Layer | Files | Responsibility |
|---|---|---|
| UI | `lib/screens/*`, `lib/theme.dart` | Screens, design system (buttons, cards, navigation, empty states) |
| State | `lib/services.dart` | Roles, cart, undo, hold / recall, receipts |
| Data | `lib/db.dart` | Schema v5, models, sales, returns, shifts, reports |
| Import | `lib/importer.dart`, `lib/mapping.dart`, `lib/tableio.dart` | Reading files / databases, column detection, verified report |
| Sync | `lib/lan.dart` | Pairing, delivery of invoices and returns, catalog pull |

## Data model (SQLite v5)

`products` (+ `name_ar`, `units_per_pack`, `strip_size`, `stock`, `expiry`, `min_stock`, `sellable`) · `alternatives` · `sales` / `sale_items` (with `unit`, `base_units`) · `returns` / `return_items` (with sync state) · `held` · `shifts` · `customers` · `settings`.

Migrations are additive and tested from v1 forward (`test_importer/barcodes_test.dart`).

## Sync protocol (phone ↔ PC)

All requests carry an `X-JO-Token` header obtained by scanning the PC's QR code.

| Request | Purpose |
|---|---|
| `GET /ping` | Connection test |
| `GET /catalog/rev` | Cheap revision check — the catalog is downloaded only when it changed |
| `GET /catalog` | Products, extra barcodes, stock, expiry, reorder levels, customers (gzip) |
| `POST /sales` | Invoices, up to 25 per request |
| `POST /returns` | Returns of invoices the PC already has |

Every invoice has a client id `<install-id>-<receipt-no>`; every return has its own. The PC answers *done*, *duplicate*, *pending* or *failed* for each, so retrying after a lost reply can never double-book.

## Snippets

### Chunked, size-bounded delivery
```dart
for (final inv in invoices) {
  final n = utf8.encode(jsonEncode(inv)).length;
  if (cur.isNotEmpty && (cur.length >= 25 || bytes + n > 180000)) {
    chunks.add(cur); cur = []; bytes = 0;
  }
  cur.add(inv); bytes += n;
}
```

### Idempotent result handling
```dart
if (st == 'done' || st == 'duplicate') {
  await Db.setReturnResult(receipt, 1);       // the PC has it
} else if (st == 'failed' && x['retryable'] != true) {
  await Db.setReturnResult(receipt, 2, note: '${x['error']}');
} // pending: stays queued for the next round
```

### Cart line math in base units
```dart
double get price => product.priceFor(unit);
double get subtotal => double.parse((price * qty).toStringAsFixed(2));
int get baseUnits => qty * product.multOf(unit);   // what leaves the shelf
```

## Testing

`flutter test test_importer` runs against an in-memory SQLite (`sqflite_common_ffi`): units and pricing, sales, returns, shifts, import modes, Excel / CSV reading, schema upgrade, and the full sync flow against a fake receiver.
