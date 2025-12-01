import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin/datatypes/node_types.dart';
import 'package:ar_flutter_plugin/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin/models/ar_node.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_math/vector_math_64.dart' as v;

import '../../../models/totem_management.dart'; // ItemAR, ItemSources, itemsSources
// opcional:
// import 'package:permission_handler/permission_handler.dart';

/* =============================================================================
 * Enums y Constantes
 * ========================================================================== */

enum ARLoadStatus { idle, loading, success, error }

class ARConfig2 {
  static const double distanceMeters = 1.2;
  static const double uniformScale = 0.80;

  // Euler por defecto (si no hay pose de cámara)
  static const List<double> fallbackEulerDeg = [0, 0, 0];
}

/* =============================================================================
 * Presets de vista / orientación
 * ========================================================================== */

enum ARViewPreset2 {
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
  static v.Vector3 presetEuler(ARViewPreset2 preset) {
    switch (preset) {
      case ARViewPreset2.front:
        return v.Vector3(0, 0, 0);
      case ARViewPreset2.back:
        return v.Vector3(0, _deg2rad(180), 0);
      case ARViewPreset2.left:
        return v.Vector3(0, _deg2rad(-90), 0);
      case ARViewPreset2.right:
        return v.Vector3(0, _deg2rad(90), 0);
      case ARViewPreset2.up:
        return v.Vector3(_deg2rad(-90), 0, 0);
      case ARViewPreset2.down:
        return v.Vector3(_deg2rad(90), 0, 0);
      case ARViewPreset2.isometric:
        return v.Vector3(_deg2rad(-30), _deg2rad(45), 0);
      case ARViewPreset2.faceCamera:
        return v.Vector3.zero(); // se recalcula con pose
    }
  }

  static double deg2rad(double d) => _deg2rad(d);
}

/* =============================================================================
 * NodeFactory: construcción segura de nodos
 * ========================================================================== */

class NodeFactory2 {
  NodeFactory2._();

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
    double uniformScale = ARConfig2.uniformScale,
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
 * ARService2: gestiona sesión, objeto actual, colocación y orientación
 * ========================================================================== */

class ARService2 {
  ARSessionManager? _session;
  ARObjectManager? _objects;

  ARNode? _current;

  ARSessionManager? get session => _session;

  ARObjectManager? get objects => _objects;

  ARNode? get currentNode => _current;

  // --- HELPER: compone y empuja la matriz actual al transformNotifier ---
  /// Suma un delta de yaw (en grados) y aplica en caliente sin recrear.
  Future<void> nudgeYawDegrees(double deltaDeg) async {
    if (_current == null) return;

    final eul = _current!.eulerAngles ?? v.Vector3.zero();
    final dy = OrientationHelper.deg2rad(deltaDeg);

    _current!.eulerAngles = v.Vector3(eul.x, eul.y + dy, eul.z);

    // Empuja la matriz actual al nativo (sin recrear)
    _pushCurrentTransform();
  }

  void _pushCurrentTransform() {
    final node = _current;
    if (node == null) return;

    final pos = node.position ?? v.Vector3.zero();
    final eul = node.eulerAngles ?? v.Vector3.zero();
    final sc = node.scale ?? v.Vector3.all(ARConfig2.uniformScale);

    // Quaternion desde euler (pitch=x, yaw=y, roll=z)
    final q = v.Quaternion.euler(eul.x, eul.y, eul.z);

    // Matrix4.compose(translation, rotation, scale)
    final m = v.Matrix4.compose(pos, q, sc);

    // 🔥 Esto dispara el listener que el plugin registró en addNode(...)
    node.transformNotifier.value = m;
  }

  /// Cambia la escala en caliente con un PORCENTAJE sobre la escala base.
  /// 100 = tamaño base (ARConfig2.uniformScale), 150 = 1.5x, 75 = 0.75x, etc.
  Future<void> setUniformScalePercent(
    double percent, {
    double minPercent = 50, // 50% del base
    double maxPercent = 200, // 200% del base
  }) async {
    if (_current == null) return;

    final p = percent.clamp(minPercent, maxPercent).toDouble();
    final base = ARConfig2.uniformScale; // escala base de tu app
    final target = base * (p / 100.0); // escala absoluta final

    _current!.scale = v.Vector3.all(target); // set en caliente
    _pushCurrentTransform(); // notifica al nativo
  }

  /// (Opcional) Cambiar por factor absoluto (1.0 = tal cual, 0.8 = -20%, 1.2 = +20%)
  Future<void> setUniformScaleFactor(
    double factor, {
    double min = 0.15,
    double max = 3.0,
  }) async {
    if (_current == null) return;
    final f = factor.clamp(min, max).toDouble();
    _current!.scale = v.Vector3.all(f);
    _pushCurrentTransform();
  }

