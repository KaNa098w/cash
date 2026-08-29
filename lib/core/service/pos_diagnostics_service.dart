import 'dart:collection';

import 'package:dio/dio.dart';

class PosDiagnosticsService {
  PosDiagnosticsService({this.maxHttpEntries = 80});

  final int maxHttpEntries;
  final ListQueue<Map<String, dynamic>> _httpEntries =
      ListQueue<Map<String, dynamic>>();

  String? _lastErrorMessage;
  Map<String, dynamic>? _lastSnapshotFile;
  List<Map<String, dynamic>> _lastSnapshotProducts = const [];
  Map<String, dynamic>? _lastBootstrapSummary;
  final List<Map<String, dynamic>> _localStorageIssues = [];

  // Diagnostics must never become a second in-memory database. A product
  // snapshot can contain tens of thousands of fairly large maps.
  static const int _snapshotSampleSize = 20;
  static const int _collectionSampleSize = 50;
  static const int _maxCloneDepth = 8;

  void recordError(String message) {
    final value = message.trim();
    if (value.isEmpty) return;
    _lastErrorMessage = value;
  }

  void recordRequest(RequestOptions options) {
    _addHttpEntry(
      _baseEntry(options)
        ..addAll({
          'phase': 'request',
          'request': _requestMap(options),
        }),
    );
  }

  void recordResponse(Response<dynamic> response) {
    _addHttpEntry(
      _baseEntry(response.requestOptions)
        ..addAll({
          'phase': 'response',
          'request': _requestMap(response.requestOptions),
          'response': _responseMap(response),
        }),
    );
  }

  void recordDioError(DioException error) {
    recordError(error.message ?? error.toString());
    _addHttpEntry(
      _baseEntry(error.requestOptions)
        ..addAll({
          'phase': 'error',
          'dio_type': error.type.name,
          'message': error.message,
          'request': _requestMap(error.requestOptions),
          'response':
              error.response == null ? null : _responseMap(error.response!),
        }),
    );
  }

  void recordManualHttp({
    required String method,
    required String url,
    dynamic requestData,
    dynamic responseData,
    int? statusCode,
    String? statusMessage,
    Object? error,
  }) {
    if (error != null) recordError(error.toString());
    _addHttpEntry({
      'at': DateTime.now().toIso8601String(),
      'phase': error == null ? 'response' : 'error',
      'request': {
        'method': method,
        'url': url,
        'data': _cloneJsonValue(requestData),
      },
      'response': error == null
          ? {
              'status_code': statusCode,
              'status_message': statusMessage,
              'data': _cloneJsonValue(responseData),
            }
          : null,
      if (error != null) 'message': error.toString(),
    });
  }

  void recordSnapshotFile(Map<String, dynamic> snapshotFile) {
    final products = (snapshotFile['products'] as List?) ?? const [];
    _lastSnapshotFile = <String, dynamic>{
      for (final entry in snapshotFile.entries)
        if (entry.key != 'products' &&
            entry.key != 'sales' &&
            entry.key != 'refunds')
          entry.key: _cloneJsonValue(entry.value),
      'products_count': products.length,
      'sales_count': (snapshotFile['sales'] as List?)?.length ?? 0,
      'refunds_count': (snapshotFile['refunds'] as List?)?.length ?? 0,
    };
    _lastSnapshotProducts = products
        .whereType<Map>()
        .take(_snapshotSampleSize)
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  void recordBootstrapSummary(Map<String, dynamic> summary) {
    _lastBootstrapSummary = <String, dynamic>{
      for (final entry in summary.entries)
        if (entry.key != 'saved_snapshot_products')
          entry.key: _cloneJsonValue(entry.value),
    };
  }

  void recordLocalStorageIssue(Map<String, dynamic> issue) {
    final normalized = Map<String, dynamic>.from(issue);
    _localStorageIssues.add(normalized);
    _lastErrorMessage = 'Local storage issue: ${normalized['file'] ?? ''}';
  }

  List<Map<String, dynamic>> get localStorageIssues =>
      List.unmodifiable(_localStorageIssues);

  Map<String, dynamic> buildReport({
    Map<String, dynamic>? localState,
    List<Map<String, dynamic>> localProducts = const [],
  }) {
    return {
      'generated_at': DateTime.now().toIso8601String(),
      'last_error_message': _lastErrorMessage,
      'http_entries': _httpEntries.toList(growable: false),
      'last_bootstrap_summary': _lastBootstrapSummary,
      'last_snapshot_file': _lastSnapshotFile,
      'last_snapshot_products': _lastSnapshotProducts,
      'local_storage_issues': localStorageIssues,
      'local_state': localState,
      'local_products_saved_from_snapshot': localProducts,
    };
  }

  Map<String, dynamic> _baseEntry(RequestOptions options) {
    return {
      'at': DateTime.now().toIso8601String(),
      'base_url': options.baseUrl,
      'path': options.path,
    };
  }

  Map<String, dynamic> _requestMap(RequestOptions options) {
    return {
      'method': options.method,
      'uri': options.uri.toString(),
      'path': options.path,
      'query': Map<String, dynamic>.from(options.queryParameters),
      'headers': Map<String, dynamic>.from(options.headers),
      'data': _cloneJsonValue(options.data),
      'extra': Map<String, dynamic>.from(options.extra),
    };
  }

  Map<String, dynamic> _responseMap(Response<dynamic> response) {
    return {
      'status_code': response.statusCode,
      'status_message': response.statusMessage,
      'headers': response.headers.map,
      'data': _cloneJsonValue(response.data),
    };
  }

  void _addHttpEntry(Map<String, dynamic> entry) {
    _httpEntries.add(entry);
    while (_httpEntries.length > maxHttpEntries) {
      _httpEntries.removeFirst();
    }
  }

  dynamic _cloneJsonValue(dynamic value, [int depth = 0]) {
    if (depth >= _maxCloneDepth) return '<max-depth>';
    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries.take(_collectionSampleSize)) {
        result[entry.key.toString()] = _cloneJsonValue(entry.value, depth + 1);
      }
      if (value.length > _collectionSampleSize) {
        result['_diagnostics_truncated_entries'] =
            value.length - _collectionSampleSize;
      }
      return result;
    }
    if (value is List) {
      final result = value
          .take(_collectionSampleSize)
          .map((item) => _cloneJsonValue(item, depth + 1))
          .toList(growable: true);
      if (value.length > _collectionSampleSize) {
        result.add({
          '_diagnostics_truncated_items': value.length - _collectionSampleSize,
        });
      }
      return List<dynamic>.unmodifiable(result);
    }
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    return value.toString();
  }
}

class PosDiagnosticsInterceptor extends Interceptor {
  PosDiagnosticsInterceptor(this._diagnostics);

  final PosDiagnosticsService _diagnostics;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _diagnostics.recordRequest(options);
    handler.next(options);
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    _diagnostics.recordResponse(response);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _diagnostics.recordDioError(err);
    handler.next(err);
  }
}
