/**
 * Metrolist Project (C) 2026
 * Licensed under GPL-3.0 | See git history for contributors
 */

package com.metrolist.music.playback

import com.metrolist.music.constants.HeadsetAction
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HeadsetClickDetectorTest {
    private val defaults = HeadsetClickSettings()

    @Test
    fun singleClickPlaysOrPausesAfterWindow() {
        val detector = HeadsetClickDetector()
        detector.onDown(0L)
        detector.onUp()

        assertNull(detector.onWindowTimeout(399L, defaults))
        assertEquals(HeadsetAction.PLAY_PAUSE, detector.onWindowTimeout(400L, defaults))
    }

    @Test
    fun doubleClickRunsDoubleAction() {
        val detector = HeadsetClickDetector()
        detector.onDown(0L)
        detector.onUp()
        detector.onDown(150L)
        detector.onUp()

        assertEquals(HeadsetAction.NEXT, detector.onWindowTimeout(550L, defaults))
    }

    @Test
    fun tripleClickRunsTripleAction() {
        val detector = HeadsetClickDetector()
        detector.onDown(0L)
        detector.onUp()
        detector.onDown(120L)
        detector.onUp()
        detector.onDown(240L)
        detector.onUp()

        assertEquals(HeadsetAction.PREVIOUS, detector.onWindowTimeout(640L, defaults))
    }

    @Test
    fun fourClicksAreClampedToTripleAction() {
        val detector = HeadsetClickDetector()
        repeat(4) { index ->
            detector.onDown(index * 100L)
            detector.onUp()
        }

        assertEquals(HeadsetAction.PREVIOUS, detector.onWindowTimeout(700L, defaults))
    }

    @Test
    fun actionsAreExecutedOncePerSequence() {
        val detector = HeadsetClickDetector()
        detector.onDown(0L)
        detector.onUp()
        assertEquals(HeadsetAction.PLAY_PAUSE, detector.onWindowTimeout(400L, defaults))
        assertNull(detector.onWindowTimeout(800L, defaults))

        detector.onDown(1000L)
        detector.onUp()
        assertEquals(HeadsetAction.PLAY_PAUSE, detector.onWindowTimeout(1400L, defaults))
    }

    @Test
    fun windowDoesNotFireWhileKeyIsStillDown() {
        val detector = HeadsetClickDetector()
        detector.onDown(0L)

        assertNull(detector.onWindowTimeout(1_000L, defaults))
    }

    @Test
    fun longPressDoesNotBecomeASingleClickWhenDisabled() {
        val detector = HeadsetClickDetector()
        detector.onDown(0L)

        assertNull(detector.onLongPressTimeout(600L, defaults))
        detector.onUp()
        assertNull(detector.onWindowTimeout(1_000L, defaults))
    }

    @Test
    fun shortPressStillBecomesASingleClick() {
        val detector = HeadsetClickDetector()
        detector.onDown(0L)
        detector.onUp()

        assertEquals(HeadsetAction.PLAY_PAUSE, detector.onWindowTimeout(400L, defaults))
    }

    @Test
    fun longPressRunsConfiguredActionWhenEnabled() {
        val settings = defaults.copy(
            longPressEnabled = true,
            longPressAction = HeadsetAction.NEXT,
        )
        val detector = HeadsetClickDetector()
        detector.onDown(0L)

        assertNull(detector.onLongPressTimeout(599L, settings))
        assertEquals(HeadsetAction.NEXT, detector.onLongPressTimeout(600L, settings))

        detector.onUp()
        assertNull(detector.onWindowTimeout(1_000L, settings))
    }
}
