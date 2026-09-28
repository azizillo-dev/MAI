import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Rasmlar telefon xotirasida saqlanadi: ilova qayta ochilganda ham tarmoqdan qayta yuklanmaydi.
final mediaCache = CacheManager(
  Config(
    'mentor_media',
    stalePeriod: const Duration(days: 60),
    maxNrOfCacheObjects: 1000,
  ),
);

/// Server rasm havolasini muddatli imzo bilan beradi (`?exp=...&sig=...`) va imzo vaqti-vaqti bilan
/// yangilanadi. Kesh kaliti — faqat fayl yo'li: har bir yuklangan fayl yangi (takrorlanmas) nom oladi,
/// shuning uchun yo'l bir xil bo'lsa, rasm ham aynan o'sha.
String mediaCacheKey(String url) {
  final uri = Uri.tryParse(url);
  return uri == null || uri.path.isEmpty ? url : uri.path;
}
