package com.documentscanner.customscanner

import android.graphics.*

/**
 * Robust document corner detection using linear regression line fitting.
 * Detects paper boundaries by scanning for brightness transitions and calculating intersection points.
 * Returns normalized coordinates (0.0 to 1.0) for resolution-independent cropping.
 */
class DocumentDetector {

    interface OnDocumentDetectedListener {
        /** Called when document edges are detected. Points are in normalized coordinates (0 to 1). */
        fun onDocumentDetected(corners: FloatArray)
        /** Called when the document position has been stable for enough frames. */
        fun onDocumentStable(corners: FloatArray)
        /** Called when no document is detected. */
        fun onDocumentLost()
    }

    var listener: OnDocumentDetectedListener? = null
    var isEnabled: Boolean = true

    // Stability tracking
    private var lastCorners: FloatArray? = null
    private var stableFrameCount = 0
    private val requiredStableFrames = 5
    private val stabilityThreshold = 0.03f // 3% shift threshold
    private var hasTriggeredStable = false

    /**
     * Process a captured Bitmap for document detection.
     * Expects preview frame bitmap (usually already scaled down for performance).
     */
    fun detectDocument(bitmap: Bitmap) {
        if (!isEnabled) return

        val corners = findDocumentCorners(bitmap)

        if (corners != null) {
            // Normalize corners (0.0 to 1.0)
            val normalizedCorners = FloatArray(8)
            val w = bitmap.width.toFloat()
            val h = bitmap.height.toFloat()
            for (i in corners.indices step 2) {
                normalizedCorners[i] = corners[i] / w
                normalizedCorners[i + 1] = corners[i + 1] / h
            }

            listener?.onDocumentDetected(normalizedCorners)
            checkStability(normalizedCorners, 1.0f, 1.0f)
        } else {
            lastCorners = null
            stableFrameCount = 0
            hasTriggeredStable = false
            listener?.onDocumentLost()
        }
    }

    /**
     * Reset stability tracking (call after a successful capture)
     */
    fun resetStability() {
        lastCorners = null
        stableFrameCount = 0
        hasTriggeredStable = false
    }

    /**
     * Check if the detected corners are stable across frames
     */
    private fun checkStability(corners: FloatArray, imageWidth: Float, imageHeight: Float) {
        val last = lastCorners
        if (last != null && last.size == corners.size) {
            val maxDelta = (0 until corners.size step 2).maxOfOrNull { i ->
                val dx = Math.abs(corners[i] - last[i]) / imageWidth
                val dy = Math.abs(corners[i + 1] - last[i + 1]) / imageHeight
                Math.max(dx, dy)
            } ?: 1f

            if (maxDelta < stabilityThreshold) {
                stableFrameCount++
                if (stableFrameCount >= requiredStableFrames && !hasTriggeredStable) {
                    hasTriggeredStable = true
                    listener?.onDocumentStable(corners)
                }
            } else {
                stableFrameCount = 1
                hasTriggeredStable = false
            }
        } else {
            stableFrameCount = 1
            hasTriggeredStable = false
        }
        lastCorners = corners.copyOf()
    }

    private class Line(val m: Float, val c: Float, val isVertical: Boolean)

    private fun fitLine(points: List<PointF>, isVertical: Boolean): Line? {
        if (points.size < 3) return null

        val n = points.size
        var sumX = 0f
        var sumY = 0f
        for (p in points) {
            sumX += p.x
            sumY += p.y
        }
        val meanX = sumX / n
        val meanY = sumY / n

        var num = 0f
        var den = 0f

        if (isVertical) {
            // x = m * y + c
            for (p in points) {
                num += (p.y - meanY) * (p.x - meanX)
                den += (p.y - meanY) * (p.y - meanY)
            }
        } else {
            // y = m * x + c
            for (p in points) {
                num += (p.x - meanX) * (p.y - meanY)
                den += (p.x - meanX) * (p.x - meanX)
            }
        }

        if (den == 0f) return null
        val m = num / den
        val c = if (isVertical) meanX - m * meanY else meanY - m * meanX

        // 1-step outlier rejection: filter points with error > threshold, then re-fit
        val threshold = 12f // pixels
        val remainingPoints = points.filter { p ->
            val error = if (isVertical) {
                Math.abs(p.x - (m * p.y + c))
            } else {
                Math.abs(p.y - (m * p.x + c))
            }
            error < threshold
        }

        if (remainingPoints.size < 3) {
            return Line(m, c, isVertical)
        }

        val rn = remainingPoints.size
        var rSumX = 0f
        var rSumY = 0f
        for (p in remainingPoints) {
            rSumX += p.x
            rSumY += p.y
        }
        val rMeanX = rSumX / rn
        val rMeanY = rSumY / rn

        var rNum = 0f
        var rDen = 0f

        if (isVertical) {
            for (p in remainingPoints) {
                rNum += (p.y - rMeanY) * (p.x - rMeanX)
                rDen += (p.y - rMeanY) * (p.y - rMeanY)
            }
        } else {
            for (p in remainingPoints) {
                rNum += (p.x - rMeanX) * (p.y - rMeanY)
                rDen += (p.x - rMeanX) * (p.x - rMeanX)
            }
        }

        if (rDen == 0f) return null
        val rm = rNum / rDen
        val rc = if (isVertical) rMeanX - rm * rMeanY else rMeanY - rm * rMeanX

        return Line(rm, rc, isVertical)
    }

