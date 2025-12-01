// lib/presentation/pages/ar_capture_page/widgets/ar_control_panel.dart
import 'package:flutter/material.dart';

class ARControlPanel extends StatelessWidget {
  // Overlays
  final bool showPoints;
  final bool showPlanes;
  final ValueChanged<bool> onTogglePoints;
  final ValueChanged<bool> onTogglePlanes;

  // Escala
  final bool scaleLocked;
  final VoidCallback onToggleScaleLock;
  final double sx, sy, sz;
  final ValueChanged<double> onScaleUniform;

  // Offset
  final double ox, oy, oz;
  final ValueChanged<double> onOffsetX;
  final ValueChanged<double> onOffsetY;
  final ValueChanged<double> onOffsetZ;

  // Rotación
  final double rx, ry, rz;
  final ValueChanged<double> onRotX;
  final ValueChanged<double> onRotY;
  final ValueChanged<double> onRotZ;

  // Pinch selector
  final Widget pinchModeSelector;

  // Reset / Close
  final Future<void> Function() onReset;
  final VoidCallback onClose;

  // ---- Colocación manual/auto ----
  final bool? planesAvailable; // habilita el toggle si ya hay al menos 1 plano
  final bool? manualPlacement; // estado del toggle
  final ValueChanged<bool>? onManualPlacementChanged;
  final Future<void> Function()? onPlaceAtCenter; // Colocar al centro
  final Future<void> Function()? onPlaceRandom; // Colocar en plano aleatorio

  const ARControlPanel({
    super.key,
    required this.showPoints,
    required this.showPlanes,
    required this.onTogglePoints,
    required this.onTogglePlanes,
    required this.scaleLocked,
    required this.onToggleScaleLock,
    required this.sx,
    required this.sy,
    required this.sz,
    required this.onScaleUniform,
    required this.ox,
    required this.oy,
    required this.oz,
    required this.onOffsetX,
    required this.onOffsetY,
    required this.onOffsetZ,
    required this.rx,
    required this.ry,
    required this.rz,
    required this.onRotX,
    required this.onRotY,
    required this.onRotZ,
    required this.pinchModeSelector,
    required this.onReset,
    required this.onClose,
    // nuevos
    this.planesAvailable,
    this.manualPlacement,
    this.onManualPlacementChanged,
    this.onPlaceAtCenter,
    this.onPlaceRandom,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasPlanes = planesAvailable ?? false;
    final bool isManual = manualPlacement ?? false;

    // Altura fija para garantizar scroll cuando el contenido es largo.
    final double panelHeight = MediaQuery.of(context).size.height * 0.46;

    return SizedBox(
      height: panelHeight,
      child: Card(
        color: Colors.black.withOpacity(0.58),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Overlays
                Row(
                  children: [
                    Expanded(
                      child: _switch(
                        'Feature points',
                        showPoints,
                        onTogglePoints,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _switch('Planes', showPlanes, onTogglePlanes),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // ---- Colocación ----
                _sectionTitle('Colocación'),
                Tooltip(
                  message: hasPlanes
                      ? 'Activa para colocar con botones (sin taps en pantalla).'
                      : 'Esperando detección de planos…',
                  child: Opacity(
                    opacity: hasPlanes ? 1.0 : 0.5,
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Manual',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        Switch(
                          value: isManual,
                          onChanged: hasPlanes
                              ? onManualPlacementChanged
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
                if (isManual) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onPlaceAtCenter,
                          icon: const Icon(Icons.filter_center_focus),
                          label: const Text('Colocar al centro'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onPlaceRandom,
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('Aleatorio'),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 8),

                _sectionTitle('Pinch mode'),
                pinchModeSelector,
                const SizedBox(height: 8),

                _sectionTitle('Scale'),
                Row(
                  children: [
                    _lockButton(
                      locked: scaleLocked,
                      onPressed: onToggleScaleLock,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _axisField('X', sx)),
                    const SizedBox(width: 8),
                    Expanded(child: _axisField('Y', sy)),
                    const SizedBox(width: 8),
                    Expanded(child: _axisField('Z', sz)),
                  ],
                ),
                Slider(value: sx, min: 0.01, max: 5, onChanged: onScaleUniform),

                _sectionTitle('Offset (m)'),
                Row(
                  children: [
                    _lockButton(locked: true, onPressed: () {}),
                    const SizedBox(width: 8),
                    Expanded(child: _axisField('X', ox)),
                    const SizedBox(width: 8),
                    Expanded(child: _axisField('Y', oy)),
                    const SizedBox(width: 8),
                    Expanded(child: _axisField('Z', oz)),
                  ],
                ),
                Slider(value: ox, min: -2, max: 2, onChanged: onOffsetX),
                Slider(value: oy, min: -2, max: 2, onChanged: onOffsetY),
                Slider(value: oz, min: -2, max: 2, onChanged: onOffsetZ),

                _sectionTitle('Rotation (°)'),
                _sliderLabeled('X', rx, -180, 180, onRotX),
                _sliderLabeled('Y', ry, -180, 180, onRotY),
                _sliderLabeled('Z', rz, -180, 180, onRotZ),

                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onReset,
                        child: const Text('Reset'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: onClose,
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ----- helpers UI -----
  Widget _switch(String t, bool val, ValueChanged<bool> onChanged) => Row(
    children: [
      Expanded(
        child: Text(t, style: const TextStyle(color: Colors.white)),
      ),
      Switch(value: val, onChanged: onChanged),
    ],
  );

  Widget _sectionTitle(String t) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 6),
      child: Text(
        t,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

  Widget _lockButton({required bool locked, required VoidCallback onPressed}) {
    return SizedBox(
      width: 38,
      height: 38,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onPressed,
        child: Icon(locked ? Icons.lock : Icons.lock_open, size: 18),
      ),
    );
  }

  Widget _axisField(String axis, double value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(axis, style: const TextStyle(color: Colors.white)),
          const Spacer(),
          Text(
            value.toStringAsPrecision(3),
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _sliderLabeled(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ${value.toStringAsFixed(0)}°',
          style: const TextStyle(color: Colors.white),
        ),
        Slider(value: value, min: min, max: max, onChanged: onChanged),
      ],
    );
  }
}
