// Lumbra — launcher para Android TV basado en FLauncher (GPL-3.0).
import 'package:flutter/material.dart';

import 'native.dart';

/// Copia en Flutter de los ajustes; el original vive en el lado nativo (Ajustes.kt).
class Config extends ChangeNotifier {
  Config._();
  static final Config i = Config._();

  Map _v = {};

  void cargar(Map valores) {
    _v = Map.of(valores);
    // Android guarda los colores como enteros con signo
    for (final clave in const ['acento', 'fondo_color']) {
      final color = _v[clave];
      if (color is int) _v[clave] = color & 0xFFFFFFFF;
    }
    notifyListeners();
  }

  /// Cambia un valor que ya se guardó por otro camino.
  void anotar(Map<String, Object?> valores) {
    _v.addAll(valores);
    notifyListeners();
  }

  void poner(String clave, Object? valor) {
    _v[clave] = valor;
    Nativo.guardar(clave, valor);
    notifyListeners();
  }

  T _leer<T>(String clave, T porDefecto) {
    final v = _v[clave];
    return v is T ? v : porDefecto;
  }

  String texto(String clave, [String porDefecto = '']) => _leer(clave, porDefecto);
  int entero(String clave, [int porDefecto = 0]) => _leer(clave, porDefecto);
  bool logico(String clave, [bool porDefecto = false]) => _leer(clave, porDefecto);

  List<String>? lista(String clave) => (_v[clave] as List?)?.cast<String>();

  bool get ligero => logico('modo_ligero');
  bool get escalaEnfoque => !ligero && logico('enfoque_escala', true);
  bool get brilloEnfoque => !ligero && logico('enfoque_brillo', true);

  int get volumen => entero('volumen', 35);
  bool get silencio => logico('silencio');

  double get ladoTarjeta => switch (texto('tarjeta_tam', 'M')) {
        'S' => 92.0,
        'L' => 134.0,
        _ => 112.0,
      };

  /// Radio de la tarjeta en proporción a su lado.
  double get formaTarjeta => switch (texto('tarjeta_forma', 'redondeada')) {
        'cuadrada' => .08,
        'circulo' => .5,
        _ => .24,
      };

  String get nombres => texto('tarjeta_nombres', 'nunca');
  bool get reloj24 => texto('reloj_formato', '12') == '24';
  String get carpetaApp => texto('carpeta_app');
  String get acentoNombre => colores.entries
      .firstWhere((e) => e.value == entero('acento', 0xFFE50914), orElse: () => colores.entries.first)
      .key;

  static const colores = {
    'Brasa': 0xFFE50914,
    'Ámbar': 0xFFF29F05,
    'Cobre': 0xFFC8703A,
    'Oro': 0xFFD4AF37,
    'Esmeralda': 0xFF10A37F,
    'Turquesa': 0xFF12A5B8,
    'Azul': 0xFF2F7BEA,
    'Violeta': 0xFF8A4FFF,
    'Rosa': 0xFFE8467C,
    'Luna': 0xFFD8DEE9,
  };
}

/// Colores de la interfaz, todos derivados del color de acento elegido.
class Tema {
  static Color get rojo => Color(Config.i.entero('acento', 0xFFE50914));

  static HSLColor get _hsl => HSLColor.fromColor(rojo);
  static Color _tono(double s, double l) => _hsl.withSaturation(s).withLightness(l).toColor();

  static Color get rojoOscuro => _tono(.87, .29);
  static Color get brasa => _hsl.withLightness((_hsl.lightness + .14).clamp(0, 1)).toColor();
  static Color get texto => Color.alphaBlend(rojo.withAlpha(14), const Color(0xFFF7F4F3));
  static Color get textoSuave => Color.alphaBlend(rojo.withAlpha(26), const Color(0xFFB4ABA9));
  static Color get panel => _tono(.45, .05).withAlpha(0xE6);
  static Color get tarjetaArriba => _tono(.38, .10);
  static Color get tarjetaAbajo => _tono(.45, .04);
  static Color get fondoTodas => _tono(.5, .02).withAlpha(0xEE);

  static Color brillo([int alfa = 0x99]) => rojo.withAlpha(alfa);

  static LinearGradient get degradadoReloj => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [brasa, rojo, rojoOscuro],
        stops: const [0, .55, 1],
      );

  static const sombraTexto = [Shadow(color: Color(0xCC000000), blurRadius: 12)];
}

/// La interfaz se diseña en 1280×720 y se escala a la pantalla.
class Lienzo extends StatelessWidget {
  final Widget child;
  const Lienzo({super.key, required this.child});

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(width: 1280, height: 720, child: child),
      );
}
