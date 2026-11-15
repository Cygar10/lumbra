# Lumbra

Launcher para Android TV con fondos de video o imagen, salvapantallas propio y mucha personalización, pensado para ir fluido incluso en TV con 1 GB de RAM.

Son dos piezas, y solo la primera es necesaria:

| Pieza | Para qué | ¿Hace falta? |
|---|---|---|
| **Launcher** (`tv/`, `Lumbra-TV.apk`) | La pantalla de inicio de la TV | Sí |
| **Programa de PC** (`pc/`, `Lumbra-PC.exe`) | Instala el launcher, convierte videos para que la TV los reproduzca fluidos y se los envía | No, es opcional |

## Qué puedes personalizar

Desde el engrane en la pantalla de inicio de la TV:

- **Fondo:** video o imagen de los archivos de la TV o de un USB, un color o nada. Puedes pausar el video, cambiar su sonido u oscurecerlo.
- **Apariencia:** color del tema, tema de iconos, tamaño y forma de las tarjetas, nombres de las apps y posición de la fila.
- **Reloj:** 12 o 24 horas, con fecha o sin ella, o sin reloj.
- **Apps:** ordenar, ocultar, volver a mostrar y ponerle a cualquiera un icono propio.
- **Música:** una tarjeta con lo que suena y sus controles. Indica si suena en la TV o en otro dispositivo (por ejemplo, Spotify en tu teléfono); en ese caso el sonido del fondo no se corta.
- **Salvapantallas:** el de Lumbra o el de tu TV; carpeta de fotos, tiempo por foto, zoom y hora.
- **Modo ligero:** para TV con poca memoria. El video queda como imagen fija y sin sonido, y las tarjetas no se agrandan ni brillan.

## Instalación

Necesitas una TV con Android TV o Google TV y activar en ella las **Opciones de desarrollador** y la **Depuración inalámbrica** (o USB).

### Opción A: con el programa de PC (lo más fácil)

1. Descarga de la sección **Releases** `Lumbra-PC.exe` (el programa del PC) y `Lumbra-TV.apk` (el launcher de la TV), y déjalos en la misma carpeta.
2. Abre `Lumbra-PC.exe` con doble clic. Se abre en su propia ventana, como cualquier programa; para cerrarlo, cierra la ventana.
3. Si te avisa de que falta ADB o FFmpeg, pulsa **Descargar lo que falta**: los baja de sus sitios oficiales y los guarda en la carpeta de datos de Lumbra, sin instalar nada más en tu PC.
4. **Solo la primera vez:** pulsa **Emparejar** y escribe la IP, el puerto y el código que muestra la TV en «Emparejar dispositivo con código».
5. Escribe la IP y el puerto de la pantalla principal de Depuración inalámbrica y pulsa **Conectar**.
6. Pulsa **Instalar en la TV**. También deja a Lumbra como pantalla de inicio y le da sus permisos.

En Linux o macOS no hay ejecutable: instala [Python 3.10 o superior](https://www.python.org/downloads/), [FFmpeg](https://ffmpeg.org/download.html) y [ADB](https://developer.android.com/tools/releases/platform-tools), y ejecuta `python3 pc/app.py`. Con `pip install pywebview` se abre en ventana propia; sin él, en tu navegador.

Luego pulsa **Añadir carpeta** para elegir dónde tienes tus videos o fotos. No hay rutas que configurar: si tienes Wallpaper Engine lo detecta solo, y si no lo tienes, no hace falta.

### Opción B: solo con ADB

```bash
adb connect IP_DE_LA_TV:PUERTO
```

```bash
adb install Lumbra-TV.apk
```

```bash
adb shell cmd package set-home-activity com.lumbra.tv/.MainActivity
```

```bash
adb shell cmd notification allow_listener com.lumbra.tv/.MediaListener
```

El último comando es opcional: permite mostrar lo que está sonando en la pantalla de inicio.

## Iconos

Recién instalado, cada app se ve con su propio logo, recortado sobre la tarjeta. Hay dos formas de cambiarlo:

- **Tema de iconos** (**Personalizar → Apariencia → Tema de iconos**): la TV descarga el tema de este repositorio y se puede quitar cuando quieras. Hay cuatro: **Color** (cada logo con su color de marca), **Blanco**, **Tono del tema** (los logos con el color que elijas) e **Iconos originales** (el icono entero llenando la tarjeta). Traen iconos para las apps más conocidas: Netflix, YouTube, YouTube Music, Prime Video, Disney+, Max, Crunchyroll, Spotify, Plex, VLC, Twitch, Kodi, Paramount+, Apple TV y Google TV. Las demás apps se adaptan al tema con su propio logo.
- **Icono propio para una app**: mantén OK sobre la app y elige **Cambiar icono**. Sirve cualquier imagen de la TV o de un USB: un PNG con fondo transparente se pone al centro de la tarjeta, y una imagen sin transparencia la llena entera.

Para añadir apps a los temas, deja su icono (PNG cuadrado, 512 px) en `temas/fuentes` con el nombre de su paquete y ejecuta `python temas/generar.py`. Los logos son de sus respectivas marcas; se incluyen solo para identificar cada app.

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

Para crear `Lumbra-PC.exe` desde `pc/`:

```bash
pip install -r requirements.txt pyinstaller pillow
```

```bash
pyinstaller --onefile --noconsole --name Lumbra-PC --add-data "web;web" --icon ../tv/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png app.py
```

Para medir el rendimiento en la TV: `flutter build apk --release --dart-define=MEDIR=true` escribe en el registro cuánto tarda cada cuadro.

## Licencia y créditos

GPL-3.0, ver [LICENSE](LICENSE). El launcher parte de [FLauncher](https://gitlab.com/flauncher/flauncher), © 2021 Étienne Fesser.

Lumbra no incluye fondos ni fotos. Los logos de los temas de iconos pertenecen a sus marcas. Wallpaper Engine es un producto de sus autores y no tiene relación con este proyecto; respeta las licencias del contenido que uses.
