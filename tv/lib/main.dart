// Lumbra — launcher para Android TV basado en FLauncher (GPL-3.0).
import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ajustes.dart';
import 'config.dart';
import 'native.dart';
import 'widgets.dart';

final _arranque = Stopwatch()..start();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('MEDIR')) _medirCuadros();
  runApp(const LumbraApp());
}

/// Solo en pruebas (--dart-define=MEDIR=true): resume en el log cuánto tarda cada cuadro.
void _medirCuadros() {
  final tiempos = <FrameTiming>[];
  WidgetsBinding.instance.addTimingsCallback(tiempos.addAll);
  Timer.periodic(const Duration(seconds: 4), (_) {
    if (tiempos.isEmpty) return;
    ms(Duration d) => d.inMicroseconds / 1000;
    final build = tiempos.map((t) => ms(t.buildDuration)).toList()..sort();
    final raster = tiempos.map((t) => ms(t.rasterDuration)).toList()..sort();
    final total = tiempos.map((t) => ms(t.totalSpan)).toList()..sort();
    p(List<double> l, double q) => l[((l.length - 1) * q).round()].toStringAsFixed(1);
    debugPrint('MEDIR n=${tiempos.length} lentos=${total.where((t) => t > 16.7).length} '
        'build p50=${p(build, .5)} p90=${p(build, .9)} raster p50=${p(raster, .5)} p90=${p(raster, .9)} '
        'max=${p(raster, 1)} total p90=${p(total, .9)} max=${p(total, 1)}');
    tiempos.clear();
  });
}

class LumbraApp extends StatelessWidget {
  const LumbraApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Lumbra',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.transparent,
          canvasColor: Colors.transparent,
        ),
        // Material transparente: sin él los textos salen con letra de depuración y subrayado amarillo
        home: const Material(type: MaterialType.transparency, child: Inicio()),
      );
}

/// Apps populares que se ponen en la fila la primera vez, si están instaladas.
const filaPopular = [
  'com.netflix.ninja',
  'com.google.android.youtube.tv',
  'com.amazon.amazonvideo.livingroom',
  'com.disney.disneyplus',
  'com.hbo.hbonow',
  'com.wbd.stream',
  'com.crunchyroll.crunchyroid',
  'com.spotify.tv.android',
  'com.plexapp.android',
  'org.videolan.vlc',
  'com.android.vending',
];

/// Cuántas apps lleva la fila la primera vez, completando con las demás instaladas.
const tamanoFilaInicial = 8;

enum Zona { fila, arriba }

enum Modal { ninguno, volumen, menu, todas, ajustes }

class Inicio extends StatefulWidget {
  const Inicio({super.key});

  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  final _foco = FocusNode();
  final _scrollFila = ScrollController();
  final _scrollTodas = ScrollController();
  StreamSubscription? _subEventos, _subApps;

  List<App> _todas = [];
  List<String> _fila = [];
  Musica? _musica;
  String _red = 'wifi';
  int _nivelRed = 3;

  Zona _zona = Zona.fila;
  int _iFila = 0;
  int _iArriba = 0;
  Modal _modal = Modal.ninguno;
  int _iMenu = 0;
  int _iTodas = 0;
  App? _appMenu;
  bool _menuDesdeTodas = false;

  int get _volumen => Config.i.volumen;
  bool get _silencio => Config.i.silencio;
  double get _lado => Config.i.ladoTarjeta;

  DateTime? _okPresionado;
  bool _okLargoUsado = false;

  @override
  void initState() {
    super.initState();
    Config.i.addListener(_alCambiarConfig);
    _iniciar();
  }

