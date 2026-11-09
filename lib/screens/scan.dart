import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../i18n.dart';
import '../theme.dart';

/// Full-screen camera scanner (barcodes + QR).
/// - continuous == false: pops with the first code read.
/// - continuous == true : keeps scanning; [onCode] handles each code and returns a short label to flash.
class ScanPage extends StatefulWidget {
  final bool continuous;
  final Future<String?> Function(String code)? onCode;
  final String Function()? footer;
  const ScanPage({super.key, this.continuous = false, this.onCode, this.footer});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final MobileScannerController _c = MobileScannerController(facing: CameraFacing.back);
  bool _busy = false;
  bool _torch = false;
  String? _flash;

  Future<void> _detect(BarcodeCapture cap) async {
    if (_busy) return;
    String? code;
    for (final b in cap.barcodes) {
      final v = b.rawValue;
      if (v != null && v.trim().isNotEmpty) {
        code = v.trim();
        break;
      }
    }
    if (code == null) return;
    _busy = true;
    HapticFeedback.mediumImpact();
    if (!widget.continuous) {
      if (mounted) Navigator.pop(context, code);
      return;
    }
    final label = await widget.onCode?.call(code);
    if (!mounted) return;
    setState(() => _flash = label);
    await Future.delayed(const Duration(milliseconds: 1100));
    if (mounted) setState(() => _flash = null);
    _busy = false;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final box = size.width * 0.72;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        MobileScanner(
          controller: _c,
          onDetect: _detect,
          errorBuilder: (c, e, w) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(tr('cam_error'), textAlign: TextAlign.center, style: const TextStyle(color: JC.danger, fontSize: 16)),
            ),
          ),
        ),
        Center(
          child: Container(
            width: box,
            height: box * 0.7,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _flash != null ? JC.success : JC.gold, width: 3),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.close, color: JC.gold, size: 28),
                  onPressed: () => Navigator.pop(context),
                ),
                const Spacer(),
                IconButton(
                  tooltip: tr('torch'),
                  icon: Icon(_torch ? Icons.flash_on : Icons.flash_off, color: JC.gold, size: 28),
                  onPressed: () async {
                    await _c.toggleTorch();
                    setState(() => _torch = !_torch);
                  },
                ),
              ]),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(context).padding.bottom),
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black, Colors.transparent]),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_flash != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: JC.success.withOpacity(0.9), borderRadius: BorderRadius.circular(10)),
                  child: Text(_flash!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              Text(tr('scan_hint'), style: const TextStyle(color: JC.silverDim)),
              if (widget.continuous && widget.footer != null) ...[
                const SizedBox(height: 10),
                Text(widget.footer!(), style: const TextStyle(color: JC.gold, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                GoldButton(label: tr('close'), icon: Icons.check, onPressed: () => Navigator.pop(context)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}
