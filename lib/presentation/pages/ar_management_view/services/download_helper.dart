import 'package:dio/dio.dart';

import 'download_models.dart';

class DownloadHelper {
  static const int _defaultDataUriMaxBytes = 8 * 1024 * 1024; // 8 MB

  // 🔸 Memos en memoria:
  // - data:URI pequeños (con tamaño conocido)
  static final Map<String, _MemoEntry> _dataMemo = {};
  // - tamaño (Content-Length) para evitar HEAD repetidos
  static final Map<String, int> _lenMemo = {};

  static Future<DownloadResult> fetchToCacheVerbose(
    String url, {
    Map<String, String>? headers,
    ProgressCb? onProgress,
    Duration connectTimeout = const Duration(seconds: 15),
    Duration receiveTimeout = const Duration(seconds: 60),
    int maxRetries = 1,
    int dataUriMaxBytes = _defaultDataUriMaxBytes,
    bool forceRefresh = false,
  }) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        responseType: ResponseType.bytes,
        headers: headers,
        followRedirects: true,
        receiveDataWhenStatusError: true,
      ),
    );

    int? contentLength;
    if (!forceRefresh && _lenMemo.containsKey(url)) {
      contentLength = _lenMemo[url];
    } else {
      try {
        final head = await dio.head(url);
        final lenStr = head.headers.value('content-length');
        if (lenStr != null) contentLength = int.tryParse(lenStr);
        if (contentLength != null) _lenMemo[url] = contentLength!;
      } catch (_) {
        // HEAD puede fallar: sin tamaño conocido
      }
    }

    final canDataUri =
        (contentLength != null &&
        contentLength > 0 &&
        contentLength <= dataUriMaxBytes);

    // 0) Reusar data:URI del memo
    if (!forceRefresh && canDataUri && _dataMemo.containsKey(url)) {
      final m = _dataMemo[url]!;
      onProgress?.call(m.contentLength, m.contentLength); // 100%
      return DownloadResult(
        success: true,
        data: m.dataUri,
        bytesReceived: m.contentLength,
        totalBytes: m.contentLength,
        extra: const {'isDataUri': true, 'source': 'mem'},
      );
    }

    // 1) Si no podemos data:URI (grande/sin tamaño) => usar https y confiar en cache HTTP
    if (!canDataUri) {
      // Nota: aquí no hay % porque no descargamos previamente.
      return DownloadResult(
        success: true,
        data: url,
        extra: const {'isDataUri': false, 'source': 'https'},
      );
    }

    // 2) Descargar con % y construir data:URI
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final res = await dio.get<List<int>>(
          url,
          onReceiveProgress: (r, t) => onProgress?.call(r, t),
          options: Options(responseType: ResponseType.bytes),
        );

        final status = res.statusCode ?? 0;
        final data = res.data;

        if (status == 200 && data != null) {
          final dataUri = Uri.dataFromBytes(
            data,
            mimeType: 'model/gltf-binary',
          ).toString();

          final len = contentLength ?? data.length;
          _dataMemo[url] = _MemoEntry(dataUri: dataUri, contentLength: len);

          return DownloadResult(
            success: true,
            data: dataUri,
            bytesReceived: data.length,
            totalBytes: len,
            extra: const {'isDataUri': true, 'source': 'mem/new'},
          );
        }
        return DownloadResult(success: false, message: 'HTTP $status');
      } catch (e) {
        if (attempt == maxRetries) {
          return DownloadResult(success: false, message: e.toString());
        }
        await Future.delayed(const Duration(milliseconds: 350));
      }
    }
    return const DownloadResult(success: false, message: 'Descarga cancelada.');
  }

  static void revokeIfNeeded(String? url) {
    /* noop */
  }
}

class _MemoEntry {
  final String dataUri;
  final int contentLength;
  const _MemoEntry({required this.dataUri, required this.contentLength});
}