  void _alCambiarConfig() {
    if (!mounted) return;
    setState(() {
      // aparecen o desaparecen elementos: el foco no debe quedar fuera de la lista
      _iArriba = _iArriba.clamp(0, _itemsArriba.length - 1);
      _iTodas = _iTodas.clamp(0, (_todasVisibles.length - 1).clamp(0, 1 << 30));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _desplazarFila());
  }

  Future<void> _iniciar() async {
    Config.i.cargar(await Nativo.ajustes());
    // antes que las apps: leerlas tarda, y la música y la red no tienen por qué esperar
    _subEventos = Nativo.eventos.listen(_alEvento);
    await _cargarApps();
    _subApps = Nativo.cambiosApps.listen((_) => _cargarApps());
  }

  Future<void> _cargarApps() async {
    final pedido = _arranque.elapsedMilliseconds;
    final apps = await Nativo.apps();
    if (const bool.fromEnvironment('MEDIR')) {
      debugPrint('MEDIR apps: pedidas a $pedido ms, llegaron a ${_arranque.elapsedMilliseconds} ms');
    }
    apps.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    if (!mounted) return;
    final guardada = Config.i.lista('fila');
    if (guardada != null) {
      _fila = guardada;
    } else if (_fila.isEmpty) {
      // primera vez: las populares que estén instaladas y, si faltan, otras hasta completar
      final instaladas = apps.map((a) => a.paquete).toSet();
      _fila = filaPopular.where(instaladas.contains).toList();
      for (final a in apps) {
        if (_fila.length >= tamanoFilaInicial) break;
        if (!_fila.contains(a.paquete)) _fila.add(a.paquete);
      }
      _guardarFila();
    }
    setState(() {
      _todas = apps;
      _iFila = _iFila.clamp(0, _itemsFila.length - 1);
    });
  }

  void _alEvento(Map e) {
    setState(() {
      switch (e['type']) {
        case 'settings':
          Config.i.cargar(e['settings'] as Map);
          final guardada = Config.i.lista('fila');
          if (guardada != null) _fila = guardada;
        case 'media':
          final m = e['media'];
          // el foco se queda en el mismo elemento aunque la tarjeta de música aparezca o se vaya
          final antes = _itemsArriba[_iArriba];
          final nueva = m == null ? null : Musica.desde(m as Map);
          // misma portada: se reusa la ya decodificada en vez de decodificarla en cada play/pausa
          _musica = nueva != null && _musica != null && listEquals(nueva.portada, _musica!.portada)
              ? nueva.conPortada(_musica!.portada)
              : nueva;
          final ahora = _itemsArriba.indexOf(antes);
          _iArriba = ahora >= 0 ? ahora : _itemsArriba.indexOf('volumen');
        case 'network':
          _red = e['kind'] as String;
          _nivelRed = e['level'] as int;
        case 'home':
          _cerrarModal();
          _zona = Zona.fila;
          _iFila = 0;
          _desplazarFila();
      }
    });
  }

  @override
  void dispose() {
    Config.i.removeListener(_alCambiarConfig);
    _subEventos?.cancel();
    _subApps?.cancel();
    _foco.dispose();
    super.dispose();
  }

  // ---------- datos derivados ----------

  Set<String> get _ocultas => (Config.i.lista('ocultas') ?? const <String>[]).toSet();

  /// Apps de la fila que siguen instaladas y no están ocultas, más la tarjeta "Todas" (null) al final.
  List<App?> get _itemsFila {
    final porPaquete = {for (final a in _todas) a.paquete: a};
    final ocultas = _ocultas;
    return [..._fila.where((p) => !ocultas.contains(p)).map((p) => porPaquete[p]).whereType<App>(), null];
  }

  List<App> get _todasVisibles {
    if (Config.i.logico('mostrar_ocultas')) return _todas;
    final ocultas = _ocultas;
    return _todas.where((a) => !ocultas.contains(a.paquete)).toList();
  }

  bool get _hayMusica => _musica != null && Config.i.logico('musica_visible', true);

  List<String> get _itemsArriba =>
      [if (_hayMusica) ...['musica', 'anterior', 'pausa', 'siguiente'], 'volumen', 'wifi', 'ajustes'];

  void _guardarFila() => Config.i.poner('fila', List.of(_fila));

  // ---------- teclado / control remoto ----------

  static final _ok = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  };

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    final k = e.logicalKey;
    if (_ok.contains(k)) {
      if (e is KeyDownEvent) {
        _okPresionado = DateTime.now();
        _okLargoUsado = false;
      } else if (e is KeyRepeatEvent && !_okLargoUsado && _okPresionado != null &&
          DateTime.now().difference(_okPresionado!) > const Duration(milliseconds: 550)) {
        _okLargoUsado = true;
        _accionLarga();
      } else if (e is KeyUpEvent) {
        if (!_okLargoUsado) _aceptar();
        _okPresionado = null;
      }
      return KeyEventResult.handled;
    }
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.contextMenu || k == LogicalKeyboardKey.info) {
      if (e is KeyDownEvent) _accionLarga();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.browserBack) {
      if (e is KeyDownEvent) _atras();
      return KeyEventResult.handled;
    }
    final dx = k == LogicalKeyboardKey.arrowRight ? 1 : (k == LogicalKeyboardKey.arrowLeft ? -1 : 0);
    final dy = k == LogicalKeyboardKey.arrowDown ? 1 : (k == LogicalKeyboardKey.arrowUp ? -1 : 0);
    if (dx == 0 && dy == 0) return KeyEventResult.ignored;
    setState(() => _mover(dx, dy));
    return KeyEventResult.handled;
  }

  void _mover(int dx, int dy) {
    switch (_modal) {
      case Modal.volumen:
        if (dx != 0) {
          _ponerVolumen((_volumen + dx * 5).clamp(0, 100), false);
        } else if (dy != 0) {
          _modal = Modal.ninguno;
          if (dy > 0) _zona = Zona.fila;
        }
      case Modal.menu:
        if (dy != 0) _iMenu = (_iMenu + dy).clamp(0, _opcionesMenu.length - 1);
      case Modal.todas:
        const c = TodasLasApps.columnas;
        if (_todasVisibles.isEmpty) return;
        final n = (_iTodas + dx + dy * c).clamp(0, _todasVisibles.length - 1);
        if (dy < 0 && _iTodas < c) return;
        _iTodas = n;
        _desplazarTodas();
      case Modal.ajustes:
        break;
      case Modal.ninguno:
        if (_zona == Zona.fila) {
          if (dy < 0) {
            _zona = Zona.arriba;
            _iArriba = _itemsArriba.indexOf('volumen');
          } else if (dx != 0) {
            _iFila = (_iFila + dx).clamp(0, _itemsFila.length - 1);
            _desplazarFila();
          }
        } else {
          if (dy > 0) {
            _zona = Zona.fila;
          } else if (dx != 0) {
            _iArriba = (_iArriba + dx).clamp(0, _itemsArriba.length - 1);
          }
        }
    }
  }

  void _ponerVolumen(int volumen, bool silencio) {
    Config.i.anotar({'volumen': volumen, 'silencio': silencio});
    Nativo.ponerVolumen(volumen, silencio);
  }

  void _aceptar() {
    setState(() {
      switch (_modal) {
        case Modal.volumen:
          _ponerVolumen(_volumen, !_silencio);
        case Modal.menu:
          _ejecutarMenu(_opcionesMenu[_iMenu]);
        case Modal.todas:
          if (_todasVisibles.isNotEmpty) Nativo.abrirApp(_todasVisibles[_iTodas].paquete);
        case Modal.ajustes:
          break;
        case Modal.ninguno:
          if (_zona == Zona.fila) {
            final app = _itemsFila[_iFila];
            if (app == null) {
              _modal = Modal.todas;
              _iTodas = 0;
            } else {
              Nativo.abrirApp(app.paquete);
            }
          } else {
            switch (_itemsArriba[_iArriba]) {
              case 'musica':
                Nativo.abrirMusica(_musica!.paquete);
              case 'anterior' || 'pausa' || 'siguiente':
                Nativo.controlMusica(_musica!.paquete, _itemsArriba[_iArriba]);
              case 'volumen':
                _modal = Modal.volumen;
              case 'wifi':
                Nativo.abrirWifi();
              case 'ajustes':
                _modal = Modal.ajustes;
            }
          }
      }
    });
  }

  void _accionLarga() {
    setState(() {
      if (_modal == Modal.todas && _todasVisibles.isNotEmpty) {
        _appMenu = _todasVisibles[_iTodas];
        _menuDesdeTodas = true;
        _modal = Modal.menu;
        _iMenu = 0;
      } else if (_modal == Modal.ninguno && _zona == Zona.fila && _itemsFila[_iFila] != null) {
        _appMenu = _itemsFila[_iFila];
        _menuDesdeTodas = false;
        _modal = Modal.menu;
        _iMenu = 0;
      }
    });
  }

  void _atras() {
    setState(() {
      if (_modal == Modal.menu && _menuDesdeTodas) {
        _modal = Modal.todas;
      } else if (_modal != Modal.ninguno) {
        _modal = Modal.ninguno;
      } else {
        _zona = Zona.fila;
        _iFila = 0;
        _desplazarFila();
      }
    });
  }

  void _cerrarModal() {
    _modal = Modal.ninguno;
    _foco.requestFocus();
  }

  List<String> get _opcionesMenu {
    final p = _appMenu?.paquete;
    if (_menuDesdeTodas) {
      return [
        _fila.contains(p) ? 'Quitar de inicio' : 'Añadir a inicio',
        _ocultas.contains(p) ? 'Mostrar esta app' : 'Ocultar esta app',
        'Información de la app',
      ];
    }
    return const ['Mover a la izquierda', 'Mover a la derecha', 'Quitar de inicio', 'Ocultar esta app', 'Información de la app'];
  }

  void _ejecutarMenu(String opcion) {
    final app = _appMenu!;
    final i = _fila.indexOf(app.paquete);
    switch (opcion) {
      case 'Mover a la izquierda':
      case 'Mover a la derecha':
        final j = i + (opcion.endsWith('izquierda') ? -1 : 1);
        if (i >= 0 && j >= 0 && j < _fila.length) {
          _fila[i] = _fila[j];
          _fila[j] = app.paquete;
          _iFila = _itemsFila.indexOf(app);
          _guardarFila();
          _desplazarFila();
        }
        return; // el menú sigue abierto para mover varias veces
      case 'Añadir a inicio':
        _fila.add(app.paquete);
        _guardarFila();
      case 'Quitar de inicio':
        _fila.remove(app.paquete);
        _guardarFila();
        _iFila = _iFila.clamp(0, _itemsFila.length - 1);
      case 'Ocultar esta app':
        Config.i.poner('ocultas', [..._ocultas, app.paquete]);
        _iFila = _iFila.clamp(0, _itemsFila.length - 1);
      case 'Mostrar esta app':
        Config.i.poner('ocultas', _ocultas.where((p) => p != app.paquete).toList());
      case 'Información de la app':
        Nativo.abrirInfo(app.paquete);
    }
    _modal = _menuDesdeTodas ? Modal.todas : Modal.ninguno;
  }

  void _desplazarFila() {
    if (!_scrollFila.hasClients) return;
    final paso = _lado + separacion;
    final objetivo = (_iFila * paso - 3 * paso).clamp(0.0, _scrollFila.position.maxScrollExtent);
    _scrollFila.animateTo(objetivo, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }

  void _desplazarTodas() {
    if (!_scrollTodas.hasClients) return;
    final fila = _iTodas ~/ TodasLasApps.columnas;
    final alto = _scrollTodas.position.viewportDimension;
    // ancho útil 1280 - 128 de márgenes - 28 de relleno; 8 columnas con 22 de espacio; celdas de 0.8 de proporción
    const anchoCelda = (1280 - 128 - 28 - 7 * 22) / TodasLasApps.columnas;
    const altoFila = anchoCelda / .8 + 22;
    final objetivo = (fila * altoFila - alto / 3).clamp(0.0, _scrollTodas.position.maxScrollExtent);
    _scrollTodas.animateTo(objetivo, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  // ---------- interfaz ----------

  @override
  Widget build(BuildContext context) {
    final arriba = _modal == Modal.ninguno && _zona == Zona.arriba;
    final items = _itemsFila;
    final todas = _todasVisibles;
    final cfg = Config.i;
    final conNombres = cfg.nombres != 'nunca';
    final altoFila = _lado + 40 + (conNombres ? 28 : 0);
    final oscurecer = cfg.entero('fondo_oscurecer');
    final posicion = cfg.texto('fila_posicion', 'abajo');
    // el panel de ajustes tapa el inicio: así no se dibuja debajo cada vez que se pulsa una tecla
    final tapado = _modal == Modal.ajustes;
    return PopScope(
      canPop: false,
      child: Focus(
        focusNode: _foco,
        autofocus: true,
        onKeyEvent: _tecla,
        child: Lienzo(
          child: Stack(children: [
            // Cada zona va en su propia capa (RepaintBoundary): lo que no cambia, Skia lo guarda ya
            // dibujado y al moverse por la fila solo se redibujan las tarjetas que cambian.
            // sombras para que se lea sobre cualquier video
            const Positioned.fill(
              child: RepaintBoundary(child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x66000000), Color(0x00000000), Color(0x00000000), Color(0xB3000000)],
                    stops: [0, .2, .55, 1],
                  ),
                ),
              )),
            ),
            if (oscurecer > 0)
              Positioned.fill(child: ColoredBox(color: Color.fromRGBO(0, 0, 0, oscurecer / 100))),
            if (_hayMusica)
              Positioned(
                left: 44,
                top: 30,
                child: Offstage(offstage: tapado, child: RepaintBoundary(
                    child: Reproduciendo(musica: _musica!, foco: arriba ? _itemsArriba[_iArriba] : null))),
              ),
            Positioned(
              right: 48,
              top: 34,
              child: Offstage(offstage: tapado, child: RepaintBoundary(child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                IconoBarra(
                  icono: iconoVolumen(_volumen, _silencio),
                  tachado: _silencio,
                  enfocado: (arriba && _itemsArriba[_iArriba] == 'volumen') || _modal == Modal.volumen,
                ),
                const SizedBox(width: 6),
                IconoBarra(icono: iconoRed(_red, _nivelRed), enfocado: arriba && _itemsArriba[_iArriba] == 'wifi'),
                const SizedBox(width: 6),
                IconoBarra(icono: Icons.settings_rounded, enfocado: arriba && _itemsArriba[_iArriba] == 'ajustes'),
                if (cfg.logico('reloj_visible', true)) ...[
                  const SizedBox(width: 18),
                  const RepaintBoundary(child: Reloj()),
                ],
              ]))),
            ),
            if (_modal == Modal.volumen)
              Positioned(
                  right: 48,
                  top: 88,
                  child: RepaintBoundary(child: PanelVolumen(volumen: _volumen, silencio: _silencio))),
            Positioned(
              left: 0,
              right: 0,
              // arriba deja libre la barra; al centro y abajo se calcula desde el borde inferior
              top: posicion == 'arriba' ? 104 : null,
              bottom: posicion == 'arriba' ? null : (posicion == 'centro' ? (720 - altoFila) / 2 : 52),
              height: altoFila,
              child: Offstage(offstage: tapado, child: ListView.separated(
                controller: _scrollFila,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 20),
                clipBehavior: Clip.none,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: separacion),
                itemBuilder: (_, i) {
                  final enfocada = _modal == Modal.ninguno && _zona == Zona.fila && i == _iFila;
                  final app = items[i];
                  final activa = enfocada || (_modal == Modal.menu && app != null && app == _appMenu);
                  final tarjeta = app == null
                      ? TarjetaTodas(enfocada: enfocada, lado: _lado)
                      : TarjetaApp(app: app, enfocada: activa, lado: _lado);
                  if (!conNombres) return tarjeta;
                  final verNombre = cfg.nombres == 'siempre' || activa;
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    tarjeta,
                    const SizedBox(height: 10),
                    SizedBox(
                      width: _lado,
                      height: 18,
                      child: verNombre
                          ? Text(app?.nombre ?? 'Todas',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Tema.texto, fontSize: 13, shadows: Tema.sombraTexto))
                          : null,
                    ),
                  ]);
                },
              )),
            ),
            if (_modal == Modal.todas || (_modal == Modal.menu && _menuDesdeTodas))
              Positioned.fill(
                child: TodasLasApps(
                  apps: todas,
                  enInicio: _fila.toSet(),
                  ocultas: _ocultas,
                  indice: _iTodas,
                  scroll: _scrollTodas,
                ),
              ),
            if (_modal == Modal.menu && _appMenu != null)
              // se abre en un sitio donde cabe aunque la fila esté arriba o las tarjetas sean grandes
              Positioned(
                left: 64,
                top: 120,
                child: MenuOpciones(titulo: _appMenu!.nombre, opciones: _opcionesMenu, indice: _iMenu),
              ),
            if (_modal == Modal.ajustes)
              Positioned.fill(
                child: RepaintBoundary(child: PanelAjustes(alCerrar: () => setState(_cerrarModal))),
              ),
          ]),
        ),
      ),
    );
  }
}
