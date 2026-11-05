/**
 * Metrolist Project (C) 2026
 * Licensed under GPL-3.0 | See git history for contributors
 */

package com.metrolist.music.playback

internal fun shouldResumeAfterBluetoothDisconnect(
    nowMs: Long,
    disconnectedAtMs: Long,
    windowMs: Long,
): Boolean {
    if (disconnectedAtMs <= 0L || windowMs <= 0L) return false
    val elapsed = nowMs - disconnectedAtMs
    return elapsed in 0..windowMs
}
