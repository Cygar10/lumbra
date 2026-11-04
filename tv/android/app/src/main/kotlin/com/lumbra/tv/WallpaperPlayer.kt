/*
 * Lumbra — launcher para Android TV basado en FLauncher (GPL-3.0).
 */
package com.lumbra.tv

import android.content.Context
import android.net.Uri
import android.view.SurfaceView
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import java.io.File

/**
 * Fondo de video detrás de la interfaz.
 *
 * REPEAT_MODE_ONE hace que ExoPlayer vuelva al inicio sin cerrar el decodificador:
 * en algunas TV (chip MStar) cerrar y reabrir el decodificador pone la pantalla en negro.
 */
class WallpaperPlayer(private val context: Context, private val surface: SurfaceView) {
    private var player: ExoPlayer? = null
    private var archivo: String? = null
    private var volumen = 0f
    private var silenciado = false
    private var otraMusica = false
    private var primerPlano = false
    private var fundido: android.animation.ValueAnimator? = null
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())
    private var intentos = 0
    private var tunel = true

    /** Se llama cuando el primer cuadro del video ya está en pantalla. */
    var alMostrar: (() -> Unit)? = null

    fun tieneCargado(ruta: String) = ruta == archivo && player != null

    fun cargar(ruta: String?) {
        if (ruta == null || !File(ruta).isFile) {
            liberar()
            return
        }
        if (tieneCargado(ruta)) {
            reanudar()
            return
        }
        archivo = ruta
        intentos = 0
        tunel = true
        iniciar()
    }

    private fun iniciar() {
        val ruta = archivo ?: return
        player?.release()
        val p = crear()
        p.setMediaItem(MediaItem.fromUri(Uri.fromFile(File(ruta))))
        p.prepare()
        p.playWhenReady = true
        vigilar()
    }

    /**
     * Si otra app aún tiene tomado el audio, a veces la pista no arranca y ExoPlayer no da error:
     * el video se queda congelado para siempre. Se comprueba que avance y, si no, se abre de nuevo.
     */
    private var ultimaPosicion = -1L

    private val comprobarAvance = object : Runnable {
        override fun run() {
            val p = player ?: return
            if (!primerPlano || !p.playWhenReady) return
            if (p.playbackState == Player.STATE_READY && p.currentPosition != ultimaPosicion && ultimaPosicion >= 0) return
            if (p.playbackState == Player.STATE_READY && ultimaPosicion >= 0) {
                android.util.Log.w("Lumbra", "fondo: el video no avanza, intento $intentos")
                if (intentos >= 6) return
                intentos++
                if (intentos >= 3) tunel = false
                iniciar()
                return
            }
            ultimaPosicion = p.currentPosition
            handler.postDelayed(this, VIGILANCIA_MS)
        }
    }

    private fun vigilar() {
        handler.removeCallbacks(comprobarAvance)
        ultimaPosicion = -1
        handler.postDelayed(comprobarAvance, VIGILANCIA_MS)
    }

    /**
     * Al salir de Netflix u otra app, la TV a veces no ha soltado el decodificador y el
     * fondo se quedaba negro: se reintenta, y desde el tercer intento sin modo túnel.
     */
    private val alFallar = object : Player.Listener {
        override fun onPlayerError(error: PlaybackException) {
            android.util.Log.w("Lumbra", "fondo: error ${error.errorCodeName}, intento $intentos")
            player?.release()
            player = null
            if (intentos >= 6) return
            intentos++
            if (intentos >= 3) tunel = false
            handler.postDelayed({ if (primerPlano) iniciar() }, 700L * intentos)
        }

        override fun onPlaybackStateChanged(state: Int) {
            // el contador de intentos no se reinicia aquí: un video congelado también llega a READY
        }

        override fun onRenderedFirstFrame() {
            alMostrar?.invoke()
            handler.postDelayed({ if (player?.isPlaying == true) intentos = 0 }, 2 * VIGILANCIA_MS + 1000)
            // el sonido entra suave una vez que ya se ve el video
            aplicar(animado = true)
        }
    }

    private fun crear(): ExoPlayer {
        val selector = DefaultTrackSelector(context).apply {
            parameters = buildUponParameters().setTunnelingEnabled(tunel).build()
        }
        val renderers = DefaultRenderersFactory(context).setEnableDecoderFallback(true)
        // el video es un archivo local: con unos segundos de búfer sobra. Por defecto ExoPlayer
        // guarda hasta 128 MB, y hay TV con 1 GB de RAM (el resto se iba a swap y daba tirones).
        val carga = DefaultLoadControl.Builder()
            .setBufferDurationsMs(3000, 6000, 500, 1000)
            .setTargetBufferBytes(10 * 1024 * 1024)
            .setPrioritizeTimeOverSizeThresholds(false)
            .build()
        val p = ExoPlayer.Builder(context, renderers)
            .setTrackSelector(selector)
            .setLoadControl(carga)
            .build()
        p.repeatMode = Player.REPEAT_MODE_ONE
        p.videoScalingMode = C.VIDEO_SCALING_MODE_SCALE_TO_FIT_WITH_CROPPING
        p.setVideoSurfaceView(surface)
        p.volume = 0f
        p.addListener(alFallar)
        player = p
        return p
    }

    fun reanudar() {
        player?.playWhenReady = true
        if (player != null) vigilar()
    }

    fun pausar() {
        player?.playWhenReady = false
    }

    fun liberar() {
        handler.removeCallbacksAndMessages(null)
        fundido?.cancel()
        player?.release()
        player = null
        archivo = null
    }

    fun ponerVolumen(valor: Float, mute: Boolean) {
        volumen = valor.coerceIn(0f, 1f)
        silenciado = mute
        aplicar(animado = false)
    }

    /** Cuando suena Spotify u otra app, el audio del fondo se baja a cero suavemente. */
    fun otraMusicaSonando(sonando: Boolean) {
        if (sonando == otraMusica) return
        otraMusica = sonando
        aplicar(animado = true)
    }

    /**
     * El fondo solo suena con el launcher delante. No se espera a onStop para callarlo: Android lo
     * manda cuando la otra app ya terminó de abrir, y al encender la TV eso tardaba más de un minuto.
     */
    fun enPrimerPlano(activo: Boolean) {
        primerPlano = activo
        aplicar(animado = false)
    }

    private companion object {
        const val VIGILANCIA_MS = 5_000L
    }

    private fun volumenEfectivo() = if (!primerPlano || silenciado || otraMusica) 0f else volumen

    private fun aplicar(animado: Boolean) {
        val p = player ?: return
        fundido?.cancel()
        val destino = volumenEfectivo()
        if (!animado) {
            p.volume = destino
            return
        }
        fundido = android.animation.ValueAnimator.ofFloat(p.volume, destino).apply {
            duration = 800
            addUpdateListener { player?.volume = it.animatedValue as Float }
            start()
        }
    }
}
