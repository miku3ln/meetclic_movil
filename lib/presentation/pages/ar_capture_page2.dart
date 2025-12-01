import 'dart:async';

import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_session_manager.dart';
import 'package:flutter/material.dart';
import 'package:meetclic_movil/ar/ar_scene_controller.dart';
import 'package:meetclic_movil/ar/preview/enums/enums-data.dart';
import 'package:meetclic_movil/presentation/pages/ar_capture_page/models/ar_transform_state.dart';
import 'package:meetclic_movil/presentation/pages/ar_capture_page/widgets/ar_control_panel.dart';
import 'package:meetclic_movil/presentation/pages/ar_capture_page/widgets/ar_hud.dart';
import 'package:meetclic_movil/presentation/pages/ar_capture_page/widgets/ar_indicators.dart';

class ARCapturePage extends StatefulWidget {
  final String uri; // p.ej. 'assets/totems/examples/HORNET.glb' o URL
  final bool isLocal; // true: assets, false: URL

  const ARCapturePage({super.key, required this.uri, this.isLocal = true});

  @override
  State<ARCapturePage> createState() => _ARCapturePageState();
}

class _ARCapturePageState extends State<ARCapturePage> {
  final ARSceneController _c = ARSceneController();

  // Overlays
  bool _showPlanes = true;
  bool _showPoints = true;

  // Transform state
  final ARTransformState _t = ARTransformState();

  // Estado UI
  bool _hasPlaced = false;
  bool _panelVisible = false;

  // Pinch
  PinchMode _pinchMode = PinchMode.scale;
  double _pinchStartScale = 1.0;
  double _pinchStartOz = 0.0;

  // Detección de planos / modo manual
  bool _planesAvailable = false;
  bool _manualPlacement = true; // <--- por defecto manual activado

