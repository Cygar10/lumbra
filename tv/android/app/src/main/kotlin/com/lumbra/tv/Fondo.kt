/*
 * Lumbra — launcher para Android TV basado en FLauncher (GPL-3.0).
 */
package com.lumbra.tv

import android.app.ActivityManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.widget.ImageView
import java.io.File
import java.util.concurrent.Executors

/**
 * Decide qué se ve detrás de la interfaz: video, imagen, color o nada.
 *
 * Al encender la TV todo el sistema está arrancando y apenas queda memoria, así que primero
 * se muestra una imagen fija (un cuadro del video guardado en disco, que no cuesta casi nada)
 * y el video con su sonido arranca cuando la TV se ha calmado.
 */
class Fondo(private val context: Context, private val cuadro: ImageView, private val video: WallpaperPlayer) {
    private val main = Handler(Looper.getMainLooper())
    private val hilo = Executors.newSingleThreadExecutor()
    private var cuadroActual: String? = null
    private var enPrimerPlano = false

    private val intentar = object : Runnable {
        override fun run() {
            if (!enPrimerPlano) return
            if (hayQueEsperar()) main.postDelayed(this, ESPERA_ENTRE_REVISIONES_MS) else aplicarVideo()
        }
    }

    init {
        video.alMostrar = { cuadro.visibility = ImageView.INVISIBLE }
    }

    private fun hayQueEsperar(): Boolean {
        val encendida = SystemClock.elapsedRealtime()
        if (encendida >= ESPERA_MAXIMA_MS) return false
        if (encendida < ESPERA_MINIMA_MS) return true
        val memoria = ActivityManager.MemoryInfo()
        (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memoria)
        return memoria.availMem < MEMORIA_LIBRE_BYTES
    }

    private val tipo get() = Ajustes.texto(context, "fondo_tipo")
    private val ruta get() = Ajustes.texto(context, "fondo_ruta")

    /** Con modo ligero o en pausa el video se queda en su imagen fija y ni se abre el decodificador. */
    private val soloCuadro get() = Ajustes.logico(context, "modo_ligero") || Ajustes.logico(context, "fondo_pausado")

    private fun hayVideo() = tipo == "archivo" && Ajustes.esVideo(ruta) && File(ruta).isFile

    /** Pinta enseguida lo que se pueda y, si toca video, lo arranca cuando la TV esté lista. */
    fun mostrar() {
        enPrimerPlano = true
        main.removeCallbacks(intentar)
        video.enPrimerPlano(true)
        video.ponerVolumen(Ajustes.entero(context, "volumen") / 100f, Ajustes.logico(context, "silencio"))
        when {
            tipo == "color" -> {
                liberarVideo()
                cuadroActual = null
                cuadro.setImageDrawable(null)
                cuadro.setBackgroundColor(Ajustes.entero(context, "fondo_color"))
                cuadro.visibility = ImageView.VISIBLE
            }
            tipo == "archivo" && File(ruta).isFile -> {
                cuadro.setBackgroundColor(Color.BLACK)
                if (hayVideo() && video.tieneCargado(ruta) && !soloCuadro) {
                    // volvió de un panel que no tapaba el launcher: el video sigue abierto
                    video.reanudar()
                    return
                }
                if (hayVideo() && video.tieneCargado(ruta) && !Ajustes.logico(context, "modo_ligero")) {
                    // pausado con el video abierto: se queda en el cuadro donde iba
                    video.pausar()
                    return
                }
                pintarCuadro(ruta)
                if (hayVideo() && !soloCuadro) {
                    main.postDelayed(intentar, RESPIRO_MS)
                } else {
                    liberarVideo()
                }
            }
            else -> {
                liberarVideo()
                cuadroActual = null
                cuadro.setImageDrawable(null)
                cuadro.setBackgroundColor(Color.BLACK)
                cuadro.visibility = ImageView.VISIBLE
            }
        }
    }

    private fun aplicarVideo() = video.cargar(ruta)

    private fun liberarVideo() = video.liberar()