    private fun intersect(horiz: Line, vert: Line): PointF? {
        val den = 1f - vert.m * horiz.m
        if (Math.abs(den) < 0.001f) return null
        val x = (vert.m * horiz.c + vert.c) / den
        val y = horiz.m * x + horiz.c
        return PointF(x, y)
    }

    private fun getLuma(pixels: IntArray, width: Int, x: Int, y: Int): Double {
        val idx = y * width + x
        if (idx in pixels.indices) {
            val c = pixels[idx]
            val r = (c shr 16) and 0xFF
            val g = (c shr 8) and 0xFF
            val b = c and 0xFF
            return 0.299 * r + 0.587 * g + 0.114 * b
        }
        return 0.0
    }

    private fun findDocumentCorners(bitmap: Bitmap): FloatArray? {
        val width = bitmap.width
        val height = bitmap.height

        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

        // 1. Calculate dynamic luma threshold based on corner regions (usually background)
        val sampleMarginX = (width * 0.05).toInt().coerceAtLeast(1)
        val sampleMarginY = (height * 0.05).toInt().coerceAtLeast(1)
        val cornerLumas = doubleArrayOf(
            getLuma(pixels, width, sampleMarginX, sampleMarginY),
            getLuma(pixels, width, width - sampleMarginX, sampleMarginY),
            getLuma(pixels, width, sampleMarginX, height - sampleMarginY),
            getLuma(pixels, width, width - sampleMarginX, height - sampleMarginY)
        )
        val bgLuma = cornerLumas.average()
        val threshold = (bgLuma + 45.0).coerceIn(95.0, 160.0)

        val topPoints = mutableListOf<PointF>()
        val bottomPoints = mutableListOf<PointF>()
        val leftPoints = mutableListOf<PointF>()
        val rightPoints = mutableListOf<PointF>()

        // Scan lines (using 7 lines distributed across the inner 70% of the dimension)
        val startX = (width * 0.15).toInt()
        val endX = (width * 0.85).toInt()
        val stepX = (endX - startX) / 6

        // Scan Top-to-Bottom
        for (i in 0..6) {
            val x = startX + i * stepX
            for (y in 0 until height / 2) {
                if (getLuma(pixels, width, x, y) > threshold) {
                    topPoints.add(PointF(x.toFloat(), y.toFloat()))
                    break
                }
            }
        }

        // Scan Bottom-to-Top
        for (i in 0..6) {
            val x = startX + i * stepX
            for (y in height - 1 downTo height / 2) {
                if (getLuma(pixels, width, x, y) > threshold) {
                    bottomPoints.add(PointF(x.toFloat(), y.toFloat()))
                    break
                }
            }
        }

        val startY = (height * 0.15).toInt()
        val endY = (height * 0.85).toInt()
        val stepY = (endY - startY) / 6

        // Scan Left-to-Right
        for (i in 0..6) {
            val y = startY + i * stepY
            for (x in 0 until width / 2) {
                if (getLuma(pixels, width, x, y) > threshold) {
                    leftPoints.add(PointF(x.toFloat(), y.toFloat()))
                    break
                }
            }
        }

        // Scan Right-to-Left
        for (i in 0..6) {
            val y = startY + i * stepY
            for (x in width - 1 downTo width / 2) {
                if (getLuma(pixels, width, x, y) > threshold) {
                    rightPoints.add(PointF(x.toFloat(), y.toFloat()))
                    break
                }
            }
        }

        // Validation: require at least 4 points on each edge to build robust lines
        if (topPoints.size < 4 || bottomPoints.size < 4 || leftPoints.size < 4 || rightPoints.size < 4) {
            return null
        }

        // Fit lines: Horizontal-ish (top, bottom) and Vertical-ish (left, right)
        val topLine = fitLine(topPoints, isVertical = false) ?: return null
        val bottomLine = fitLine(bottomPoints, isVertical = false) ?: return null
        val leftLine = fitLine(leftPoints, isVertical = true) ?: return null
        val rightLine = fitLine(rightPoints, isVertical = true) ?: return null

        // Find intersections
        val topLeft = intersect(topLine, leftLine) ?: return null
        val topRight = intersect(topLine, rightLine) ?: return null
        val bottomRight = intersect(bottomLine, rightLine) ?: return null
        val bottomLeft = intersect(bottomLine, leftLine) ?: return null

        // Validate the shape dimensions
        val w1 = Math.abs(topRight.x - topLeft.x)
        val w2 = Math.abs(bottomRight.x - bottomLeft.x)
        val h1 = Math.abs(bottomLeft.y - topLeft.y)
        val h2 = Math.abs(bottomRight.y - topRight.y)
        val minDim = Math.min(width, height)

        if (w1 < minDim * 0.3f || w2 < minDim * 0.3f || h1 < minDim * 0.3f || h2 < minDim * 0.3f) {
            return null
        }

        return floatArrayOf(
            Math.max(0f, Math.min(width.toFloat(), topLeft.x)), Math.max(0f, Math.min(height.toFloat(), topLeft.y)),
            Math.max(0f, Math.min(width.toFloat(), topRight.x)), Math.max(0f, Math.min(height.toFloat(), topRight.y)),
            Math.max(0f, Math.min(width.toFloat(), bottomRight.x)), Math.max(0f, Math.min(height.toFloat(), bottomRight.y)),
            Math.max(0f, Math.min(width.toFloat(), bottomLeft.x)), Math.max(0f, Math.min(height.toFloat(), bottomLeft.y))
        )
    }
}
