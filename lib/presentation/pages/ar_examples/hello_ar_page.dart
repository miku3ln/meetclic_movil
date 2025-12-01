import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_session_manager.dart';
import 'package:flutter/material.dart';

class HelloArPage extends StatefulWidget {
  const HelloArPage({super.key});
  @override
  State<HelloArPage> createState() => _HelloArPageState();
}

class _HelloArPageState extends State<HelloArPage> {
  ARSessionManager? _arSessionManager;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hello AR')),
      body: ARView(
        onARViewCreated:
            (
              ARSessionManager arSessionManager,
              ARObjectManager arObjectManager,
              ARAnchorManager arAnchorManager,
              ARLocationManager arLocationManager,
            ) async {
              _arSessionManager = arSessionManager;

              await _arSessionManager!.onInitialize(
                showFeaturePoints: true, // puntos
                showPlanes: false, // sin planos aún
                showWorldOrigin: false,
                handleTaps: false,
              );
              await arObjectManager.onInitialize();
            },
      ),
    );
  }

  @override
  void dispose() {
    _arSessionManager?.dispose();
    super.dispose();
  }
}