    /** Silencio inmediato: otra pantalla acaba de ponerse encima. */
    fun silenciar() {
        enPrimerPlano = false
        main.removeCallbacks(intentar)
        video.enPrimerPlano(false)
    }

    /**
     * Suelta el decodificador y la memoria. Lo que se veía queda de imagen fija para que al volver
     * al launcher no haya negro mientras el video se abre otra vez.
     */
    fun soltar() {
        silenciar()
        val ruta = ruta
        if (tipo == "archivo" && Ajustes.esVideo(ruta)) {
            cuadro.visibility = ImageView.VISIBLE
        }
        liberarVideo()
    }

    private fun pintarCuadro(ruta: String) {
        cuadro.visibility = ImageView.VISIBLE
        if (ruta == cuadroActual) return
        cuadroActual = ruta
        val ancho = maxOf(cuadro.width, context.resources.displayMetrics.widthPixels)
        val alto = maxOf(cuadro.height, context.resources.displayMetrics.heightPixels)
        hilo.execute {
            val imagen = try {
                if (Ajustes.esVideo(ruta)) cuadroDeVideo(ruta, ancho) else Imagenes.leer(ruta, ancho, alto)
            } catch (e: Exception) {
                android.util.Log.w("Lumbra", "fondo: no se pudo leer $ruta: $e")
                null
            }
            main.post { if (ruta == cuadroActual) cuadro.setImageBitmap(imagen) }
        }
    }

    /** Un cuadro del video, guardado junto a la caché: sacarlo cuesta segundos, leerlo casi nada. */
    private fun cuadroDeVideo(ruta: String, ancho: Int): Bitmap? {
        val original = File(ruta)
        val guardado = File(context.cacheDir, "cuadro_${ruta.hashCode()}_${original.lastModified()}.jpg")
        if (guardado.isFile) return BitmapFactory.decodeFile(guardado.path)
        val lector = MediaMetadataRetriever()
        try {
            lector.setDataSource(ruta)
            val cuadro = lector.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC) ?: return null
            val escalado = if (cuadro.width > ancho) Bitmap.createScaledBitmap(cuadro, ancho, cuadro.height * ancho / cuadro.width, true) else cuadro
            context.cacheDir.listFiles { f -> f.name.startsWith("cuadro_${ruta.hashCode()}_") }?.forEach { it.delete() }
            guardado.outputStream().use { escalado.compress(Bitmap.CompressFormat.JPEG, 88, it) }
            return escalado
        } finally {
            lector.release()
        }
    }

    fun cerrar() {
        silenciar()
        liberarVideo()
        hilo.shutdown()
    }

    private companion object {
        const val RESPIRO_MS = 250L
        const val ESPERA_ENTRE_REVISIONES_MS = 3_000L

        // medido en una TV de 1 GB: en los primeros minutos Android sigue abriendo y cerrando apps
        const val ESPERA_MINIMA_MS = 60_000L
        const val ESPERA_MAXIMA_MS = 180_000L
        const val MEMORIA_LIBRE_BYTES = 180L * 1024 * 1024
    }
}

object Imagenes {
    /** Lee una imagen sin gastar más memoria de la que la pantalla puede mostrar, recortada a su forma. */
    fun leer(ruta: String, ancho: Int, alto: Int): Bitmap? {
        val medidas = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(ruta, medidas)
        if (medidas.outWidth <= 0 || medidas.outHeight <= 0) return null
        var muestra = 1
        while (medidas.outWidth / (muestra * 2) >= ancho && medidas.outHeight / (muestra * 2) >= alto) muestra *= 2
        val original = BitmapFactory.decodeFile(ruta, BitmapFactory.Options().apply { inSampleSize = muestra }) ?: return null
        val escala = maxOf(ancho.toFloat() / original.width, alto.toFloat() / original.height)
        val w = (ancho / escala).toInt().coerceIn(1, original.width)
        val h = (alto / escala).toInt().coerceIn(1, original.height)
        val recorte = Bitmap.createBitmap(original, (original.width - w) / 2, (original.height - h) / 2, w, h)
        return Bitmap.createScaledBitmap(recorte, ancho, alto, true)
    }
}
