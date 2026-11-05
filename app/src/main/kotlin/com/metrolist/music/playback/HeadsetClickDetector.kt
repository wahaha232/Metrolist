/**
 * Metrolist Project (C) 2026
 * Licensed under GPL-3.0 | See git history for contributors
 */

package com.metrolist.music.playback

import com.metrolist.music.constants.HeadsetAction

internal data class HeadsetClickSettings(
    val enabled: Boolean = true,
    val windowMs: Long = 400L,
    val doubleClickAction: HeadsetAction = HeadsetAction.NEXT,
    val tripleClickAction: HeadsetAction = HeadsetAction.PREVIOUS,
    val longPressEnabled: Boolean = false,
    val longPressAction: HeadsetAction = HeadsetAction.NONE,
    val longPressMs: Long = 600L,
)

/**
 * Pure click accumulator for KEYCODE_HEADSETHOOK / KEYCODE_MEDIA_PLAY_PAUSE.
 *
 * The caller forwards key down/up events and has to schedule two timeouts:
 * [onLongPressTimeout] while the key is held and [onWindowTimeout] after the key is released.
 */
internal class HeadsetClickDetector {
    private var clickCount = 0
    private var lastPressAt = 0L
    private var keyDown = false
    private var longPressFired = false

    fun onDown(nowMs: Long) {
        keyDown = true
        longPressFired = false
        clickCount += 1
        lastPressAt = nowMs
    }

    fun onUp() {
        keyDown = false
    }

    fun onLongPressTimeout(
        nowMs: Long,
        settings: HeadsetClickSettings,
    ): HeadsetAction? {
        if (!keyDown || longPressFired) return null
        if (nowMs - lastPressAt < settings.longPressMs) return null

        // A long hold is never a single click, even when the custom long-press action is off.
        // This keeps the system voice assistant from also toggling playback.
        longPressFired = true
        clickCount = 0
        if (!settings.longPressEnabled || settings.longPressAction == HeadsetAction.NONE) {
            return null
        }
        return settings.longPressAction
    }

    fun onWindowTimeout(
        nowMs: Long,
        settings: HeadsetClickSettings,
    ): HeadsetAction? {
        if (clickCount == 0 || keyDown) return null
        if (nowMs - lastPressAt < settings.windowMs) return null

        val count = clickCount
        clickCount = 0
        lastPressAt = 0L
        return when (count) {
            1 -> HeadsetAction.PLAY_PAUSE
            2 -> settings.doubleClickAction
            else -> settings.tripleClickAction
        }
    }

    fun reset() {
        clickCount = 0
        lastPressAt = 0L
        keyDown = false
        longPressFired = false
    }
}
