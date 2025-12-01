// lib/exercises/a03_tap_place_glb_assets.dart
//
// Ejercicio 3 — Tap → Colocar GLB (assets) — CON DIAGNÓSTICO
// -------------------------------------------------------------
// Objetivo:
// - Detectar taps sobre un plano (hit test) y crear un ARPlaneAnchor.
// - Anclar un modelo .glb local (assets) en ese anchor.
// - Permitir quitar el modelo (reset) desde la UI.
// - Mostrar UI/UX de diagnóstico: verifica asset, captura errores paso a paso,
//   y los muestra en pantalla (tarjeta + SnackBar).
//
// Qué verás:
// - Con tracking listo y planos detectados, toca una superficie y se colocará
//   el modelo GLB. Si algo falla, verás el motivo exacto.
//
// Dependencias (pubspec.yaml):
//   ar_flutter_plugin: ^0.9.0
//   vector_math: ^2.1.4
//
// Assets (pubspec.yaml):
//   flutter:
//     assets:
//       - assets/totems/examples/HORNET.glb
//
// Notas Clean Code:
// - Separación de responsabilidades y nombres expresivos.
// - _verifyAssetAvailable(): verifica que el GLB esté empaquetado.
// - _setInfo/_setError: centralizan UI de estado/errores.
// -------------------------------------------------------------
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin/models/ar_anchor.dart';
import 'package:ar_flutter_plugin/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin/models/ar_node.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:vector_math/vector_math_64.dart' show Vector3;

class A03TapPlaceGlbAssets extends StatefulWidget {
  const A03TapPlaceGlbAssets({super.key});

  @override
  State<A03TapPlaceGlbAssets> createState() => _A03TapPlaceGlbAssetsState();
}

class _A03TapPlaceGlbAssetsState extends State<A03TapPlaceGlbAssets> {
  // Managers
  ARSessionManager? _arSessionManager;
  ARObjectManager? _arObjectManager;
  ARAnchorManager? _arAnchorManager;
  ARLocationManager? _arLocationManager;

  // Estado de escena
  ARPlaneAnchor? _placedAnchor;
  ARNode? _placedNode;

  // Estado de UI/depuración
  bool _isReady = false;
  bool _showPlanes = true;
  bool _showWorldOrigin = false;
  bool _showFeaturePoints = true; // FIX #2: por defecto encendidos
  String _statusText = 'Inicializando…';
  String? _lastError;
  String? _manifestSummary; // pista si el asset no está en el bundle

  // Config del asset (ajusta a tu ruta exacta)
  static const String _assetGlbPath =
      'assets/totems/examples/mikasa/gothic__elegance_texture_anime_girl.glb';
  static Vector3 _defaultScale = Vector3(0.2, 0.2, 0.2);

  // Utilidades de estado
  void _setInfo(String msg) {
    debugPrint('[INFO] $msg');
    if (!mounted) return;
    setState(() => _statusText = msg);
  }

