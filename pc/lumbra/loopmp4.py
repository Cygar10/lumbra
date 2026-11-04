"""Reescribe el índice (moov) de un MP4 para repetirlo N veces sin duplicar el video.

convert.py lo usa con N=1 para dejar el audio del bucle listo para repetirse:
el launcher repite el video solo (modo «repetir uno» de ExoPlayer) y la unión
no debe sonar. Con N>1 el archivo apunta N
veces a los mismos bytes del mdat: crece unos KB en lugar de N veces el clip.

Requisitos del clip de entrada: una pista de video sin B-frames (sin ctts), GOP
cerrado, como mucho una pista de audio y moov al final (sin +faststart), para
que los offsets del mdat no cambien al agrandar el moov.

Audio: AAC decodifica cada frame mezclándolo con el anterior, así que repetir
un clip de audio normal deja un chasquido en la unión. convert.py codifica el
audio del bucle tres veces seguidas (audio_triple=True) y aquí solo se usa la
copia del medio: su primer frame ya se codificó a continuación del final del
bucle, igual que lo que el decodificador tendrá antes al repetirse.
"""
import struct

CONTENEDORES = {b"moov", b"trak", b"mdia", b"minf", b"stbl", b"edts", b"dinf"}


def _leer_cajas(data, inicio, fin):
    cajas = []
    i = inicio
    while i < fin:
        tam, tipo = struct.unpack(">I4s", data[i:i + 8])
        cab = 8
        if tam == 1:
            tam = struct.unpack(">Q", data[i + 8:i + 16])[0]
            cab = 16
        elif tam == 0:
            tam = fin - i
        cajas.append([tipo, data[i + cab:i + tam]])
        i += tam
    return cajas


def _arbol(data):
    """Convierte una caja contenedora en lista [tipo, hijos|bytes]."""
    nodos = []
    for tipo, cuerpo in _leer_cajas(data, 0, len(data)):
        nodos.append([tipo, _arbol(cuerpo) if tipo in CONTENEDORES else cuerpo])
    return nodos


def _serializar(nodos):
    out = bytearray()
    for tipo, cuerpo in nodos:
        if isinstance(cuerpo, list):
            cuerpo = _serializar(cuerpo)
        out += struct.pack(">I4s", len(cuerpo) + 8, tipo) + cuerpo
    return bytes(out)


def _buscar(nodos, tipo):
    for n in nodos:
        if n[0] == tipo:
            return n
    return None


# posición del campo de duración en mvhd / tkhd / mdhd, según la versión de la caja
_POS_DUR = {0: {b"mvhd": 16, b"mdhd": 16, b"tkhd": 20},
            1: {b"mvhd": 24, b"mdhd": 24, b"tkhd": 28}}


def _dur(nodo):
    v = nodo[1][0]
    p = _POS_DUR[v][nodo[0]]
    return struct.unpack(">Q" if v else ">I", nodo[1][p:p + (8 if v else 4)])[0]


def _poner_dur(nodo, valor):
    v = nodo[1][0]
    p = _POS_DUR[v][nodo[0]]
    if not v and valor > 0xFFFFFFFF:
        raise ValueError("Demasiadas repeticiones para un MP4 versión 0")
    b = bytearray(nodo[1])
    b[p:p + (8 if v else 4)] = struct.pack(">Q" if v else ">I", valor)
    nodo[1] = bytes(b)


def _tabla(cuerpo, fmt_entrada):
    """Lee una tabla full-box: (cabecera, lista de tuplas)."""
    cab = cuerpo[:4]
    cuenta = struct.unpack(">I", cuerpo[4:8])[0]
    t = struct.calcsize(fmt_entrada)
    filas = [struct.unpack(fmt_entrada, cuerpo[8 + i * t: 8 + (i + 1) * t]) for i in range(cuenta)]
    return cab, filas


def _escribir_tabla(cab, filas, fmt_entrada):
    return cab + struct.pack(">I", len(filas)) + b"".join(struct.pack(fmt_entrada, *f) for f in filas)


def _partes(trak):
    mdia = _buscar(trak, b"mdia")[1]
    stbl = _buscar(_buscar(mdia, b"minf")[1], b"stbl")[1]
    tipo = _buscar(mdia, b"hdlr")[1][8:12]
    return mdia, stbl, tipo


