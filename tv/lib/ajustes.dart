// Lumbra — launcher para Android TV basado en FLauncher (GPL-3.0).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'native.dart';

/// Una fila de ajustes. Con [cambiar] se mueve con ←/→ y OK avanza; con [accion] OK la ejecuta.
class Opcion {
  final String titulo;
  final String? ayuda;
  final String Function()? valor;
  final void Function(int direccion)? cambiar;
  final VoidCallback? accion;
  final Color Function()? muestra;

  const Opcion(this.titulo, {this.ayuda, this.valor, this.cambiar, this.accion, this.muestra});
}

class Seccion {
  final String titulo;
  final IconData icono;
  final List<Opcion> Function() opciones;
  const Seccion(this.titulo, this.icono, this.opciones);
}

/// Pantalla de personalización. No se toca nada detrás de ella mientras está abierta, salvo el
/// propio fondo y los colores, para ver cada cambio al momento.
class PanelAjustes extends StatefulWidget {
  final VoidCallback alCerrar;
  const PanelAjustes({super.key, required this.alCerrar});

  @override
  State<PanelAjustes> createState() => _PanelAjustesState();
}

/// Lo que se está eligiendo en el explorador de archivos.
enum _Eleccion { fondo, carpetaSalva }

class _PanelAjustesState extends State<PanelAjustes> {
  final _foco = FocusNode();
  final _scroll = ScrollController();
  int _seccion = 0;
  int _fila = 0;
  bool _enFilas = false;
  _Eleccion? _eleccion;
  Map _salva = {};

  Config get c => Config.i;

  @override
  void initState() {
    super.initState();
    _leerSalva();
    _pedirFoco();
  }

