package com.documentscanner.customscanner

import android.graphics.*
import android.util.Base64
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.*

/**
 * Processes captured images: perspective correction using Matrix.setPolyToPoly(),
 * EXIF rotation, division-based document enhancement filter, and saving.
 */
class ImageProcessor {

    companion object {
        /**
         * Apply perspective correction to an image given 4 normalized corner points.
         *
         * @param bitmap The source image
         * @param corners 8 floats: top-left(x,y), top-right(x,y), bottom-right(x,y), bottom-left(x,y) (normalized 0.0 to 1.0)
         * @return The corrected bitmap
         */
        fun applyPerspectiveCorrection(bitmap: Bitmap, corners: FloatArray?): Bitmap {
            val w = bitmap.width.toFloat()
            val h = bitmap.height.toFloat()

            // Source points (document corners in the original image)
            val srcPoints = if (corners == null || corners.size != 8) {
                // Fallback: default crop with a 1.5% margin around the image boundaries
                val mx = w * 0.015f
                val my = h * 0.015f
                floatArrayOf(
                    mx, my,          // top-left
                    w - mx, my,      // top-right
                    w - mx, h - my,  // bottom-right
                    mx, h - my       // bottom-left
                )
            } else {
                floatArrayOf(
                    corners[0] * w, corners[1] * h,
                    corners[2] * w, corners[3] * h,
                    corners[4] * w, corners[5] * h,
                    corners[6] * w, corners[7] * h
                )
            }

            // Calculate the output dimensions based on document corners
            val topWidth = distance(srcPoints[0], srcPoints[1], srcPoints[2], srcPoints[3])
            val bottomWidth = distance(srcPoints[6], srcPoints[7], srcPoints[4], srcPoints[5])
            val leftHeight = distance(srcPoints[0], srcPoints[1], srcPoints[6], srcPoints[7])
            val rightHeight = distance(srcPoints[2], srcPoints[3], srcPoints[4], srcPoints[5])

            val outputWidth = Math.max(topWidth, bottomWidth).toInt().coerceIn(100, 4096)
            val outputHeight = Math.max(leftHeight, rightHeight).toInt().coerceIn(100, 4096)

            // Destination points (corners of the output rectangle)
            val dstPoints = floatArrayOf(
                0f, 0f,                                    // top-left
                outputWidth.toFloat(), 0f,                  // top-right
                outputWidth.toFloat(), outputHeight.toFloat(), // bottom-right
                0f, outputHeight.toFloat()                  // bottom-left
            )

            // Calculate perspective transform matrix
            val matrix = Matrix()
            val success = matrix.setPolyToPoly(srcPoints, 0, dstPoints, 0, 4)

            if (!success) {
                return bitmap // Transform failed, return original
            }

            // Create output bitmap and apply transform
            val outputBitmap = Bitmap.createBitmap(outputWidth, outputHeight, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(outputBitmap)
            canvas.drawColor(Color.WHITE)

            val paint = Paint().apply {
                isAntiAlias = true
                isFilterBitmap = true
                isDither = true
            }

            canvas.drawBitmap(bitmap, matrix, paint)

            return outputBitmap
        }

        /**
         * Rotate a bitmap based on EXIF orientation metadata
         */
        fun rotateBitmapIfNeeded(bytes: ByteArray, bitmap: Bitmap): Bitmap {
            try {
                val exifInterface = android.media.ExifInterface(java.io.ByteArrayInputStream(bytes))
                val orientation = exifInterface.getAttributeInt(
                    android.media.ExifInterface.TAG_ORIENTATION,
                    android.media.ExifInterface.ORIENTATION_NORMAL
                )
                val matrix = Matrix()
                var angle = 0f
                when (orientation) {
                    android.media.ExifInterface.ORIENTATION_ROTATE_90 -> angle = 90f
                    android.media.ExifInterface.ORIENTATION_ROTATE_180 -> angle = 180f
                    android.media.ExifInterface.ORIENTATION_ROTATE_270 -> angle = 270f
                    else -> return bitmap
                }
                matrix.postRotate(angle)
                val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
                if (rotated != bitmap) {
                    bitmap.recycle()
                }
                return rotated
            } catch (e: Exception) {
                return bitmap
            }
        }

        /**
         * Enhance document scan: division-based background whitening and contrast/saturation boost.
         */
        fun enhanceDocument(bitmap: Bitmap): Bitmap {
            val width = bitmap.width
            val height = bitmap.height

            // 1. Create a downscaled version of the bitmap for background estimation
            val scale = 8
            val smallW = (width / scale).coerceAtLeast(10)
            val smallH = (height / scale).coerceAtLeast(10)
            val smallBitmap = Bitmap.createScaledBitmap(bitmap, smallW, smallH, true)

            val smallPixels = IntArray(smallW * smallH)
            smallBitmap.getPixels(smallPixels, 0, smallW, 0, 0, smallW, smallH)
            smallBitmap.recycle()

            // 2. Blur the downscaled version using horizontal and vertical box blur
            val blurredSmallPixels = boxBlur(smallPixels, smallW, smallH, 6)
            val blurredSmallBitmap = Bitmap.createBitmap(blurredSmallPixels, smallW, smallH, Bitmap.Config.ARGB_8888)

            // 3. Upscale the blurred background map back to full resolution bilinearly
            val blurredBgBitmap = Bitmap.createScaledBitmap(blurredSmallBitmap, width, height, true)
            blurredSmallBitmap.recycle()

            // 4. Perform division and contrast/saturation adjustment
            val origPixels = IntArray(width * height)
            val blurPixels = IntArray(width * height)
            bitmap.getPixels(origPixels, 0, width, 0, 0, width, height)
            blurredBgBitmap.getPixels(blurPixels, 0, width, 0, 0, width, height)
            blurredBgBitmap.recycle()

            val outPixels = IntArray(width * height)

            // Parameters aligned with iOS: gamma=2.2, contrast=2.4, brightness=-0.12 (scaled to 0-255 range: -30.6f)
            val contrast = 2.40f
            val brightness = -30.6f
            val saturation = 1.15f
            val gamma = 2.2f

            for (i in origPixels.indices) {
                val c = origPixels[i]
                val r = (c shr 16) and 0xFF
                val g = (c shr 8) and 0xFF
                val b = c and 0xFF

                val bc = blurPixels[i]
                val br = ((bc shr 16) and 0xFF).coerceAtLeast(1)
                val bg = ((bc shr 8) and 0xFF).coerceAtLeast(1)
                val bb = (bc and 0xFF).coerceAtLeast(1)

                // 1. Division: orig / blur
                val vr = (r.toFloat() / br.toFloat()).coerceIn(0f, 1f)
                val vg = (g.toFloat() / bg.toFloat()).coerceIn(0f, 1f)
                val vb = (b.toFloat() / bb.toFloat()).coerceIn(0f, 1f)

                // 2. Normal pencil-sharpening & background-whitening path
                val gr = Math.pow(vr.toDouble(), gamma.toDouble()).toFloat()
                val gg = Math.pow(vg.toDouble(), gamma.toDouble()).toFloat()
                val gb = Math.pow(vb.toDouble(), gamma.toDouble()).toFloat()

                // Contrast & Brightness formula: out = ((g - 0.5) * contrast + 0.5) * 255 + brightness
                var nr = (((gr - 0.5f) * contrast + 0.5f) * 255f + brightness).toInt().coerceIn(0, 255)
                var ng = (((gg - 0.5f) * contrast + 0.5f) * 255f + brightness).toInt().coerceIn(0, 255)
                var nb = (((gb - 0.5f) * contrast + 0.5f) * 255f + brightness).toInt().coerceIn(0, 255)

                // 4. Saturation adjustment
                if (saturation != 1.0f) {
                    val gray = (0.299f * nr + 0.587f * ng + 0.114f * nb)
                    nr = (gray + (nr - gray) * saturation).toInt().coerceIn(0, 255)
                    ng = (gray + (ng - gray) * saturation).toInt().coerceIn(0, 255)
                    nb = (gray + (nb - gray) * saturation).toInt().coerceIn(0, 255)
                }

                // 5. Red preservation: merge red content back
                if (isLikelyTeacherMarkColor(r, g, b)) {
                    nr = Math.max(r, 230)
                    ng = g
                    nb = b
                }


                outPixels[i] = (0xFF000000.toInt()) or (nr shl 16) or (ng shl 8) or nb
            }

            val outBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            outBitmap.setPixels(outPixels, 0, width, 0, 0, width, height)
            return outBitmap
        }

        private fun isLikelyTeacherMarkColor(r: Int, g: Int, b: Int): Boolean {
            val maxValue = maxOf(r, g, b)
            val minValue = minOf(r, g, b)
            val delta = maxValue - minValue
            val saturation = if (maxValue == 0) 0.0 else delta.toDouble() / maxValue.toDouble()
            var hue = 0.0

            if (delta > 0) {
                hue = when (maxValue) {
                    r -> ((g - b).toDouble() / delta.toDouble()) % 6.0
                    g -> ((b - r).toDouble() / delta.toDouble()) + 2.0
                    else -> ((r - g).toDouble() / delta.toDouble()) + 4.0
                }
                hue *= 60.0
                if (hue < 0) hue += 360.0
            }

            return (hue <= 35.0 || hue >= 325.0) &&
                saturation >= 0.30 &&
                maxValue >= 38 &&
                r > g + 10 &&
                r > b + 15
        }

        private fun boxBlur(pixels: IntArray, width: Int, height: Int, radius: Int): IntArray {
            val size = width * height
            val out = IntArray(size)
            val temp = IntArray(size)

            // Horizontal pass
            for (y in 0 until height) {
                var rSum = 0
                var gSum = 0
                var bSum = 0
                val rowOffset = y * width

                for (x in -radius until width + radius) {
                    val addX = x + radius
                    if (addX < width) {
                        val p = pixels[rowOffset + addX]
                        rSum += (p shr 16) and 0xFF
                        gSum += (p shr 8) and 0xFF
                        bSum += p and 0xFF
                    }

                    val removeX = x - radius
                    if (removeX >= 0) {
                        val p = pixels[rowOffset + removeX]
                        rSum -= (p shr 16) and 0xFF
                        gSum -= (p shr 8) and 0xFF
                        bSum -= p and 0xFF
                    }

                    if (x in 0 until width) {
                        val count = Math.min(x + radius, width - 1) - Math.max(x - radius, 0) + 1
                        val r = rSum / count
                        val g = gSum / count
                        val b = bSum / count
                        temp[rowOffset + x] = (0xFF000000.toInt()) or (r shl 16) or (g shl 8) or b
                    }
                }
            }

            // Vertical pass
            for (x in 0 until width) {
                var rSum = 0
                var gSum = 0
                var bSum = 0

                for (y in -radius until height + radius) {
                    val addY = y + radius
                    if (addY < height) {
                        val p = temp[addY * width + x]
                        rSum += (p shr 16) and 0xFF
                        gSum += (p shr 8) and 0xFF
                        bSum += p and 0xFF
                    }

                    val removeY = y - radius
                    if (removeY >= 0) {
                        val p = temp[removeY * width + x]
                        rSum -= (p shr 16) and 0xFF
                        gSum -= (p shr 8) and 0xFF
                        bSum -= p and 0xFF
                    }

                    if (y in 0 until height) {
                        val count = Math.min(y + radius, height - 1) - Math.max(y - radius, 0) + 1
                        val r = rSum / count
                        val g = gSum / count
                        val b = bSum / count
                        out[y * width + x] = (0xFF000000.toInt()) or (r shl 16) or (g shl 8) or b
                    }
                }
            }

            return out
        }

        /**
         * Save a bitmap as JPEG and return the file path
         */
        fun saveToFile(bitmap: Bitmap, cacheDir: File, pageNumber: Int, quality: Int): String {
            val dateFormat = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault())
            val timestamp = dateFormat.format(Date())
            val fileName = "DOCUMENT_SCAN_${pageNumber}_${timestamp}.jpg"
            val file = File(cacheDir, fileName)

            FileOutputStream(file).use { fos ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, quality, fos)
            }

            return file.absolutePath
        }

        /**
         * Convert a bitmap to base64 string
         */
        fun toBase64(bitmap: Bitmap, quality: Int): String {
            val byteArrayOutputStream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, quality, byteArrayOutputStream)
            val byteArray = byteArrayOutputStream.toByteArray()
            return Base64.encodeToString(byteArray, Base64.DEFAULT)
        }

        /**
         * Calculate distance between two points
         */
        private fun distance(x1: Float, y1: Float, x2: Float, y2: Float): Float {
            val dx = x2 - x1
            val dy = y2 - y1
            return Math.sqrt((dx * dx + dy * dy).toDouble()).toFloat()
        }
    }
}
