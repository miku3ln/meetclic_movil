// lib/exercises/a01_hello_ar_feature_points.dart
//
// Ejercicio 1 — Hello AR — Feature Points (ar_flutter_plugin puro)
// Qué hace:
// - Inicializa ARView y enciende los feature points.
// - Muestra un overlay simple con mensajes (sin enum de tracking).
//
// Notas:
// - ar_flutter_plugin NO expone ARTrackingState ni onError en ARSessionManager.
// - Para manejar errores, usamos try/catch al inicializar.
//
// Dependencias (pubspec.yaml):
//   ar_flutter_plugin: ^0.9.0  // o la versión estable que uses

import 'dart:io' show Platform;

import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_session_manager.dart';
import 'package:flutter/material.dart';

class A01HelloArFeaturePoints extends StatefulWidget {
  const A01HelloArFeaturePoints({super.key});

  @override
  State<A01HelloArFeaturePoints> createState() =>
      _A01HelloArFeaturePointsState();
}

class _A01HelloArFeaturePointsState extends State<A01HelloArFeaturePoints> {
  ARSessionManager? _arSessionManager;
  ARObjectManager? _arObjectManager;
  ARAnchorManager? _arAnchorManager;
  ARLocationManager? _arLocationManager; // ④ parámetro extra

  String _statusText = 'Inicializando…';

  @override
  void dispose() {
    _arSessionManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('A01 — Hello AR (Feature Points)')),
      body: Stack(
        children: [
          // ✅ Firma correcta: callback void con 4 managers
          ARView(onARViewCreated: _onARViewCreated),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: _StatusCard(statusText: _statusText),
          ),
        ],
      ),
    );
  }

  // ✅ Debe ser void y con 4 parámetros (sin async)
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

    // Llamamos a un método async separado
    _initArSession();
  }

  // 🔧 Parte asíncrona separada
  Future<void> _initArSession() async {
    try {
      await _arSessionManager!.onInitialize(
        showFeaturePoints: true,
        showPlanes: false,
        showWorldOrigin: false,
        handlePans: false,
        handleRotation: false,
        handleTaps: false,
      );

      if (!mounted) return;
      setState(() {
        _statusText = Platform.isAndroid
            ? 'Listo. Mueve la cámara (ARCore).'
            : 'Listo. Mueve la cámara (ARKit).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusText = 'Error al iniciar AR: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al iniciar AR: $e')));
    }
  }
}

class _StatusCard extends StatelessWidget {
  final String statusText;
  const _StatusCard({required this.statusText});

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
              const SizedBox(height: 6),
              const Text('• Feature points: encendidos'),
              const Text('• Planos: apagados (ver Ejercicio 2)'),
              const Text('• Origen del mundo: apagado (ver Ejercicio 2)'),
              const SizedBox(height: 6),
              Text(
                'Tip: muévete despacio y apunta a superficies con textura y buena luz.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
