package com.documentscanner.customscanner

import android.content.Context
import android.graphics.*
import android.util.AttributeSet
import android.view.View

/**
 * Custom overlay View that draws detected document edges on top of the camera preview.
 * Draws a semi-transparent blue polygon highlighting the document boundary.
 */
class ScannerOverlayView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    /** Current document corner points (8 floats: x0,y0, x1,y1, x2,y2, x3,y3) */
    private var corners: FloatArray? = null

    /** Paint for the polygon border */
    private val borderPaint = Paint().apply {
        color = Color.parseColor("#2196F3") // Material Blue
        style = Paint.Style.STROKE
        strokeWidth = 4f
        isAntiAlias = true
        strokeJoin = Paint.Join.ROUND
    }

    /** Paint for the polygon fill */
    private val fillPaint = Paint().apply {
        color = Color.parseColor("#1A2196F3") // 10% opacity blue
        style = Paint.Style.FILL
        isAntiAlias = true
    }

    /** Paint for corner dots */
    private val cornerPaint = Paint().apply {
        color = Color.parseColor("#2196F3")
        style = Paint.Style.FILL
        isAntiAlias = true
    }

    /**
     * Update the document corners to draw.
     * @param corners 8 floats (4 corners x,y) in normalized coordinates, or null to clear
     */
    fun setDocumentCorners(corners: FloatArray?) {
        this.corners = corners
        invalidate()
    }

    /** Clear the overlay */
    fun clearOverlay() {
        corners = null
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val pts = corners ?: return
        if (pts.size != 8) return

        // Scale corners from image coordinates to view coordinates
        val scaledCorners = scaleToView(pts)

        // Draw the polygon path
        val path = Path().apply {
            moveTo(scaledCorners[0], scaledCorners[1])
            lineTo(scaledCorners[2], scaledCorners[3])
            lineTo(scaledCorners[4], scaledCorners[5])
            lineTo(scaledCorners[6], scaledCorners[7])
            close()
        }

        canvas.drawPath(path, fillPaint)
        canvas.drawPath(path, borderPaint)

        // Draw corner dots
        val cornerRadius = 8f
        for (i in 0 until 8 step 2) {
            canvas.drawCircle(scaledCorners[i], scaledCorners[i + 1], cornerRadius, cornerPaint)
        }
    }

    private fun scaleToView(corners: FloatArray): FloatArray {
        return FloatArray(8) { i ->
            if (i % 2 == 0) corners[i] * width else corners[i] * height
        }
    }
}
