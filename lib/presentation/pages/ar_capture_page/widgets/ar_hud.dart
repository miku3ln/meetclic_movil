// lib/ar/widgets/ar_hud.dart

import 'package:flutter/material.dart';
import 'package:meetclic_movil/ar/preview/enums/enums-data.dart';

class ARHud extends StatelessWidget {
  final PinchMode pinchMode;
  final double currentScale;
  final double currentOz;
  final double initialScale;
  final double initialOz;

  const ARHud({
    super.key,
    required this.pinchMode,
    required this.currentScale,
    required this.currentOz,
    required this.initialScale,
    required this.initialOz,
  });

  @override
  Widget build(BuildContext context) {
    final bool isScale = pinchMode == PinchMode.scale;
    final double cur = isScale ? currentScale : currentOz;
    final double ini = isScale ? initialScale : initialOz;
    final double delta = cur - ini;

    final String label = isScale ? 'Scale' : 'Dist Z';
    final String unit = isScale ? '×' : ' m';

    final String fCur = isScale
        ? cur.toStringAsPrecision(3)
        : cur.toStringAsFixed(2);
    final String fIni = isScale
        ? ini.toStringAsPrecision(3)
        : ini.toStringAsFixed(2);
    final String fDelta =
        '${delta >= 0 ? '+' : ''}${isScale ? delta.toStringAsPrecision(3) : delta.toStringAsFixed(2)}$unit';

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.pinch, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(isScale ? 'Pinch: Scale' : 'Pinch: Distance'),
                ],
              ),
              const SizedBox(width: 12),
              Text('$label: $fCur$unit'),
              const SizedBox(width: 10),
              Text('init: $fIni$unit'),
              const SizedBox(width: 10),
              Text('Δ: $fDelta'),
            ],
          ),
        ),
      ),
    );
  }
}
