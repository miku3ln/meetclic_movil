// lib/ar/models/ar_transform_state.dart

class ARTransformState {
  // Escala
  double sx, sy, sz;
  bool scaleLocked;

  // Rotación (grados)
  double rx, ry, rz;

  // Offset (metros)
  double ox, oy, oz;

  // Valores iniciales (para HUD)
  double initialScale;
  double initialOz;

  ARTransformState({
    this.sx = 1,
    this.sy = 1,
    this.sz = 1,
    this.scaleLocked = true,
    this.rx = 0,
    this.ry = 0,
    this.rz = 0,
    this.ox = 0,
    this.oy = 0.05,
    this.oz = 0,
    this.initialScale = 1,
    this.initialOz = 0,
  });

  void reset() {
    sx = sy = sz = 1;
    rx = ry = rz = 0;
    ox = 0;
    oy = 0.05;
    oz = 0;
    scaleLocked = true;
    initialScale = sx;
    initialOz = oz;
  }
}
