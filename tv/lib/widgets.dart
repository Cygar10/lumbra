// Lumbra — launcher para Android TV basado en FLauncher (GPL-3.0).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'native.dart';
import 'sombras.dart';
import 'config.dart';

const separacion = 26.0;

/// Tarjeta de app con el mismo estilo para todas: fondo oscuro del tema y el logo al centro.
class TarjetaApp extends StatelessWidget {
  final App app;
  final bool enfocada;
  final bool marcada;
  final double lado;

  /// atenuada: app oculta que se está viendo en «Todas las apps»
  final bool atenuada;

  const TarjetaApp(
      {super.key, required this.app, required this.enfocada, this.marcada = false, required this.lado, this.atenuada = false});

  @override
  Widget build(BuildContext context) {
    final cfg = Config.i;
    final curva = lado * cfg.formaTarjeta;
    final radio = BorderRadius.circular(curva);
    Widget logo;
    if (app.propio != null) {
      // logo propio enviado desde la PC: ya viene centrado y sin fondo
      // vienen a 512 px: se decodifican a 256 (la tarjeta enfocada mide ~128) y ocupan la cuarta parte
      logo = Image.memory(app.propio!, cacheWidth: 256, filterQuality: FilterQuality.medium, gaplessPlayback: true);
    } else if (app.logo != null) {
      logo = Image.memory(app.logo!, filterQuality: FilterQuality.medium, gaplessPlayback: true);
    } else {
      logo = Center(
        child: Text(app.nombre.characters.first.toUpperCase(),
            style: TextStyle(color: Tema.texto, fontSize: lado * .4, fontWeight: FontWeight.w700)),
      );
    }

    return AnimatedScale(
      scale: enfocada && cfg.escalaEnfoque ? 1.14 : 1,
      duration: cfg.ligero ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: ConSombra(
        radio: curva,
        brillo: BoxShadow(color: Tema.brillo(), blurRadius: 26, spreadRadius: 1),
        brilla: enfocada && cfg.brilloEnfoque,
        sombras: const [BoxShadow(color: Color(0x88000000), blurRadius: 14, offset: Offset(0, 6))],
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: lado,
        height: lado,
        decoration: BoxDecoration(
          borderRadius: radio,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Tema.tarjetaArriba, Tema.tarjetaAbajo],
          ),
          // a 720p un borde de 1 px se ve dentado en las curvas; 1.5 px tenue se ve liso
          border: Border.all(
            color: enfocada ? Tema.rojo : Tema.brillo(0x40),
            width: enfocada ? 2.5 : 1.5,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // los logos ya traen el margen transparente: no hace falta recortarlos (un recorte cuesta en cada cuadro)
            if (atenuada) Opacity(opacity: .35, child: logo) else logo,
            if (marcada)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(color: Tema.rojo, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Tarjeta "Todas las apps" al final de la fila.
class TarjetaTodas extends StatelessWidget {
  final bool enfocada;
  final double lado;
  const TarjetaTodas({super.key, required this.enfocada, required this.lado});

  @override
  Widget build(BuildContext context) => AnimatedScale(
        scale: enfocada && Config.i.escalaEnfoque ? 1.14 : 1,
        duration: Config.i.ligero ? Duration.zero : const Duration(milliseconds: 180),
        child: ConSombra(
          radio: lado * Config.i.formaTarjeta,
          brillo: BoxShadow(color: Tema.brillo(), blurRadius: 26),
          brilla: enfocada && Config.i.brilloEnfoque,
          duracion: Duration.zero,
          child: Container(
            width: lado,
            height: lado,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(lado * Config.i.formaTarjeta),
              color: Tema.panel.withAlpha(0x99),
              border: Border.all(color: enfocada ? Tema.rojo : Tema.brillo(0x33), width: enfocada ? 2.5 : 1),
            ),
            child: Icon(Icons.apps_rounded, color: Tema.texto, size: lado * .41),
          ),
        ),
      );
}

// ---------------- barra superior ----------------

class Reloj extends StatefulWidget {
  const Reloj({super.key});

  @override
  State<Reloj> createState() => _RelojState();
}

class _RelojState extends State<Reloj> {
  Timer? _timer;
  DateTime _ahora = DateTime.now();

  @override
  void initState() {
    super.initState();
    _programar();
  }

  void _programar() {
    final espera = Duration(seconds: 60 - DateTime.now().second);
    _timer = Timer(espera, () {
      if (!mounted) return;
      setState(() => _ahora = DateTime.now());
      _programar();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static const _dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
  static const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

  @override
  Widget build(BuildContext context) {
    final cfg = Config.i;
    final h = cfg.reloj24 ? _ahora.hour : (_ahora.hour % 12 == 0 ? 12 : _ahora.hour % 12);
    final m = _ahora.minute.toString().padLeft(2, '0');
    final sufijo = _ahora.hour < 12 ? 'a. m.' : 'p. m.';
    final hora = ShaderMask(
      shaderCallback: (r) => Tema.degradadoReloj.createShader(r),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('$h:$m',
              style: const TextStyle(
                  color: Colors.white, fontSize: 40, fontWeight: FontWeight.w300, letterSpacing: 1, height: 1)),
          if (!cfg.reloj24) ...[
            const SizedBox(width: 6),
            Text(sufijo,
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w500, height: 1)),
          ],
        ],
      ),
    );
    if (!cfg.logico('reloj_fecha')) return hora;
    return Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
      hora,
      const SizedBox(height: 3),
      Text('${_dias[_ahora.weekday - 1]} ${_ahora.day} ${_meses[_ahora.month - 1]}',
          style: TextStyle(color: Tema.texto, fontSize: 14, shadows: Tema.sombraTexto)),
    ]);
  }
}

/// Icono redondo de la barra de arriba (volumen, wifi, ajustes).
class IconoBarra extends StatelessWidget {
  final IconData icono;
  final bool enfocado;
  final bool tachado;

  const IconoBarra({super.key, required this.icono, required this.enfocado, this.tachado = false});

  @override
  Widget build(BuildContext context) => ConSombra(
        circulo: true,
        brillo: BoxShadow(color: Tema.brillo(), blurRadius: 16),
        brilla: enfocado,
        duracion: const Duration(milliseconds: 150),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enfocado ? Tema.rojo : Colors.transparent,
          ),
          child: Icon(icono,
              size: 22,
              color: enfocado ? Colors.white : (tachado ? Tema.rojo : Tema.textoSuave),
              shadows: Tema.sombraTexto),
        ),
      );
}