  double getCurrentUniformScale() {
    final sc = _current?.scale ?? v.Vector3.all(ARConfig2.uniformScale);
    return (sc.x + sc.y + sc.z) / 3.0;
  }

  Future<void> setUniformScale(
    double target, {
    double minS = 0.15,
    double maxS = 3.0,
  }) async {
    if (_current == null) return;
    final clamped = target.clamp(minS, maxS).toDouble();
    await _recreateWith(scale: v.Vector3.all(clamped));
  }

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
      // sin taps de planos
      handlePans: false,
      // 🔥 gestos nativos
      handleRotation: false,
      // 🔥 gestos nativos
      showAnimatedGuide: false,
    );
    await _objects!.onInitialize();

    // 🔥 callbacks de gestos (aplican la matriz final al nodo)
    _setupNativeGestures();
  }

  void _setupNativeGestures() {
    if (_objects == null) return;

    _objects!.onPanEnd = (String nodeName, v.Matrix4 transform) async {
      //await _arRecreateNodeFromTransform(transform);
    };

    _objects!.onRotationEnd = (String nodeName, v.Matrix4 transform) async {
      await _arRecreateNodeFromTransform(transform);
    };
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
    double distanceMeters = ARConfig2.distanceMeters,
    double uniformScale = ARConfig2.uniformScale,
    ARViewPreset2? initialPreset,
  }) async {
    if (_session == null || _objects == null) {
      throw StateError('AR no inicializado todavía.');
    }
    if (!NodeFactory2.isValidGlbUrl(url)) {
      throw ArgumentError('URL inválida o no .glb: $url');
    }

    await removeCurrentNodeIfAny();

    final pose = await _computePoseAhead(distanceMeters);

    // Base mirando a cámara
    var euler = pose.euler;

    // Si piden un preset inicial distinto a faceCamera, úsalo (absoluto)
    if (initialPreset != null && initialPreset != ARViewPreset2.faceCamera) {
      euler = OrientationHelper.presetEuler(initialPreset);
    }

    final node = NodeFactory2.webGlb(
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
      scale: scale ?? node.scale ?? v.Vector3.all(ARConfig2.uniformScale),
    );

    try {
      await _objects?.removeNode(node);
    } catch (_) {}

    final ok = await _objects?.addNode(newNode);
    if (ok == true) {
      _current = newNode;
    }
  }

  /// Recrea el nodo actual desde la transformación nativa post-gesto
  Future<void> _arRecreateNodeFromTransform(v.Matrix4 transform) async {
    if (_current == null) return;

    // Extraer componentes
    final pos = transform.getTranslation(); // v.Vector3
    final euler = _matrixToEulerXYZ(transform); // v.Vector3 (pitch,yaw,roll)
    final scale = _extractScale(transform); // v.Vector3

    // Reaplicar al nodo actual
    await _recreateWith(
      position: v.Vector3(pos.x, pos.y, pos.z),
      euler: euler,
      scale: scale,
    );
  }

  /// Convierte Matrix4 -> Euler XYZ (pitch=X, yaw=Y, roll=Z) en radianes
  v.Vector3 _matrixToEulerXYZ(v.Matrix4 m) {
    final r00 = m.entry(0, 0), r01 = m.entry(0, 1), r02 = m.entry(0, 2);
    final r10 = m.entry(1, 0), r11 = m.entry(1, 1), r12 = m.entry(1, 2);
    final r20 = m.entry(2, 0), r21 = m.entry(2, 1), r22 = m.entry(2, 2);

    final pitch = math.asin((-r20).clamp(-1.0, 1.0)); // X
    double yaw, roll; // Y, Z
    if ((r20).abs() < 0.999999) {
      roll = math.atan2(r21, r22);
      yaw = math.atan2(r10, r00);
    } else {
      // Gimbal lock
      roll = 0.0;
      yaw = math.atan2(-r01, r11);
    }
    return v.Vector3(pitch, yaw, roll);
  }

  /// Extrae la escala desde Matrix4
  v.Vector3 _extractScale(v.Matrix4 m) {
    final x = v.Vector3(m.entry(0, 0), m.entry(1, 0), m.entry(2, 0));
    final y = v.Vector3(m.entry(0, 1), m.entry(1, 1), m.entry(2, 1));
    final z = v.Vector3(m.entry(0, 2), m.entry(1, 2), m.entry(2, 2));
    return v.Vector3(x.length, y.length, z.length);
  }

  /// Aplica un preset de orientación (front/back/left/right/up/down/isometric/faceCamera).
  /// `absolute=true` aplica euler absolutos; `false` suma deltas.
  Future<void> applyViewPreset(
    ARViewPreset2 preset, {
    bool absolute = true,
  }) async {
    if (_current == null) return;

    if (preset == ARViewPreset2.faceCamera) {
      final pose = await _computePoseAhead(ARConfig2.distanceMeters);
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
    final pose = await _computePoseAhead(ARConfig2.distanceMeters);
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
  // === Rotación por swipe (yaw) con throttle ===
  static const Duration _kYawThrottle = Duration(milliseconds: 80);
  double _pendingYawDeg = 0.0; // acumulador de grados
  bool _yawTickScheduled = false;

  // sensibilidad: grados por píxel horizontal
  static const double _yawDegPerPixel = 0.25;

  void _applyYawThrottled(double deltaYawDeg) {
    _pendingYawDeg += deltaYawDeg;
    if (_yawTickScheduled) return;

    _yawTickScheduled = true;
    Future.delayed(_kYawThrottle, () async {
      final val = _pendingYawDeg;
      _pendingYawDeg = 0.0;
      _yawTickScheduled = false;

      if (val.abs() > 0.0001 && _ar.currentNode != null) {
        await _ar.nudgeYawDegrees(val); // aplica en caliente
      }
    });
  }

  Future<void> _flushYaw() async {
    final val = _pendingYawDeg;
    _pendingYawDeg = 0.0;
    _yawTickScheduled = false;

    if (val.abs() > 0.0001 && _ar.currentNode != null) {
      await _ar.nudgeYawDegrees(val);
    }
  }

  bool _isCapturing = false; // bloquea botón + muestra loading
  bool _hideUiDuringCapture = false; // oculta chip “Listo” e InfoCardAR2
  // Pinch-to-zoom
  double _pinchStartScale =
      ARConfig2.uniformScale; // escala de partida del nodo
  bool _isPinching = false;
  // === Pinch-to-zoom (con throttle) ===
  static const Duration _kPinchThrottle = Duration(milliseconds: 80);

  bool _pinchTickScheduled = false;
  double? _pendingPercent;

  void _applyScalePercentThrottled(double percent) {
    _pendingPercent = percent;
    if (_pinchTickScheduled) return;

    _pinchTickScheduled = true;
    Future.delayed(_kPinchThrottle, () async {
      final val = _pendingPercent;
      _pendingPercent = null;
      _pinchTickScheduled = false;

      if (val != null && _ar.currentNode != null) {
        await _ar.setUniformScalePercent(val); // usa el método EN CALIENTE
      }
    });
  }

  Future<void> _flushPinchPercent() async {
    final val = _pendingPercent;
    _pendingPercent = null;
    _pinchTickScheduled = false;

    if (val != null && _ar.currentNode != null) {
      await _ar.setUniformScalePercent(val);
    }
  }

  Future<void> _handleCapture() async {
    if (_isCapturing) return;
    if (_ar.currentNode == null) return;

    setState(() {
      _isCapturing = true;
      _hideUiDuringCapture = true; // Oculta UI antes de capturar
    });

    try {
      // Esperar a que el frame se pinte
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;

      final ctx = _captureKey.currentContext;
      if (ctx == null) throw Exception('Context nulo al capturar.');

      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Boundary no encontrado.');

      // Verificar que el boundary haya pintado
      // ignore: invalid_use_of_protected_member
      if (boundary.debugNeedsPaint) {
        await WidgetsBinding.instance.endOfFrame;
      }

      final pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('No se pudo generar PNG.');

      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final fileName =
          'ar_capture_${DateTime.now().millisecondsSinceEpoch}.png';
      await File('${dir.path}/$fileName').writeAsBytes(bytes);

      final res = await ImageGallerySaverPlus.saveImage(
        bytes,
        name: fileName,
        quality: 100,
        isReturnImagePathOfIOS: true,
      );

      final ok = (res != null) && (res['isSuccess'] == true);
      if (!ok) throw Exception('Fallo al guardar en galería.');

      UiHelpers.showSnack(context, 'Captura guardada en Galería ✅');
    } catch (e, st) {
      debugPrint('[AR] capture/save error: $e\n$st');
      UiHelpers.showSnack(
        context,
        'Error al capturar/guardar:\n$e',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _hideUiDuringCapture = false;
        });
      }
    }
  }

  // Servicio AR (sesión, objetos, colocación)
  final ARService2 _ar = ARService2();

  // Dropdown
  late ItemAR _selected;

  // Estado
  ARLoadStatus _status = ARLoadStatus.idle;
  String? _lastError;

  // Retícula visible hasta que el usuario coloque el modelo
  bool _showReticle = true;

  // 🔹 Key para capturar la vista completa (cámara + modelo + overlays)
  final GlobalKey _captureKey = GlobalKey();

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

    // ⚠️ Ya no colocamos automáticamente: mostramos retícula y esperamos tap
    setState(() {
      _showReticle = true;
    });
  }

  /* =========================
   * Proceso: Colocación
   * ======================= */

  // Tap en la retícula -> coloca el totem seleccionado
  Future<void> _onReticleTap() async {
    if (_status == ARLoadStatus.loading) return;

    _setStatus(ARLoadStatus.loading);
    UiHelpers.showSnack(context, 'Colocando: ${_selected.id}');

    try {
      final ok = await _ar.placeGlbInFront(
        url: _selected.sources.glb,
        distanceMeters: ARConfig2.distanceMeters,
        uniformScale: ARConfig2.uniformScale,
        initialPreset: ARViewPreset2.front,
      );
      if (ok) {
        _setStatus(ARLoadStatus.success);
        UiHelpers.showSnack(context, 'Modelo colocado ✔');
        setState(() {
          _showReticle = false; // ocultamos retícula tras colocar
        });
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
      UiHelpers.showSnack(context, 'Error colocando:\n$e', error: true);
      debugPrint('[AR] place error: $e\n$st');
    }
  }

  // Cambio de totem desde el dropdown
  Future<void> _onSelectChanged(ItemAR val) async {
    setState(() => _selected = val);

    // ✅ limpiar cualquier nodo previo y resetear estado/retícula
    _setStatus(ARLoadStatus.idle, err: null);
    await _ar.removeCurrentNodeIfAny();

    setState(() {
      _showReticle =
          true; // mostrar retícula para que el usuario vuelva a colocar
    });

    UiHelpers.showSnack(
      context,
      'Seleccionado: ${_selected.id}. Toca la retícula para colocar.',
    );
  }

  /* =========================
   * Proceso: Captura
   * ======================= */

  // Opcional:
  // import 'package:permission_handler/permission_handler.dart';
  Future<void> _captureAndSavePng() async {
    try {
      if (_ar.currentNode == null) return; // solo con modelo

      final ctx = _captureKey.currentContext;
      if (ctx == null) {
        UiHelpers.showSnack(
          context,
          'No se pudo capturar (context nulo).',
          error: true,
        );
        return;
      }
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        UiHelpers.showSnack(
          context,
          'No se pudo capturar (boundary nulo).',
          error: true,
        );
        return;
      }

      // Render a PNG con la densidad real del dispositivo
      final pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        UiHelpers.showSnack(
          context,
          'No se pudo convertir a PNG.',
          error: true,
        );
        return;
      }
      final bytes = byteData.buffer.asUint8List();

      // (opcional) guarda también un archivo temporal
      final dir = await getTemporaryDirectory();
      final fileName =
          'ar_capture_${DateTime.now().millisecondsSinceEpoch}.png';
      final tempPath = '${dir.path}/$fileName';
      await File(tempPath).writeAsBytes(bytes);

      // Guardar en galería (Android/iOS)
      final res = await ImageGallerySaverPlus.saveImage(
        bytes,
        name: fileName,
        quality: 100,
        isReturnImagePathOfIOS: true,
      );

      final ok = (res != null) && (res['isSuccess'] == true);
      if (ok) {
        UiHelpers.showSnack(context, 'Captura guardada en Galería ✅');
      } else {
        UiHelpers.showSnack(
          context,
          'No se pudo guardar en la galería.',
          error: true,
        );
      }
    } catch (e, st) {
      debugPrint('[AR] capture/save error: $e\n$st');
      UiHelpers.showSnack(
        context,
        'Error al capturar/guardar:\n$e',
        error: true,
      );
    }
  }

  Future<void> _captureAndSavePng2() async {
    try {
      // Solo si hay un nodo (modelo) activo
      if (_ar.currentNode == null) return;

      final ctx = _captureKey.currentContext;
      if (ctx == null) {
        UiHelpers.showSnack(
          context,
          'No se pudo capturar (context nulo).',
          error: true,
        );
        return;
      }

      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        UiHelpers.showSnack(
          context,
          'No se pudo capturar (boundary nulo).',
          error: true,
        );
        return;
      }

      final pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        UiHelpers.showSnack(
          context,
          'No se pudo convertir imagen a PNG.',
          error: true,
        );
        return;
      }

      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/ar_capture_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(path);
      await file.writeAsBytes(bytes);

      UiHelpers.showSnack(context, 'Captura guardada:\n$path');
    } catch (e, st) {
      debugPrint('[AR] capture error: $e\n$st');
      UiHelpers.showSnack(context, 'Error al capturar:\n$e', error: true);
    }
  }

  /* =========================
   * Build
   * ======================= */
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bool hasModel = _ar.currentNode != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AR – Sin hits (dropdown)'),
        actions: [
          IconButton(
            tooltip: 'Recolocar al frente',
            onPressed: () async {
              await _ar.recenterInFront();
              setState(() {}); // refresco visual mínimo
            },
            icon: const Icon(Icons.center_focus_strong),
          ),
          PopupMenuButton<String>(
            tooltip: 'Vistas',
            onSelected: (k) async {
              switch (k) {
                case 'front':
                  await _ar.applyViewPreset(ARViewPreset2.front);
                  break;
                case 'back':
                  await _ar.applyViewPreset(ARViewPreset2.back);
                  break;
                case 'left':
                  await _ar.applyViewPreset(ARViewPreset2.left);
                  break;
                case 'right':
                  await _ar.applyViewPreset(ARViewPreset2.right);
                  break;
                case 'up':
                  await _ar.applyViewPreset(ARViewPreset2.up);
                  break;
                case 'down':
                  await _ar.applyViewPreset(ARViewPreset2.down);
                  break;
                case 'iso':
                  await _ar.applyViewPreset(ARViewPreset2.isometric);
                  break;
                case 'face':
                  await _ar.applyViewPreset(ARViewPreset2.faceCamera);
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
      body: RepaintBoundary(
        // 🔸 envolvemos todo para poder capturar
        key: _captureKey,
        child: Stack(
          children: [
            // Vista AR
            // Vista AR con pinch-to-zoom controlado (throttle)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (_) {
                if (_ar.currentNode == null) return;
                _isPinching = true;
                _pinchStartScale = _ar
                    .getCurrentUniformScale(); // escala actual
                _pendingPercent = null;
                _pinchTickScheduled = false;
              },
              onScaleUpdate: (details) {
                if (!_isPinching || _ar.currentNode == null) return;

                // escala objetivo absoluta (uniforme)
                final targetUniform =
                    _pinchStartScale * details.scale; // 1.0 = sin cambio

                // convertir a PORCENTAJE respecto al base (ARConfig2.uniformScale)
                final base = ARConfig2.uniformScale;
                final percent = (targetUniform / base) * 100.0;

                // throttle para no saturar el canal
                _applyScalePercentThrottled(percent);
              },
              onScaleEnd: (_) async {
                if (!_isPinching) return;
                _isPinching = false;
                await _flushPinchPercent(); // aplica el último valor pendiente
              },
              child: ARView(
                onARViewCreated: _onARViewCreated,
                planeDetectionConfig: PlaneDetectionConfig.none,
              ),
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
                        await _onSelectChanged(
                          val,
                        ); // ✅ limpiar y mostrar retícula
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

            // Retícula centrada (tocar para colocar el totem seleccionado)
            if (_showReticle) const _CenterReticle(),

            // Card informativa flotante abajo (ahora con botón "Capturar" centrado)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: InfoCardAR2(
                item: _selected,
                lastError: _lastError,
                onCapturePressed: hasModel
                    ? _captureAndSavePng
                    : null, // 🔸 habilita solo con modelo
              ),
            ),

            // Botón invisible que capta el tap EXACTAMENTE sobre la retícula
            if (_showReticle)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: false,
                  child: Center(
                    child: SizedBox(
                      width: 120,
                      height: 120,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _onReticleTap, // 👈 colocar seleccionado
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
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

/// Retícula simple centrada (visual)
class _CenterReticle extends StatelessWidget {
  const _CenterReticle();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true, // la interacción se maneja por el InkWell superpuesto
      child: Center(
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white70, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 8, spreadRadius: 1),
            ],
          ),
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.white70,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class InfoCardAR2 extends StatelessWidget {
  final ItemAR item;
  final String? lastError;
  final VoidCallback? onCapturePressed;
  final bool isCapturing;

  const InfoCardAR2({
    super.key,
    required this.item,
    this.lastError,
    this.onCapturePressed,
    this.isCapturing = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool captureEnabled = onCapturePressed != null && !isCapturing;

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
            const SizedBox(height: 12),
            Row(
              children: [
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: captureEnabled ? onCapturePressed : null,
                  icon: isCapturing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_alt_rounded),
                  label: Text(isCapturing ? 'Guardando…' : 'Capturar'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
