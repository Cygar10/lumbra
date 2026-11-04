/*
 * Lumbra — launcher para Android TV basado en FLauncher (GPL-3.0).
 */
package com.lumbra.tv

import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.view.KeyEvent
import java.io.ByteArrayOutputStream

/**
 * Sin este servicio Android no deja leer las sesiones multimedia de otras apps.
 * Se habilita con: cmd notification allow_listener com.lumbra.tv/.MediaListener
 */
class MediaListener : NotificationListenerService() {
    // Android mantiene vivo este servicio: así también se entera cuando la TV sale de reposo
    override fun onListenerConnected() = Encendido.escucharPantalla(this)
}

/** Sigue lo que suena en la TV (Spotify, YouTube Music…) y avisa con título, artista y portada. */
class MediaWatcher(private val context: Context, private val alCambiar: (Map<String, Any?>?) -> Unit) {
    private val manager = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
    private val componente = ComponentName(context, MediaListener::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private var controladores = listOf<MediaController>()
    private var ultimo: Map<String, Any?>? = null
    private var ultimaPortada: Pair<String, ByteArray?>? = null

    private val callback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) = publicar()
        override fun onMetadataChanged(metadata: MediaMetadata?) = publicar()
        override fun onSessionDestroyed() = actualizarSesiones(null)
    }

    private val sesiones = MediaSessionManager.OnActiveSessionsChangedListener { actualizarSesiones(it) }

    fun iniciar() {
        try {
            manager.addOnActiveSessionsChangedListener(sesiones, componente, handler)
            actualizarSesiones(manager.getActiveSessions(componente))
        } catch (e: SecurityException) {
            // falta el permiso de notificaciones: no hay indicador de música
            alCambiar(null)
        }
    }

    private companion object {
        val ENTRE_CANCIONES = setOf(
            PlaybackState.STATE_BUFFERING, PlaybackState.STATE_CONNECTING,
            PlaybackState.STATE_SKIPPING_TO_NEXT, PlaybackState.STATE_SKIPPING_TO_PREVIOUS,
            PlaybackState.STATE_SKIPPING_TO_QUEUE_ITEM,
        )
    }

    fun detener() {
        handler.removeCallbacks(ocultar)
        try {
            manager.removeOnActiveSessionsChangedListener(sesiones)
        } catch (_: Exception) {
        }
        controladores.forEach { it.unregisterCallback(callback) }
        controladores = emptyList()
    }

    private fun actualizarSesiones(lista: List<MediaController>?) {
        controladores.forEach { it.unregisterCallback(callback) }
        controladores = (lista ?: try {
            manager.getActiveSessions(componente)
        } catch (e: SecurityException) {
            emptyList()
        }).filter { it.packageName != context.packageName }
        controladores.forEach { it.registerCallback(callback, handler) }
        publicar()
    }

    private val ocultar = Runnable {
        ultimo = null
        alCambiar(null)
    }

    private fun publicar() {
        // al cambiar de canción Spotify pasa por BUFFERING / SKIPPING_TO_NEXT: también cuenta
        val activo = controladores.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING }
            ?: controladores.firstOrNull { it.playbackState?.state in ENTRE_CANCIONES && it.metadata != null }
            ?: controladores.firstOrNull {
                it.playbackState?.state == PlaybackState.STATE_PAUSED && it.metadata != null
            }
        val datos = activo?.let { c ->
            val m = c.metadata ?: return@let null
            val titulo = m.getString(MediaMetadata.METADATA_KEY_TITLE)
                ?: m.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
            if (titulo.isNullOrBlank()) return@let null
            val artista = m.getString(MediaMetadata.METADATA_KEY_ARTIST)
                ?: m.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
                ?: m.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE)
            mapOf(
                "package" to c.packageName,
                "title" to titulo,
                "artist" to artista,
                "playing" to (c.playbackState?.state == PlaybackState.STATE_PLAYING),
                "art" to portada(c.packageName + titulo, m),
            )
        }
        if (datos == null) {
            // no se quita la tarjeta enseguida: entre canciones la sesión queda vacía un instante
            if (ultimo != null && !handler.hasCallbacks(ocultar)) handler.postDelayed(ocultar, 2000)
            return
        }
        handler.removeCallbacks(ocultar)
        if (datos != ultimo) {
            ultimo = datos
            alCambiar(datos)
        }
    }

    private fun portada(clave: String, m: MediaMetadata): ByteArray? {
        ultimaPortada?.let { if (it.first == clave && it.second != null) return it.second }
        val bmp = m.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: m.getBitmap(MediaMetadata.METADATA_KEY_ART)
            ?: m.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
        val bytes = bmp?.let {
            val chica = Bitmap.createScaledBitmap(it, 160, 160 * it.height / maxOf(it.width, 1), true)
            ByteArrayOutputStream().also { s -> chica.compress(Bitmap.CompressFormat.JPEG, 90, s) }.toByteArray()
        }
        ultimaPortada = clave to bytes
        return bytes
    }

    /** true si alguna otra app está reproduciendo audio ahora mismo. */
    fun hayMusica() = controladores.any { it.playbackState?.state == PlaybackState.STATE_PLAYING }

    fun control(paquete: String, accion: String) {
        val c = controladores.firstOrNull { it.packageName == paquete } ?: return
        // Spotify TV ignora transportControls.pause(); las teclas multimedia sí las obedece
        val tecla = when (accion) {
            "anterior" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            "siguiente" -> KeyEvent.KEYCODE_MEDIA_NEXT
            "pausa" -> if (c.playbackState?.state == PlaybackState.STATE_PLAYING) KeyEvent.KEYCODE_MEDIA_PAUSE
            else KeyEvent.KEYCODE_MEDIA_PLAY
            else -> return
        }
        c.dispatchMediaButtonEvent(KeyEvent(KeyEvent.ACTION_DOWN, tecla))
        c.dispatchMediaButtonEvent(KeyEvent(KeyEvent.ACTION_UP, tecla))
    }

    fun abrir(paquete: String) {
        controladores.firstOrNull { it.packageName == paquete }?.sessionActivity?.let {
            try {
                it.send()
                return
            } catch (_: Exception) {
            }
        }
        context.packageManager.getLeanbackLaunchIntentForPackage(paquete)
            ?.let { context.startActivity(it.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }
}