IconData iconoVolumen(int volumen, bool silencio) {
  if (silencio || volumen == 0) return Icons.volume_off_rounded;
  if (volumen < 40) return Icons.volume_down_rounded;
  return Icons.volume_up_rounded;
}

IconData iconoRed(String tipo, int nivel) {
  switch (tipo) {
    case 'ethernet':
      return Icons.settings_ethernet_rounded;
    case 'wifi':
      return const [
        Icons.network_wifi_1_bar_rounded,
        Icons.network_wifi_2_bar_rounded,
        Icons.network_wifi_3_bar_rounded,
        Icons.wifi_rounded,
      ][nivel.clamp(0, 3)];
    case 'none':
      return Icons.wifi_off_rounded;
    default:
      return Icons.public_rounded;
  }
}

/// Panel que baja del icono de volumen: ←/→ sube o baja, OK silencia.
class PanelVolumen extends StatelessWidget {
  final int volumen;
  final bool silencio;

  const PanelVolumen({super.key, required this.volumen, required this.silencio});

  @override
  Widget build(BuildContext context) => ConSombra(
        radio: 18,
        sombras: const [BoxShadow(color: Color(0xAA000000), blurRadius: 30)],
        child: Container(
        width: 330,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
        decoration: BoxDecoration(
          color: Tema.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Tema.brillo(0x55)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(iconoVolumen(volumen, silencio), color: silencio ? Tema.rojo : Tema.texto, size: 24),
              const SizedBox(width: 10),
              Text('Sonido del fondo', style: TextStyle(color: Tema.texto, fontSize: 17, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(silencio ? 'Silencio' : '$volumen %',
                  style: TextStyle(color: silencio ? Tema.rojo : Tema.textoSuave, fontSize: 16)),
            ]),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                child: Stack(children: [
                  Container(color: const Color(0x33FFFFFF)),
                  FractionallySizedBox(
                    widthFactor: silencio ? 0 : volumen / 100,
                    child: Container(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [Tema.rojoOscuro, Tema.brasa])),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Text('←  →  ajustar      OK  silenciar',
                style: TextStyle(color: Tema.textoSuave, fontSize: 12.5, letterSpacing: .3)),
          ],
        ),
      ),
      );
}

// ---------------- música ----------------

class Reproduciendo extends StatelessWidget {
  final Musica musica;

  /// qué parte tiene el foco: 'musica' (abrir la app), 'anterior', 'pausa', 'siguiente' o null
  final String? foco;

  const Reproduciendo({super.key, required this.musica, required this.foco});

  bool get enfocado => foco == 'musica';

