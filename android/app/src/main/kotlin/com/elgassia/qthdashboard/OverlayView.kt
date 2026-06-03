package com.elgassia.qthdashboard

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.View
import kotlin.math.cos
import kotlin.math.sin

/**
 * Compact always-on-top compass, drawn natively to MIRROR the in-app bearing ring
 * (see `_BearingRingPainter` in home_screen.dart): same ring, North marker, heading
 * cursor/arrow, secondary dash and POI dots (city / waypoint / MOB).
 *
 * Layout (≈ 200 × 84 dp):
 *   [ bearing ring + dots ]   087°
 *                             <info line 1>
 *                             <info line 2>
 *
 * All colours arrive as ARGB ints from Dart so the app's single palette (incl. the
 * pure-red night rule) stays authoritative; this view hard-codes no semantic colour.
 */
@SuppressLint("ViewConstructor")
class OverlayView(context: Context) : View(context) {

    private val d = resources.displayMetrics.density
    private fun dp(v: Float) = v * d

    // ── Data (set on the main thread, then invalidate) ─────────────────────────
    @Volatile var heading = 0f
    @Volatile var headingValid = true
    @Volatile var windRose = false
    @Volatile var secondaryBearing = Float.NaN
    @Volatile var primaryColor = Color.WHITE
    @Volatile var secondaryColor = Color.GRAY
    @Volatile var northColor = Color.RED
    @Volatile var ringColor = Color.WHITE
    @Volatile var line1 = ""
    @Volatile var line2 = ""
    @Volatile var bgColor = 0xCC000000.toInt()
    @Volatile var textColor = Color.WHITE
    @Volatile var subColor = Color.LTGRAY
    // POI markers (parallel arrays): bearing°, ARGB colour, size scale.
    @Volatile var markerBearings = DoubleArray(0)
    @Volatile var markerColors = IntArray(0)
    @Volatile var markerScales = DoubleArray(0)

