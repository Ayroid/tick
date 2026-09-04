package com.ayroid.tick

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The sum that the whole app rests on.
 *
 * These run on the JVM with no device and no Android framework, which is why
 * [Usage.fold] takes a list of plain [Usage.Moment]s rather than reading the
 * system cursor itself.
 */
class UsageTest {

    private val start = 0L
    private val end = 60 * 60_000L // a one-hour window

    private fun resumed(pkg: String, min: Int) =
        Usage.Moment(pkg, Usage.RESUMED, min * 60_000L)

    private fun paused(pkg: String, min: Int) =
        Usage.Moment(pkg, Usage.PAUSED, min * 60_000L)

    private fun screenOff(min: Int) =
        Usage.Moment("android", Usage.SCREEN_OFF, min * 60_000L)

    private fun minutes(w: Usage.Window, pkg: String) =
        (w.byPackage[pkg]?.ms ?: 0) / 60_000

    @Test
    fun `a session runs until another app takes over`() {
        val w = Usage.fold(listOf(resumed("a", 10), resumed("b", 25)), start, end)
        assertEquals(15, minutes(w, "a"))
        assertEquals(35, minutes(w, "b")) // and b runs to the end
        assertEquals(1, w.byPackage["a"]?.opens)
    }

    /**
     * A pause is not the end of a session, and this is the assertion that says
     * so. Apps pause for things the user never perceives as leaving: a system
     * dialog, the shade, a sub-activity, a cancelled gesture.
     *
     * Measured against Digital Wellbeing on one real day, ending on pause lost
     * 67 of WhatsApp's 97 minutes across 329 pause/resume cycles.
     */
    @Test
    fun `a pause does not end a session`() {
        val w = Usage.fold(
            listOf(resumed("a", 10), paused("a", 20), resumed("b", 40)),
            start,
            end,
        )
        assertEquals(30, minutes(w, "a")) // 10 to 40, not 10 to 20
    }

    @Test
    fun `resuming the same app after a pause is not a second open`() {
        val w = Usage.fold(
            listOf(resumed("a", 10), paused("a", 20), resumed("a", 30), resumed("b", 40)),
            start,
            end,
        )
        assertEquals(30, minutes(w, "a"))
        assertEquals(1, w.byPackage["a"]?.opens)
    }

    /**
     * The first regression. Android fires ACTIVITY_PAUSED *and then*
     * ACTIVITY_STOPPED for the same activity. An earlier version treated both
     * as a close and credited the second from the window start — a launcher
     * opened 345 times reported 5144 hours in a single day.
     */
    @Test
    fun `a stop trailing a pause adds nothing`() {
        val w = Usage.fold(
            listOf(resumed("a", 10), paused("a", 25), paused("a", 25), resumed("b", 25)),
            start,
            end,
        )
        assertEquals(15, minutes(w, "a"))
        assertEquals(35, minutes(w, "b"))
    }

    @Test
    fun `the screen going off ends the session`() {
        val w = Usage.fold(
            listOf(resumed("a", 10), screenOff(20), resumed("a", 40)),
            start,
            end,
        )
        assertEquals(30, minutes(w, "a")) // 10-20 and 40-60, never 20-40
        assertEquals(2, w.byPackage["a"]?.opens)
    }

    @Test
    fun `a phone put down mid-app does not accrue time`() {
        val w = Usage.fold(listOf(resumed("a", 5), screenOff(10)), start, end)
        assertEquals(5, minutes(w, "a"))
    }

    @Test
    fun `an app still in front when the window closes is closed at the end`() {
        val w = Usage.fold(listOf(resumed("a", 40)), start, end)
        assertEquals(20, minutes(w, "a"))
    }

    @Test
    fun `an app already in front when the window opens counts from the start`() {
        val w = Usage.fold(listOf(paused("a", 12)), start, end)
        assertEquals(12, minutes(w, "a"))
    }

    /**
     * Only one app can have been in front when the window opened, and it is
     * not left as current afterwards — nothing says what took over.
     */
    @Test
    fun `only one app is credited for the run before the window`() {
        val w = Usage.fold(
            listOf(paused("a", 5), resumed("b", 5), paused("c", 30)),
            start,
            end,
        )
        assertEquals(5, minutes(w, "a"))
        assertEquals(55, minutes(w, "b"))
        assertEquals(0, minutes(w, "c"))
    }

    @Test
    fun `switching back and forth splits the time between them`() {
        val w = Usage.fold(
            listOf(resumed("a", 0), resumed("b", 10), resumed("a", 30), resumed("b", 45)),
            start,
            end,
        )
        assertEquals(25, minutes(w, "a")) // 0-10 and 30-45
        assertEquals(35, minutes(w, "b")) // 10-30 and 45-60
        assertEquals(2, w.byPackage["a"]?.opens)
        assertEquals(2, w.byPackage["b"]?.opens)
    }

    @Test
    fun `a rotation is not a second open`() {
        val w = Usage.fold(
            listOf(resumed("a", 10), resumed("a", 20), resumed("b", 30)),
            start,
            end,
        )
        assertEquals(20, minutes(w, "a"))
        assertEquals(1, w.byPackage["a"]?.opens)
    }

    @Test
    fun `unlocks are counted and belong to no app`() {
        val w = Usage.fold(
            listOf(
                Usage.Moment("android", Usage.UNLOCK, 1000),
                resumed("a", 10),
                Usage.Moment("android", Usage.UNLOCK, 2000),
            ),
            start,
            end,
        )
        assertEquals(2, w.unlocks)
        assertEquals(0, minutes(w, "android"))
    }

    /**
     * The invariant. Sessions are disjoint by construction, so no stream —
     * however malformed — can total more than the window it was measured in.
     * This is what the very first version of this function violated by four
     * orders of magnitude.
     */
    @Test
    fun `no stream can total more than the window it covers`() {
        val moments = ArrayList<Usage.Moment>()
        for (i in 0 until 20) {
            moments.add(resumed("launcher", i * 3))
            moments.add(paused("launcher", i * 3 + 1))
            moments.add(paused("launcher", i * 3 + 1)) // the trailing STOPPED
            moments.add(resumed("app", i * 3 + 1))
            moments.add(paused("app", i * 3 + 3))
            moments.add(paused("app", i * 3 + 3))
        }
        moments.add(screenOff(59))
        val w = Usage.fold(moments, start, end)
        val total = w.byPackage.values.sumOf { it.ms }
        assertTrue("summed $total ms out of a ${end - start} ms window", total <= end - start)
        assertEquals(20, minutes(w, "launcher"))
        assertEquals(39, minutes(w, "app"))
    }

    @Test
    fun `an empty stream is an empty window, not a full one`() {
        val w = Usage.fold(emptyList(), start, end)
        assertEquals(0, w.byPackage.size)
        assertEquals(0, w.unlocks)
    }
}
