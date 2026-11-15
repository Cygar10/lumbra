"""Genera los temas de iconos de Lumbra a partir de los iconos oficiales de cada app.

    python temas/generar.py

Lee temas/fuentes/<paquete>.png (el icono de la app, 512 px) y escribe:

    temas/color/   el logo con los colores de la marca, sin el cuadro de fondo
    temas/blanco/  el logo en blanco (también lo usa el tema «Tono del tema», que la TV pinta)
    temas/marca/   el icono original completo, que en la TV llena toda la tarjeta
    temas/indice.json  la lista que la TV consulta para descargar los temas

Para añadir una app: deja su icono en temas/fuentes con el nombre de su paquete y vuelve a
ejecutar esto. Las apps que no estén en un tema se ven con el logo automático de la TV.
Necesita Pillow (pip install pillow).
"""
import json
import os
import shutil

from PIL import Image

AQUI = os.path.dirname(os.path.abspath(__file__))
FUENTES = os.path.join(AQUI, "fuentes")
LADO = 512

NOMBRES = {
    "com.netflix.ninja": "Netflix",
    "com.google.android.youtube.tv": "YouTube",
    "com.google.android.youtube.tvmusic": "YouTube Music",
    "com.amazon.amazonvideo.livingroom": "Prime Video",
    "com.disney.disneyplus": "Disney+",
    "com.wbd.stream": "Max",
    "com.crunchyroll.crunchyroid": "Crunchyroll",
    "com.spotify.tv.android": "Spotify",
    "com.plexapp.android": "Plex",
    "org.videolan.vlc": "VLC",
    "tv.twitch.android.app": "Twitch",
    "org.xbmc.kodi": "Kodi",
    "com.cbs.ott": "Paramount+",
    "com.apple.atve.androidtv.appletv": "Apple TV",
    "com.google.android.videos": "Google TV",
    "com.google.android.youtube.tvkids": "YouTube Kids",
    "tv.pluto.android": "Pluto TV",
    "com.tubitv": "Tubi",
    "com.univision.prendetv": "ViX",
    "com.peacocktv.peacockandroid": "Peacock",
    "com.hulu.livingroomplus": "Hulu",
    "com.dazn": "DAZN",
    "com.espn.score_center": "ESPN",
    "deezer.android.tv": "Deezer",
    "com.amazon.music.tv": "Amazon Music",
    "com.apple.android.music": "Apple Music",
    "ar.tvplayer.tv": "TiviMate",
    "org.jellyfin.androidtv": "Jellyfin",
    "com.stremio.one": "Stremio",
    "com.mubi": "MUBI",
    "com.esaba.downloader": "Downloader",
}

# casos que la regla general no resuelve bien
#   blanco: el logo es blanco sobre un fondo con degradado: se separa por lo blanco que es
#   claro: el logo es claro (de cualquier color) sobre un fondo oscuro con degradado
#   sin_negro: las partes negras del logo se vuelven huecos (el contorno de Twitch)
#   claro_desde: con «claro», desde qué brillo cuenta como logo (por defecto 75)
#   huecos_desde: qué tan blanco debe ser algo para volverse hueco (por defecto 170)
#   huecos: en el tema blanco, las partes blancas del logo se vuelven huecos (como el ▶ de YouTube)
#   oscuro: el logo es oscuro sobre un fondo claro con degradado (Amazon Music)
#   amarillo: el logo es amarillo sobre un fondo con degradado (Tubi)
#   tono: color con que se pinta el logo en el tema «color» (por defecto, el del fondo si es vivo)
AJUSTES = {
    "com.disney.disneyplus": {"blanco": True},
    "com.wbd.stream": {"blanco": True},
    "com.apple.atve.androidtv.appletv": {"claro": True, "huecos": False},
    "com.plexapp.android": {"claro": True, "huecos": False},
    "org.xbmc.kodi": {"huecos": True, "huecos_desde": 200},
    "tv.twitch.android.app": {"sin_negro": True},
    "com.google.android.youtube.tv": {"huecos": True},
    "com.google.android.youtube.tvmusic": {"huecos": True},
    "org.videolan.vlc": {"huecos": True},
    "com.univision.prendetv": {"blanco": True},
    "ar.tvplayer.tv": {"claro": True, "claro_desde": 115, "huecos": False},
    "com.apple.android.music": {"oscuro": True},
    "com.peacocktv.peacockandroid": {"claro": True, "huecos": False},
    "org.jellyfin.androidtv": {"claro": True, "huecos": False},
    "com.amazon.music.tv": {"oscuro": True, "tono": (37, 209, 218)},
    "com.tubitv": {"amarillo": True},
    "com.google.android.youtube.tvkids": {"huecos": True},
}

