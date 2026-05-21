package com.documentscanner.customscanner

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.media.Image
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.TextureView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import java.io.ByteArrayOutputStream

/**
 * Custom document scanner Activity with Camera2 API.
 * Supports page limits and auto-confirm (auto-close after reaching limit).
 *
 * Intent Extras (input):
 * - "maxNumDocuments" (Int): maximum pages to scan
 * - "autoConfirm" (Boolean): auto-close after reaching limit
 * - "responseType" (String): "imageFilePath" or "base64"
 * - "croppedImageQuality" (Int): JPEG quality 0-100
 *
 * Result Extras (output):
 * - "scannedImages" (ArrayList<String>): file paths or base64 strings
 */
class ScannerActivity : Activity() {

    companion object {
        const val EXTRA_MAX_NUM_DOCUMENTS = "maxNumDocuments"
        const val EXTRA_AUTO_CONFIRM = "autoConfirm"
        const val EXTRA_RESPONSE_TYPE = "responseType"
        const val EXTRA_CROPPED_IMAGE_QUALITY = "croppedImageQuality"
        const val EXTRA_SCANNED_IMAGES = "scannedImages"
        private const val CAMERA_PERMISSION_REQUEST = 1001
    }

    // Configuration
    private var maxNumDocuments = 1
    private var autoConfirm = true
    private var responseType = "imageFilePath"
    private var croppedImageQuality = 100

    // Components
    private lateinit var cameraManager: CameraManager
    private val documentDetector = DocumentDetector()

    // UI elements
    private lateinit var textureView: TextureView
    private lateinit var overlayView: ScannerOverlayView
    private lateinit var captureButton: View
    private lateinit var doneButton: View
    private lateinit var pageCounterLabel: TextView
    private lateinit var statusLabel: TextView

    // State
    private val scannedResults = ArrayList<String>()
    private var currentCorners: FloatArray? = null
    private var isScanComplete = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Parse intent extras
        maxNumDocuments = intent.getIntExtra(EXTRA_MAX_NUM_DOCUMENTS, 1)
        autoConfirm = intent.getBooleanExtra(EXTRA_AUTO_CONFIRM, true)
        responseType = intent.getStringExtra(EXTRA_RESPONSE_TYPE) ?: "imageFilePath"
        croppedImageQuality = intent.getIntExtra(EXTRA_CROPPED_IMAGE_QUALITY, 100)

