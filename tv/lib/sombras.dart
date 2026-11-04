// Lumbra — launcher para Android TV basado en FLauncher (GPL-3.0).
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Sombras y brillos difuminados dibujados una sola vez como imagen.
///
/// En TV modestas difuminar una BoxShadow en cada cuadro costaba ~15 ms de GPU y daba tirones
/// al moverse por la fila; pintar la imagen ya difuminada cuesta casi nada y se ve igual.
class ConSombra extends StatelessWidget {
  /// sombras fijas (debajo del brillo, en el mismo orden que una BoxDecoration)
  final List<BoxShadow> sombras;

  /// brillo que aparece y se apaga con [brilla] (va debajo de las sombras fijas)
  final BoxShadow? brillo;
  final bool brilla;
  final double radio;
  final bool circulo;
  final Duration duracion;
  final Widget child;

  const ConSombra({
    super.key,
    this.sombras = const [],
    this.brillo,
    this.brilla = false,
    this.radio = 0,
    this.circulo = false,
    this.duracion = const Duration(milliseconds: 180),
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (brillo == null) return CustomPaint(painter: _Pintor(this, 0), child: child);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: brilla ? 1 : 0),
      duration: duracion,
      builder: (_, t, hijo) => CustomPaint(painter: _Pintor(this, t), child: hijo),
      child: child,
    );
  }
}

class _Pintor extends CustomPainter {
  final ConSombra w;
  final double brillo;

  _Pintor(this.w, this.brillo);

  @override
  void paint(Canvas canvas, Size size) {
    if (brillo > 0) _dibujar(canvas, size, w.brillo!, brillo);
    for (final s in w.sombras) {
      _dibujar(canvas, size, s, 1);
    }
  }

  void _dibujar(Canvas canvas, Size size, BoxShadow s, double opacidad) {
    final img = _imagen(size, w.radio, w.circulo, s);
    canvas.drawImage(
      img.imagen,
      s.offset - Offset(img.margen, img.margen),
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, opacidad)
        ..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_Pintor old) =>
      old.brillo != brillo || old.w.radio != w.radio || old.w.sombras != w.sombras || old.w.brillo != w.brillo;
}

final _cache = <String, ({ui.Image imagen, double margen})>{};

({ui.Image imagen, double margen}) _imagen(Size tam, double radio, bool circulo, BoxShadow s) {
  final clave = '${tam.width.toStringAsFixed(1)}x${tam.height.toStringAsFixed(1)} $radio $circulo '
      '${s.color.toARGB32()} ${s.blurRadius} ${s.spreadRadius}';
  final hecha = _cache[clave];
  if (hecha != null) return hecha;
  // la tarjeta de música cambia de ancho con cada canción: no se deja crecer sin límite
  if (_cache.length > 48) {
    for (final v in _cache.values) {
      v.imagen.dispose();
    }
    _cache.clear();
  }
  // lo que se extiende el difuminado: 3 sigmas
  final margen = (3 * Shadow.convertRadiusToSigma(s.blurRadius) + s.spreadRadius + 1).ceilToDouble();
  final grabadora = ui.PictureRecorder();
  final rect = Rect.fromLTWH(margen, margen, tam.width, tam.height).inflate(s.spreadRadius);
  final pintura = Paint()
    ..color = s.color
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, Shadow.convertRadiusToSigma(s.blurRadius));
  final c = Canvas(grabadora);
  if (circulo) {
    c.drawOval(rect, pintura);
  } else {
    c.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(radio + s.spreadRadius)), pintura);
  }
  final dibujo = grabadora.endRecording();
  final imagen = dibujo.toImageSync((tam.width + 2 * margen).ceil(), (tam.height + 2 * margen).ceil());
  dibujo.dispose();
  return _cache[clave] = (imagen: imagen, margen: margen);
}
