import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../network/api_exception.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Asosiy tugma: yuklanish holatida spinner ko'rsatadi va qayta bosilmaydi.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, this.onPressed, this.loading = false, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: loading
          ? SizedBox(
              key: const ValueKey('loading'),
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: context.colors.onPrimary),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            ),
    );
    return FilledButton(
      onPressed: loading || onPressed == null
          ? (loading ? () {} : null)
          : () {
              HapticFeedback.lightImpact();
              onPressed!();
            },
      child: child,
    );
  }
}

/// Holat belgisi: rang + ikonka + matn (faqat rangga tayanmaymiz).
enum StatusTone { success, warning, danger, info, neutral }

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.tone, this.icon});

  final String label;
  final StatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final (fg, bg) = switch (tone) {
      StatusTone.success => (c.success, c.successContainer),
      StatusTone.warning => (c.warning, c.warningContainer),
      StatusTone.danger => (c.danger, c.dangerContainer),
      StatusTone.info => (c.info, c.infoContainer),
      StatusTone.neutral => (context.colors.onSurfaceVariant, context.colors.surfaceContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Rangli ogohlantirish/ma'lumot bloki.
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.text, this.title, this.tone = StatusTone.info, this.icon});

  final String? title;
  final String text;
  final StatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final (fg, bg, defaultIcon) = switch (tone) {
      StatusTone.success => (c.success, c.successContainer, Icons.check_circle_rounded),
      StatusTone.warning => (c.warning, c.warningContainer, Icons.warning_amber_rounded),
      StatusTone.danger => (c.danger, c.dangerContainer, Icons.error_outline_rounded),
      _ => (c.info, c.infoContainer, Icons.info_outline_rounded),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defaultIcon, color: fg, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(title!, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 14.5)),
                  ),
                Text(text, style: TextStyle(color: context.colors.onSurface, fontSize: 14, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bo'sh holat: foydalanuvchi keyin nima qilishini doim biladi.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 46, color: context.colors.primary),
          ),
          const SizedBox(height: 20),
          Text(title, style: context.text.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            message,
            style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 24),
            PrimaryButton(label: actionLabel!, icon: actionIcon, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}

/// Yuklashda xato bo'lsa: nima bo'lganini aytadi va qayta urinish imkonini beradi.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final network = error is ApiException && (error as ApiException).isNetwork;
    return EmptyState(
      icon: network ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
      title: network ? "Internet yo'q" : "Yuklab bo'lmadi",
      message: errorText(error),
      actionLabel: 'Qayta urinish',
      actionIcon: Icons.refresh_rounded,
      onAction: onRetry,
    );
  }
}

/// Oq kartochka ichidagi bo'lim
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(Insets.lg), this.onTap});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Profil rasmi; rasm bo'lmasa yoki yuklanmasa — bosh harflar.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.initials, this.size = 44, this.color, this.imageUrl, this.ring});

  final String initials;
  final double size;
  final Color? color;
  final String? imageUrl;

  /// Atrofidagi rangli halqa (reyting shohsupasi uchun)
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), shape: BoxShape.circle),
      child: Text(
        initials,
        style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: size * 0.36),
      ),
    );
    final Widget body = imageUrl == null
        ? fallback
        : ClipOval(
            child: Image.network(
              imageUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              // Imzolangan havola vaqt o'tib almashadi: rasm yuklanguncha bosh harflar ko'rinadi
              frameBuilder: (context, child, frame, sync) => frame == null && !sync ? fallback : child,
              errorBuilder: (_, _, _) => fallback,
              cacheWidth: (size * 3).round(),
            ),
          );
    if (ring == null) return body;
    return Container(
      padding: EdgeInsets.all(size * 0.045),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring!, width: size * 0.045)),
      child: body,
    );
  }
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? context.appColors.danger : null,
    ),
  );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Bekor qilish')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: destructive ? TextButton.styleFrom(foregroundColor: context.appColors.danger) : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