  // autofocus no basta: el launcher ya tiene el foco y no lo cedería
  void _pedirFoco() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _foco.requestFocus();
      });

  Future<void> _leerSalva() async {
    final info = await Nativo.infoSalva();
    if (mounted) setState(() => _salva = info);
  }

  @override
  void dispose() {
    _foco.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------- ayudas para declarar opciones ----------

  Opcion _interruptor(String titulo, String clave, {bool porDefecto = false, String? ayuda}) {
    void alternar(int _) => c.poner(clave, !c.logico(clave, porDefecto));
    return Opcion(titulo,
        ayuda: ayuda, valor: () => c.logico(clave, porDefecto) ? 'Sí' : 'No', cambiar: alternar);
  }

  Opcion _elegir(String titulo, String clave, Map<String, String> valores, {String? ayuda, VoidCallback? despues}) {
    final claves = valores.keys.toList();
    return Opcion(titulo,
        ayuda: ayuda,
        valor: () => valores[c.texto(clave, claves.first)] ?? valores[claves.first]!,
        cambiar: (d) {
          final i = claves.indexOf(c.texto(clave, claves.first));
          c.poner(clave, claves[(i + d) % claves.length]);
          despues?.call();
        });
  }

  Opcion _numero(String titulo, String clave, List<int> pasos, String Function(int) texto, {String? ayuda}) => Opcion(titulo,
      ayuda: ayuda,
      valor: () => texto(c.entero(clave, pasos.first)),
      cambiar: (d) {
        var i = pasos.indexOf(c.entero(clave, pasos.first));
        if (i < 0) i = 0;
        c.poner(clave, pasos[(i + d).clamp(0, pasos.length - 1)]);
      });

  static String _nombreDe(String ruta) => ruta.split('/').last;

  String get _descripcionFondo => switch (c.texto('fondo_tipo', 'archivo')) {
        'color' => 'Color',
        'ninguno' => 'Sin fondo',
        _ => c.texto('fondo_ruta').isEmpty ? 'Sin elegir' : _nombreDe(c.texto('fondo_ruta')),
      };

  static const _coloresFondo = {
    'Noche': 0xFF12080A,
    'Negro': 0xFF000000,
    'Grafito': 0xFF1B1D22,
    'Azul noche': 0xFF0B1426,
    'Bosque': 0xFF0B1F17,
    'Vino': 0xFF2A0A12,
  };

  // ---------- secciones ----------

  late final List<Seccion> _secciones = [
    Seccion('Fondo', Icons.wallpaper_rounded, () {
      final esVideo = RegExp(r'\.(mp4|mkv|webm|mov|m4v|avi|ts)$', caseSensitive: false).hasMatch(c.texto('fondo_ruta'));
      final conArchivo = c.texto('fondo_tipo', 'archivo') == 'archivo';
      return [
        Opcion('Elegir video o imagen', ayuda: 'De los archivos de la TV o de una memoria USB', valor: () => _descripcionFondo, accion: () => _abrirExplorador(_Eleccion.fondo)),
        _elegir('Tipo de fondo', 'fondo_tipo', const {'archivo': 'Video o imagen', 'color': 'Color', 'ninguno': 'Sin fondo'}),
        if (c.texto('fondo_tipo') == 'color')
          Opcion('Color del fondo',
              valor: () => _coloresFondo.entries
                  .firstWhere((e) => e.value == c.entero('fondo_color'), orElse: () => _coloresFondo.entries.first)
                  .key,
              muestra: () => Color(c.entero('fondo_color', 0xFF12080A)),
              cambiar: (d) {
                final v = _coloresFondo.values.toList();
                final i = v.indexOf(c.entero('fondo_color', v.first));
                c.poner('fondo_color', v[(i + d) % v.length]);
              }),
        if (conArchivo && esVideo) _interruptor('Pausar el video', 'fondo_pausado', ayuda: 'Queda una imagen fija y no suena'),
        if (conArchivo && esVideo)
          _numero('Sonido del fondo', 'volumen', [for (var v = 0; v <= 100; v += 5) v], (v) => v == 0 ? 'Sin sonido' : '$v %'),
        _numero('Oscurecer el fondo', 'fondo_oscurecer', const [0, 15, 30, 45, 60, 75], (v) => v == 0 ? 'No' : '$v %',
            ayuda: 'Para que se lean mejor los iconos'),
      ];
    }),
    Seccion('Apariencia', Icons.palette_rounded, () => [
          Opcion('Color del tema',
              valor: () => c.acentoNombre,
              muestra: () => Tema.rojo,
              cambiar: (d) {
                final v = Config.colores.values.toList();
                final i = v.indexOf(c.entero('acento', v.first));
                c.poner('acento', v[(i + d) % v.length]);
              }),
          _elegir('Tamaño de las tarjetas', 'tarjeta_tam', const {'M': 'Medianas', 'S': 'Pequeñas', 'L': 'Grandes'}),
          _elegir('Forma de las tarjetas', 'tarjeta_forma', const {'redondeada': 'Redondeadas', 'cuadrada': 'Cuadradas', 'circulo': 'Círculos'}),
          _elegir('Nombre de las apps', 'tarjeta_nombres', const {'nunca': 'No mostrar', 'enfocada': 'Solo la elegida', 'siempre': 'Siempre'}),
          _elegir('Posición de la fila', 'fila_posicion', const {'abajo': 'Abajo', 'centro': 'Al centro', 'arriba': 'Arriba'}),
          _interruptor('Agrandar la tarjeta elegida', 'enfoque_escala', porDefecto: true),
          _interruptor('Brillo en la tarjeta elegida', 'enfoque_brillo', porDefecto: true),
        ]),
    Seccion('Reloj', Icons.schedule_rounded, () => [
          _interruptor('Mostrar reloj', 'reloj_visible', porDefecto: true),
          _elegir('Formato de hora', 'reloj_formato', const {'12': '12 horas (a. m. / p. m.)', '24': '24 horas'}),
          _interruptor('Mostrar la fecha', 'reloj_fecha'),
        ]),
    Seccion('Apps', Icons.apps_rounded, () => [
          _interruptor('Tarjeta de música', 'musica_visible', porDefecto: true, ayuda: 'Muestra lo que está sonando y sus controles'),
          _interruptor('Ver apps ocultas', 'mostrar_ocultas', ayuda: 'En «Todas las apps», para volver a mostrarlas'),
          const Opcion('Ordenar y ocultar apps',
              ayuda: 'Mantén OK sobre una app: en la fila la mueves, y en «Todas las apps» la añades, quitas u ocultas'),
        ]),
    Seccion('Salvapantallas', Icons.photo_library_rounded, () {
      final propio = c.texto('salva_motor', 'sistema') == 'lumbra';
      return [
        _elegir('Usar', 'salva_motor', const {'sistema': 'El de la TV', 'lumbra': 'El de Lumbra'}, despues: _leerSalva),
        if (propio) ...[
          Opcion('Carpeta de fotos',
              ayuda: '${_salva['photos'] ?? 0} fotos encontradas',
              valor: () => c.texto('salva_carpeta').isEmpty ? 'La enviada desde la PC' : _nombreDe(c.texto('salva_carpeta')),
              accion: () => _abrirExplorador(_Eleccion.carpetaSalva)),
          _numero('Tiempo por foto', 'salva_segundos', const [10, 15, 20, 30, 60, 120, 300], (v) => v < 60 ? '$v s' : '${v ~/ 60} min'),
          _elegir('Zoom de las fotos', 'salva_zoom', const {'normal': 'Normal', 'lento': 'Lento', 'rapido': 'Rápido', 'no': 'Sin zoom'}),
          _elegir('Orden', 'salva_orden', const {'azar': 'Al azar', 'nombre': 'Por nombre'}),
          _interruptor('Mostrar la hora', 'salva_reloj', porDefecto: true),
          if (_salva['activeInSystem'] == true)
            const Opcion('Cuándo se activa', ayuda: 'Se cambia en los ajustes de la TV')
          else
            _numero('Activar sin usar la TV tras', 'salva_minutos', const [5, 10, 15, 20, 30, 45, 60], (v) => '$v min'),
          Opcion('Probar ahora', accion: Nativo.probarSalva),
        ],
        Opcion('Ajustes de salvapantallas de la TV',
            ayuda: propio && _salva['activeInSystem'] != true ? 'Si aparece Lumbra en la lista, elígelo: así también funciona con otras apps abiertas' : null,
            accion: Nativo.abrirAjustesSalva),
      ];
    }),
    Seccion('General', Icons.tune_rounded, () => [
          _interruptor('Abrir Lumbra al encender', 'abrir_al_encender',
              ayuda: 'La TV siempre empieza aquí, no en la última entrada o app que tenías abierta'),
          _interruptor('Modo ligero', 'modo_ligero',
              ayuda: 'Para TV con poca memoria: el video queda como imagen fija y sin sonido, y las tarjetas no se agrandan ni brillan'),
          Opcion('Ajustes de la TV', accion: Nativo.abrirAjustes),
          Opcion('Restablecer apariencia y fondo', ayuda: 'Se conservan el archivo de fondo y tus apps', accion: () async {
            c.cargar(await Nativo.restablecer());
            setState(() => _fila = 0);
          }),
        ]),
  ];

  // ---------- control remoto ----------

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.handled;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.browserBack) {
      if (e is KeyDownEvent) _atras();
      return KeyEventResult.handled;
    }
    final opciones = _secciones[_seccion].opciones();
    setState(() {
      if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
        final d = k == LogicalKeyboardKey.arrowDown ? 1 : -1;
        if (_enFilas) {
          _fila = (_fila + d).clamp(0, opciones.length - 1);
          _desplazar();
        } else {
          _seccion = (_seccion + d).clamp(0, _secciones.length - 1);
          _fila = 0;
        }
      } else if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.arrowLeft) {
        final d = k == LogicalKeyboardKey.arrowRight ? 1 : -1;
        if (!_enFilas) {
          if (d > 0) _enFilas = true;
        } else {
          final o = opciones[_fila.clamp(0, opciones.length - 1)];
          if (o.cambiar != null) {
            o.cambiar!(d);
            _ajustarFila();
          } else if (d < 0) {
            _enFilas = false;
          }
        }
      } else if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
        if (e is! KeyDownEvent) return;
        if (!_enFilas) {
          _enFilas = true;
        } else {
          final o = opciones[_fila.clamp(0, opciones.length - 1)];
          if (o.accion != null) {
            o.accion!();
          } else if (o.cambiar != null) {
            o.cambiar!(1);
            _ajustarFila();
          }
        }
      }
    });
    return KeyEventResult.handled;
  }

  // al cambiar una opción pueden aparecer o desaparecer otras
  void _ajustarFila() {
    final n = _secciones[_seccion].opciones().length;
    _fila = _fila.clamp(0, n - 1);
  }

  void _atras() {
    if (_enFilas) {
      setState(() => _enFilas = false);
    } else {
      widget.alCerrar();
    }
  }

  void _desplazar() {
    if (!_scroll.hasClients) return;
    final objetivo = (_fila * 74.0 - 180).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(objetivo, duration: const Duration(milliseconds: 160), curve: Curves.easeOut);
  }

  // ---------- explorador ----------

  Future<void> _abrirExplorador(_Eleccion eleccion) async {
    final permiso = await Nativo.pedirPermisoArchivos();
    if (!mounted) return;
    if (!permiso) {
      setState(() => _sinPermiso = true);
      return;
    }
    setState(() {
      _sinPermiso = false;
      _eleccion = eleccion;
    });
  }

  bool _sinPermiso = false;

  void _cerrarExplorador() {
    setState(() => _eleccion = null);
    _pedirFoco();
    _leerSalva();
  }

  // ---------- interfaz ----------

  @override
  Widget build(BuildContext context) {
    if (_eleccion != null) {
      final soloCarpeta = _eleccion == _Eleccion.carpetaSalva;
      return Explorador(
        soloCarpeta: soloCarpeta,
        titulo: soloCarpeta ? 'Elige la carpeta de fotos' : 'Elige un video o una imagen',
        alCerrar: _cerrarExplorador,
        alElegir: (ruta) {
          if (soloCarpeta) {
            c.poner('salva_carpeta', ruta);
          } else {
            c.poner('fondo_tipo', 'archivo');
            c.poner('fondo_pausado', false);
            c.poner('fondo_ruta', ruta);
          }
          _cerrarExplorador();
        },
      );
    }
    final opciones = _secciones[_seccion].opciones();
    final actual = _enFilas && opciones.isNotEmpty ? opciones[_fila.clamp(0, opciones.length - 1)] : null;
    return Focus(
      focusNode: _foco,
      autofocus: true,
      onKeyEvent: _tecla,
      child: Container(
        // deja ver el fondo a la derecha para comprobar los cambios
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Tema.fondoTodas, Tema.fondoTodas, Tema.fondoTodas.withAlpha(0xB0)]),
        ),
        padding: const EdgeInsets.fromLTRB(56, 40, 56, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Personalizar', style: TextStyle(color: Tema.texto, fontSize: 30, fontWeight: FontWeight.w300, letterSpacing: 1)),
          const SizedBox(height: 22),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 270,
                child: Column(children: [
                  for (var i = 0; i < _secciones.length; i++)
                    _FilaSeccion(seccion: _secciones[i], enfocada: !_enFilas && i == _seccion, activa: i == _seccion),
                ]),
              ),
              const SizedBox(width: 34),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  itemCount: opciones.length,
                  itemBuilder: (_, i) => _FilaOpcion(opcion: opciones[i], enfocada: _enFilas && i == _fila),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Text(
            _sinPermiso
                ? 'La TV no dio permiso para leer archivos. Vuelve a intentarlo o usa el programa de PC.'
                : actual?.cambiar != null
                    ? '←  →  cambiar      ATRÁS  volver'
                    : actual?.accion != null
                        ? 'OK  abrir      ATRÁS  volver'
                        : 'OK  entrar      ATRÁS  salir',
            style: TextStyle(color: _sinPermiso ? Tema.brasa : Tema.textoSuave, fontSize: 14),
          ),
        ]),
      ),
    );
  }
}

