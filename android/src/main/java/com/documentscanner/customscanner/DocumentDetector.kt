package com.documentscanner.customscanner

import android.graphics.*

/**
 * Simple document edge detection using Android built-in APIs.
 * Detects the largest quadrilateral in camera frames for document boundary overlay.
 *
 * This is a best-effort detection. The manual capture button is the primary
 * interaction method; auto-detection enhances the experience but is not required.
 */
class DocumentDetector {

    interface OnDocumentDetectedListener {
        /** Called when document edges are detected. Points are in image coordinates. */
        fun onDocumentDetected(corners: FloatArray)
        /** Called when the document position has been stable for enough frames */
        fun onDocumentStable(corners: FloatArray)
        /** Called when no document is detected */
        fun onDocumentLost()
    }

    var listener: OnDocumentDetectedListener? = null
    var isEnabled: Boolean = true

    // Stability tracking
    private var lastCorners: FloatArray? = null
    private var stableFrameCount = 0
    private val requiredStableFrames = 5
    private val stabilityThreshold = 0.03f // 3% of image dimension
    private var hasTriggeredStable = false

    /**
     * Process a captured Bitmap for document detection.
     * Call this with camera preview frames (scaled down for performance).
     */
    fun detectDocument(bitmap: Bitmap) {
        if (!isEnabled) return

        // Scale down for faster processing
        val scaleFactor = 4
        val smallBitmap = Bitmap.createScaledBitmap(
            bitmap,
            bitmap.width / scaleFactor,
            bitmap.height / scaleFactor,
            false
        )

        val corners = findDocumentCorners(smallBitmap)
        smallBitmap.recycle()

        if (corners != null) {
            // Scale corners back to original image size
            val scaledCorners = FloatArray(8)
            for (i in corners.indices) {
                scaledCorners[i] = corners[i] * scaleFactor
            }

            listener?.onDocumentDetected(scaledCorners)
            checkStability(scaledCorners, bitmap.width.toFloat(), bitmap.height.toFloat())
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

    /**
     * Simple document corner detection using edge analysis.
     * Returns 8 floats (4 corner points: x0,y0, x1,y1, x2,y2, x3,y3) or null.
     * Points are ordered: top-left, top-right, bottom-right, bottom-left.
     */
    private fun findDocumentCorners(bitmap: Bitmap): FloatArray? {
        val width = bitmap.width
        val height = bitmap.height

        // Convert to grayscale
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        val gray = IntArray(width * height)
        for (i in pixels.indices) {
            val r = (pixels[i] shr 16) and 0xFF
            val g = (pixels[i] shr 8) and 0xFF
            val b = pixels[i] and 0xFF
            gray[i] = (0.299 * r + 0.587 * g + 0.114 * b).toInt()
        }

        // Apply simple edge detection (Sobel-like)
        val edges = IntArray(width * height)
        for (y in 1 until height - 1) {
            for (x in 1 until width - 1) {
                val gx = -gray[(y - 1) * width + (x - 1)] + gray[(y - 1) * width + (x + 1)] +
                        -2 * gray[y * width + (x - 1)] + 2 * gray[y * width + (x + 1)] +
                        -gray[(y + 1) * width + (x - 1)] + gray[(y + 1) * width + (x + 1)]
                val gy = -gray[(y - 1) * width + (x - 1)] - 2 * gray[(y - 1) * width + x] - gray[(y - 1) * width + (x + 1)] +
                        gray[(y + 1) * width + (x - 1)] + 2 * gray[(y + 1) * width + x] + gray[(y + 1) * width + (x + 1)]
                edges[y * width + x] = Math.min(255, Math.sqrt((gx * gx + gy * gy).toDouble()).toInt())
            }
        }

        // Find strong edge points and try to detect a quadrilateral
        // Use a simplified approach: scan from edges inward to find document boundaries
        val threshold = 60
        val margin = width / 20 // 5% margin

        // Scan from each side to find the document edge
        var topEdge = margin
        var bottomEdge = height - margin
        var leftEdge = margin
        var rightEdge = width - margin

        // Find top edge
        for (y in margin until height / 2) {
            var edgeCount = 0
            for (x in margin until width - margin) {
                if (edges[y * width + x] > threshold) edgeCount++
            }
            if (edgeCount > (width - 2 * margin) / 4) {
                topEdge = y
                break
            }
        }

        // Find bottom edge
        for (y in height - margin - 1 downTo height / 2) {
            var edgeCount = 0
            for (x in margin until width - margin) {
                if (edges[y * width + x] > threshold) edgeCount++
            }
            if (edgeCount > (width - 2 * margin) / 4) {
                bottomEdge = y
                break
            }
        }

        // Find left edge
        for (x in margin until width / 2) {
            var edgeCount = 0
            for (y in topEdge until bottomEdge) {
                if (edges[y * width + x] > threshold) edgeCount++
            }
            if (edgeCount > (bottomEdge - topEdge) / 4) {
                leftEdge = x
                break
            }
        }

        // Find right edge
        for (x in width - margin - 1 downTo width / 2) {
            var edgeCount = 0
            for (y in topEdge until bottomEdge) {
                if (edges[y * width + x] > threshold) edgeCount++
            }
            if (edgeCount > (bottomEdge - topEdge) / 4) {
                rightEdge = x
                break
            }
        }

        // Validate that we found a reasonable rectangle
        val docWidth = rightEdge - leftEdge
        val docHeight = bottomEdge - topEdge
        if (docWidth < width / 4 || docHeight < height / 4) {
            return null // Too small to be a document
        }

        // Return corners: top-left, top-right, bottom-right, bottom-left
        return floatArrayOf(
            leftEdge.toFloat(), topEdge.toFloat(),
            rightEdge.toFloat(), topEdge.toFloat(),
            rightEdge.toFloat(), bottomEdge.toFloat(),
            leftEdge.toFloat(), bottomEdge.toFloat()
        )
    }
}