    fun applyData() = postInvalidate()

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.LEFT }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(dp(200f).toInt(), dp(84f).toInt())
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat(); val h = height.toFloat()

        // Background pill
        fill.style = Paint.Style.FILL; fill.color = bgColor
        canvas.drawRoundRect(RectF(0f, 0f, w, h), dp(12f), dp(12f), fill)

        val cx = dp(44f); val cy = h / 2f; val r = dp(32f)

        // ── Ring ──────────────────────────────────────────────────────────────
        stroke.color = ringColor
        stroke.alpha = if (windRose) 180 else 70
        stroke.strokeWidth = dp(if (windRose) 2f else 1.5f)
        canvas.drawCircle(cx, cy, r, stroke)
        stroke.alpha = 255

        if (windRose) {
            // Rotating cardinal/intercardinal ticks; North = red arc + pointer + "N".
            for (i in 0 until 8) {
                val rel = ((i * 45.0) - heading + 360.0) % 360.0
                if (i == 0) {
                    drawArc(canvas, cx, cy, r, rel, northColor, dp(5f), 18.0)
                    drawTick(canvas, cx, cy, r, rel, northColor, dp(3f), dp(11f))
                    drawText(canvas, "N", cx, cy, r - dp(20f), rel, northColor, dp(11f))
                } else {
                    val cardinal = i % 2 == 0
                    drawTick(canvas, cx, cy, r, rel,
                        withAlpha(ringColor, if (cardinal) 200 else 130),
                        dp(if (cardinal) 2.6f else 1.4f), dp(if (cardinal) 8f else 6f))
                }
            }
            if (!secondaryBearing.isNaN()) {
                drawDash(canvas, cx, cy, r, (secondaryBearing - heading + 360f) % 360f,
                    secondaryColor)
            }
            // Fixed heading cursor at the top (12 o'clock).
            drawTriangle(canvas, cx, cy, r, 0.0, primaryColor, dp(9f))
        } else {
            // Absolute (North-up): 4-tick crosshair + needle to the heading.
            for (q in 0 until 4) {
                drawTick(canvas, cx, cy, r, q * 90.0, withAlpha(ringColor, 90),
                    dp(1.4f), dp(5f))
            }
            drawTick(canvas, cx, cy, r, 0.0, northColor, dp(2f), dp(7f)) // North mark
            if (headingValid) drawNeedle(canvas, cx, cy, r, heading.toDouble(), primaryColor)
            if (!secondaryBearing.isNaN()) {
                drawDot(canvas, cx, cy, r, secondaryBearing.toDouble(), secondaryColor, dp(2.5f))
            }
        }

        // ── POI dots (city / waypoint / MOB) ───────────────────────────────────
        for (i in markerBearings.indices) {
            val rel = if (windRose) (markerBearings[i] - heading + 360.0) % 360.0
                      else markerBearings[i]
            val scale = if (i < markerScales.size) markerScales[i] else 1.0
            val color = if (i < markerColors.size) markerColors[i] else primaryColor
            val (x, y) = pt(cx, cy, r, rel)
            fill.style = Paint.Style.FILL
            fill.color = withAlpha(color, 70)
            canvas.drawCircle(x, y, dp(5f) * scale.toFloat(), fill)   // glow
            fill.color = color
            canvas.drawCircle(x, y, dp(3f) * scale.toFloat(), fill)   // dot
            if (scale > 1.3) {                                        // MOB outline
                stroke.color = withAlpha(if (windRose) northColor else color, 160)
                stroke.strokeWidth = dp(1.3f)
                canvas.drawCircle(x, y, dp(3f) * scale.toFloat() + dp(1.3f), stroke)
            }
        }

        // ── Numeric heading + info lines ────────────────────────────────────────
        val tx = dp(86f)
        text.color = textColor; text.isFakeBoldText = true; text.textSize = dp(22f)
        canvas.drawText(if (headingValid) "${Math.round(heading)}°" else "---", tx, cy - dp(4f), text)

        text.isFakeBoldText = false
        val maxW = w - tx - dp(8f)
        text.color = subColor; text.textSize = dp(11.5f)
        canvas.drawText(ellipsize(line1, maxW), tx, cy + dp(12f), text)
        if (line2.isNotEmpty()) {
            text.textSize = dp(10f)
            canvas.drawText(ellipsize(line2, maxW), tx, cy + dp(26f), text)
        }
    }

    // ── Geometry helpers (deg: 0 = up/North-of-frame, clockwise) ───────────────

    private fun pt(cx: Float, cy: Float, r: Float, deg: Double): Pair<Float, Float> {
        val a = Math.toRadians(deg)
        return Pair(cx + r * sin(a).toFloat(), cy - r * cos(a).toFloat())
    }

    private fun withAlpha(color: Int, a: Int) =
        Color.argb(a, Color.red(color), Color.green(color), Color.blue(color))

    private fun drawTick(c: Canvas, cx: Float, cy: Float, r: Float, deg: Double,
                         color: Int, width: Float, len: Float) {
        val (ox, oy) = pt(cx, cy, r, deg)
        val (ix, iy) = pt(cx, cy, r - len, deg)
        stroke.color = color; stroke.strokeWidth = width; stroke.strokeCap = Paint.Cap.ROUND
        c.drawLine(ox, oy, ix, iy, stroke)
    }

    private fun drawArc(c: Canvas, cx: Float, cy: Float, r: Float, centerDeg: Double,
                        color: Int, width: Float, halfSpanDeg: Double) {
        stroke.color = color; stroke.strokeWidth = width
        stroke.strokeCap = Paint.Cap.ROUND; stroke.style = Paint.Style.STROKE
        // Android arc: 0° = 3 o'clock, clockwise.  Our deg 0 = up = Android -90.
        val start = (centerDeg - 90 - halfSpanDeg).toFloat()
        c.drawArc(RectF(cx - r, cy - r, cx + r, cy + r), start, (halfSpanDeg * 2).toFloat(), false, stroke)
    }

    private fun drawTriangle(c: Canvas, cx: Float, cy: Float, r: Float, deg: Double,
                             color: Int, len: Float) {
        val (tx, ty) = pt(cx, cy, r - len, deg)
        val (lx, ly) = pt(cx, cy, r, deg - 6)
        val (rx, ry) = pt(cx, cy, r, deg + 6)
        fill.style = Paint.Style.FILL; fill.color = color
        c.drawPath(Path().apply { moveTo(tx, ty); lineTo(lx, ly); lineTo(rx, ry); close() }, fill)
    }

    private fun drawNeedle(c: Canvas, cx: Float, cy: Float, r: Float, deg: Double, color: Int) {
        val (tx, ty) = pt(cx, cy, r * 0.92f, deg)
        val (lx, ly) = pt(cx, cy, r * 0.40f, deg - 140)
        val (rx, ry) = pt(cx, cy, r * 0.40f, deg + 140)
        fill.style = Paint.Style.FILL; fill.color = color
        c.drawPath(Path().apply {
            moveTo(tx, ty); lineTo(lx, ly); lineTo(cx, cy); lineTo(rx, ry); close()
        }, fill)
    }

    private fun drawDash(c: Canvas, cx: Float, cy: Float, r: Float, deg: Float, color: Int) {
        val (ox, oy) = pt(cx, cy, r + dp(1f), deg.toDouble())
        val (ix, iy) = pt(cx, cy, r - dp(9f), deg.toDouble())
        stroke.color = withAlpha(color, 220); stroke.strokeWidth = dp(3f); stroke.strokeCap = Paint.Cap.ROUND
        c.drawLine(ox, oy, ix, iy, stroke)
    }

    private fun drawDot(c: Canvas, cx: Float, cy: Float, r: Float, deg: Double, color: Int, rad: Float) {
        val (x, y) = pt(cx, cy, r, deg)
        fill.style = Paint.Style.FILL; fill.color = color
        c.drawCircle(x, y, rad, fill)
    }

    private fun drawText(c: Canvas, s: String, cx: Float, cy: Float, r: Float, deg: Double,
                         color: Int, size: Float) {
        val (x, y) = pt(cx, cy, r, deg)
        text.color = color; text.isFakeBoldText = true; text.textSize = size
        text.textAlign = Paint.Align.CENTER
        c.drawText(s, x, y + size / 3f, text)
        text.textAlign = Paint.Align.LEFT
    }

    private fun ellipsize(s: String, maxW: Float): String {
        if (text.measureText(s) <= maxW) return s
        var out = s
        while (out.isNotEmpty() && text.measureText("$out…") > maxW) out = out.dropLast(1)
        return "$out…"
    }
}
