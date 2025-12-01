import 'dart:math' as math;

import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin/datatypes/node_types.dart';
import 'package:ar_flutter_plugin/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin/models/ar_node.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as v;

import '../../../models/totem_management.dart'; // ItemAR, ItemSources, itemsSources

/* =============================================================================
 * Enums y Constantes
 * ========================================================================== */

enum ARLoadStatus { idle, loading, success, error }

class ARConfig {
  static const double distanceMeters = 1.2;
  static const double uniformScale = 0.80;
  // Euler por defecto (si no hay pose de cámara)
  static const List<double> fallbackEulerDeg = [0, 0, 0];
}

/* =============================================================================
 * Presets de vista / orientación
 * ========================================================================== */

enum ARViewPreset {
  faceCamera, // mirar a la cámara (por defecto)
  front, // frontal
  back, // 180° yaw
  left, // -90° yaw
  right, // 90° yaw
  up, // -90° pitch
  down, //  90° pitch
  isometric, // 3/4 agradable
}

/* =============================================================================
 * Helpers de Orientación
 * ========================================================================== */

class OrientationHelper {
  OrientationHelper._();

  static double _deg2rad(double d) => d * math.pi / 180.0;

  /// Convierte grados a radianes (Vector3)
  static v.Vector3 degListToRadVec(List<double> deg) {
    return v.Vector3(_deg2rad(deg[0]), _deg2rad(deg[1]), _deg2rad(deg[2]));
  }

  /// Calcula eulerAngles para que el modelo mire a la cámara.
  /// Usa zAxis (forward) de la cámara; invierte yaw para “mirar hacia” cámara.
  static v.Vector3 faceCameraEuler(v.Vector3 zAxis) {
    final forward = zAxis.normalized();
    final yaw = math.atan2(forward.x, forward.z) + math.pi;
    const double pitch = 0.0;
    const double roll = 0.0;
    return v.Vector3(pitch, yaw, roll);
  }

  /// Devuelve euler predefinidos por preset.
  static v.Vector3 presetEuler(ARViewPreset preset) {
    switch (preset) {
      case ARViewPreset.front:
        return v.Vector3(0, 0, 0);
      case ARViewPreset.back:
        return v.Vector3(0, _deg2rad(180), 0);
      case ARViewPreset.left:
        return v.Vector3(0, _deg2rad(-90), 0);
      case ARViewPreset.right:
        return v.Vector3(0, _deg2rad(90), 0);
      case ARViewPreset.up:
        return v.Vector3(_deg2rad(-90), 0, 0);
      case ARViewPreset.down:
        return v.Vector3(_deg2rad(90), 0, 0);
      case ARViewPreset.isometric:
        return v.Vector3(_deg2rad(-30), _deg2rad(45), 0);
      case ARViewPreset.faceCamera:
        return v.Vector3.zero(); // se recalcula con pose
    }
  }

  static double deg2rad(double d) => _deg2rad(d);
}

/* =============================================================================
 * NodeFactory: construcción segura de nodos
 * ========================================================================== */

class NodeFactory {
  NodeFactory._();

  static bool isValidGlbUrl(String url) {
    if (url.isEmpty) return false;
    final u = Uri.tryParse(url);
    return u != null &&
        (u.isScheme('http') || u.isScheme('https')) &&
        u.path.toLowerCase().endsWith('.glb');
  }

  static ARNode webGlb({
    required String url,
    required v.Vector3 position,
    required v.Vector3 eulerAngles,
    double uniformScale = ARConfig.uniformScale,
  }) {
    return ARNode(
      type: NodeType.webGLB,
      uri: url,
      position: position,
      eulerAngles: eulerAngles,
      scale: v.Vector3.all(uniformScale),
    );
  }
}

/* =============================================================================
 * ARService: gestiona sesión, objeto actual, colocación y orientación
 * ========================================================================== */

class ARService {
  ARSessionManager? _session;
  ARObjectManager? _objects;

  ARNode? _current;

  ARSessionManager? get session => _session;
  ARObjectManager? get objects => _objects;
  ARNode? get currentNode => _current;