class _FilaSeccion extends StatelessWidget {
  final Seccion seccion;
  final bool enfocada;
  final bool activa;
  const _FilaSeccion({required this.seccion, required this.enfocada, required this.activa});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: enfocada ? Tema.rojo : (activa ? const Color(0x22FFFFFF) : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(seccion.icono, size: 24, color: enfocada ? Colors.white : Tema.textoSuave),
          const SizedBox(width: 14),
          Text(seccion.titulo,
              style: TextStyle(color: enfocada ? Colors.white : Tema.texto, fontSize: 18, fontWeight: FontWeight.w500)),
        ]),
      );
}

class _FilaOpcion extends StatelessWidget {
  final Opcion opcion;
  final bool enfocada;
  const _FilaOpcion({required this.opcion, required this.enfocada});

  @override
  Widget build(BuildContext context) {
    final texto = enfocada ? Colors.white : Tema.texto;
    final suave = enfocada ? const Color(0xDDFFFFFF) : Tema.textoSuave;
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: enfocada ? Tema.rojo : const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(opcion.titulo, style: TextStyle(color: texto, fontSize: 18, fontWeight: FontWeight.w500)),
            if (opcion.ayuda != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(opcion.ayuda!, style: TextStyle(color: suave, fontSize: 13)),
              ),
          ]),
        ),
        if (opcion.muestra != null) ...[
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(left: 14, right: 10),
            decoration: BoxDecoration(
              color: opcion.muestra!(),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xAAFFFFFF), width: 1.5),
            ),
          ),
        ],
        if (opcion.valor != null) ...[
          const SizedBox(width: 12),
          if (opcion.cambiar != null) Icon(Icons.chevron_left_rounded, size: 22, color: suave),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(opcion.valor!(),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: texto, fontSize: 16)),
          ),
          if (opcion.cambiar != null) Icon(Icons.chevron_right_rounded, size: 22, color: suave),
        ] else if (opcion.accion != null)
          Icon(Icons.chevron_right_rounded, size: 24, color: suave),
      ]),
    );
  }
}

