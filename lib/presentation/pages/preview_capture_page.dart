// lib/preview/capture/preview_capture_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meetclic_movil/ar/preview/controllers/preview_scene_controller.dart';
import 'package:meetclic_movil/ar/preview/enums/enums-data.dart';
import 'package:meetclic_movil/ar/preview/widgets/glb_preview_view.dart';
import 'package:meetclic_movil/presentation/pages/ar_capture_page/models/ar_transform_state.dart';
import 'package:meetclic_movil/presentation/pages/ar_capture_page/widgets/ar_control_panel.dart';
import 'package:meetclic_movil/presentation/pages/ar_capture_page/widgets/ar_hud.dart';
import 'package:meetclic_movil/presentation/pages/ar_capture_page/widgets/ar_indicators.dart';

class PreviewCapturePage extends StatefulWidget {
  final String uri;
  final bool isLocal;
  const PreviewCapturePage({super.key, required this.uri, this.isLocal = true});

  @override
  State<PreviewCapturePage> createState() => _PreviewCapturePageState();
}

class _PreviewCapturePageState extends State<PreviewCapturePage> {
  final _c = PreviewSceneController();
  final _t = ARTransformState();

  bool _panelVisible = false;
  bool _hasPlaced = true; // en preview, cargamos de una
  bool _showPlanes = true, _showPoints = true;

  PinchMode _pinchMode = PinchMode.scale;
  double _pinchStartScale = 1, _pinchStartOz = 0;

  Timer? _pulse;
  bool _renderPulse = false;
  DateTime _lastBuildAt = DateTime.now();

  @override
  void initState() {
    super.initState();

    // pulso para el indicador
    _pulse = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _renderPulse = !_renderPulse);
    });

    // 👇 Cargar el modelo una vez montada la vista
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // El GlbPreviewView usa el uri directamente; no necesitamos placeAt(null,...)
      setState(() {
        _hasPlaced = true;
        _t.initialScale = _t.sx;
        _t.initialOz = _t.oz;
      });

      // No-op seguro (por si tu controller hace algo inicial)
      await _c.init(
        showPlanes: _showPlanes,
        showFeaturePoints: _showPoints,
        context: context,
      );

      // ❌ NO llamar a placeAt con null (rompe la tipificación).
      // await _c.placeAt(null, uri: widget.uri, local: widget.isLocal);
    });
  }

  @override
  void dispose() {
    _pulse?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _lastBuildAt = DateTime.now();

    return Scaffold(
      body: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (_) {
              _pinchStartScale = _t.sx;
              _pinchStartOz = _t.oz;
            },
            onScaleUpdate: _handlePinch,
            child: GlbPreviewView(
              uri: widget.uri,
              isLocal: widget.isLocal,
              controller: _c,
            ),
          ),

          // HUD
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

          // Indicadores izquierda
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

          // Panel
          if (_panelVisible)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: ARControlPanel(
                manualPlacement: false,
                showPoints: _showPoints,
                showPlanes: _showPlanes,
                onTogglePoints: (v) async {
                  setState(() => _showPoints = v);
                },
                onTogglePlanes: (v) async {
                  setState(() => _showPlanes = v);
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
                pinchModeSelector: _pinchSelector(),
                onReset: _onReset,
                onClose: () => setState(() => _panelVisible = false),
              ),
            ),

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

  // Gestos
  Future<void> _handlePinch(ScaleUpdateDetails d) async {
    if (!_hasPlaced || d.pointerCount < 2) return;
    if (_pinchMode == PinchMode.scale) {
      final s = (_pinchStartScale * d.scale).clamp(0.01, 5.0);
      setState(() {
        _t.sx = s;
        if (_t.scaleLocked) _t.sy = _t.sz = s;
      });
      await _c.setUniformScale(_t.sx);
    } else {
      const sensitivity = 0.6;
      final newOz = (_pinchStartOz + (d.scale - 1.0) * sensitivity).clamp(
        -3.0,
        3.0,
      );
      setState(() => _t.oz = newOz);
      await _c.setOffset(_t.ox, _t.oy, _t.oz);
    }
  }

  // Sliders
  Future<void> _onScaleUniform(double v) async {
    setState(() {
      _t.sx = v;
      if (_t.scaleLocked) _t.sy = _t.sz = v;
    });
    await _c.setUniformScale(_t.sx);
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

  Future<void> _onReset() async {
    await _c.reset();
    setState(() => _t.reset());
  }

  Widget _pinchSelector() => Row(
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

  Widget _hint() => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'Cargando modelo…',
        style: TextStyle(color: Colors.white),
      ),
    ),
  );
}
