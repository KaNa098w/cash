import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class PosMaintenanceResult {
  const PosMaintenanceResult({required this.memoryBytes, this.diskError});

  final int memoryBytes;
  final Object? diskError;
}

/// Maintenance is deliberately limited to disposable image caches. Financial
/// storage, preferences, payment journals and product databases are untouched.
class PosMaintenanceService {
  PosMaintenanceService({
    Future<void> Function()? clearDiskCache,
    int Function()? clearMemoryCache,
  })  : _clearDiskCache = clearDiskCache ?? _clearDiskImages,
        _clearMemoryCache = clearMemoryCache ?? _clearMemoryImages;

  static final instance = PosMaintenanceService();
  final Future<void> Function() _clearDiskCache;
  final int Function() _clearMemoryCache;
  Future<PosMaintenanceResult>? _running;

  Future<PosMaintenanceResult> optimize() =>
      _running ??= _optimize().whenComplete(() => _running = null);

  Future<PosMaintenanceResult> _optimize() async {
    Object? diskError;
    try {
      await _clearDiskCache();
    } catch (error) {
      diskError = error;
    }
    return PosMaintenanceResult(
      memoryBytes: _clearMemoryCache(),
      diskError: diskError,
    );
  }

  static Future<void> _clearDiskImages() => DefaultCacheManager().emptyCache();

  static int _clearMemoryImages() {
    final cache = PaintingBinding.instance.imageCache;
    final bytes = cache.currentSizeBytes;
    cache.clear();
    return bytes;
  }
}