def _tamanos(stbl):
    n = _buscar(stbl, b"stsz")[1]
    fijo, cuenta = struct.unpack(">II", n[4:12])
    if fijo:
        return [fijo] * cuenta
    return list(struct.unpack(f">{cuenta}I", n[12:12 + 4 * cuenta]))


def _offsets_chunks(stbl):
    n = _buscar(stbl, b"stco") or _buscar(stbl, b"co64")
    return n, (">I" if n[0] == b"stco" else ">Q")


def _repetir_video(stbl, veces):
    """Repite la tabla completa: los mismos chunks N veces."""
    if _buscar(stbl, b"ctts"):
        raise ValueError("El clip no debe tener B-frames (ctts)")
    n_stts = _buscar(stbl, b"stts")
    cab, filas = _tabla(n_stts[1], ">II")
    n_stts[1] = _escribir_tabla(cab, filas * veces, ">II")
    total_muestras = sum(c for c, _ in filas)

    n_stss = _buscar(stbl, b"stss")
    if n_stss:
        cab, filas = _tabla(n_stss[1], ">I")
        nuevas = [(s + k * total_muestras,) for k in range(veces) for (s,) in filas]
        n_stss[1] = _escribir_tabla(cab, nuevas, ">I")

    n_stsz = _buscar(stbl, b"stsz")
    cab = n_stsz[1][:4]
    tam_fijo, cuenta = struct.unpack(">II", n_stsz[1][4:12])
    if tam_fijo:
        n_stsz[1] = cab + struct.pack(">II", tam_fijo, cuenta * veces)
    else:
        n_stsz[1] = cab + struct.pack(">II", 0, cuenta * veces) + n_stsz[1][12:12 + 4 * cuenta] * veces

    n_stco, fmt_off = _offsets_chunks(stbl)
    cab, offs = _tabla(n_stco[1], fmt_off)
    n_chunks = len(offs)
    n_stco[1] = _escribir_tabla(cab, offs * veces, fmt_off)

    n_stsc = _buscar(stbl, b"stsc")
    cab, filas = _tabla(n_stsc[1], ">III")
    nuevas = [(primero + k * n_chunks, spc, desc) for k in range(veces) for (primero, spc, desc) in filas]
    n_stsc[1] = _escribir_tabla(cab, nuevas, ">III")


def _repetir_audio(stbl, desde, cuantas, veces):
    """Toma las muestras [desde, desde+cuantas) y las repite, una muestra por chunk."""
    tamanos = _tamanos(stbl)
    n_stco, fmt_off = _offsets_chunks(stbl)
    cab_co, chunks = _tabla(n_stco[1], fmt_off)
    cab_sc, stsc = _tabla(_buscar(stbl, b"stsc")[1], ">III")
    # offset de cada muestra a partir de chunks + stsc
    offsets, i = [], 0
    for c, (off,) in enumerate(chunks, start=1):
        spc = next(s for (primero, s, _) in reversed(stsc) if primero <= c)
        for _ in range(spc):
            offsets.append(off)
            off += tamanos[i]
            i += 1
    cab_tt, stts = _tabla(_buscar(stbl, b"stts")[1], ">II")
    deltas = [d for (c, d) in stts for _ in range(c)]
    if desde + cuantas > len(tamanos):
        raise ValueError("El audio es más corto que el video")

    sel = range(desde, desde + cuantas)
    runs = []
    for d in [deltas[j] for j in sel] * veces:
        if runs and runs[-1][1] == d:
            runs[-1][0] += 1
        else:
            runs.append([1, d])
    _buscar(stbl, b"stts")[1] = _escribir_tabla(cab_tt, runs, ">II")
    n_stsz = _buscar(stbl, b"stsz")
    n_stsz[1] = (n_stsz[1][:4] + struct.pack(">II", 0, cuantas * veces)
                 + struct.pack(f">{cuantas}I", *[tamanos[j] for j in sel]) * veces)
    n_stco[1] = _escribir_tabla(cab_co, [(offsets[j],) for j in sel] * veces, fmt_off)
    _buscar(stbl, b"stsc")[1] = _escribir_tabla(cab_sc, [(1, 1, stsc[0][2])], ">III")
    # AAC no lleva stss; los grupos de muestras (roll) dejarían de cuadrar
    stbl[:] = [n for n in stbl if n[0] not in (b"stss", b"sbgp", b"sgpd")]
    return sum(deltas[j] for j in sel) * veces