  /// Inicializa sesión y gestor de objetos (sin planos ni guías).
  Future<void> init({
    required ARSessionManager sessionManager,
    required ARObjectManager objectManager,
  }) async {
    _session = sessionManager;
    _objects = objectManager;

    await _session!.onInitialize(
      showFeaturePoints: false,
      showPlanes: false,
      customPlaneTexturePath: null,
      showWorldOrigin: false,
      handleTaps: false,
      // Si tu versión de plugin lo tiene, descomenta:
      // showAnimatedGuide: false,
    );
    await _objects!.onInitialize();
  }

  /// Limpia el nodo y cierra sesión.
  Future<void> dispose() async {
    try {
      if (_current != null) {
        await _objects?.removeNode(_current!);
      }
    } catch (_) {}
    _current = null;
    _session?.dispose();
  }

  /// Elimina el nodo actual si existe.
  Future<void> removeCurrentNodeIfAny() async {
    if (_current != null) {
      try {
        await _objects?.removeNode(_current!);
      } catch (_) {
        // ignore
      } finally {
        _current = null;
      }
    }
  }

  /// Pose frente a la cámara a X metros y euler mirando a cámara.
  Future<({v.Vector3 position, v.Vector3 euler, v.Vector3 zAxis})>
  _computePoseAhead(double distanceMeters) async {
    v.Vector3 camPos = v.Vector3.zero();
    v.Vector3 zAxis = v.Vector3(0, 0, 1); // fallback

    try {
      final camPose = await _session!.getCameraPose();
      if (camPose != null) {
        camPos = camPose.getTranslation();
        zAxis = v.Vector3(
          camPose.entry(0, 2),
          camPose.entry(1, 2),
          camPose.entry(2, 2),
        ).normalized();
      }
    } catch (_) {
      // fallback silencioso
    }

    final targetPos = camPos - zAxis * distanceMeters;
    final euler = OrientationHelper.faceCameraEuler(zAxis);

    return (position: targetPos, euler: euler, zAxis: zAxis);
  }

  /// Coloca un GLB remoto frente a la cámara, sustituyendo el nodo actual.
  /// Opcionalmente aplica un preset inicial distinto a faceCamera.
  Future<bool> placeGlbInFront({
    required String url,
    double distanceMeters = ARConfig.distanceMeters,
    double uniformScale = ARConfig.uniformScale,
    ARViewPreset? initialPreset,
  }) async {
    if (_session == null || _objects == null) {
      throw StateError('AR no inicializado todavía.');
    }
    if (!NodeFactory.isValidGlbUrl(url)) {
      throw ArgumentError('URL inválida o no .glb: $url');
    }

    await removeCurrentNodeIfAny();

    final pose = await _computePoseAhead(distanceMeters);

    // Base mirando a cámara
    var euler = pose.euler;

    // Si piden un preset inicial distinto a faceCamera, úsalo (absoluto)
    if (initialPreset != null && initialPreset != ARViewPreset.faceCamera) {
      euler = OrientationHelper.presetEuler(initialPreset);
    }

    final node = NodeFactory.webGlb(
      url: url,
      position: pose.position,
      eulerAngles: euler,
      uniformScale: uniformScale,
    );

    final added = await _objects!.addNode(node);
    if (added == true) {
      _current = node;
      return true;
    }
    return false;
  }

  /// Re-crear el nodo conservando uri y algunas transformaciones.
  /// Se usa en vez de `updateNode` (que no existe).
  Future<void> _recreateWith({
    v.Vector3? position,
    v.Vector3? euler,
    v.Vector3? scale,
  }) async {
    final node = _current;
    if (node == null) return;
    final uri = node.uri ?? '';
    if (uri.isEmpty) return;

    final newNode = ARNode(
      type: node.type,
      uri: uri,
      position: position ?? node.position ?? v.Vector3.zero(),
      eulerAngles: euler ?? node.eulerAngles ?? v.Vector3.zero(),
      scale: scale ?? node.scale ?? v.Vector3.all(ARConfig.uniformScale),
    );

    try {
      await _objects?.removeNode(node);
    } catch (_) {}

    final ok = await _objects?.addNode(newNode);
    if (ok == true) {
      _current = newNode;
    }
  }