        // Fullscreen dark theme
        window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        )

        setupUI()
        setupDetector()

        // Check camera permission
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            == PackageManager.PERMISSION_GRANTED) {
            startCamera()
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CAMERA),
                CAMERA_PERMISSION_REQUEST
            )
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        cameraManager.stopCamera()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (requestCode == CAMERA_PERMISSION_REQUEST) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                startCamera()
            } else {
                setResult(RESULT_CANCELED)
                finish()
            }
        }
    }

    // MARK: - UI Setup

    private fun setupUI() {
        val rootLayout = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
        }

        // Camera preview
        textureView = TextureView(this)
        rootLayout.addView(textureView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // Document edge overlay
        overlayView = ScannerOverlayView(this)
        rootLayout.addView(overlayView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // Top bar with cancel button and status
        val topBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(8), dp(16), dp(8))
        }

        val cancelButton = TextView(this).apply {
            text = "✕"
            textSize = 24f
            setTextColor(Color.WHITE)
            setPadding(dp(12), dp(8), dp(12), dp(8))
            setOnClickListener { cancelScan() }
        }
        topBar.addView(cancelButton)

        statusLabel = TextView(this).apply {
            text = "Position document in view"
            textSize = 14f
            setTextColor(Color.parseColor("#CCFFFFFF"))
            gravity = Gravity.CENTER
            setPadding(dp(8), 0, dp(8), 0)
        }
        topBar.addView(statusLabel, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

        // Spacer for symmetry
        val spacer = View(this)
        topBar.addView(spacer, LinearLayout.LayoutParams(dp(48), dp(48)))

        rootLayout.addView(topBar, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.TOP
        ))

        // Bottom bar
        val bottomBar = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(Color.parseColor("#B3000000")) // 70% black
            setPadding(0, dp(16), 0, dp(32))
        }

        // Capture button - white circle
        captureButton = View(this).apply {
            background = createCaptureButtonDrawable()
            setOnClickListener { onCaptureButtonTapped() }
        }
        val captureSize = dp(70)
        bottomBar.addView(captureButton, LinearLayout.LayoutParams(captureSize, captureSize).apply {
            gravity = Gravity.CENTER_HORIZONTAL
        })

        // Done button (initially hidden)
        doneButton = TextView(this).apply {
            text = "Done"
            textSize = 18f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#2196F3"))
            setPadding(dp(32), dp(12), dp(32), dp(12))
            visibility = View.GONE
            setOnClickListener { finishScan() }
        }
        bottomBar.addView(doneButton, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.CENTER_HORIZONTAL
            topMargin = dp(8)
        })

        // Page counter
        pageCounterLabel = TextView(this).apply {
            textSize = 16f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            typeface = android.graphics.Typeface.MONOSPACE
        }
        bottomBar.addView(pageCounterLabel, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            topMargin = dp(8)
            gravity = Gravity.CENTER_HORIZONTAL
        })

        rootLayout.addView(bottomBar, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM
        ))

        setContentView(rootLayout)
        updatePageCounter()
    }

    private fun createCaptureButtonDrawable(): android.graphics.drawable.Drawable {
        return object : android.graphics.drawable.Drawable() {
            private val borderPaint = android.graphics.Paint().apply {
                color = Color.WHITE
                style = android.graphics.Paint.Style.STROKE
                strokeWidth = 6f
                isAntiAlias = true
            }
            private val fillPaint = android.graphics.Paint().apply {
                color = Color.parseColor("#4DFFFFFF") // 30% white
                style = android.graphics.Paint.Style.FILL
                isAntiAlias = true
            }
            override fun draw(canvas: android.graphics.Canvas) {
                val cx = bounds.exactCenterX()
                val cy = bounds.exactCenterY()
                val radius = Math.min(cx, cy) - 4f
                canvas.drawCircle(cx, cy, radius, fillPaint)
                canvas.drawCircle(cx, cy, radius, borderPaint)
            }
            override fun setAlpha(alpha: Int) {}
            override fun setColorFilter(colorFilter: android.graphics.ColorFilter?) {}
            override fun getOpacity(): Int = android.graphics.PixelFormat.TRANSLUCENT
        }
    }

    // MARK: - Camera & Detection

    private fun startCamera() {
        cameraManager = CameraManager(this)
        cameraManager.callback = object : CameraManager.CameraCallback {
            override fun onPreviewFrame(image: Image) {
                // Not used with current Camera2 setup
            }

            override fun onPhotoCaptured(image: Image) {
                processPhoto(image)
            }

            override fun onError(message: String) {
                runOnUiThread {
                    statusLabel.text = "Error: $message"
                }
            }
        }
        cameraManager.startCamera(textureView)
    }

    private fun setupDetector() {
        documentDetector.listener = object : DocumentDetector.OnDocumentDetectedListener {
            override fun onDocumentDetected(corners: FloatArray) {
                runOnUiThread {
                    currentCorners = corners
                    overlayView.setDocumentCorners(corners,
                        textureView.width, textureView.height)
                    statusLabel.text = "Hold steady..."
                }
            }

            override fun onDocumentStable(corners: FloatArray) {
                runOnUiThread {
                    if (!isScanComplete) {
                        currentCorners = corners
                        statusLabel.text = "Auto-capturing..."
                        performCapture()
                    }
                }
            }

            override fun onDocumentLost() {
                runOnUiThread {
                    currentCorners = null
                    overlayView.clearOverlay()
                    if (!isScanComplete) {
                        statusLabel.text = "Position document in view"
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private fun onCaptureButtonTapped() {
        if (isScanComplete) return
        performCapture()
    }

    private fun performCapture() {
        documentDetector.isEnabled = false
        statusLabel.text = "Capturing..."

        // Flash effect
        val flashView = View(this).apply {
            setBackgroundColor(Color.WHITE)
            alpha = 0f
        }
        (window.decorView as FrameLayout).addView(flashView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
        flashView.animate().alpha(0.5f).setDuration(100).withEndAction {
            flashView.animate().alpha(0f).setDuration(100).withEndAction {
                (window.decorView as FrameLayout).removeView(flashView)
            }
        }

        cameraManager.capturePhoto()
    }

    private fun processPhoto(image: Image) {
        val buffer = image.planes[0].buffer
        val bytes = ByteArray(buffer.remaining())
        buffer.get(bytes)
        image.close()

        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: run {
            runOnUiThread { statusLabel.text = "Failed to process image" }
            return
        }

        Thread {
            val corrected = ImageProcessor.applyPerspectiveCorrection(bitmap, currentCorners)

            val result = when (responseType) {
                "base64" -> ImageProcessor.toBase64(corrected, croppedImageQuality)
                else -> ImageProcessor.saveToFile(corrected, cacheDir, scannedResults.size, croppedImageQuality)
            }

            if (corrected != bitmap) corrected.recycle()
            bitmap.recycle()

            runOnUiThread {
                scannedResults.add(result)
                updatePageCounter()

                if (scannedResults.size >= maxNumDocuments) {
                    handleScanComplete()
                } else {
                    documentDetector.resetStability()
                    documentDetector.isEnabled = true
                    statusLabel.text = "Position next document"
                }
            }
        }.start()
    }

    private fun handleScanComplete() {
        isScanComplete = true
        documentDetector.isEnabled = false
        overlayView.clearOverlay()

        if (autoConfirm) {
            finishScan()
        } else {
            captureButton.visibility = View.GONE
            doneButton.visibility = View.VISIBLE
            statusLabel.text = "Scan complete. Tap Done to confirm."
        }
    }

    private fun finishScan() {
        cameraManager.stopCamera()
        val resultIntent = Intent().apply {
            putStringArrayListExtra(EXTRA_SCANNED_IMAGES, scannedResults)
        }
        setResult(RESULT_OK, resultIntent)
        finish()
    }

    private fun cancelScan() {
        cameraManager.stopCamera()
        setResult(RESULT_CANCELED)
        finish()
    }

    // MARK: - Helpers

    private fun updatePageCounter() {
        pageCounterLabel.text = "${scannedResults.size}/${maxNumDocuments}"
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }
}
