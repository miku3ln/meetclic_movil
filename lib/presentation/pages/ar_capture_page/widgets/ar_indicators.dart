// lib/ar/widgets/ar_indicators.dart

import 'package:flutter/material.dart';
import 'package:meetclic_movil/ar/preview/enums/enums-data.dart';

class ARIndicators extends StatelessWidget {
  final bool showPlanes;
  final bool showPoints;
  final PinchMode pinchMode;
  final double scaleX;
  final double oz;
  final double initialOz;

  // NUEVO: indicadores de renderizado
  final bool renderPulse; // cambia true/false cada segundo
  final Duration sinceLastBuild; // tiempo transcurrido desde último build

  const ARIndicators({
    super.key,
    required this.showPlanes,
    required this.showPoints,
    required this.pinchMode,
    required this.scaleX,
    required this.oz,
    required this.initialOz,
    required this.renderPulse,
    required this.sinceLastBuild,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip(IconData icon, String text, {Color? bg}) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg ?? Colors.white12,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Text(text, style: const TextStyle(color: Colors.white)),
          ],
        ),
      );
    }

    final Color planesBg = (showPlanes
        ? Colors.green.withOpacity(.25)
        : Colors.red.withOpacity(.25));
    final Color pointsBg = (showPoints
        ? Colors.green.withOpacity(.25)
        : Colors.red.withOpacity(.25));

    final String modeTxt = pinchMode == PinchMode.scale ? 'Scale' : 'Distance';
    final String scaleTxt = 'S: ${scaleX.toStringAsPrecision(3)}×';
    final String ozTxt =
        'Z: ${oz.toStringAsFixed(2)} m (Δ ${((oz - initialOz) >= 0 ? '+' : '')}${(oz - initialOz).toStringAsFixed(2)})';

    // NUEVO: Render indicator
    final String sinceTxt = _formatSince(sinceLastBuild);
    final Color pulseBg = renderPulse
        ? Colors.green.withOpacity(.35)
        : Colors.amber.withOpacity(.35);
    final String pulseTxt = renderPulse
        ? 'Render: activo'
        : 'Render: en espera';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        chip(
          Icons.grid_on,
          'Planes: ${showPlanes ? "ON" : "OFF"}',
          bg: planesBg,
        ),
        chip(
          Icons.blur_circular,
          'Features: ${showPoints ? "ON" : "OFF"}',
          bg: pointsBg,
        ),
        chip(Icons.swap_calls, 'Mode: $modeTxt'),
        chip(Icons.straighten, scaleTxt),
        chip(Icons.vertical_align_center, ozTxt),
        // NUEVOS
        chip(Icons.add, '$pulseTxt', bg: pulseBg),
        chip(Icons.timer_outlined, 'Último build: $sinceTxt'),
      ],
    );
  }

  String _formatSince(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m}m ${s}s';
  }
}
