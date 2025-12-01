import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart'; // usa el channel propio

import '../../../models/totem_management.dart';

class ARDropdownViewerPage extends StatefulWidget {
  const ARDropdownViewerPage({super.key});

  @override
  State<ARDropdownViewerPage> createState() => _ARDropdownViewerPageState();
}

class _ARDropdownViewerPageState extends State<ARDropdownViewerPage> {
  late ItemAR _selected;
  bool _showInfo = true;

  // Channel para eventos del <model-viewer>
  late final JavascriptChannel _mvChannel;

  @override
  void initState() {
    super.initState();
    _selected = itemsSources.first;

    _mvChannel = JavascriptChannel(
      'MV',
      onMessageReceived: (msg) {
        // msg.message es String (si mandas JSON desde JS, aquí lo recibes)
        debugPrint('[ModelViewer] ${msg.message}');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final iosUsdz = null; // si algún día tienes USDZ por ítem, úsalo

    return Scaffold(
      appBar: AppBar(
        title: const Text('Totems 3D / AR'),
        actions: [
          IconButton(
            tooltip: _showInfo ? 'Ocultar info' : 'Mostrar info',
            icon: Icon(_showInfo ? Icons.info_outline : Icons.info),
            onPressed: () => setState(() => _showInfo = !_showInfo),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _showInfo = !_showInfo),
        icon: Icon(_showInfo ? Icons.visibility_off : Icons.visibility),
        label: Text(_showInfo ? 'Ocultar' : 'Info'),
      ),
      body: Column(
        children: [
          // ==========================
          //       DROPDOWN SELECT
          // ==========================
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Selecciona un Totem',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<ItemAR>(
                  isExpanded: true,
                  value: _selected,
                  menuMaxHeight: 420,
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
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() {
                      _selected = val; // <- cambia el seleccionado
                      // El ModelViewer se recarga porque su key depende del id
                    });
                  },
                ),
              ),
            ),
          ),

          // ==========================
          //   VISOR + CARD FLOTANTE
          // ==========================
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ModelViewer(
                    key: ValueKey(_selected.id), // <- fuerza recarga al cambiar
                    src: _selected.sources.glb, // GLB remoto
                    iosSrc: iosUsdz, // USDZ si lo tienes (Quick Look)
                    alt: _selected.title,
                    poster: _selected.sources.img,
                    ar: true,
                    arModes: const ['webxr', 'scene-viewer', 'quick-look'],
                    cameraControls: true,
                    autoRotate: true,

                    // eventos via JS -> Flutter
                    javascriptChannels: {_mvChannel},
                    relatedJs: """
                      (function(){
                        const wait = () => new Promise(r => setTimeout(r, 0));
                        async function init(){
                          await wait();
                          const mv = document.querySelector('model-viewer');
                          if(!mv){ setTimeout(init, 50); return; }
                          const post = (name, detail) => MV.postMessage(JSON.stringify({event: name, detail}));
                          mv.addEventListener('load',    () => post('load', {}));
                          mv.addEventListener('error',   (e) => post('error', {type: e?.detail?.type || 'unknown'}));
                          mv.addEventListener('progress',(e) => post('progress', {total: e.totalProgress}));
                        }
                        init();
                      })();
                    """,
                  ),
                ),

                if (Platform.isIOS && iosUsdz == null)
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.orange.withOpacity(0.95),
                      child: const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text(
                          'En iOS, para AR necesitas un archivo .usdz. Se muestra en 3D.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),

                if (_showInfo)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: _InfoCard(item: _selected),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final ItemAR item;
  const _InfoCard({required this.item});

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
        child: Row(
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
                mainAxisSize: MainAxisSize.min,
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
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
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
          ],
        ),
      ),
    );
  }
}
