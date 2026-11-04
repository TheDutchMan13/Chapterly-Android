import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/pairing_qr.dart';

/// Point the camera at the QR code shown by Chapterly on the PC. Pops with the
/// pairing code (16 characters) once a valid code has been read.
class PairScanScreen extends StatelessWidget {
  const PairScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CodeScanScreen<String>(
      parse: parsePairingQr,
      title: 'Scan code from your PC',
      hint: 'Point the camera at the code shown by Chapterly on your PC.',
      wrongCodeHint: 'That is not a Chapterly code. Use the code shown by '
          'Chapterly on your PC.',
    );
  }
}

/// A camera page that reads QR codes only. [parse] turns the text of a code
/// into a result, or null if it is not the kind of code wanted; the page pops
/// with the first result, once.
class CodeScanScreen<T extends Object> extends StatefulWidget {
  const CodeScanScreen({
    super.key,
    required this.parse,
    required this.title,
    required this.hint,
    required this.wrongCodeHint,
  });

  final T? Function(String text) parse;
  final String title;
  final String hint;
  final String wrongCodeHint;

  @override
  State<CodeScanScreen<T>> createState() => _CodeScanScreenState<T>();
}

class _CodeScanScreenState<T extends Object> extends State<CodeScanScreen<T>> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;
  bool _wrongCode = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_done) return;
    T? code;
    var sawOther = false;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      code = widget.parse(value);
      if (code != null) break;
      sawOther = true;
    }
    if (code == null) {
      if (sawOther && !_wrongCode) setState(() => _wrongCode = true);
      return;
    }
    // One scan is handled once, even if the camera reports the code again.
    _done = true;
    await _controller.stop();
    if (!mounted) return;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final status = _wrongCode ? widget.wrongCodeHint : widget.hint;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Toggle flashlight',
            icon: const Icon(Icons.flashlight_on),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              final denied =
                  error.errorCode == MobileScannerErrorCode.permissionDenied;
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    denied
                        ? 'Chapterly needs the camera to scan the code. '
                            'Allow it in your phone\'s settings, then try again.'
                        : 'The camera could not be started.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(status),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
