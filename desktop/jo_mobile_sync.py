#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
jo_mobile_sync.py - desktop receiver for the JO POS mobile app (backup point-of-sale).

Put this file next to jo_pharmacy_pro.py. It uses ONLY the Python standard library.

What it does
  * Listens on the local Wi-Fi/LAN (default port 8765).
  * POST /api/sales    <- phone sends the sales made while the main system was down.
                          Writes them into JO PHARMA's `sales` + `sale_items` tables.
                          Safe to repeat: a receipt_no that already exists is skipped.
  * GET  /api/products -> phone downloads barcode / name / price from `medications`.
  * GET  /api/ping     -> connection test.
  * `--import file.json` loads a JSON file exported from the phone (no network needed).

Run standalone (desktop app can be open; SQLite WAL allows it):
    python jo_mobile_sync.py                      # uses ./jo_pharmacy.db or env JO_DB
    python jo_mobile_sync.py --db "D:\\JO\\jo_pharmacy.db" --port 8765
    python jo_mobile_sync.py --import jo_sales_20261109_1530.json

Run inside the desktop app (3 lines, e.g. at the end of the app's startup):
    import jo_mobile_sync
    jo_mobile_sync.start_in_thread(DB_PATH)       # DB_PATH already exists in jo_pharmacy_pro.py

Stock: by default NO stock is deducted (the sale rows are added for reporting/accounting only).
Use --deduct-stock to also subtract the sold quantity from medications.quantity. This is a
simple subtraction; it does not touch batch/FIFO tables - review before enabling.
"""
import argparse
import hmac
import json
import os
import secrets
import socket
import sqlite3
import sys
import threading
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

APP_NAME = "JO PHARMA"
MAX_BODY = 25 * 1024 * 1024
HERE = os.path.dirname(os.path.abspath(__file__))
KEY_FILE = os.path.join(HERE, "jo_mobile_sync.key")


# ----------------------------------------------------------------- database
def _connect(db_path):
    conn = sqlite3.connect(db_path, timeout=15)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout=15000")
    return conn


def _columns(conn, table):
    return {r["name"] for r in conn.execute(f"PRAGMA table_info({table})")}


def _insert(conn, table, row, cols):
    data = {k: v for k, v in row.items() if k in cols}
    names = ",".join(data)
    marks = ",".join("?" for _ in data)
    cur = conn.execute(f"INSERT INTO {table}({names}) VALUES({marks})", list(data.values()))
    return cur.lastrowid


def _num(v, default=0.0):
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def _date(v):
    s = str(v or "").strip()
    try:
        datetime.strptime(s, "%Y-%m-%d %H:%M:%S")
        return s
    except ValueError:
        return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def import_sales(db_path, payload, deduct_stock=False, log=print):
    """Insert the sales of a phone payload. Returns (accepted_receipts, duplicate_receipts)."""
    sales = payload.get("sales") or []
    device = str(payload.get("device") or "Mobile")[:40]
    accepted, duplicates = [], []
    conn = _connect(db_path)
    try:
        sale_cols = _columns(conn, "sales")
        item_cols = _columns(conn, "sale_items")
        has_meds = bool(_columns(conn, "medications"))
        for s in sales:
            receipt = str(s.get("receipt_no") or "").strip()
            if not receipt:
                continue
            if conn.execute("SELECT 1 FROM sales WHERE receipt_no=?", (receipt,)).fetchone():
                duplicates.append(receipt)
                continue
            items = s.get("items") or []
            subtotal = round(sum(_num(i.get("price")) * _num(i.get("qty")) for i in items), 2)
            discount = round(min(max(_num(s.get("discount")), 0.0), subtotal), 2)
            net = round(subtotal - discount, 2)
            payment = str(s.get("payment") or "Cash")
            if payment not in ("Cash", "Card", "Wallet", "Credit"):
                payment = "Cash"
            conn.execute("BEGIN IMMEDIATE")
            try:
                profit = 0.0
                lines = []
                for i in items:
                    code = str(i.get("barcode") or "").strip()
                    med = None
                    if has_meds and code:
                        med = conn.execute("SELECT id, cost FROM medications WHERE barcode=?", (code,)).fetchone()
                    qty = int(_num(i.get("qty"), 1))
                    price = _num(i.get("price"))
                    cost = _num(med["cost"]) if med else 0.0
                    if med:
                        profit += (price - cost) * qty
                    lines.append((i, med, qty, price, cost))
                profit = round(profit - discount, 2)
                sale_id = _insert(conn, "sales", {
                    "receipt_no": receipt,
                    "customer_name": "Walk-in Customer",
                    "cashier_name": "MOBILE: " + device,
                    "subtotal": subtotal,
                    "discount": discount,
                    "tax": 0.0,
                    "net_total": net,
                    "payment_method": payment,
                    "date_time": _date(s.get("created_at")),
                    "status": "completed",
                    "received": net,
                    "profit": profit,
                }, sale_cols)
                for i, med, qty, price, cost in lines:
                    _insert(conn, "sale_items", {
                        "sale_id": sale_id,
                        "medication_id": med["id"] if med else 0,
                        "medication_name": str(i.get("name") or ""),
                        "barcode": str(i.get("barcode") or ""),
                        "unit_price": price,
                        "quantity": qty,
                        "unit_type": "pack",
                        "subtotal": round(price * qty, 2),
                        "cost_price": cost,
                        "name_ar": "",
                    }, item_cols)
                    if deduct_stock and med:
                        conn.execute("UPDATE medications SET quantity=MAX(quantity-?,0) WHERE id=?", (qty, med["id"]))
                try:
                    conn.execute(
                        "INSERT INTO activity_log(user,action,details,date_time) VALUES(?,?,?,?)",
                        ("MOBILE", "mobile_sale", f"{receipt} = {net} ({device})",
                         datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
                except sqlite3.Error:
                    pass
                conn.execute("COMMIT")
                accepted.append(receipt)
            except Exception:
                conn.execute("ROLLBACK")
                raise
        log(f"[JO-SYNC] {device}: {len(accepted)} new, {len(duplicates)} already present")
    finally:
        conn.close()
    return accepted, duplicates


def list_products(db_path):
    conn = _connect(db_path)
    try:
        rows = conn.execute("SELECT barcode, name, price FROM medications ORDER BY name").fetchall()
        return [{"barcode": r["barcode"], "name": r["name"], "price": r["price"]} for r in rows]
    finally:
        conn.close()


# ------------------------------------------------------------------ server
def load_or_create_key(path=KEY_FILE):
    try:
        with open(path, "r", encoding="utf-8") as f:
            k = f.read().strip()
            if k:
                return k
    except OSError:
        pass
    k = secrets.token_hex(3).upper()          # short, easy to type on the phone
    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write(k)
    except OSError:
        pass
    return k


def lan_ips():
    ips = set()
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("10.255.255.255", 1))
        ips.add(s.getsockname()[0])
        s.close()
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ips.add(info[4][0])
    except OSError:
        pass
    return sorted(i for i in ips if not i.startswith("127."))


def make_server(db_path, host="0.0.0.0", port=8765, key=None, deduct_stock=False, log=print):
    key = key if key is not None else load_or_create_key()

    class Handler(BaseHTTPRequestHandler):
        server_version = "JOMobileSync/1.0"

        def log_message(self, fmt, *args):  # quiet
            pass

        def _send(self, code, obj):
            body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _authorized(self):
            if not key:
                return True
            got = self.headers.get("X-JO-Key", "")
            return hmac.compare_digest(got.encode(), key.encode())

        def do_GET(self):
            if not self._authorized():
                return self._send(401, {"error": "bad key"})
            try:
                if self.path.startswith("/api/ping"):
                    return self._send(200, {"ok": True, "name": APP_NAME + " @ " + socket.gethostname()})
                if self.path.startswith("/api/products"):
                    return self._send(200, {"products": list_products(db_path)})
                return self._send(404, {"error": "not found"})
            except Exception as e:  # noqa
                log(f"[JO-SYNC] error: {e}")
                return self._send(500, {"error": str(e)})

        def do_POST(self):
            if not self._authorized():
                return self._send(401, {"error": "bad key"})
            try:
                n = int(self.headers.get("Content-Length", "0"))
                if n <= 0 or n > MAX_BODY:
                    return self._send(413, {"error": "bad size"})
                payload = json.loads(self.rfile.read(n).decode("utf-8"))
                if self.path.startswith("/api/sales"):
                    acc, dup = import_sales(db_path, payload, deduct_stock, log)
                    return self._send(200, {"accepted": acc, "duplicates": dup})
                return self._send(404, {"error": "not found"})
            except Exception as e:  # noqa
                log(f"[JO-SYNC] error: {e}")
                return self._send(500, {"error": str(e)})

    srv = ThreadingHTTPServer((host, port), Handler)
    srv.jo_key = key
    return srv


def start_in_thread(db_path, port=8765, key=None, deduct_stock=False, log=print):
    """Start the receiver inside another program (e.g. the desktop app). Returns the server."""
    srv = make_server(db_path, "0.0.0.0", port, key, deduct_stock, log)
    threading.Thread(target=srv.serve_forever, name="jo-mobile-sync", daemon=True).start()
    return srv


# --------------------------------------------------------------------- CLI
def main():
    ap = argparse.ArgumentParser(description="JO POS mobile -> JO PHARMA receiver")
    ap.add_argument("--db", default=os.environ.get("JO_DB", os.path.join(os.getcwd(), "jo_pharmacy.db")))
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--key", default=None, help="pairing key (default: saved in jo_mobile_sync.key)")
    ap.add_argument("--deduct-stock", action="store_true", help="also subtract sold quantities from medications")
    ap.add_argument("--import", dest="import_file", help="import a JSON file exported from the phone, then exit")
    a = ap.parse_args()

    if not os.path.exists(a.db):
        print(f"Database not found: {a.db}\nUse --db PATH or set JO_DB.")
        return 1

    if a.import_file:
        with open(a.import_file, "r", encoding="utf-8-sig") as f:
            payload = json.load(f)
        acc, dup = import_sales(a.db, payload, a.deduct_stock)
        print(f"Imported {len(acc)} sales, skipped {len(dup)} duplicates.")
        return 0

    srv = make_server(a.db, "0.0.0.0", a.port, a.key, a.deduct_stock)
    print("=" * 60)
    print(" JO POS mobile receiver is running")
    print(f" Database : {a.db}")
    for ip in lan_ips() or ["<this-PC-IP>"]:
        print(f" Phone server address : {ip}:{a.port}")
    print(f" Pairing key          : {srv.jo_key or '(none)'}")
    print(" Keep the phone on the same Wi-Fi. Ctrl+C to stop.")
    print("=" * 60)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
