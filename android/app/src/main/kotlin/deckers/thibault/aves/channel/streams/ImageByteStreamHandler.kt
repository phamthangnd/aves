package deckers.thibault.aves.channel.streams

import android.app.Activity
import android.graphics.Bitmap
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.bumptech.glide.Glide
import com.bumptech.glide.load.DecodeFormat
import com.bumptech.glide.load.engine.DiskCacheStrategy
import com.bumptech.glide.request.RequestOptions
import deckers.thibault.aves.decoder.VideoThumbnail
import deckers.thibault.aves.utils.BitmapUtils.applyExifOrientation
import deckers.thibault.aves.utils.MimeTypes.canHaveAlpha
import deckers.thibault.aves.utils.MimeTypes.isSupportedByFlutter
import deckers.thibault.aves.utils.MimeTypes.isVideo
import deckers.thibault.aves.utils.MimeTypes.needRotationAfterGlide
import deckers.thibault.aves.utils.StorageUtils.openInputStream
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream

class ImageByteStreamHandler(private val activity: Activity, private val arguments: Any?) : EventChannel.StreamHandler {
    private lateinit var eventSink: EventSink
    private lateinit var handler: Handler

    override fun onListen(args: Any, eventSink: EventSink) {
        this.eventSink = eventSink
        handler = Handler(Looper.getMainLooper())

        Thread { streamImage() }.start()
    }

    override fun onCancel(o: Any) {}

    private fun success(bytes: ByteArray) {
        handler.post { eventSink.success(bytes) }
    }

    private fun error(errorCode: String, errorMessage: String, errorDetails: Any?) {
        handler.post { eventSink.error(errorCode, errorMessage, errorDetails) }
    }

    private fun endOfStream() {
        handler.post { eventSink.endOfStream() }
    }

    // Supported image formats:
    // - Flutter (as of v1.20): JPEG, PNG, GIF, Animated GIF, WebP, Animated WebP, BMP, and WBMP
    // - Android: https://developer.android.com/guide/topics/media/media-formats#image-formats
    // - Glide: https://github.com/bumptech/glide/blob/master/library/src/main/java/com/bumptech/glide/load/ImageHeaderParser.java
    private fun streamImage() {
        if (arguments !is Map<*, *>) {
            endOfStream()
            return
        }

        val mimeType = arguments["mimeType"] as String?
        val uri = (arguments["uri"] as String?)?.let { Uri.parse(it) }
        val rotationDegrees = arguments["rotationDegrees"] as Int
        val isFlipped = arguments["isFlipped"] as Boolean

        if (mimeType == null || uri == null) {
            error("streamImage-args", "failed because of missing arguments", null)
            endOfStream()
            return
        }

        if (isVideo(mimeType)) {
            streamVideoByGlide(uri)
        } else if (!isSupportedByFlutter(mimeType, rotationDegrees, isFlipped)) {
            // decode exotic format on platform side, then encode it in portable format for Flutter
            streamImageByGlide(uri, mimeType, rotationDegrees, isFlipped)
        } else {
            // to be decoded by Flutter
            streamImageAsIs(uri)
        }
        endOfStream()
    }

    private fun streamImageAsIs(uri: Uri) {
        try {
            openInputStream(activity, uri).use { input -> input?.let { streamBytes(it) } }
        } catch (e: IOException) {
            error("streamImage-image-read-exception", "failed to get image from uri=$uri", e.message)
        }
    }

    private fun streamImageByGlide(uri: Uri, mimeType: String, rotationDegrees: Int, isFlipped: Boolean) {
        val target = Glide.with(activity)
            .asBitmap()
            .apply(options)
            .load(uri)
            .submit()
        try {
            var bitmap = target.get()
            if (needRotationAfterGlide(mimeType)) {
                bitmap = applyExifOrientation(activity, bitmap, rotationDegrees, isFlipped)
            }
            if (bitmap != null) {
                val stream = ByteArrayOutputStream()
                // we compress the bitmap because Dart Image.memory cannot decode the raw bytes
                // Bitmap.CompressFormat.PNG is slower than JPEG, but it allows transparency
                if (canHaveAlpha(mimeType)) {
                    bitmap.compress(Bitmap.CompressFormat.PNG, 0, stream)
                } else {
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 100, stream)
                }
                success(stream.toByteArray())
            } else {
                error("streamImage-image-decode-null", "failed to get image from uri=$uri", null)
            }
        } catch (e: Exception) {
            var errorDetails = e.message
            if (errorDetails?.isNotEmpty() == true) {
                errorDetails = errorDetails.split("\n".toRegex(), 2).first()
            }
            error("streamImage-image-decode-exception", "failed to get image from uri=$uri", errorDetails)
        } finally {
            Glide.with(activity).clear(target)
        }
    }

    private fun streamVideoByGlide(uri: Uri) {
        val target = Glide.with(activity)
            .asBitmap()
            .apply(options)
            .load(VideoThumbnail(activity, uri))
            .submit()
        try {
            val bitmap = target.get()
            if (bitmap != null) {
                val stream = ByteArrayOutputStream()
                // we compress the bitmap because Dart Image.memory cannot decode the raw bytes
                // Bitmap.CompressFormat.PNG is slower than JPEG
                bitmap.compress(Bitmap.CompressFormat.JPEG, 100, stream)
                success(stream.toByteArray())
            } else {
                error("streamImage-video-null", "failed to get image from uri=$uri", null)
            }
        } catch (e: Exception) {
            error("streamImage-video-exception", "failed to get image from uri=$uri", e.message)
        } finally {
            Glide.with(activity).clear(target)
        }
    }

    private fun streamBytes(inputStream: InputStream) {
        val buffer = ByteArray(bufferSize)
        var len: Int
        while (inputStream.read(buffer).also { len = it } != -1) {
            // cannot decode image on Flutter side when using `buffer` directly
            success(buffer.copyOf(len))
        }
    }

    companion object {
        const val CHANNEL = "deckers.thibault/aves/imagebytestream"

        const val bufferSize = 2 shl 17 // 256kB

        // request a fresh image with the highest quality format
        val options = RequestOptions()
            .format(DecodeFormat.PREFER_ARGB_8888)
            .diskCacheStrategy(DiskCacheStrategy.NONE)
            .skipMemoryCache(true)
    }
}