  Widget _boton(IconData icono, String id, {double tam = 24}) {
    final activo = foco == id;
    return ConSombra(
      circulo: true,
      brillo: BoxShadow(color: Tema.brillo(), blurRadius: 14),
      brilla: activo,
      duracion: const Duration(milliseconds: 140),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: activo ? Tema.rojo : const Color(0x22FFFFFF),
        ),
        child: Icon(icono, size: tam, color: activo ? Colors.white : Tema.texto),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ConSombra(
        radio: 16,
        brillo: BoxShadow(color: Tema.brillo(0x88), blurRadius: 20),
        brilla: enfocado,
        sombras: const [BoxShadow(color: Color(0x66000000), blurRadius: 16)],
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(maxWidth: 600),
        padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
        decoration: BoxDecoration(
          color: Tema.panel.withAlpha(0xB3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: enfocado ? Tema.rojo : Tema.brillo(0x33), width: enfocado ? 2 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 56,
              height: 56,
              child: musica.portada != null
                  ? Image.memory(musica.portada!, fit: BoxFit.cover, gaplessPlayback: true)
                  : Container(color: Tema.tarjetaArriba, child: Icon(Icons.music_note_rounded, color: Tema.rojo)),
            ),
          ),
          const SizedBox(width: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 270),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(musica.titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Tema.texto, fontSize: 17, fontWeight: FontWeight.w600)),
                if (musica.artista != null)
                  Text(musica.artista!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Tema.textoSuave, fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // se mueve 15 veces por segundo: en su propia capa para no redibujar el resto de la tarjeta
          RepaintBoundary(child: Barras(activas: musica.sonando)),
          const SizedBox(width: 14),
          _boton(Icons.skip_previous_rounded, 'anterior'),
          const SizedBox(width: 6),
          _boton(musica.sonando ? Icons.pause_rounded : Icons.play_arrow_rounded, 'pausa', tam: 26),
          const SizedBox(width: 6),
          _boton(Icons.skip_next_rounded, 'siguiente'),
        ]),
      ),
      );
}

/// Ecualizador animado mientras suena la música.
class Barras extends StatefulWidget {
  final bool activas;
  const Barras({super.key, required this.activas});

  @override
  State<Barras> createState() => _BarrasState();
}

class _BarrasState extends State<Barras> {
  // 15 cuadros por segundo: a 60 la TV redibujaba toda la pantalla sin parar mientras sonaba música
  static const _paso = Duration(milliseconds: 66);
  Timer? _timer;
  double _valor = 0;

  @override
  void initState() {
    super.initState();
    _ajustar();
  }

  @override
  void didUpdateWidget(Barras old) {
    super.didUpdateWidget(old);
    _ajustar();
  }

  void _ajustar() {
    if (widget.activas && !Config.i.ligero && _timer == null) {
      _timer = Timer.periodic(_paso, (_) => setState(() => _valor = (_valor + 66 / 1400) % 1));
    } else if (!widget.activas || Config.i.ligero) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(4, (i) {
            final t = _valor * 2 * math.pi;
            final alto = widget.activas ? 6 + 16 * (0.5 + 0.5 * math.sin(t * (1 + i * .37) + i * 1.7)).abs() : 5.0;
            return Container(
              width: 4,
              height: alto,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(color: Tema.rojo, borderRadius: BorderRadius.circular(2)),
            );
          }),
        );
}

// ---------------- menús ----------------

class MenuOpciones extends StatelessWidget {
  final String titulo;
  final List<String> opciones;
  final int indice;

  const MenuOpciones({super.key, required this.titulo, required this.opciones, required this.indice});

  @override
  Widget build(BuildContext context) => ConSombra(
        radio: 18,
        sombras: const [BoxShadow(color: Color(0xAA000000), blurRadius: 30)],
        child: Container(
        width: 360,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Tema.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Tema.brillo(0x55)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
            child: Text(titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Tema.textoSuave, fontSize: 14, letterSpacing: .4)),
          ),
          for (var i = 0; i < opciones.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: i == indice ? Tema.rojo : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(opciones[i],
                  style: TextStyle(
                      color: i == indice ? Colors.white : Tema.texto, fontSize: 17, fontWeight: FontWeight.w500)),
            ),
        ]),
      ),
      );
}

/// Cuadrícula con todas las apps instaladas (las de inicio llevan un punto de color).
class TodasLasApps extends StatelessWidget {
  static const columnas = 8;
  final List<App> apps;
  final Set<String> enInicio;
  final Set<String> ocultas;
  final int indice;
  final ScrollController scroll;

  const TodasLasApps(
      {super.key, required this.apps, required this.enInicio, required this.ocultas, required this.indice, required this.scroll});

  @override
  Widget build(BuildContext context) => Container(
        color: Tema.fondoTodas,
        padding: const EdgeInsets.fromLTRB(64, 40, 64, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Todas las apps',
              style: TextStyle(color: Tema.texto, fontSize: 30, fontWeight: FontWeight.w300, letterSpacing: 1)),
          const SizedBox(height: 4),
          Text('OK abre  ·  mantén OK o MENÚ para ver más opciones',
              style: TextStyle(color: Tema.textoSuave, fontSize: 14)),
          const SizedBox(height: 18),
          Expanded(
            child: GridView.builder(
              controller: scroll,
              padding: const EdgeInsets.all(14),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columnas,
                mainAxisSpacing: 22,
                crossAxisSpacing: 22,
                childAspectRatio: .8,
              ),
              itemCount: apps.length,
              itemBuilder: (_, i) => Column(children: [
                TarjetaApp(
                    app: apps[i],
                    enfocada: i == indice,
                    marcada: enInicio.contains(apps[i].paquete),
                    atenuada: ocultas.contains(apps[i].paquete),
                    lado: 104),
                const SizedBox(height: 10),
                Text(apps[i].nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: i == indice ? Tema.texto : Tema.textoSuave, fontSize: 13)),
              ]),
            ),
          ),
        ]),
      );
}
