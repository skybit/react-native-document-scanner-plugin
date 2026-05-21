package com.documentscanner.customscanner

import android.graphics.*
import android.util.Base64
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.*

/**
 * Processes captured images: perspective correction using Matrix.setPolyToPoly()
 * and saving as JPEG files or base64 strings.
 */
class ImageProcessor {

    companion object {
        /**
         * Apply perspective correction to an image given 4 corner points.
         *
         * @param bitmap The source image
         * @param corners 8 floats: top-left(x,y), top-right(x,y), bottom-right(x,y), bottom-left(x,y)
         * @return The corrected bitmap
         */
        fun applyPerspectiveCorrection(bitmap: Bitmap, corners: FloatArray?): Bitmap {
            if (corners == null || corners.size != 8) {
                return bitmap // No corners, return original
            }

            // Calculate the output dimensions based on document corners
            val topWidth = distance(corners[0], corners[1], corners[2], corners[3])
            val bottomWidth = distance(corners[6], corners[7], corners[4], corners[5])
            val leftHeight = distance(corners[0], corners[1], corners[6], corners[7])
            val rightHeight = distance(corners[2], corners[3], corners[4], corners[5])

            val outputWidth = Math.max(topWidth, bottomWidth).toInt().coerceIn(100, 4096)
            val outputHeight = Math.max(leftHeight, rightHeight).toInt().coerceIn(100, 4096)

            // Source points (document corners in the original image)
            val srcPoints = corners

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