  /// Aplica un preset de orientación (front/back/left/right/up/down/isometric/faceCamera).
  /// `absolute=true` aplica euler absolutos; `false` suma deltas.
  Future<void> applyViewPreset(
    ARViewPreset preset, {
    bool absolute = true,
  }) async {
    if (_current == null) return;

    if (preset == ARViewPreset.faceCamera) {
      final pose = await _computePoseAhead(ARConfig.distanceMeters);
      if (absolute) {
        await _recreateWith(euler: pose.euler);
      } else {
        final cur = _current!.eulerAngles ?? v.Vector3.zero();
        await _recreateWith(
          euler: v.Vector3(
            cur.x + pose.euler.x,
            cur.y + pose.euler.y,
            cur.z + pose.euler.z,
          ),
        );
      }
      return;
    }

    final eulPreset = OrientationHelper.presetEuler(preset);
    if (absolute) {
      await _recreateWith(euler: eulPreset);
    } else {
      final cur = _current!.eulerAngles ?? v.Vector3.zero();
      await _recreateWith(
        euler: v.Vector3(
          cur.x + eulPreset.x,
          cur.y + eulPreset.y,
          cur.z + eulPreset.z,
        ),
      );
    }
  }

  /// “Empuje fino” en grados (positivo/negativo) para yaw/pitch/roll.
  Future<void> nudgeOrientation({
    double yawDeg = 0,
    double pitchDeg = 0,
    double rollDeg = 0,
  }) async {
    if (_current == null) return;
    final cur = _current!.eulerAngles ?? v.Vector3.zero();
    final dx = OrientationHelper.deg2rad(pitchDeg);
    final dy = OrientationHelper.deg2rad(yawDeg);
    final dz = OrientationHelper.deg2rad(rollDeg);
    await _recreateWith(euler: v.Vector3(cur.x + dx, cur.y + dy, cur.z + dz));
  }

  /// Re-centra el modelo al frente (recalcula posición/rotación frente a cámara).
  Future<void> recenterInFront() async {
    if (_current == null) return;
    final pose = await _computePoseAhead(ARConfig.distanceMeters);
    await _recreateWith(position: pose.position, euler: pose.euler);
  }
}

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

/* =============================================================================
 * Página principal
 * ========================================================================== */

class ARNoHitDropdownPage extends StatefulWidget {
  const ARNoHitDropdownPage({super.key});

  @override
  State<ARNoHitDropdownPage> createState() => _ARNoHitDropdownPageState();
}

class _ARNoHitDropdownPageState extends State<ARNoHitDropdownPage> {
  // Servicio AR (sesión, objetos, colocación)
  final ARService _ar = ARService();

  // Dropdown
  late ItemAR _selected;