TEMAS = [
    {"id": "color", "nombre": "Color", "carpeta": "color", "filtro": "ninguno", "relleno": False,
     "descripcion": "Cada logo con los colores de su marca"},
    {"id": "blanco", "nombre": "Blanco", "carpeta": "blanco", "filtro": "blanco", "relleno": False,
     "descripcion": "Todos los logos en blanco, limpio y uniforme"},
    {"id": "acento", "nombre": "Tono del tema", "carpeta": "blanco", "filtro": "acento", "relleno": False,
     "descripcion": "Los logos con el color de tema que elijas"},
    {"id": "marca", "nombre": "Iconos originales", "carpeta": "marca", "filtro": "ninguno", "relleno": True,
     "descripcion": "El icono completo de cada app llenando la tarjeta"},
]


def _pixeles(im):
    return im.get_flattened_data() if hasattr(im, "get_flattened_data") else im.getdata()


def _borde(im):
    """Colores del borde del icono, para saber si tiene un fondo de un solo color."""
    px = im.load()
    w, h = im.size
    return [px[x, y] for x in range(0, w, 8) for y in (1, h - 2)] + \
           [px[x, y] for y in range(0, h, 8) for x in (1, w - 2)]


def _quitar_color(im, fondo):
    """«Color a transparencia»: cada píxel pierde la parte que se mezcló con el fondo.

    Así los bordes quedan suaves (semitransparentes) en vez de dentados o con un halo del color
    del fondo, y los huecos del logo (que tienen el color del fondo) quedan transparentes.
    """
    datos = []
    for r, g, b, a in _pixeles(im):
        alfa = 0.0
        for c, f in ((r, fondo[0]), (g, fondo[1]), (b, fondo[2])):
            if c > f:
                alfa = max(alfa, (c - f) / (255 - f))
            elif c < f:
                alfa = max(alfa, (f - c) / f)
        # el ruido de compresión del fondo no debe quedar como una neblina
        alfa = min(1.0, max(0.0, (alfa - 0.05) / 0.95))
        if alfa <= 0:
            datos.append((0, 0, 0, 0))
            continue
        color = tuple(min(255, max(0, round((c - f * (1 - alfa)) / alfa))) for c, f in zip((r, g, b), fondo))
        datos.append(color + (round(alfa * a),))
    salida = Image.new("RGBA", im.size)
    salida.putdata(datos)
    return salida


def _solo_lo_blanco(im):
    """Logo blanco sobre un fondo con degradado: la transparencia sale de lo blanco que es cada píxel."""
    datos = []
    for r, g, b, a in _pixeles(im):
        alfa = min(1.0, max(0.0, (min(r, g, b) - 130) / 110))
        datos.append((255, 255, 255, round(alfa * a)))
    salida = Image.new("RGBA", im.size)
    salida.putdata(datos)
    return salida


def _por_alfa(im, alfa_de, color):
    """Logo de un solo color sobre un fondo con degradado, con una regla propia para la transparencia."""
    datos = []
    for r, g, b, a in _pixeles(im):
        alfa = min(1.0, max(0.0, alfa_de(r, g, b)))
        datos.append(color + (round(alfa * a),))
    salida = Image.new("RGBA", im.size)
    salida.putdata(datos)
    return salida


def _solo_lo_claro(im, desde=75):
    """Logo claro de cualquier color sobre un fondo oscuro con degradado (Apple TV, Plex)."""
    datos = []
    for r, g, b, a in _pixeles(im):
        alfa = min(1.0, max(0.0, (max(r, g, b) - desde) / 110))
        if alfa <= 0:
            datos.append((0, 0, 0, 0))
            continue
        datos.append(tuple(min(255, round(c / max(alfa, .6))) for c in (r, g, b)) + (round(alfa * a),))
    salida = Image.new("RGBA", im.size)
    salida.putdata(datos)
    return salida



