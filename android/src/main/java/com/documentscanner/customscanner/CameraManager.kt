package com.documentscanner.customscanner

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.camera2.*
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Size
import android.view.Surface
import android.view.TextureView
import androidx.core.content.ContextCompat

/**
 * Manages Camera2 API lifecycle for document scanning.
 * Provides camera preview on a TextureView and supports photo capture.
 */
class CameraManager(private val context: Context) {

    interface CameraCallback {
        fun onPreviewFrame(image: Image)
        fun onPhotoCaptured(image: Image)
        fun onError(message: String)
    }

    var callback: CameraCallback? = null

    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var previewImageReader: ImageReader? = null
    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null
    private var textureView: TextureView? = null

    // Camera characteristics
    private var previewSize: Size = Size(1920, 1080)

    /**
     * Start the camera preview on the given TextureView
     */
    fun startCamera(textureView: TextureView) {
        this.textureView = textureView
        startBackgroundThread()

        if (textureView.isAvailable) {
            openCamera()
        } else {
            textureView.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
                    openCamera()
                }
                override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {}
                override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean = true
                override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {}
            }
        }
    }

    /**
     * Stop the camera and release resources
     */
    fun stopCamera() {
        try {
            captureSession?.close()
            captureSession = null
            cameraDevice?.close()
            cameraDevice = null
            imageReader?.close()
            imageReader = null
            previewImageReader?.close()
            previewImageReader = null
            stopBackgroundThread()
        } catch (e: Exception) {
            // Ignore cleanup errors
        }
    }

    /**
     * Capture a high-resolution photo
     */
    fun capturePhoto() {
        val camera = cameraDevice ?: return
        val session = captureSession ?: return
        val reader = imageReader ?: return

        try {
            val captureBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE).apply {
                addTarget(reader.surface)
                set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                set(CaptureRequest.JPEG_QUALITY, 100.toByte())
            }

            session.capture(captureBuilder.build(), object : CameraCaptureSession.CaptureCallback() {
                override fun onCaptureFailed(session: CameraCaptureSession, request: CaptureRequest, failure: CaptureFailure) {
                    callback?.onError("Photo capture failed")
                }
            }, backgroundHandler)
        } catch (e: CameraAccessException) {
            callback?.onError("Camera access error: ${e.message}")
        }
    }

    // MARK: - Private methods

    private fun openCamera() {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED) {
            callback?.onError("Camera permission not granted")
            return
        }

        val manager = context.getSystemService(Context.CAMERA_SERVICE) as android.hardware.camera2.CameraManager

        try {
            // Find the back-facing camera
            val cameraId = manager.cameraIdList.firstOrNull { id ->
                val characteristics = manager.getCameraCharacteristics(id)
                characteristics.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
            } ?: run {
                callback?.onError("No back camera found")
                return
            }

            val characteristics = manager.getCameraCharacteristics(cameraId)
            val map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)

            // Select appropriate preview size
            map?.getOutputSizes(SurfaceTexture::class.java)?.let { sizes ->
                previewSize = chooseOptimalSize(sizes)
            }

            // Create ImageReader for photo capture
            imageReader = ImageReader.newInstance(
                previewSize.width, previewSize.height,
                ImageFormat.JPEG, 2
            ).apply {
                setOnImageAvailableListener({ reader ->
                    reader.acquireLatestImage()?.let { image ->
                        callback?.onPhotoCaptured(image)
                    }
                }, backgroundHandler)
            }

            manager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraDevice = camera
                    createPreviewSession()
                }
                override fun onDisconnected(camera: CameraDevice) {
                    camera.close()
                    cameraDevice = null
                }
                override fun onError(camera: CameraDevice, error: Int) {
                    camera.close()
                    cameraDevice = null
                    callback?.onError("Camera error: $error")
                }
            }, backgroundHandler)
        } catch (e: CameraAccessException) {
            callback?.onError("Unable to access camera: ${e.message}")
        } catch (e: SecurityException) {
            callback?.onError("Camera permission denied")
        }
    }

    private fun createPreviewSession() {
        val camera = cameraDevice ?: return
        val texture = textureView ?: return
        val reader = imageReader ?: return

        try {
            val surfaceTexture = texture.surfaceTexture ?: return
            surfaceTexture.setDefaultBufferSize(previewSize.width, previewSize.height)
            val previewSurface = Surface(surfaceTexture)

            val previewRequest = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                addTarget(previewSurface)
                set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
            }

            camera.createCaptureSession(
                listOf(previewSurface, reader.surface),
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        captureSession = session
                        try {
                            session.setRepeatingRequest(previewRequest.build(), null, backgroundHandler)
                        } catch (e: CameraAccessException) {
                            callback?.onError("Failed to start preview: ${e.message}")
                        }
                    }
                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        callback?.onError("Camera configuration failed")
                    }
                },
                backgroundHandler
            )
        } catch (e: CameraAccessException) {
            callback?.onError("Failed to create preview session: ${e.message}")
        }
    }

    private fun chooseOptimalSize(sizes: Array<Size>): Size {
        // Prefer sizes around 1920x1080 for good quality without being too large
        val targetWidth = 1920
        val targetHeight = 1080

        return sizes
            .filter { it.width <= 2560 && it.height <= 1920 }
            .minByOrNull { Math.abs(it.width - targetWidth) + Math.abs(it.height - targetHeight) }
            ?: sizes.first()
    }

    private fun startBackgroundThread() {
        backgroundThread = HandlerThread("CameraBackground").also { it.start() }
        backgroundHandler = Handler(backgroundThread!!.looper)
    }

    private fun stopBackgroundThread() {
        backgroundThread?.quitSafely()
        try {
            backgroundThread?.join()
            backgroundThread = null
            backgroundHandler = null
        } catch (e: InterruptedException) {
            // Ignore
        }
    }
}
