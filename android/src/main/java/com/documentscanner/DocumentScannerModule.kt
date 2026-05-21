package com.documentscanner

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Base64
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.IntentSenderRequest
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts.StartActivityForResult
import androidx.activity.result.contract.ActivityResultContracts.StartIntentSenderForResult
import com.documentscanner.customscanner.ScannerActivity
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.WritableArray
import com.facebook.react.bridge.WritableMap
import com.facebook.react.bridge.WritableNativeArray
import com.facebook.react.bridge.WritableNativeMap
import com.facebook.react.module.annotations.ReactModule
import com.google.mlkit.vision.documentscanner.GmsDocumentScanner
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult.Page
import java.io.ByteArrayOutputStream
import java.io.FileNotFoundException
import java.util.Objects

@ReactModule(name = DocumentScannerModule.NAME)
class DocumentScannerModule(reactContext: ReactApplicationContext) :
  NativeDocumentScannerSpec(reactContext) {

  override fun getName(): String {
    return NAME
  }

  @Throws(FileNotFoundException::class)
  fun getImageInBase64(currentActivity: Activity, croppedImageUri: Uri, quality: Int): String {
    val bitmap = BitmapFactory.decodeStream(
      currentActivity.contentResolver.openInputStream(croppedImageUri)
    )
    val byteArrayOutputStream = ByteArrayOutputStream()
    bitmap.compress(Bitmap.CompressFormat.JPEG, quality, byteArrayOutputStream)
    val byteArray = byteArrayOutputStream.toByteArray()
    return Base64.encodeToString(byteArray, Base64.DEFAULT)
  }

  override fun scanDocument(options: ReadableMap, promise: Promise) {
    val currentActivity = reactApplicationContext.getCurrentActivity()
    val maxNumDocuments = if (options.hasKey("maxNumDocuments")) options.getInt("maxNumDocuments") else null
    val autoConfirm = if (options.hasKey("autoConfirm")) options.getBoolean("autoConfirm") else true

    if (maxNumDocuments != null && maxNumDocuments > 0 && autoConfirm) {
      // Use custom scanner when maxNumDocuments is set with autoConfirm
      launchCustomScanner(currentActivity, options, maxNumDocuments, autoConfirm, promise)
    } else if (maxNumDocuments != null && maxNumDocuments > 0) {
      // Use custom scanner for page-limited scanning without autoConfirm too
      launchCustomScanner(currentActivity, options, maxNumDocuments, autoConfirm, promise)
    } else {
      // Use ML Kit scanner (existing behavior)
      launchMLKitScanner(currentActivity, options, promise)
    }
  }

  // MARK: - Custom Scanner

  private fun launchCustomScanner(
    currentActivity: Activity?,
    options: ReadableMap,
    maxNumDocuments: Int,
    autoConfirm: Boolean,
    promise: Promise
  ) {
    if (currentActivity == null) {
      promise.reject("error", "Unable to get current activity")
      return
    }

    val croppedImageQuality = if (options.hasKey("croppedImageQuality")) {
      options.getInt("croppedImageQuality")
    } else {
      100
    }
    val responseType = if (options.hasKey("responseType")) {
      options.getString("responseType") ?: "imageFilePath"
    } else {
      "imageFilePath"
    }

    val scannerLauncher = (currentActivity as ComponentActivity).activityResultRegistry.register(
      "custom-document-scanner",
      StartActivityForResult()
    ) { result ->
      val response: WritableMap = WritableNativeMap()

      if (result.resultCode == Activity.RESULT_OK) {
        val scannedImages = result.data?.getStringArrayListExtra(ScannerActivity.EXTRA_SCANNED_IMAGES)
        val docScanResults: WritableArray = WritableNativeArray()

        scannedImages?.forEach { imagePath ->
          docScanResults.pushString(imagePath)
        }

        response.putArray("scannedImages", docScanResults)
        response.putString("status", "success")
        promise.resolve(response)
      } else {
        response.putString("status", "cancel")
        promise.resolve(response)
      }
    }

    val intent = Intent(currentActivity, ScannerActivity::class.java).apply {
      putExtra(ScannerActivity.EXTRA_MAX_NUM_DOCUMENTS, maxNumDocuments)
      putExtra(ScannerActivity.EXTRA_AUTO_CONFIRM, autoConfirm)
      putExtra(ScannerActivity.EXTRA_RESPONSE_TYPE, responseType)
      putExtra(ScannerActivity.EXTRA_CROPPED_IMAGE_QUALITY, croppedImageQuality)
    }

    scannerLauncher.launch(intent)
  }

  // MARK: - ML Kit Scanner (existing behavior)

  private fun launchMLKitScanner(
    currentActivity: Activity?,
    options: ReadableMap,
    promise: Promise
  ) {
    val response: WritableMap = WritableNativeMap()

    val documentScannerOptionsBuilder = GmsDocumentScannerOptions.Builder()
      .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
      .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)

    if (options.hasKey("maxNumDocuments")) {
      documentScannerOptionsBuilder.setPageLimit(
        options.getInt("maxNumDocuments")
      )
    }

    val croppedImageQuality: Int = if (options.hasKey("croppedImageQuality")) {
      options.getInt("croppedImageQuality")
    } else {
      100
    }

    val scanner: GmsDocumentScanner =
      GmsDocumentScanning.getClient(documentScannerOptionsBuilder.build())
    val scannerLauncher: ActivityResultLauncher<IntentSenderRequest?> =
      (currentActivity as ComponentActivity).activityResultRegistry.register(
        "document-scanner",
        StartIntentSenderForResult(),
        { result ->
          if (result.resultCode == Activity.RESULT_OK) {
            val documentScanningResult: GmsDocumentScanningResult? =
              GmsDocumentScanningResult.fromActivityResultIntent(
                result.data
              )
            val docScanResults: WritableArray = WritableNativeArray()

            if (documentScanningResult != null) {
              val pages: MutableList<Page>? = documentScanningResult.pages
              if (pages != null) {
                for (page in pages) {
                  val croppedImageUri: Uri = page.imageUri
                  var croppedImageResults: String? = croppedImageUri.toString()

                  if (options.hasKey("responseType") && Objects.equals(
                      options.getString("responseType"),
                      "base64"
                    )
                  ) {
                    try {
                      croppedImageResults =
                        this.getImageInBase64(currentActivity, croppedImageUri, croppedImageQuality)
                    } catch (error: FileNotFoundException) {
                      promise.reject("document scan error", error.message)
                    }
                  }

                  docScanResults.pushString(croppedImageResults)
                }
              }
            }

            response.putArray(
              "scannedImages",
              docScanResults
            )
            response.putString("status", "success")
            promise.resolve(response)
          } else if (result.resultCode == Activity.RESULT_CANCELED) {
            // when user cancels document scan
            response.putString("status", "cancel")
            promise.resolve(response)
          }
        }
      )

    scanner.getStartScanIntent(currentActivity)
      .addOnSuccessListener({ intentSender ->
        scannerLauncher.launch(
          IntentSenderRequest.Builder(
            intentSender
          ).build()
        )
      })
      .addOnFailureListener({ error ->
        // document scan error
        promise.reject("document scan error", error.message)
      })
  }

  companion object {
    const val NAME = "DocumentScanner"
  }
}
