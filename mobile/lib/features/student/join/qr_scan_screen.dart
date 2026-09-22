import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../groups/data/group_models.dart';

/// Ustoz ko'rsatgan QR kodni skanerlaydi va [InviteLink] qaytaradi.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;
  DateTime _lastWarning = DateTime(0);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final link = InviteLink.tryParse(barcode.rawValue ?? '');
      if (link != null) {
        _handled = true;
        HapticFeedback.mediumImpact();
        context.pop(link);
        return;
      }
    }
    // Boshqa QR: har kadrda emas, 3 soniyada bir marta ogohlantiramiz
    if (DateTime.now().difference(_lastWarning) > const Duration(seconds: 3)) {
      _lastWarning = DateTime.now();
      showSnack(context, "Bu Mentor AI guruh QR kodi emas", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final box = size.width * 0.7;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('QR kodni skanerlang', style: TextStyle(color: Colors.white)),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) => IconButton(
              tooltip: 'Chiroq',
              onPressed: _controller.toggleTorch,
              icon: Icon(
                state.torchState == TorchState.on ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(error: error),
          ),
          // Ramka atrofini xiralashtiramiz: foydalanuvchi qayerga qaratishni biladi
          IgnorePointer(
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.55), BlendMode.srcOut),
              child: Stack(
                children: [
                  Container(decoration: const BoxDecoration(color: Colors.black, backgroundBlendMode: BlendMode.dstOut)),
                  Center(
                    child: Container(
                      width: box,
                      height: box,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: box,
                height: box,
                decoration: BoxDecoration(
                  border: Border.all(color: Palette.info, width: 3),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 60,
            child: Text(
              "Ustozingiz ko'rsatgan QR kodni ramka ichiga joylang",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: EmptyState(
          icon: denied ? Icons.no_photography_rounded : Icons.videocam_off_rounded,
          title: denied ? 'Kameraga ruxsat berilmagan' : "Kamerani ochib bo'lmadi",
          message: denied
              ? "QR kodni skanerlash uchun telefon sozlamalaridan Mentor AI'ga kamera ruxsatini bering. "
                  "Yoki orqaga qaytib, kod va parolni qo'lda kiriting."
              : "Orqaga qaytib, guruh kodi va parolini qo'lda kiriting.",
          actionLabel: 'Orqaga',
          onAction: () => context.pop(),
        ),
      ),
    );
  }
}