/// Explorador de archivos manejable con el control remoto, con vista previa de la imagen elegida.
class Explorador extends StatefulWidget {
  final String titulo;
  final bool soloCarpeta;
  final void Function(String ruta) alElegir;
  final VoidCallback alCerrar;

  const Explorador({super.key, required this.titulo, required this.soloCarpeta, required this.alElegir, required this.alCerrar});

  @override
  State<Explorador> createState() => _ExploradorState();
}

class _ExploradorState extends State<Explorador> {
  final _foco = FocusNode();
  final _scroll = ScrollController();
  final _pila = <String>[];
  List<Entrada> _entradas = [];
  int _i = 0;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _raices();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _foco.requestFocus();
    });
  }

  @override
  void dispose() {
    _foco.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _raices() async {
    final raices = await Nativo.raices();
    if (!mounted) return;
    setState(() {
      _pila.clear();
      _entradas = raices;
      _i = 0;
      _cargando = false;
    });
  }

  Future<void> _abrir(String ruta) async {
    setState(() => _cargando = true);
    final lista = await Nativo.listar(ruta);
    if (!mounted) return;
    setState(() {
      _entradas = widget.soloCarpeta ? lista.where((e) => e.tipo == 'dir').toList() : lista;
      _i = 0;
      _cargando = false;
      if (_pila.isEmpty || _pila.last != ruta) _pila.add(ruta);
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  bool get _hayUsarCarpeta => widget.soloCarpeta && _pila.isNotEmpty;
  int get _total => _entradas.length + (_hayUsarCarpeta ? 1 : 0);

  void _atras() {
    if (_pila.isEmpty) {
      widget.alCerrar();
    } else {
      _pila.removeLast();
      if (_pila.isEmpty) {
        _raices();
      } else {
        _abrir(_pila.last);
      }
    }
  }

  void _aceptar() {
    if (_hayUsarCarpeta && _i == 0) {
      widget.alElegir(_pila.last);
      return;
    }
    final indice = _i - (_hayUsarCarpeta ? 1 : 0);
    if (indice < 0 || indice >= _entradas.length) return;
    final e = _entradas[indice];
    if (e.tipo == 'dir') {
      _abrir(e.ruta);
    } else {
      widget.alElegir(e.ruta);
    }
  }

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.handled;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.browserBack || k == LogicalKeyboardKey.arrowLeft) {
      if (e is KeyDownEvent) _atras();
    } else if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter || k == LogicalKeyboardKey.arrowRight) {
      if (e is KeyDownEvent) _aceptar();
    } else if ((k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) && _total > 0) {
      setState(() => _i = (_i + (k == LogicalKeyboardKey.arrowDown ? 1 : -1)).clamp(0, _total - 1));
      if (_scroll.hasClients) {
        _scroll.animateTo((_i * 52.0 - 200).clamp(0.0, _scroll.position.maxScrollExtent),
            duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
      }
    }
    return KeyEventResult.handled;
  }

  static IconData _icono(String tipo) => switch (tipo) {
        'dir' => Icons.folder_rounded,
        'video' => Icons.movie_rounded,
        _ => Icons.image_rounded,
      };

  Widget _fila(String nombre, IconData icono, bool enfocada) => Container(
        height: 46,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: enfocada ? Tema.rojo : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(icono, size: 22, color: enfocada ? Colors.white : Tema.textoSuave),
          const SizedBox(width: 12),
          Expanded(
            child: Text(nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: enfocada ? Colors.white : Tema.texto, fontSize: 16)),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final indice = _i - (_hayUsarCarpeta ? 1 : 0);
    final elegida = indice >= 0 && indice < _entradas.length ? _entradas[indice] : null;
    return Focus(
      focusNode: _foco,
      autofocus: true,
      onKeyEvent: _tecla,
      child: Container(
        color: Tema.fondoTodas,
        padding: const EdgeInsets.fromLTRB(56, 40, 56, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.titulo, style: TextStyle(color: Tema.texto, fontSize: 28, fontWeight: FontWeight.w300)),
          const SizedBox(height: 4),
          Text(_pila.isEmpty ? 'Dispositivos' : _pila.last,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Tema.textoSuave, fontSize: 14)),
          const SizedBox(height: 16),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: _cargando
                    ? const SizedBox.shrink()
                    : _total == 0
                        ? Text('No hay nada que elegir aquí.', style: TextStyle(color: Tema.textoSuave, fontSize: 16))
                        : ListView.builder(
                            controller: _scroll,
                            itemCount: _total,
                            itemExtent: 52,
                            itemBuilder: (_, i) {
                              if (_hayUsarCarpeta && i == 0) return _fila('Usar esta carpeta', Icons.check_circle_rounded, _i == 0);
                              final e = _entradas[i - (_hayUsarCarpeta ? 1 : 0)];
                              return _fila(e.nombre, _icono(e.tipo), i == _i);
                            },
                          ),
              ),
              if (!widget.soloCarpeta) ...[
                const SizedBox(width: 30),
                SizedBox(
                  width: 440,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        color: const Color(0x22FFFFFF),
                        child: elegida?.tipo == 'image'
                            // decodificada al tamaño de la vista previa: una foto de 12 MP no llega a memoria entera
                            ? Image.file(File(elegida!.ruta), key: ValueKey(elegida.ruta), cacheWidth: 440, fit: BoxFit.cover, gaplessPlayback: true,
                                errorBuilder: (_, _, _) => Icon(Icons.broken_image_rounded, color: Tema.textoSuave, size: 48))
                            : Icon(elegida?.tipo == 'video' ? Icons.movie_rounded : Icons.folder_open_rounded, color: Tema.textoSuave, size: 56),
                      ),
                    ),
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 10),
          Text('OK  abrir o elegir      ATRÁS  subir', style: TextStyle(color: Tema.textoSuave, fontSize: 14)),
        ]),
      ),
    );
  }
}
