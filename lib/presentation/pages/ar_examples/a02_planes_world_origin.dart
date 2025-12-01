// lib/exercises/a02_planes_world_origin.dart
//
// Ejercicio 2 — Planes + Origen del Mundo (ar_flutter_plugin)
// Objetivo:
// - Visualizar detección de planos (showPlanes) y el origen del mundo (ejes XYZ).
// - Incluir UI/UX para confirmar visualmente que las opciones están activas.
//
// Qué verás:
// - Superficie con una "trama" de planos detectados (cuando showPlanes = true).
// - Ejes XYZ en el origen del mundo (cuando showWorldOrigin = true).
// - Chips de estado y toggles para activar/desactivar cada opción.
//
// Notas:
// - ar_flutter_plugin permite cambiar debug options con onInitialize(). Aquí
//   las re-aplicamos cuando el usuario cambia los toggles.
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

class A02PlanesWorldOrigin extends StatefulWidget {
  const A02PlanesWorldOrigin({super.key});

  @override
  State<A02PlanesWorldOrigin> createState() => _A02PlanesWorldOriginState();
}

class _A02PlanesWorldOriginState extends State<A02PlanesWorldOrigin> {
  ARSessionManager? _arSessionManager;
  ARObjectManager? _arObjectManager;
  ARAnchorManager? _arAnchorManager;
  ARLocationManager? _arLocationManager;

  // Opciones de debug (con estado para UI)
  bool _showPlanes = true;
  bool _showWorldOrigin = true;
  bool _initialized = false;

  String _statusText = 'Inicializando…';

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
          label: _showPlanes ? 'Planos: ON' : 'Planos: OFF',
          on: _showPlanes,
          icon: Icons.grid_on,
        ),
        _StateChip(
          label: _showWorldOrigin ? 'Origen XYZ: ON' : 'Origen XYZ: OFF',
          on: _showWorldOrigin,
          icon: Icons.explore,
        ),
        _StateChip(
          label: _initialized ? 'AR: Listo' : 'AR: Cargando…',
          on: _initialized,
          icon: Icons.check_circle,
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('A02 — Planos + Origen del Mundo'),
        actions: [
          IconButton(
            tooltip: 'Ayuda',
            icon: const Icon(Icons.help_outline),
            onPressed: _showHelp,
          ),
        ],
      ),
      body: Stack(
        children: [
          // ARView (con callback de 4 parámetros, sin async)
          ARView(onARViewCreated: _onARViewCreated),

          // Chips de estado (visual arriba)
          Positioned(left: 12, right: 12, top: 12, child: topChips),

          // Overlay de status / mensajes
          Positioned(
            left: 12,
            right: 12,
            bottom: 88,
            child: _StatusCard(statusText: _statusText),
          ),
        ],
      ),

      // Controles UX para encender/apagar en vivo
      bottomNavigationBar: _BottomDebugBar(
        showPlanes: _showPlanes,
        showWorldOrigin: _showWorldOrigin,
        onTogglePlanes: (v) => _toggleOption(planes: v),
        onToggleOrigin: (v) => _toggleOption(origin: v),
      ),
      floatingActionButton: FloatingActionButton.extended(
        label: const Text('Reaplicar opciones'),
        icon: const Icon(Icons.refresh),
        onPressed: _applyDebugOptions,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // Callback de creación: debe ser void y tener 4 parámetros
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

    // Inicialización asíncrona separada
    _initArSession();
  }

  Future<void> _initArSession() async {
    try {
      await _arSessionManager!.onInitialize(
        showFeaturePoints:
            false, // En este ejercicio nos centramos en planos/origen
        showPlanes: _showPlanes,
        showWorldOrigin: _showWorldOrigin,
        handlePans: false,
        handleRotation: false,
        handleTaps: false,
      );

      if (!mounted) return;
      setState(() {
        _initialized = true;
        _statusText = Platform.isAndroid
            ? 'Apunta a superficies con textura. (ARCore)'
            : 'Apunta a superficies con textura. (ARKit)';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusText = 'Error al iniciar AR: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al iniciar AR: $e')));
    }
  }

  // Reaplica onInitialize con los flags actuales
  Future<void> _applyDebugOptions() async {
    if (_arSessionManager == null) return;
    try {
      await _arSessionManager!.onInitialize(
        showFeaturePoints: false,
        showPlanes: _showPlanes,
        showWorldOrigin: _showWorldOrigin,
        handlePans: false,
        handleRotation: false,
        handleTaps: false,
      );

      if (!mounted) return;
      setState(() {
        _statusText =
            'Opciones aplicadas → Planos: ${_showPlanes ? "ON" : "OFF"} | Origen: ${_showWorldOrigin ? "ON" : "OFF"}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusText = 'Error al reconfigurar: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al reconfigurar: $e')));
    }
  }

  void _toggleOption({bool? planes, bool? origin}) {
    if (planes != null) _showPlanes = planes;
    if (origin != null) _showWorldOrigin = origin;
    setState(() {});
  }

  void _showHelp() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final textStyle = Theme.of(
          ctx,
        ).textTheme.bodyMedium?.copyWith(color: Colors.white);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: DefaultTextStyle(
            style: textStyle ?? const TextStyle(color: Colors.white),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  '¿Qué debo ver?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  '• Con "Planos: ON", verás una trama sobre superficies detectadas (suelo/mesa).',
                ),
                Text(
                  '• Con "Origen XYZ: ON", verás tres ejes de colores en el punto (0,0,0).',
                ),
                SizedBox(height: 12),
                Text(
                  'Tips: mueve el dispositivo lentamente, buena iluminación y superficies con textura.',
                ),
                SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Chip de estado con color según ON/OFF
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

/// Barra inferior con toggles para showPlanes y showWorldOrigin
class _BottomDebugBar extends StatelessWidget {
  final bool showPlanes;
  final bool showWorldOrigin;
  final ValueChanged<bool> onTogglePlanes;
  final ValueChanged<bool> onToggleOrigin;

  const _BottomDebugBar({
    required this.showPlanes,
    required this.showWorldOrigin,
    required this.onTogglePlanes,
    required this.onToggleOrigin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.8),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8 + 8), // +8 por FAB center
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _ToggleRow(
            label: 'Planos',
            value: showPlanes,
            onChanged: onTogglePlanes,
            icon: Icons.grid_on,
          ),
          _ToggleRow(
            label: 'Origen XYZ',
            value: showWorldOrigin,
            onChanged: onToggleOrigin,
            icon: Icons.explore,
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData icon;

  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.white)),
        const SizedBox(width: 8),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.lightGreenAccent,
        ),
      ],
    );
  }
}

/// Tarjeta de mensajes de estado
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
              const Text(
                '• "Planos: ON" → se muestra la trama de superficies.',
              ),
              const Text(
                '• "Origen XYZ: ON" → se muestra el eje RGB en (0,0,0).',
              ),
              const SizedBox(height: 6),
              Text(
                'Tip: si no ves planos, mueve el móvil en forma de 8 para ayudar al tracking.',
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