  void _setError(String msg) {
    debugPrint('[ERROR] $msg');
    if (!mounted) return;
    setState(() {
      _lastError = msg;
      _statusText = 'Error: $msg';
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _arSessionManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topChips = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StateChip(
          label: _isReady ? 'AR: Listo' : 'AR: Cargando…',
          on: _isReady,
          icon: Icons.check_circle,
        ),
        _StateChip(
          label: _showPlanes ? 'Planos: ON' : 'Planos: OFF',
          on: _showPlanes,
          icon: Icons.grid_on,
        ),
        _StateChip(
          label: _placedNode == null
              ? 'Modelo: No colocado'
              : 'Modelo: Colocado',
          on: _placedNode != null,
          icon: Icons.toys,
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('A03 — Tap → Colocar GLB (assets)'),
        actions: [
          IconButton(
            tooltip: 'Ver AssetManifest',
            icon: const Icon(Icons.list_alt),
            onPressed: () async {
              await _debugAssetManifest();
              final msg =
                  _manifestSummary ?? 'Manifest inspeccionado (ver consola).';
              if (!mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(msg)));
              setState(() {});
            },
          ),
          IconButton(
            tooltip: 'Ayuda',
            icon: const Icon(Icons.help_outline),
            onPressed: _showHelp,
          ),
        ],
      ),
      body: Stack(
        children: [
          // ARView al fondo
          ARView(onARViewCreated: _onARViewCreated),

          // FIX #1: Overlays que NO bloquean taps al ARView
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: IgnorePointer(ignoring: true, child: topChips),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 92,
            child: IgnorePointer(
              ignoring: true,
              child: _StatusCard(
                statusText: _statusText,
                extra: _placedNode == null
                    ? 'Toca un plano para colocar el modelo.'
                    : 'Toca otro punto para reubicar (se reemplaza).',
                errorText: _lastError,
                manifestHint: _manifestSummary,
              ),
            ),
          ),
        ],
      ),

      // Barra inferior (sí interactúa)
      bottomNavigationBar: _BottomBar(
        showPlanes: _showPlanes,
        showFeaturePoints: _showFeaturePoints,
        onTogglePlanes: (v) => _applyDebugOptions(planes: v),
        onToggleFeaturePoints: (v) => _applyDebugOptions(featurePoints: v),
        onReset: _removePlacedModel,
      ),
    );
  }

  // Callback de creación: firma correcta (void, 4 managers)
  void _onARViewCreated(
    ARSessionManager arSessionManager,
    ARObjectManager arObjectManager,
    ARAnchorManager arAnchorManager,
    ARLocationManager arLocationManager,
  ) {
    _arSessionManager = arSessionManager;
    _arObjectManager = arObjectManager;
    _arAnchorManager = arAnchorManager;
    _arLocationManager = arLocationManager;

    _initArSession(); // inicialización
    _wireSessionCallbacks(); // taps
  }

  // Inicializa sesión + ObjectManager (FIX #3)
  Future<void> _initArSession() async {
    if (_arSessionManager == null) {
      _setError('ARSessionManager no inicializado.');
      return;
    }
    try {
      await _arSessionManager!.onInitialize(
        showFeaturePoints: _showFeaturePoints,
        showPlanes: _showPlanes,
        showWorldOrigin: _showWorldOrigin,
        handlePans: false,
        handleRotation: false,
        handleTaps: true,
      );

      // IMPORTANTE: algunos builds requieren inicializar también el ObjectManager
      await _arObjectManager?.onInitialize(); // FIX #3

      if (!mounted) return;
      _lastError = null;
      setState(() {
        _isReady = true;
        _statusText = Platform.isAndroid
            ? 'Listo. Apunta a una superficie y toca para colocar. (ARCore)'
            : 'Listo. Apunta a una superficie y toca para colocar. (ARKit)';
      });
    } catch (e) {
      _setError('Fallo al iniciar la sesión AR: $e');
    }
  }

  // Taps (vive en ARSessionManager)
  void _wireSessionCallbacks() {
    _arSessionManager?.onPlaneOrPointTap = (List<ARHitTestResult> hits) async {
      if (hits.isEmpty) {
        _setError('No hubo impacto de hit-test. Toca un plano detectado.');
        return;
      }
      // await _placeModelAtHit(hits.first);
      await _placeTextMarkerAtHit(hits.first, 'Hola AR 👋');
    };
  }

  String? _floatingLabel; // overlay de texto

  Future<void> _placeTextMarkerAtHit(ARHitTestResult hit, String text) async {
    // Limpieza si ya hay algo
    if (_placedNode != null || _placedAnchor != null) {
      await _removePlacedModel();
    }

    // 1) Crear anchor desde el hit
    final anchor = ARPlaneAnchor(transformation: hit.worldTransform);
    bool? didAddAnchor = false;
    try {
      didAddAnchor = await _arAnchorManager!.addAnchor(anchor);
    } catch (e) {
      _setError('Fallo addAnchor(): $e');
      return;
    }
    if (didAddAnchor != true) {
      _setError('addAnchor() devolvió false (no se creó el anchor).');
      return;
    }

    // 2) No agregamos ningún Node → solo visualizamos overlay
    setState(() {
      _placedAnchor = anchor;
      _placedNode = null;
      _floatingLabel = text;
      _statusText = 'Anchor creado sin GLB (solo texto).';
      _lastError = null;
    });

    // Ocultar el texto flotante después de unos segundos
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _floatingLabel = null);
    });
  }

  // Verifica que el asset GLB esté en el bundle
  /// Verifica que el asset exista **y** da diagnóstico útil.
  /// - Comprueba que la clave está en el bundle (rootBundle.load)
  /// - Lee cabecera GLB (magic/version/length)
  /// - Inspecciona el chunk JSON para detectar extensiones problemáticas
  ///   (p. ej. Draco, BasisU) o texturas externas no embebidas.
  /// Devuelve `true` si el asset es accesible (aunque tenga warnings),
  /// `false` si definitivamente no está empaquetado.
  Future<bool> _verifyAssetAvailable(String assetPath) async {
    // 1) Carga desde bundle
    ByteData data;
    try {
      data = await rootBundle.load(assetPath);
    } catch (e) {
      // Asset no empaquetado: muestra pistas desde el manifest
      try {
        final manifestJson = await rootBundle.loadString('AssetManifest.json');
        final Map<String, dynamic> manifest =
            json.decode(manifestJson) as Map<String, dynamic>;
        final hasExactKey = manifest.keys.contains(assetPath);
        final similar = manifest.keys
            .where(
              (k) =>
                  k.toLowerCase() == assetPath.toLowerCase() ||
                  (k.startsWith('assets/') &&
                      assetPath.startsWith('assets/') &&
                      k.split('/').last.toLowerCase() ==
                          assetPath.split('/').last.toLowerCase()),
            )
            .take(5)
            .toList();
        _setError(
          [
            'Asset no encontrado en el bundle:',
            '• clave buscada: $assetPath',
            '• ¿clave exacta en manifest?: $hasExactKey',
            '• similares: ${similar.isEmpty ? "ninguna" : similar.join(", ")}',
            'Revisa pubspec (indentación/case) y recompila (flutter clean && flutter run).',
          ].join('\n'),
        );
      } catch (e2) {
        _setError(
          'Asset no encontrado: $assetPath. Además, no se pudo leer AssetManifest.json: $e2',
        );
      }
      return false;
    }

    // 2) Validación de cabecera GLB (12 bytes)
    if (data.lengthInBytes < 12) {
      _setError('GLB demasiado pequeño (${data.lengthInBytes} bytes).');
      return true;
    }
    final bd = data.buffer.asByteData();
    final magic = String.fromCharCodes([
      bd.getUint8(0),
      bd.getUint8(1),
      bd.getUint8(2),
      bd.getUint8(3),
    ]);
    final version = bd.getUint32(4, Endian.little);
    final declaredLen = bd.getUint32(8, Endian.little);
    final realLen = data.lengthInBytes;
    if (magic != 'glTF' || version != 2 || declaredLen != realLen) {
      _setError(
        'Cabecera GLB sospechosa (magic=$magic, version=$version, declared=$declaredLen, real=$realLen).',
      );
      return true; // existe, pero puede fallar
    }

    // 3) Leer chunk JSON y listar extensionsUsed/Required
    if (realLen < 20) {
      _setError('GLB sin chunk JSON.');
      return true;
    }
    try {
      final jsonLen = bd.getUint32(12, Endian.little);
      final jsonType = bd.getUint32(16, Endian.little); // 'JSON' = 0x4E4F534A
      const jsonTag = 0x4E4F534A;
      if (jsonType != jsonTag || 20 + jsonLen > realLen) {
        _setError('Chunk JSON inválido (type=$jsonType, len=$jsonLen).');
        return true;
      }
      final jsonBytes = data.buffer.asUint8List(20, jsonLen);
      final jsonText = utf8.decode(jsonBytes, allowMalformed: true);

      Map<String, dynamic> root;
      try {
        root = json.decode(jsonText) as Map<String, dynamic>;
      } catch (_) {
        root = const {};
      }

      List<dynamic> used = (root['extensionsUsed'] as List?) ?? const [];
      List<dynamic> req = (root['extensionsRequired'] as List?) ?? const [];

      final hasDraco =
          used.contains('KHR_draco_mesh_compression') ||
          req.contains('KHR_draco_mesh_compression');
      final hasBasisU =
          used.contains('KHR_texture_basisu') ||
          req.contains('KHR_texture_basisu');

      final hasExternalImages = () {
        final images = (root['images'] as List?) ?? const [];
        for (final img in images) {
          if (img is Map && img['uri'] is String) {
            final uri = (img['uri'] as String).toLowerCase();
            if (!uri.startsWith('data:')) return true; // no embebida
          }
        }
        return false;
      }();

      final warnings = <String>[];
      if (hasDraco)
        warnings.add(
          'Extensión requerida: KHR_draco_mesh_compression (NO soportada).',
        );
      if (hasBasisU)
        warnings.add(
          'Extensión: KHR_texture_basisu (puede no estar soportada).',
        );
      if (hasExternalImages)
        warnings.add('Imágenes no embebidas (URIs externas).');

      if (warnings.isNotEmpty) {
        _setError(
          [
            'El GLB está empaquetado y es glTF 2.0, pero podría fallar en Sceneform:',
            ...warnings.map((w) => '• $w'),
            'Re-exporta como GLB Binary: Draco OFF, imágenes embebidas, sin extensiones no soportadas.',
          ].join('\n'),
        );
      } else {
        _setInfo(
          'Asset OK en bundle (glTF v$version, $realLen bytes). Sin extensiones problemáticas detectadas.',
        );
      }
    } catch (e) {
      _setError('No se pudo analizar el JSON interno del GLB: $e');
    }

    return true; // existe; ya dimos advertencias si aplica
  }

  // Inspecciona AssetManifest para pistas
  Future<void> _debugAssetManifest() async {
    try {
      final jsonStr = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifest =
          json.decode(jsonStr) as Map<String, dynamic>;
      final keys = manifest.keys.toList()..sort();
      final hornet = keys.where((k) => k.contains('HORNET')).toList();
      final folder = keys
          .where((k) => k.startsWith('assets/totems/examples/'))
          .toList();
      debugPrint('--- AssetManifest (primeros 40) ---');
      for (final k in keys.take(40)) debugPrint(k);
      debugPrint('--- Claves con "HORNET" ---');
      hornet.forEach(debugPrint);
      debugPrint('--- En carpeta assets/totems/examples/ ---');
      folder.forEach(debugPrint);
      _manifestSummary = hornet.isNotEmpty
          ? 'Manifest OK: ${hornet.length} clave(s) con HORNET.'
          : 'Manifest: no hay entradas con HORNET.';
    } catch (e) {
      _manifestSummary = 'No se pudo leer AssetManifest.json: $e';
      debugPrint('[ASSET] Error leyendo AssetManifest.json: $e');
    }
  }

  // Colocar (o recolocar) el modelo
  Future<void> _placeModelAtHit(ARHitTestResult hit) async {}

  // Eliminar modelo/ancla
  Future<void> _removePlacedModel() async {
    try {
      if (_placedNode != null) {
        await _arObjectManager?.removeNode(_placedNode!);
        _placedNode = null;
      }
    } catch (e) {
      _setError('Fallo removeNode(): $e');
    }

    try {
      if (_placedAnchor != null) {
        await _arAnchorManager?.removeAnchor(_placedAnchor!);
        _placedAnchor = null;
      }
    } catch (e) {
      _setError('Fallo removeAnchor(): $e');
    }

    if (!mounted) return;
    setState(() => _statusText = 'Modelo eliminado.');
  }

  // Reaplica opciones de depuración (planes / feature points) e inicializa ObjectManager
  Future<void> _applyDebugOptions({bool? planes, bool? featurePoints}) async {
    if (planes != null) _showPlanes = planes;
    if (featurePoints != null) _showFeaturePoints = featurePoints;
    setState(() {}); // refresca switches

    if (_arSessionManager == null) {
      _setError('ARSessionManager no inicializado.');
      return;
    }

    try {
      await _arSessionManager!.onInitialize(
        showFeaturePoints: _showFeaturePoints,
        showPlanes: _showPlanes,
        showWorldOrigin: _showWorldOrigin,
        handlePans: false,
        handleRotation: false,
        handleTaps: true,
      );
      await _arObjectManager?.onInitialize(); // mantener en sync
      _setInfo(
        'Opciones aplicadas → Planos: ${_showPlanes ? "ON" : "OFF"} | FeaturePoints: ${_showFeaturePoints ? "ON" : "OFF"}',
      );
    } catch (e) {
      _setError('Error al reconfigurar opciones: $e');
    }
  }

  void _showHelp() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final st = Theme.of(
          ctx,
        ).textTheme.bodyMedium?.copyWith(color: Colors.white);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: DefaultTextStyle(
            style: st ?? const TextStyle(color: Colors.white),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  '¿Qué hace este ejercicio?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  '• Toca un plano detectado para crear un anchor y colocar un GLB local.',
                ),
                Text('• Overlays no bloquean toques (IgnorePointer).'),
                Text(
                  '• Feature Points ON por defecto para ayudarte a “madurar” el plano.',
                ),
                Text(
                  '• ARObjectManager se inicializa para asegurar raycast y nodes.',
                ),
                SizedBox(height: 12),
                Text(
                  'Si no hay hit-test: evita tocar sobre overlays, usa superficies con textura y buena luz, mueve el móvil en “8”.',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StateChip extends StatelessWidget {
  final String label;
  final bool on;
  final IconData icon;
  const _StateChip({required this.label, required this.on, required this.icon});

  @override
  Widget build(BuildContext context) {
    final color = on ? Colors.greenAccent : Colors.grey;
    return Chip(
      avatar: Icon(icon, size: 18, color: Colors.black),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: color,
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String statusText;
  final String? extra;
  final String? errorText;
  final String? manifestHint;
  const _StatusCard({
    required this.statusText,
    this.extra,
    this.errorText,
    this.manifestHint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: Colors.black.withOpacity(0.55),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DefaultTextStyle(
          style: theme.textTheme.bodyMedium!.copyWith(color: Colors.white),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                statusText,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (extra != null) ...[
                const SizedBox(height: 6),
                Text(
                  extra!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ],
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  '⚠️ $errorText',
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              ],
              if (manifestHint != null) ...[
                const SizedBox(height: 6),
                Text(
                  '📦 $manifestHint',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final bool showPlanes;
  final bool showFeaturePoints;
  final ValueChanged<bool> onTogglePlanes;
  final ValueChanged<bool> onToggleFeaturePoints;
  final VoidCallback onReset;

  const _BottomBar({
    required this.showPlanes,
    required this.showFeaturePoints,
    required this.onTogglePlanes,
    required this.onToggleFeaturePoints,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.8),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.delete),
            label: const Text('Quitar modelo'),
            onPressed: onReset,
          ),
          const Spacer(),
          Row(
            children: [
              const Icon(Icons.grid_on, color: Colors.white),
              const SizedBox(width: 8),
              const Text('Planos', style: TextStyle(color: Colors.white)),
              const SizedBox(width: 8),
              Switch(
                value: showPlanes,
                onChanged: onTogglePlanes,
                activeColor: Colors.lightGreenAccent,
              ),
              const SizedBox(width: 18),
              const Icon(Icons.blur_on, color: Colors.white),
              const SizedBox(width: 8),
              const Text('Feature Pts', style: TextStyle(color: Colors.white)),
              const SizedBox(width: 8),
              Switch(
                value: showFeaturePoints,
                onChanged: onToggleFeaturePoints,
                activeColor: Colors.lightGreenAccent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
