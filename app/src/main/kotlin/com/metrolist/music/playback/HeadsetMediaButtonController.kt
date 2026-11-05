/**
 * Metrolist Project (C) 2026
 * Licensed under GPL-3.0 | See git history for contributors
 */

package com.metrolist.music.playback

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.KeyEvent
import com.metrolist.music.constants.HeadsetAction

internal class HeadsetMediaButtonController(
    private val settingsProvider: () -> HeadsetClickSettings,
    private val onAction: (HeadsetAction) -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())
    private val detector = HeadsetClickDetector()
    private var longPressRunnable: Runnable? = null
    private var windowRunnable: Runnable? = null

    /**
     * @return true when the event was consumed by the multi-click logic. Standard media keys
     *         (next/previous/seek/voice assistant) are intentionally left to Media3.
     */
    fun handleKeyEvent(event: KeyEvent): Boolean {
        val settings = settingsProvider()
        if (!settings.enabled) return false
        if (event.keyCode != KeyEvent.KEYCODE_HEADSETHOOK &&
            event.keyCode != KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
        ) {
            return false
        }

        when (event.action) {
            KeyEvent.ACTION_DOWN -> {
                if (event.repeatCount == 0) {
                    cancelWindow()
                    detector.onDown(SystemClock.elapsedRealtime())
                    scheduleLongPress(settings)
                }
                return true
            }

            KeyEvent.ACTION_UP -> {
                cancelLongPress()
                detector.onUp()
                scheduleWindow(settings)
                return true
            }
        }
        return false
    }

    private fun scheduleLongPress(settings: HeadsetClickSettings) {
        cancelLongPress()
        // Always arm the timeout: even with the custom action disabled it marks the press as a
        // long press so it is not executed as a single click.
        val runnable = Runnable {
            detector.onLongPressTimeout(SystemClock.elapsedRealtime(), settings)?.let(onAction)
        }
        longPressRunnable = runnable
        handler.postDelayed(runnable, settings.longPressMs)
    }

    private fun scheduleWindow(settings: HeadsetClickSettings) {
        cancelWindow()
        val runnable = Runnable {
            detector.onWindowTimeout(SystemClock.elapsedRealtime(), settings)?.let(onAction)
        }
        windowRunnable = runnable
        handler.postDelayed(runnable, settings.windowMs)
    }

    private fun cancelLongPress() {
        longPressRunnable?.let(handler::removeCallbacks)
        longPressRunnable = null
    }

    private fun cancelWindow() {
        windowRunnable?.let(handler::removeCallbacks)
        windowRunnable = null
    }

    fun release() {
        cancelLongPress()
        cancelWindow()
        detector.reset()
    }
}
