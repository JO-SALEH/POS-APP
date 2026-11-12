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

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  // autoStart:false -> we start the camera ourselves, catch the real error and can retry (after the user allows the camera, etc.)
  final MobileScannerController _c = MobileScannerController(facing: CameraFacing.back, autoStart: false);
  bool _busy = false;
  bool _torch = false;
  String? _flash;
  bool _starting = true; // camera is being started / waiting for the permission dialog
  bool _running = false;
  bool _wasRunning = false; // was running when the app went to the background
  bool _denied = false; // permission refused
  String? _errText; // the real error, shown on screen

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted || _running) return;
    setState(() {
      _starting = true;
      _errText = null;
      _denied = false;
    });
    try {
      await _c.start(); // asks for the camera permission the first time
      _running = true;
    } on MobileScannerException catch (e) {
      if (mounted) {
        setState(() {
          _denied = e.errorCode == MobileScannerErrorCode.permissionDenied;
          _errText = '$e';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errText = '$e');
    }
    if (mounted) setState(() => _starting = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // back from the phone Settings (permission just allowed) or from the background
      if (_errText != null && _denied) {
        _start();
      } else if (_wasRunning) {
        _wasRunning = false;
        _start();
      }
    } else if (state == AppLifecycleState.paused && _running) {
      _wasRunning = true;
      _running = false;
      _c.stop();
    }
  }

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
    WidgetsBinding.instance.removeObserver(this);
    _c.dispose();
    super.dispose();
  }

  Widget _errorPanel() => Container(
        color: Colors.black,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography_outlined, color: JC.danger, size: 56),
            const SizedBox(height: 14),
            Text(_denied ? tr('cam_denied') : tr('cam_error'),
                textAlign: TextAlign.center, style: const TextStyle(color: JC.danger, fontSize: 16, height: 1.5)),
            const SizedBox(height: 14),
            GoldButton(label: tr('cam_retry'), icon: Icons.refresh, onPressed: _start),
            const SizedBox(height: 18),
            Text(tr('cam_details'), style: const TextStyle(color: JC.muted, fontSize: 12)),
            const SizedBox(height: 4),
            SelectableText(_errText ?? '',
                textDirection: TextDirection.ltr, textAlign: TextAlign.center, style: const TextStyle(color: JC.silverDim, fontSize: 11)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final box = size.width * 0.72;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        MobileScanner(controller: _c, onDetect: _detect),
        if (_errText != null) _errorPanel(),
        if (_starting && _errText == null)
          Center(child: Text(tr('cam_starting'), style: const TextStyle(color: JC.silverDim))),
        if (_errText == null)
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
                    try {
                      await _c.toggleTorch();
                      if (mounted) setState(() => _torch = !_torch);
                    } catch (_) {} // some phones have no flash
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
