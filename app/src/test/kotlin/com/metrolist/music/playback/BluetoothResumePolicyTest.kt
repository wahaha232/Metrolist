/**
 * Metrolist Project (C) 2026
 * Licensed under GPL-3.0 | See git history for contributors
 */

package com.metrolist.music.playback

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BluetoothResumePolicyTest {
    @Test
    fun resumesInsideTheConfiguredWindow() {
        assertTrue(
            shouldResumeAfterBluetoothDisconnect(
                nowMs = 100_000L,
                disconnectedAtMs = 99_000L,
                windowMs = 60_000L,
            )
        )
    }

    @Test
    fun doesNotResumeAfterTheWindow() {
        assertFalse(
            shouldResumeAfterBluetoothDisconnect(
                nowMs = 200_000L,
                disconnectedAtMs = 100_000L,
                windowMs = 60_000L,
            )
        )
    }

    @Test
    fun doesNotResumeWhenNeverDisconnected() {
        assertFalse(
            shouldResumeAfterBluetoothDisconnect(
                nowMs = 100_000L,
                disconnectedAtMs = 0L,
                windowMs = 60_000L,
            )
        )
    }

    @Test
    fun ignoresClockSkewBeforeTheDisconnect() {
        assertFalse(
            shouldResumeAfterBluetoothDisconnect(
                nowMs = 99_000L,
                disconnectedAtMs = 100_000L,
                windowMs = 60_000L,
            )
        )
    }
}
