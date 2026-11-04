# Lumbra

Launcher para Android TV con fondos de video o imagen, salvapantallas propio y mucha personalización, pensado para ir fluido incluso en TV con 1 GB de RAM.

Son dos piezas, y solo la primera es necesaria:

| Pieza | Para qué | ¿Hace falta? |
|---|---|---|
| **Launcher** (`tv/`) | La pantalla de inicio de la TV | Sí |
| **Programa de PC** (`pc/`) | Convierte videos para que la TV los reproduzca fluidos y se los envía | No, es opcional |

## Qué puedes personalizar

Desde el engrane en la pantalla de inicio de la TV:

- **Fondo:** video o imagen de los archivos de la TV o de un USB, un color o nada. Puedes pausar el video, cambiar su sonido u oscurecerlo.
- **Apariencia:** color del tema, tamaño y forma de las tarjetas, nombres de las apps y posición de la fila.
- **Reloj:** 12 o 24 horas, con fecha o sin ella, o sin reloj.
- **Apps:** ordenar, ocultar y volver a mostrar.
- **Salvapantallas:** el de Lumbra o el de tu TV; carpeta de fotos, tiempo por foto, zoom y hora.
- **Modo ligero:** para TV con poca memoria. El video queda como imagen fija y sin sonido, y las tarjetas no se agrandan ni brillan.

## Instalación

Necesitas una TV con Android TV o Google TV y activar en ella las **Opciones de desarrollador** y la **Depuración inalámbrica** (o USB).

### Opción A: con el programa de PC (lo más fácil)

1. Instala [FFmpeg](https://ffmpeg.org/download.html) y [ADB](https://developer.android.com/tools/releases/platform-tools).
2. Descarga de la sección **Releases** `Lumbra.exe` y `lumbra.apk`, y déjalos en la misma carpeta.
3. Abre `Lumbra.exe` con doble clic. Se abre en tu navegador; para cerrarlo, pulsa **Salir**. En Linux o macOS instala [Python 3.10 o superior](https://www.python.org/downloads/) y ejecuta `python3 pc/app.py`.
4. **Solo la primera vez:** pulsa **Emparejar** y escribe la IP, el puerto y el código que muestra la TV en «Emparejar dispositivo con código».
5. Escribe la IP y el puerto de la pantalla principal de Depuración inalámbrica y pulsa **Conectar**.
6. Pulsa **Instalar en la TV**. También deja a Lumbra como pantalla de inicio y le da sus permisos.

Luego pulsa **Añadir carpeta** para elegir dónde tienes tus videos o fotos. No hay rutas que configurar: si tienes Wallpaper Engine lo detecta solo, y si no lo tienes, no hace falta.

### Opción B: solo con ADB

```bash
adb connect IP_DE_LA_TV:PUERTO
```

```bash
adb install lumbra.apk
```

```bash
adb shell cmd package set-home-activity com.lumbra.tv/.MainActivity
```

```bash
adb shell cmd notification allow_listener com.lumbra.tv/.MediaListener
```

El último comando es opcional: permite mostrar lo que está sonando en la pantalla de inicio.

## Salvapantallas

Tiene dos modos, que se eligen en **Personalizar → Salvapantallas**:

- **El de la TV:** Lumbra no toca nada. Es lo predeterminado.
- **El de Lumbra:** pasa las fotos de la carpeta que elijas. Puedes usar cualquier carpeta de la TV o de un USB, o pulsar **Subir fotos al salvapantallas** en el programa de PC. El zoom es opcional (normal, lento, rápido o sin zoom) y se calcula en la propia TV, así que funciona con cualquier foto.

Las fotos siempre se ven en HD: se dibujan a la resolución real de la pantalla, hasta 1080p, aunque la TV muestre su interfaz a 720p. Para que se vean nítidas, usa fotos de 1920x1080 o más; el programa de PC te avisa si alguna es más pequeña.

Si tu TV no deja elegir salvapantallas, Lumbra lo abre por sí mismo tras el tiempo que indiques, aunque solo mientras estés en la pantalla de inicio.

## Compilar

Con [Flutter](https://docs.flutter.dev/get-started/install):

```bash
cd tv
```

```bash
flutter build apk --release --target-platform android-arm,android-arm64
```

Para crear `Lumbra.exe` desde `pc/`:

```bash
pyinstaller --onefile --noconsole --name Lumbra --add-data "web;web" app.py
```

Para medir el rendimiento en la TV: `flutter build apk --release --dart-define=MEDIR=true` escribe en el registro cuánto tarda cada cuadro.

## Licencia y créditos

GPL-3.0, ver [LICENSE](LICENSE). El launcher parte de [FLauncher](https://gitlab.com/flauncher/flauncher), © 2021 Étienne Fesser.

Lumbra no incluye fondos ni fotos. Wallpaper Engine es un producto de sus autores y no tiene relación con este proyecto; respeta las licencias del contenido que uses.