  // Monitores
  Timer? _renderTimer;
  Timer? _probeTimer; // sondea planos con raycast al centro
  bool _renderPulse = false;
  DateTime _lastBuildAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Pulso visual de render
    _renderTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _renderPulse = !_renderPulse);
    });

    // Sondéo periódico para detectar si hay algún plano
    _probeTimer = Timer.periodic(const Duration(milliseconds: 900), (_) async {
      final hit = await _c.raycastScreen(0.5, 0.5);
      final hasPlane = hit != null;
      if (hasPlane != _planesAvailable) {
        setState(() => _planesAvailable = hasPlane);
      }
    });
  }

  @override
  void dispose() {
    _renderTimer?.cancel();
    _probeTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  Future<void> _onReset() async {
    await _c.reset();
    setState(() {
      _t.reset();
      _hasPlaced = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    _lastBuildAt = DateTime.now();

    return Scaffold(
      body: Stack(
        children: [
          // ===== AR camera + tracking =====
          GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onScaleStart: (_) {
              _pinchStartScale = _t.sx;
              _pinchStartOz = _t.oz;
            },
            onScaleUpdate: _handlePinchUpdate,
            // Sólo manejamos tap-to-place cuando NO estamos en modo manual
            onTapUp: _manualPlacement
                ? null
                : (d) async {
                    // Usa la posición del tap (d.localPosition) -> normaliza a 0..1
                    // Si tu plugin solo acepta normalizado, usamos Size del contexto.
                    final box = context.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    final size = box.size;
                    final nx = (d.localPosition.dx / size.width).clamp(
                      0.0,
                      1.0,
                    );
                    final ny = (d.localPosition.dy / size.height).clamp(
                      0.0,
                      1.0,
                    );

                    final hit = await _c.raycastScreen(nx, ny);
                    if (hit != null) {
                      await _c.placeAt(
                        hit,
                        uri: widget.uri,
                        local: widget.isLocal,
                      );
                      await _applyPanelToController();
                      _t.initialScale = _t.sx;
                      _t.initialOz = _t.oz;
                      setState(() => _hasPlaced = true);
                    }
                  },
            child: ARView(
              planeDetectionConfig: PlaneDetectionConfig.horizontal,
              onARViewCreated: _onCreated,
            ),
          ),

          // ===== HUD (arriba) =====
          Positioned(
            left: 12,
            right: 12,
            top: 0,
            child: SafeArea(
              child: _hasPlaced
                  ? ARHud(
                      pinchMode: _pinchMode,
                      currentScale: _t.sx,
                      currentOz: _t.oz,
                      initialScale: _t.initialScale,
                      initialOz: _t.initialOz,
                    )
                  : _hint(),
            ),
          ),

          // ===== Indicadores (columna izquierda) =====
          Positioned(
            top: 72,
            left: 8,
            child: SafeArea(
              child: ARIndicators(
                showPlanes: _showPlanes,
                showPoints: _showPoints,
                pinchMode: _pinchMode,
                scaleX: _t.sx,
                oz: _t.oz,
                initialOz: _t.initialOz,
                renderPulse: _renderPulse,
                sinceLastBuild: DateTime.now().difference(_lastBuildAt),
              ),
            ),
          ),

          // ===== Panel de controles (abajo) =====
          if (_panelVisible)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(
                top: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.60,
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: GestureDetector(
                      behavior: HitTestBehavior
                          .opaque, // asegura capturar taps dentro
                      onTap: () {}, // evita que “transfieran” al ARView debajo
                      child: SingleChildScrollView(
                        primary: false,
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ARControlPanel(
                          showPoints: _showPoints,
                          showPlanes: _showPlanes,
                          onTogglePoints: (v) async {
                            setState(() => _showPoints = v);
                            await _c.reconfigureOverlays(
                              showFeaturePoints: _showPoints,
                              showPlanes: _showPlanes,
                            );
                          },
                          onTogglePlanes: (v) async {
                            setState(() => _showPlanes = v);
                            await _c.reconfigureOverlays(
                              showFeaturePoints: _showPoints,
                              showPlanes: _showPlanes,
                            );
                          },
                          scaleLocked: _t.scaleLocked,
                          onToggleScaleLock: () =>
                              setState(() => _t.scaleLocked = !_t.scaleLocked),
                          sx: _t.sx,
                          sy: _t.sy,
                          sz: _t.sz,
                          onScaleUniform: _onScaleUniform,
                          ox: _t.ox,
                          oy: _t.oy,
                          oz: _t.oz,
                          onOffsetX: _onOffsetX,
                          onOffsetY: _onOffsetY,
                          onOffsetZ: _onOffsetZ,
                          rx: _t.rx,
                          ry: _t.ry,
                          rz: _t.rz,
                          onRotX: _onRotX,
                          onRotY: _onRotY,
                          onRotZ: _onRotZ,
                          pinchModeSelector: _pinchModeSelector(),
                          onReset: _onReset,
                          onClose: () => setState(() => _panelVisible = false),

                          // Colocación manual (tuyos)
                          planesAvailable: _planesAvailable,
                          manualPlacement: _manualPlacement,
                          onManualPlacementChanged: (v) =>
                              setState(() => _manualPlacement = v),
                          onPlaceAtCenter: _placeAtCenter,
                          onPlaceRandom: _placeAtRandom,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // FAB para mostrar panel
          if (!_panelVisible)
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                onPressed: () => setState(() => _panelVisible = true),
                label: const Text('Controls'),
                icon: const Icon(Icons.tune),
              ),
            ),
        ],
      ),
    );
  }

  // ---------- Creación de ARView ----------
  Future<void> _onCreated(
    ARSessionManager s,
    ARObjectManager o,
    ARAnchorManager a,
    ARLocationManager l,
  ) async {
    await _c.init(
      s,
      o,
      anchors: a,
      showPlanes: _showPlanes,
      showFeaturePoints: _showPoints,
    );

    // Si se usa modo tap-to-place (manual = false), también soportamos tap nativo del plugin:
    s.onPlaneOrPointTap = (hits) async {
      if (_manualPlacement) return; // deshabilitado en manual
      if (hits.isEmpty) return;
      await _c.placeAt(hits.first, uri: widget.uri, local: widget.isLocal);
      await _applyPanelToController();
      _t.initialScale = _t.sx;
      _t.initialOz = _t.oz;
      setState(() {
        _hasPlaced = true;
        _planesAvailable = true; // ya hubo hit
      });
    };
  }

  // ---------- Acciones de colocación manual ----------
  Future<void> _placeAtCenter() async {
    if (!_planesAvailable) return;
    final hit = await _c.raycastScreen(0.5, 0.5);
    if (hit == null) return;
    await _c.placeAt(hit, uri: widget.uri, local: widget.isLocal);
    await _applyPanelToController();
    _t.initialScale = _t.sx;
    _t.initialOz = _t.oz;
    setState(() => _hasPlaced = true);
  }

  Future<void> _placeAtRandom() async {
    if (!_planesAvailable) return;

    // Muestra rápida: probamos algunos puntos en pantalla y usamos el primer hit.
    const samples = <Offset>[
      Offset(0.25, 0.25),
      Offset(0.75, 0.25),
      Offset(0.25, 0.75),
      Offset(0.75, 0.75),
      Offset(0.5, 0.5),
      Offset(0.15, 0.6),
      Offset(0.85, 0.4),
      Offset(0.5, 0.3),
      Offset(0.4, 0.8),
    ];

    dynamic firstHit;
    for (final s in samples) {
      final hit = await _c.raycastScreen(s.dx, s.dy);
      if (hit != null) {
        firstHit = hit;
        break;
      }
    }
    if (firstHit == null) return;

    await _c.placeAt(firstHit, uri: widget.uri, local: widget.isLocal);
    await _applyPanelToController();
    _t.initialScale = _t.sx;
    _t.initialOz = _t.oz;
    setState(() => _hasPlaced = true);
  }

  // ---------- Gestos: pinch ----------
  Future<void> _handlePinchUpdate(ScaleUpdateDetails details) async {
    if (!_hasPlaced) return;
    if (details.pointerCount < 2) return;

    if (_pinchMode == PinchMode.scale) {
      final double newScale = (_pinchStartScale * details.scale).clamp(
        0.01,
        5.0,
      );
      setState(() {
        _t.sx = newScale;
        if (_t.scaleLocked) _t.sy = _t.sz = newScale;
      });
      await _c.setUniformScale(_t.sx);
    } else {
      const double sensitivity = 0.6; // m por unidad de pinch
      final double dz = (details.scale - 1.0) * sensitivity;
      final double newOz = (_pinchStartOz + dz).clamp(-3.0, 3.0);
      setState(() => _t.oz = newOz);
      await _c.setOffset(_t.ox, _t.oy, _t.oz);
    }
  }

  // ---------- Selector de modo pinch ----------
  Widget _pinchModeSelector() {
    return Row(
      children: [
        Expanded(
          child: ChoiceChip(
            selected: _pinchMode == PinchMode.scale,
            label: const Text('Scale'),
            onSelected: (_) => setState(() => _pinchMode = PinchMode.scale),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ChoiceChip(
            selected: _pinchMode == PinchMode.distance,
            label: const Text('Distance (Z)'),
            onSelected: (_) => setState(() => _pinchMode = PinchMode.distance),
          ),
        ),
      ],
    );
  }

  // ---------- Aplicar transformaciones ----------
  Future<void> _applyPanelToController() async {
    if (_t.scaleLocked) {
      await _c.setUniformScale(_t.sx);
    } else {
      await _c.setScaleXYZ(_t.sx, _t.sy, _t.sz);
    }
    await _c.setOffset(_t.ox, _t.oy, _t.oz);
    await _c.setRotationEulerDeg(_t.rx, _t.ry, _t.rz);
  }

  // ---------- Sliders ----------
  Future<void> _onScaleUniform(double v) async {
    setState(() {
      _t.sx = v;
      if (_t.scaleLocked) _t.sy = _t.sz = v;
    });
    await _applyPanelToController();
  }

  Future<void> _onOffsetX(double v) async {
    setState(() => _t.ox = v);
    await _c.setOffset(_t.ox, _t.oy, _t.oz);
  }

  Future<void> _onOffsetY(double v) async {
    setState(() => _t.oy = v);
    await _c.setOffset(_t.ox, _t.oy, _t.oz);
  }

  Future<void> _onOffsetZ(double v) async {
    setState(() => _t.oz = v);
    await _c.setOffset(_t.ox, _t.oy, _t.oz);
  }

  Future<void> _onRotX(double v) async {
    setState(() => _t.rx = v);
    await _c.setRotationEulerDeg(_t.rx, _t.ry, _t.rz);
  }

  Future<void> _onRotY(double v) async {
    setState(() => _t.ry = v);
    await _c.setRotationEulerDeg(_t.rx, _t.ry, _t.rz);
  }

  Future<void> _onRotZ(double v) async {
    setState(() => _t.rz = v);
    await _c.setRotationEulerDeg(_t.rx, _t.ry, _t.rz);
  }

  // ---------- Hint ----------
  Widget _hint() => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'Toca un plano para colocar el modelo\n(o usa “Colocar al centro/Aleatorio” en modo Manual).',
        style: TextStyle(color: Colors.white),
        textAlign: TextAlign.center,
      ),
    ),
  );
}
