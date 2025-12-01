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
import 'package:vector_math/vector_math_64.dart' as v; // usa 64

import '../../../models/totem_management.dart';

enum ARLoadStatus { idle, loading, success, error }

class ARNoHitDropdownPage extends StatefulWidget {
  const ARNoHitDropdownPage({super.key});

  @override
  State<ARNoHitDropdownPage> createState() => _ARNoHitDropdownPageState();
}

class _ARNoHitDropdownPageState extends State<ARNoHitDropdownPage> {
  // Managers
  ARSessionManager? _arSessionManager;
  ARObjectManager? _arObjectManager;

  // Nodo actual
  ARNode? _currentNode;

  // Dropdown
  late ItemAR _selected;

  // Parámetros
  final double distanceMeters = 1.2;
  final double uniformScale = 0.2;
  final List<double> eulerDeg = const [0, 180, 0];

  // Estado y errores
  ARLoadStatus _status = ARLoadStatus.idle;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _selected = itemsSources.first;
  }

  @override
  void dispose() {
    _arSessionManager?.dispose();
    super.dispose();
  }

  // Helpers UI
  void _showSnack(String msg, {bool error = false}) {
    debugPrint(msg);
    final sb = SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red[700] : Colors.black87,
      duration: const Duration(seconds: 3),
    );
    ScaffoldMessenger.of(context).showSnackBar(sb);
  }

  void _setStatus(ARLoadStatus s, {String? err}) {
    setState(() {
      _status = s;
      _lastError = err;
    });
  }

  bool _isValidUrl(String url) {
    if (url.isEmpty) return false;
    final u = Uri.tryParse(url);
    return u != null &&
        (u.isScheme('http') || u.isScheme('https')) &&
        u.path.toLowerCase().endsWith('.glb');
  }

  // Inicializa AR
  Future<void> _onARViewCreated(
    ARSessionManager sessionManager,
    ARObjectManager objectManager,
    ARAnchorManager anchorManager,
    ARLocationManager locationManager,
  ) async {
    _arSessionManager = sessionManager;
    _arObjectManager = objectManager;

    try {
      await _arSessionManager!.onInitialize(
        showFeaturePoints: false,
        showPlanes: false,
        customPlaneTexturePath: null,
        showWorldOrigin: false,
        handleTaps: false,
      );
      await _arObjectManager!.onInitialize();
      _showSnack('AR inicializado');
    } catch (e, st) {
      _setStatus(ARLoadStatus.error, err: 'Fallo inicializando AR: $e');
      debugPrint('[AR] Init error: $e\n$st');
      return;
    }

    // Coloca el primer modelo
    await _placeCurrentInFront();
  }

  Future<void> _removeCurrentNodeIfAny() async {
    if (_currentNode != null) {
      try {
        final removed = await _arObjectManager?.removeNode(_currentNode!);
        debugPrint('[AR] removeNode -> $removed');
      } catch (e, st) {
        debugPrint('[AR] Error al remover nodo anterior: $e\n$st');
      } finally {
        _currentNode = null;
      }
    }
  }

  // Coloca el nodo seleccionado frente a la cámara
  Future<void> _placeCurrentInFront() async {
    if (_arObjectManager == null || _arSessionManager == null) {
      _setStatus(ARLoadStatus.error, err: 'AR no iniciado aún');
      _showSnack('AR no iniciado aún', error: true);
      return;
    }

    // Validación de URL
    final url = _selected.sources.glb;
    if (!_isValidUrl(url)) {
      _setStatus(ARLoadStatus.error, err: 'URL inválida o no es .glb: $url');
      _showSnack('URL inválida o no es .glb:\n$url', error: true);
      return;
    }

    _setStatus(ARLoadStatus.loading);
    _showSnack('Cargando modelo: ${_selected.id}');

    await _removeCurrentNodeIfAny();

    v.Vector3 camPos = v.Vector3.zero();
    v.Vector3 zAxis = v.Vector3(0, 0, 1); // fallback

    try {
      final camPose = await _arSessionManager!.getCameraPose();
      if (camPose != null) {
        camPos = camPose.getTranslation();
        zAxis = v.Vector3(
          camPose.entry(0, 2),
          camPose.entry(1, 2),
          camPose.entry(2, 2),
        ).normalized();
      } else {
        debugPrint('[AR] getCameraPose() devolvió null (usando fallback)');
      }
    } catch (e, st) {
      debugPrint(
        '[AR] Error leyendo pose de cámara: $e\n$st (usando fallback)',
      );
    }

    final targetPos = camPos - zAxis * distanceMeters;

    // Construcción del nodo
    ARNode node;
    try {
      node = ARNode(
        type: NodeType.webGLB,
        uri: url, // ← AQUÍ se provee la URL remota del .glb
        position: targetPos,
        eulerAngles: v.Vector3(
          _deg2rad(eulerDeg[0]),
          _deg2rad(eulerDeg[1]),
          _deg2rad(eulerDeg[2]),
        ),
        scale: v.Vector3(uniformScale, uniformScale, uniformScale),
      );
    } catch (e, st) {
      _setStatus(ARLoadStatus.error, err: 'No se pudo construir el nodo: $e');
      _showSnack('No se pudo construir el nodo', error: true);
      debugPrint('[AR] ARNode ctor error: $e\n$st');
      return;
    }

    // Añadir a la escena
    try {
      final added = await _arObjectManager!.addNode(node);
      debugPrint('[AR] addNode -> $added');
      if (added == true) {
        _currentNode = node;
        _setStatus(ARLoadStatus.success);
        _showSnack('Modelo cargado ✔');
      } else {
        _setStatus(ARLoadStatus.error, err: 'addNode devolvió false');
        _showSnack('No se pudo añadir el nodo (addNode=false)', error: true);
      }
    } catch (e, st) {
      _setStatus(ARLoadStatus.error, err: 'Excepción en addNode: $e');
      _showSnack('Error añadiendo el nodo:\n$e', error: true);
      debugPrint('[AR] addNode exception: $e\n$st');
    }
  }

  double _deg2rad(double d) => d * math.pi / 180.0;

  Color _statusColor() {
    switch (_status) {
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

  String _statusText() {
    switch (_status) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AR – Sin hits (dropdown)'),
        actions: [
          IconButton(
            tooltip: 'Recolocar al frente',
            onPressed: _placeCurrentInFront,
            icon: const Icon(Icons.center_focus_strong),
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
                      await _placeCurrentInFront(); // recoloca el nuevo
                    },
                  ),
                ),
              ),
            ),
          ),

          // Chip de estado (arriba derecha)
          Positioned(
            right: 12,
            top: 12 + 56, // debajo del dropdown
            child: Chip(
              label: Text(
                _statusText(),
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: _statusColor(),
            ),
          ),

          // Loader grande si está cargando
          if (_status == ARLoadStatus.loading)
            const Center(child: CircularProgressIndicator()),

          // Card informativa flotante abajo
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _InfoCardAR(item: _selected, lastError: _lastError),
          ),
        ],
      ),
    );
  }
}

class _InfoCardAR extends StatelessWidget {
  final ItemAR item;
  final String? lastError;
  const _InfoCardAR({required this.item, this.lastError});

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
