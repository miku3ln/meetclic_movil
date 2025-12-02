import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

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
    String? headReason; // <-- para saber por qué no tenemos content-length

    // ===========================
    // 0) Intentar leer desde memo
    // ===========================
    if (!forceRefresh && _lenMemo.containsKey(url)) {
      contentLength = _lenMemo[url];
    } else {
      // ===================================
      // 1) Intentar HEAD para obtener tamaño
      // ===================================
      try {
        final head = await dio.head(
          url,
          options: Options(
            followRedirects: true,
            // No lances excepción sólo por status != 200
            validateStatus: (s) => s != null && s < 500,
          ),
        );

        final status = head.statusCode ?? 0;

        if (status >= 200 && status < 300) {
          // HEAD OK pero puede o no traer content-length
          final lenStr = head.headers.value('content-length');

          if (lenStr != null) {
            contentLength = int.tryParse(lenStr);
            if (contentLength != null) {
              _lenMemo[url] = contentLength!;
              headReason = 'ok-with-content-length';
            } else {
              headReason = 'invalid-content-length-format';
            }
          } else {
            // Respuesta correcta pero sin cabecera de tamaño
            headReason = 'no-content-length-header';
          }
        } else {
          // HEAD respondió pero con status "raro"
          if (status == 405) {
            headReason = 'method-not-allowed'; // Servidor no soporta HEAD
          } else if (status == 403) {
            headReason = 'forbidden';
          } else if (status == 404) {
            headReason = 'not-found';
          } else if (status == 301 ||
              status == 302 ||
              status == 307 ||
              status == 308) {
            headReason = 'redirect-without-final-head';
          } else {
            headReason = 'unexpected-status-$status';
          }
        }

        // Debug opcional
        // ignore: avoid_print
        print(
          '[DownloadHelper] HEAD $url -> status=$status, reason=$headReason',
        );
        // ignore: avoid_print
        print('[DownloadHelper] HEAD headers: ${head.headers.map}');
      } on DioException catch (e) {
        // Posibles causas de error en dio.head
        switch (e.type) {
          case DioExceptionType.connectionTimeout:
            headReason = 'connection-timeout';
            break;
          case DioExceptionType.sendTimeout:
            headReason = 'send-timeout';
            break;
          case DioExceptionType.receiveTimeout:
            headReason = 'receive-timeout';
            break;
          case DioExceptionType.badResponse:
            final status = e.response?.statusCode;
            headReason = 'bad-response-${status ?? 'unknown'}';
            break;
          case DioExceptionType.cancel:
            headReason = 'request-cancelled';
            break;
          case DioExceptionType.badCertificate:
            headReason = 'bad-certificate';
            break;
          case DioExceptionType.connectionError:
            headReason = 'connection-error';
            break;
          case DioExceptionType.unknown:
          default:
            headReason = 'unknown-dio-error';
            break;
        }

        // Debug opcional
        // ignore: avoid_print
        print(
          '[DownloadHelper] HEAD error for $url -> type=${e.type}, reason=$headReason, error=$e',
        );
      } catch (e, st) {
        // Cualquier error no esperado
        headReason = 'unexpected-exception-${e.runtimeType}';
        // ignore: avoid_print
        print('[DownloadHelper] HEAD unexpected error for $url -> $e');
        // ignore: avoid_print
        print(st);
      }
    }

    // =======================================================
    // 2) Decidir si podemos usar data:URI o no
    // =======================================================
    final canDataUri =
        (contentLength != null &&
        contentLength > 0 &&
        contentLength <= dataUriMaxBytes);

    // Archivo demasiado grande para data:URI
    final isTooBigForDataUri =
        (contentLength != null && contentLength > dataUriMaxBytes);

    // 2.1) Reusar data:URI en memoria si aplica
    if (!forceRefresh && canDataUri && _dataMemo.containsKey(url)) {
      final m = _dataMemo[url]!;
      onProgress?.call(m.contentLength, m.contentLength); // 100%
      return DownloadResult(
        success: true,
        data: m.dataUri,
        bytesReceived: m.contentLength,
        totalBytes: m.contentLength,
        extra: {
          'isDataUri': true,
          'source': 'mem',
          if (headReason != null) 'headReason': headReason,
        },
      );
    }

    // 2.2) Caso A: archivo demasiado grande para data:URI
    //      -> Hacemos GET solo para mostrar progreso, pero devolvemos la URL https.
    if (isTooBigForDataUri) {
      if (onProgress != null) {
        try {
          await dio.get<List<int>>(
            url,
            onReceiveProgress: (r, t) {
              // t debería ser == contentLength; si no, usamos contentLength conocido
              final total = (t > 0) ? t : (contentLength ?? t);
              onProgress(r, total);
            },
            options: Options(responseType: ResponseType.bytes),
          );
        } catch (e) {
          // Si falla esta descarga de "previsualización", igual devolvemos la URL
          // y dejamos que el plugin AR haga su trabajo.
          // ignore: avoid_print
          print('[DownloadHelper] preview GET failed for $url: $e');
        }
      }

      return DownloadResult(
        success: true,
        data: url,
        extra: {
          'isDataUri': false,
          'source': 'https-large',
          'canDataUri': false,
          'contentLength': contentLength,
          if (headReason != null) 'headReason': headReason,
        },
      );
    }

    // 2.3) Caso B: no podemos usar data:URI (tamaño desconocido/0 o HEAD falló)
    if (!canDataUri) {
      // Aquí ya sabemos por qué no: tamaño desconocido, muy grande sin HEAD, etc.
      return DownloadResult(
        success: true,
        data: url,
        extra: {
          'isDataUri': false,
          'source': 'https',
          'canDataUri': false,
          'contentLength': contentLength,
          if (headReason != null) 'headReason': headReason,
        },
      );
    }

    // =======================================================
    // 3) Descargar con progreso y construir data:URI
    // =======================================================
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
            extra: {
              'isDataUri': true,
              'source': 'mem/new',
              if (headReason != null) 'headReason': headReason,
            },
          );
        }

        return DownloadResult(
          success: false,
          message: 'HTTP $status',
          extra: {
            'phase': 'get',
            'status': status,
            if (headReason != null) 'headReason': headReason,
          },
        );
      } on DioException catch (e) {
        // Error en GET, también detallado
        if (attempt == maxRetries) {
          return DownloadResult(
            success: false,
            message: e.toString(),
            extra: {
              'phase': 'get',
              'dioType': e.type.toString(),
              if (e.response?.statusCode != null)
                'status': e.response!.statusCode,
              if (headReason != null) 'headReason': headReason,
            },
          );
        }
        await Future.delayed(const Duration(milliseconds: 350));
      } catch (e) {
        if (attempt == maxRetries) {
          return DownloadResult(
            success: false,
            message: e.toString(),
            extra: {
              'phase': 'get',
              'errorType': e.runtimeType.toString(),
              if (headReason != null) 'headReason': headReason,
            },
          );
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

enum ARLoadStatus { idle, loading, success, error }
/* =============================================================================
 * UI Helpers
 * ========================================================================== */

class UiHelpers {
  UiHelpers._();

  static void showSnack(
    BuildContext context,
    String msg, {
    bool error = false,
  }) {
    final sb = SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red[700] : Colors.black87,
      duration: const Duration(seconds: 3),
    );
    ScaffoldMessenger.of(context).showSnackBar(sb);
  }

  static Color statusColor(ARLoadStatus s) {
    switch (s) {
      case ARLoadStatus.loading:
        return Colors.amber[700]!;
      case ARLoadStatus.success:
        return Colors.green[700]!;
      case ARLoadStatus.error:
        return Colors.red[700]!;
      case ARLoadStatus.idle:
      default:
        return Colors.blueGrey[600]!;
    }
  }

  static String statusText(ARLoadStatus s) {
    switch (s) {
      case ARLoadStatus.loading:
        return 'Cargando…';
      case ARLoadStatus.success:
        return 'Listo';
      case ARLoadStatus.error:
        return 'Error';
      case ARLoadStatus.idle:
      default:
        return 'Listo';
    }
  }
}