def _retraso_inicial(trak):
    """Muestras de relleno al inicio del AAC según la lista de edición (normalmente 1024)."""
    edts = _buscar(trak, b"edts")
    elst = edts and _buscar(edts[1], b"elst")
    if not elst:
        return 0
    v = elst[1][0]
    cuenta = struct.unpack(">I", elst[1][4:8])[0]
    ancho = 20 if v else 12
    for k in range(cuenta):
        entrada = elst[1][8 + k * ancho:8 + (k + 1) * ancho]
        media_time = struct.unpack(">q" if v else ">i", entrada[8:16] if v else entrada[4:8])[0]
        if media_time >= 0:  # -1 = tramo vacío
            return media_time
    return 0


def repetir(entrada, salida, veces, audio_triple=False):
    with open(entrada, "rb") as f:
        data = f.read()
    cajas = _leer_cajas(data, 0, len(data))
    tipos = [c[0] for c in cajas]
    if tipos.index(b"moov") < tipos.index(b"mdat"):
        raise ValueError("El clip debe tener el moov al final (sin +faststart)")

    moov = _arbol(next(c[1] for c in cajas if c[0] == b"moov"))
    traks = {}
    for n in moov:
        if n[0] == b"trak":
            traks.setdefault(_partes(n[1])[2], []).append(n)
    if len(traks.get(b"vide", [])) != 1 or len(traks.get(b"soun", [])) > 1 or len(traks) > 2:
        raise ValueError("El clip debe tener una pista de video y como mucho una de audio")

    escala_mov = struct.unpack(">I", _buscar(moov, b"mvhd")[1][(20 if _buscar(moov, b"mvhd")[1][0] else 12):][:4])[0]
    t_video = traks[b"vide"][0]
    mdia_v, stbl_v, _ = _partes(t_video[1])
    n_mdhd_v = _buscar(mdia_v, b"mdhd")
    escala_v = struct.unpack(">I", n_mdhd_v[1][(20 if n_mdhd_v[1][0] else 12):][:4])[0]
    dur_v = _dur(n_mdhd_v)
    _repetir_video(stbl_v, veces)
    _poner_dur(n_mdhd_v, dur_v * veces)
    dur_mov = round(dur_v * escala_mov / escala_v) * veces
    _poner_dur(_buscar(t_video[1], b"tkhd"), dur_mov)

    if b"soun" in traks:
        t_audio = traks[b"soun"][0]
        mdia_a, stbl_a, _ = _partes(t_audio[1])
        n_mdhd_a = _buscar(mdia_a, b"mdhd")
        escala_a = struct.unpack(">I", n_mdhd_a[1][(20 if n_mdhd_a[1][0] else 12):][:4])[0]
        _, stts = _tabla(_buscar(stbl_a, b"stts")[1], ">II")
        por_muestra = stts[0][1]
        # cuántas muestras de audio dura un bucle de video (convert.py hace que sea exacto)
        cuantas = round(dur_v / escala_v * escala_a / por_muestra)
        desde = 0
        if audio_triple:
            desde = round(_retraso_inicial(t_audio[1]) / por_muestra) + cuantas
        _poner_dur(n_mdhd_a, _repetir_audio(stbl_a, desde, cuantas, veces))
        _poner_dur(_buscar(t_audio[1], b"tkhd"), dur_mov)

    _poner_dur(_buscar(moov, b"mvhd"), dur_mov)
    # las listas de edición recortarían la duración (o el relleno del AAC): se quitan
    for lista in traks.values():
        for n in lista:
            n[1] = [h for h in n[1] if h[0] != b"edts"]

    nuevo_moov = _serializar([[b"moov", moov]])
    # todo lo anterior al moov se copia byte a byte para no mover el mdat
    inicio_moov = 0
    while data[inicio_moov + 4:inicio_moov + 8] != b"moov":
        tam = struct.unpack(">I", data[inicio_moov:inicio_moov + 4])[0]
        if tam == 1:
            tam = struct.unpack(">Q", data[inicio_moov + 8:inicio_moov + 16])[0]
        inicio_moov += tam
    fin_moov = inicio_moov + struct.unpack(">I", data[inicio_moov:inicio_moov + 4])[0]
    with open(salida, "wb") as f:
        f.write(data[:inicio_moov])
        f.write(nuevo_moov)
        f.write(data[fin_moov:])
