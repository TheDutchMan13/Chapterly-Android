import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/open_library_client.dart';

/// What the scan screen hands back: the scanned ISBN and, if Open Library
/// knows it, the matching book.
class ScannedBook {
  const ScannedBook({required this.isbn, this.book});

  final String isbn;
  final OpenLibraryBook? book;
}

String? _firstCode(BarcodeCapture capture) {
  for (final barcode in capture.barcodes) {
    final value = barcode.rawValue;
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

/// Point the camera at the barcode on the back of a book.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.client});

  final OpenLibraryClient client;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA],
  );
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final code = _firstCode(capture);
    if (code == null) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final book = await widget.client.lookupIsbn(code);
      if (!mounted) return;
      Navigator.of(context).pop(ScannedBook(isbn: code, book: book));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Could not reach Open Library. '
            'Check your connection, then scan again.';
      });
      // Pause before scanning again so a bad connection does not loop.
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    final status = message ??
        (_busy
            ? 'Looking up book…'
            : 'Point the camera at the barcode on the back of the book.');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan a barcode'),
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
          MobileScanner(controller: _controller, onDetect: _onDetect),
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
                    child: Row(
                      children: [
                        if (_busy && message == null) ...[
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(child: Text(status)),
                      ],
                    ),
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
