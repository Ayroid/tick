package com.ayroid.tick

import org.junit.Assert.assertEquals
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

    private fun resumed(pkg: String, atMinute: Int) =
        Usage.Moment(pkg, Usage.RESUMED, atMinute * 60_000L)

    private fun paused(pkg: String, atMinute: Int) =
        Usage.Moment(pkg, Usage.PAUSED, atMinute * 60_000L)

    private fun minutes(window: Usage.Window, pkg: String) =
        (window.byPackage[pkg]?.ms ?: 0) / 60_000

    @Test
    fun `a resume and a pause is the span between them`() {
        val w = Usage.fold(listOf(resumed("a", 10), paused("a", 25)), start, end)
        assertEquals(15, minutes(w, "a"))
        assertEquals(1, w.byPackage["a"]?.opens)
    }

    /**
     * The regression test. Android fires ACTIVITY_PAUSED and then
     * ACTIVITY_STOPPED for the same activity, and both arrive here as PAUSED.
     * Counting the second one cost four orders of magnitude: a launcher opened
     * 345 times reported 5144 hours of use in a single day.
     */
    @Test
    fun `a stop trailing a pause is not counted twice`() {
        val w = Usage.fold(
            listOf(resumed("a", 10), paused("a", 25), paused("a", 25)),
            start,
            end,
        )
        assertEquals(15, minutes(w, "a"))
    }

    @Test
    fun `a stop arriving much later than its pause adds nothing`() {
        val w = Usage.fold(
            listOf(resumed("a", 10), paused("a", 25), paused("a", 50)),
            start,
            end,
        )
        assertEquals(15, minutes(w, "a"))
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
     * Only one app can have been in front when the window opened. A background
     * activity stopping later must not be handed the same credit — that is the
     * same bug as the double count, wearing a different hat.
     */
    @Test
    fun `only one app is credited for the run before the window`() {
        val w = Usage.fold(
            listOf(paused("a", 5), resumed("b", 5), paused("b", 10), paused("c", 30)),
            start,
            end,
        )
        assertEquals(5, minutes(w, "a"))
        assertEquals(5, minutes(w, "b"))
        assertEquals(0, minutes(w, "c"))
    }

    @Test
    fun `switching apps closes the one being left`() {
        val w = Usage.fold(
            listOf(resumed("a", 0), resumed("b", 10), resumed("a", 30), paused("a", 45)),
            start,
            end,
        )
        assertEquals(25, minutes(w, "a")) // 0-10 and 30-45
        assertEquals(20, minutes(w, "b")) // 10-30
        assertEquals(2, w.byPackage["a"]?.opens)
        assertEquals(1, w.byPackage["b"]?.opens)
    }

    @Test
    fun `a rotation is not a second open`() {
        val w = Usage.fold(
            listOf(resumed("a", 10), resumed("a", 20), paused("a", 30)),
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
     * A realistic day cannot exceed the window it was measured in. This is the
     * assertion that would have caught the original bug on sight.
     */
    @Test
    fun `a day of switching never totals more than the day`() {
        val moments = ArrayList<Usage.Moment>()
        for (i in 0 until 20) {
            moments.add(resumed("launcher", i * 3))
            moments.add(paused("launcher", i * 3 + 1))
            moments.add(paused("launcher", i * 3 + 1)) // the trailing STOPPED
            moments.add(resumed("app", i * 3 + 1))
            moments.add(paused("app", i * 3 + 3))
            moments.add(paused("app", i * 3 + 3))
        }
        val w = Usage.fold(moments, start, end)
        val total = w.byPackage.values.sumOf { it.ms }
        assertEquals(20, minutes(w, "launcher"))
        assertEquals(40, minutes(w, "app"))
        assert(total <= end - start) { "summed $total ms out of a ${end - start} ms window" }
    }

    @Test
    fun `an empty stream is an empty window, not a full one`() {
        val w = Usage.fold(emptyList(), start, end)
        assertEquals(0, w.byPackage.size)
        assertEquals(0, w.unlocks)
    }
}
