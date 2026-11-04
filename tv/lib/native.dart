// Lumbra — launcher para Android TV basado en FLauncher (GPL-3.0).

import 'package:flutter/services.dart';

const _metodos = MethodChannel('lumbra/method');
const _apps = EventChannel('lumbra/apps');
const _estado = EventChannel('lumbra/state');

class App {
  final String nombre;
  final String paquete;
  final Uint8List? logo; // logo sin el cuadro de color de la app, centrado con margen
  final Uint8List? propio; // icono propio puesto desde la PC

  App.desde(Map m)
      : nombre = m['name'] as String,
        paquete = m['packageName'] as String,
        logo = m['logo'] as Uint8List?,
        propio = m['custom'] as Uint8List?;
}

class Musica {
  final String paquete;
  final String titulo;
  final String? artista;
  final bool sonando;
  final Uint8List? portada;

  Musica.desde(Map m)
      : paquete = m['package'] as String,
        titulo = m['title'] as String,
        artista = m['artist'] as String?,
        sonando = m['playing'] as bool,
        portada = m['art'] as Uint8List?;

  Musica._(this.paquete, this.titulo, this.artista, this.sonando, this.portada);

  Musica conPortada(Uint8List? p) => Musica._(paquete, titulo, artista, sonando, p);
}

/// Un archivo o carpeta del explorador. tipo: dir, video o image.
class Entrada {
  final String nombre;
  final String ruta;
  final String tipo;

  Entrada.desde(Map m)
      : nombre = m['name'] as String,
        ruta = m['path'] as String,
        tipo = m['kind'] as String? ?? 'dir';
}

class Nativo {
  static Future<List<App>> apps() async {
    final lista = await _metodos.invokeListMethod<Map>('getApplications') ?? [];
    return lista.map(App.desde).toList();
  }

  static Future<void> abrirApp(String paquete) => _metodos.invokeMethod('launchApp', paquete);
  static Future<void> abrirAjustes() => _metodos.invokeMethod('openSettings');
  static Future<void> abrirWifi() => _metodos.invokeMethod('openWifiSettings');
  static Future<void> abrirInfo(String paquete) => _metodos.invokeMethod('openAppInfo', paquete);
  static Future<void> abrirMusica(String paquete) => _metodos.invokeMethod('openMedia', paquete);

  /// accion: anterior, pausa (alterna con reproducir) o siguiente.
  static Future<void> controlMusica(String paquete, String accion) =>
      _metodos.invokeMethod('mediaControl', {'package': paquete, 'action': accion});

  static Future<void> ponerVolumen(int volumen, bool silencio) =>
      _metodos.invokeMethod('setVolume', {'volume': volumen, 'muted': silencio});

  static Future<Map> ajustes() async => await _metodos.invokeMapMethod('getSettings') ?? {};
  static Future<void> guardar(String clave, Object? valor) =>
      _metodos.invokeMethod('setSetting', {'key': clave, 'value': valor});
  static Future<Map> restablecer() async => await _metodos.invokeMapMethod('resetSettings') ?? {};

  static Future<bool> pedirPermisoArchivos() async => await _metodos.invokeMethod<bool>('requestMediaPermission') ?? false;

  static Future<List<Entrada>> raices() async {
    final lista = await _metodos.invokeListMethod<Map>('storageRoots') ?? [];
    return lista.map(Entrada.desde).toList();
  }

  static Future<List<Entrada>> listar(String ruta) async {
    final lista = await _metodos.invokeListMethod<Map>('listDir', ruta) ?? [];
    return lista.map(Entrada.desde).toList();
  }

  static Future<Map> infoSalva() async => await _metodos.invokeMapMethod('screensaverInfo') ?? {};
  static Future<void> probarSalva() => _metodos.invokeMethod('testScreensaver');
  static Future<void> abrirAjustesSalva() => _metodos.invokeMethod('openDreamSettings');

  /// Eventos: settings, media, network, home.
  static Stream<Map> get eventos => _estado.receiveBroadcastStream().map((e) => e as Map);

  /// Avisa cuando se instala o desinstala una app.
  static Stream<dynamic> get cambiosApps => _apps.receiveBroadcastStream();
}