def extraer(paquete, icono):
    """El logo sin el cuadro de fondo, y el color de ese fondo (o None si no era de un color)."""
    ajuste = AJUSTES.get(paquete, {})
    borde = _borde(icono)
    if ajuste.get("blanco"):
        return _solo_lo_blanco(icono), None
    if ajuste.get("claro"):
        return _solo_lo_claro(icono, ajuste.get("claro_desde", 75)), None
    if ajuste.get("oscuro"):
        return _por_alfa(icono, lambda r, g, b: (170 - max(r, g, b)) / 110, (20, 20, 20)), ajuste.get("tono")
    if ajuste.get("amarillo"):
        return _por_alfa(icono, lambda r, g, b: (min(r, g) - b - 60) / 110, (255, 233, 0)), None
    if sum(1 for c in borde if c[3] < 40) > len(borde) * .8:
        return icono, None  # ya viene sin fondo (YouTube, Kodi…)
    # el tono medio del borde: con un degradado suave (Apple TV, Plex) también sirve
    fondo = sorted(borde, key=lambda c: c[0] + c[1] + c[2])[len(borde) // 2][:3]
    return _quitar_color(icono, fondo), fondo


def centrar(logo, ocupar=.50, maximo=.80):
    """Recorta lo transparente y lo centra. Se iguala el área visible, no el ancho: así una
    palabra larga (NETFLIX) y un símbolo cuadrado (Spotify) se ven del mismo «peso»."""
    caja = logo.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    if not caja:
        return Image.new("RGBA", (LADO, LADO))
    recorte = logo.crop(caja)
    w, h = recorte.size
    escala = min(LADO * ocupar / (w * h) ** .5, LADO * maximo / max(w, h))
    nuevo = recorte.resize((max(1, round(w * escala)), max(1, round(h * escala))), Image.LANCZOS)
    lienzo = Image.new("RGBA", (LADO, LADO))
    lienzo.alpha_composite(nuevo, ((LADO - nuevo.width) // 2, (LADO - nuevo.height) // 2))
    return lienzo


def _brillo(c):
    return .299 * c[0] + .587 * c[1] + .114 * c[2]


def _medidas(logo):
    """Qué parte del logo es blanca, oscura o de color (solo píxeles visibles)."""
    blancos = oscuros = colores = 0
    for r, g, b, a in _pixeles(logo):
        if a < 128:
            continue
        if min(r, g, b) > 215:
            blancos += 1
        elif _brillo((r, g, b)) < 60:
            oscuros += 1
        else:
            colores += 1
    total = max(1, blancos + oscuros + colores)
    return blancos / total, oscuros / total, colores / total


def _sin_negro(logo):
    alfa = Image.new("L", logo.size)
    alfa.putdata([round(a * min(1.0, max(0.0, (_brillo((r, g, b)) - 40) / 80))) for r, g, b, a in _pixeles(logo)])
    logo = logo.copy()
    logo.putalpha(alfa)
    return logo


def _pintar(logo, color):
    r, g, b = color
    return Image.merge("RGBA", (Image.new("L", logo.size, r), Image.new("L", logo.size, g),
                                Image.new("L", logo.size, b), logo.getchannel("A")))


def version_color(logo, fondo):
    """Sobre la tarjeta oscura: un logo blanco o negro se pinta con el color de la marca."""
    blancos, oscuros, _ = _medidas(logo)
    vivo = fondo and max(fondo) - min(fondo) > 90 and _brillo(fondo) > 60
    if vivo and (blancos > .85 or oscuros > .6):
        return _pintar(logo, fondo)
    if oscuros > .6:
        return _pintar(logo, (235, 235, 235))
    return logo


def version_blanca(paquete, logo):
    blancos, _, colores = _medidas(logo)
    huecos = AJUSTES.get(paquete, {}).get("huecos")
    if huecos is None:
        huecos = colores > .3 and blancos > .03
    alfa = logo.getchannel("A")
    if huecos:
        # lo blanco que va dentro del logo (el ▶ de YouTube) queda como hueco, con borde suave
        no_blanco = Image.new("L", logo.size)
        desde = AJUSTES.get(paquete, {}).get("huecos_desde", 170)
        no_blanco.putdata([255 - min(255, max(0, (min(r, g, b) - desde) * 255 // max(1, 255 - desde) * 2))
                           for r, g, b, _ in _pixeles(logo)])
        alfa = Image.composite(alfa, Image.new("L", logo.size), no_blanco)
    # un azul claro sobre blanco queda medio transparente al quitar el fondo: en blanco se ve gris
    alfa = alfa.point(lambda v: min(255, v * 8 // 5))
    return Image.merge("RGBA", (Image.new("L", logo.size, 255),) * 3 + (alfa,))


def version_marca(icono):
    """El icono entero. Los que vienen sin fondo (YouTube, Kodi) se agrandan para llenar igual que los demás."""
    caja = icono.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    if caja and caja != (0, 0, LADO, LADO):
        recorte = icono.crop(caja)
        escala = LADO * .94 / max(recorte.size)
        recorte = recorte.resize((round(recorte.width * escala), round(recorte.height * escala)), Image.LANCZOS)
        icono = Image.new("RGBA", (LADO, LADO))
        icono.alpha_composite(recorte, ((LADO - recorte.width) // 2, (LADO - recorte.height) // 2))
    return icono.resize((384, 384), Image.LANCZOS)


def main():
    for carpeta in ("color", "blanco", "marca"):
        shutil.rmtree(os.path.join(AQUI, carpeta), ignore_errors=True)
        os.makedirs(os.path.join(AQUI, carpeta))
    apps = []
    for archivo in sorted(os.listdir(FUENTES)):
        paquete, ext = os.path.splitext(archivo)
        if ext.lower() != ".png":
            continue
        icono = Image.open(os.path.join(FUENTES, archivo)).convert("RGBA").resize((LADO, LADO), Image.LANCZOS)
        logo, fondo = extraer(paquete, icono)
        if AJUSTES.get(paquete, {}).get("sin_negro"):
            logo = _sin_negro(logo)
        centrar(version_color(logo, fondo)).save(os.path.join(AQUI, "color", archivo), optimize=True)
        centrar(version_blanca(paquete, logo)).save(os.path.join(AQUI, "blanco", archivo), optimize=True)
        version_marca(icono).save(os.path.join(AQUI, "marca", archivo), optimize=True)
        apps.append(paquete)
        print("listo:", NOMBRES.get(paquete, paquete))
    indice = {"version": 1, "temas": [{**t, "apps": apps} for t in TEMAS]}
    with open(os.path.join(AQUI, "indice.json"), "w", encoding="utf-8") as f:
        json.dump(indice, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