  // Estado
  ARLoadStatus _status = ARLoadStatus.idle;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _selected = itemsSources.first;
  }

  @override
  void dispose() {
    _ar.dispose();
    super.dispose();
  }

  void _setStatus(ARLoadStatus s, {String? err}) {
    setState(() {
      _status = s;
      _lastError = err;
    });
  }

  /* =========================
   * Proceso: Inicialización
   * ======================= */
  Future<void> _onARViewCreated(
    ARSessionManager sessionManager,
    ARObjectManager objectManager,
    ARAnchorManager anchorManager,
    ARLocationManager locationManager,
  ) async {
    try {
      await _ar.init(
        sessionManager: sessionManager,
        objectManager: objectManager,
      );
      UiHelpers.showSnack(context, 'AR inicializado');
    } catch (e, st) {
      _setStatus(ARLoadStatus.error, err: 'Fallo inicializando AR: $e');
      debugPrint('[AR] Init error: $e\n$st');
      return;
    }

    await _placeSelectedInFront();
  }

  /* =========================
   * Proceso: Colocación
   * ======================= */
  Future<void> _placeSelectedInFront() async {
    _setStatus(ARLoadStatus.loading);
    UiHelpers.showSnack(context, 'Cargando modelo: ${_selected.id}');

    try {
      final ok = await _ar.placeGlbInFront(
        url: _selected.sources.glb,
        distanceMeters: ARConfig.distanceMeters,
        uniformScale: ARConfig.uniformScale,
        initialPreset: ARViewPreset.front, // puedes cambiarlo
      );
      if (ok) {
        _setStatus(ARLoadStatus.success);
        UiHelpers.showSnack(context, 'Modelo cargado ✔');
      } else {
        _setStatus(
          ARLoadStatus.error,
          err: 'No se pudo añadir el nodo (addNode=false)',
        );
        UiHelpers.showSnack(
          context,
          'No se pudo añadir el nodo (addNode=false)',
          error: true,
        );
      }
    } catch (e, st) {
      _setStatus(ARLoadStatus.error, err: '$e');
      UiHelpers.showSnack(
        context,
        'Error colocando el modelo:\n$e',
        error: true,
      );
      debugPrint('[AR] place error: $e\n$st');
    }
  }

  /* =========================
   * Build
   * ======================= */
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AR – Sin hits (dropdown)'),
        actions: [
          IconButton(
            tooltip: 'Recolocar al frente',
            onPressed: _ar.recenterInFront,
            icon: const Icon(Icons.center_focus_strong),
          ),
          PopupMenuButton<String>(
            tooltip: 'Vistas',
            onSelected: (k) async {
              switch (k) {
                case 'front':
                  await _ar.applyViewPreset(ARViewPreset.front);
                  break;
                case 'back':
                  await _ar.applyViewPreset(ARViewPreset.back);
                  break;
                case 'left':
                  await _ar.applyViewPreset(ARViewPreset.left);
                  break;
                case 'right':
                  await _ar.applyViewPreset(ARViewPreset.right);
                  break;
                case 'up':
                  await _ar.applyViewPreset(ARViewPreset.up);
                  break;
                case 'down':
                  await _ar.applyViewPreset(ARViewPreset.down);
                  break;
                case 'iso':
                  await _ar.applyViewPreset(ARViewPreset.isometric);
                  break;
                case 'face':
                  await _ar.applyViewPreset(ARViewPreset.faceCamera);
                  break;
              }
              setState(() {});
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'face', child: Text('Mirar a cámara')),
              PopupMenuItem(value: 'front', child: Text('Frontal')),
              PopupMenuItem(value: 'back', child: Text('Trasera')),
              PopupMenuItem(value: 'left', child: Text('Izquierda')),
              PopupMenuItem(value: 'right', child: Text('Derecha')),
              PopupMenuItem(value: 'up', child: Text('Arriba')),
              PopupMenuItem(value: 'down', child: Text('Abajo')),
              PopupMenuItem(value: 'iso', child: Text('Isométrica')),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          // Vista AR
          ARView(
            onARViewCreated: _onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.none,
          ),

          // Dropdown flotante arriba
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<ItemAR>(
                    isExpanded: true,
                    value: _selected,
                    items: itemsSources.map((item) {
                      return DropdownMenuItem<ItemAR>(
                        value: item,
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                item.sources.img,
                                width: 42,
                                height: 42,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox(
                                  width: 42,
                                  height: 42,
                                  child: Icon(Icons.image),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) async {
                      if (val == null) return;
                      setState(() => _selected = val);
                      await _placeSelectedInFront(); // recoloca el nuevo
                    },
                  ),
                ),
              ),
            ),
          ),

          // Chip de estado (debajo del dropdown)
          Positioned(
            right: 12,
            top: 12 + 56,
            child: Chip(
              label: Text(
                UiHelpers.statusText(_status),
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: UiHelpers.statusColor(_status),
            ),
          ),

          // Overlay de carga
          if (_status == ARLoadStatus.loading)
            Container(
              color: Colors.black54,
              child: const Center(child: _LoadingOverlay()),
            ),

          // Card informativa flotante abajo
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: InfoCardAR(item: _selected, lastError: _lastError),
          ),
        ],
      ),
    );
  }
}

/* =============================================================================
 * Widgets de UI
 * ========================================================================== */

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        CircularProgressIndicator(),
        SizedBox(height: 12),
        Text(
          'Cargando…',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class InfoCardAR extends StatelessWidget {
  final ItemAR item;
  final String? lastError;
  const InfoCardAR({super.key, required this.item, this.lastError});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    item.sources.img,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      width: 72,
                      height: 72,
                      child: Icon(Icons.image_not_supported),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.blueGrey,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (lastError != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      lastError!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.red[700]),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.place, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '${item.position.lat.toStringAsFixed(5)}, ${item.position.lng.toStringAsFixed(5)}',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
