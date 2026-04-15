package io.hazor.shield

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.security.MessageDigest

/**
 * Hazor Shield Flutter plugin — Android platform channel.
 *
 * Play Integrity API has two modes:
 * - **Standard** (recommended): warm-token via `prepareIntegrityToken`
 *   at startup, then fast `request(requestHash)` per call. Needs a
 *   Google Cloud project number declared in the hosting app's
 *   `AndroidManifest.xml`:
 *
 *   ```xml
 *   <meta-data
 *       android:name="io.hazor.shield.cloudProjectNumber"
 *       android:value="123456789012" />
 *   ```
 *
 * - **Classic**: per-call `requestIntegrityToken`. Slower but no cloud
 *   project number required. Used as fallback when the meta-data is
 *   missing or Standard preparation fails.
 *
 * Method channel contract (matches attestation.dart):
 *   requestPlayIntegrity(nonce) → String token
 */
class HazorShieldPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var appContext: Context? = null

    private var standardProvider: StandardIntegrityTokenProvider? = null
    private var cloudProjectNumber: Long? = null
    private var preparingProvider: Boolean = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "io.hazor.shield/attestation")
        channel.setMethodCallHandler(this)
        appContext = binding.applicationContext
        cloudProjectNumber = readCloudProjectNumber(binding.applicationContext)
        prepareStandardProviderIfPossible()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        standardProvider = null
        appContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "requestPlayIntegrity" -> {
                val nonce = call.argument<String>("nonce") ?: ""
                requestPlayIntegrity(nonce, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun requestPlayIntegrity(nonce: String, result: Result) {
        val provider = standardProvider
        if (provider != null) {
            requestStandard(provider, nonce, result)
            return
        }
        // Standard wasn't prepared (missing cloud project number or
        // preparation failed) — try Classic. Also fire a lazy retry
        // for Standard in case preparation happens to finish later.
        prepareStandardProviderIfPossible()
        requestClassic(nonce, result)
    }

    private fun requestStandard(
        provider: StandardIntegrityTokenProvider,
        nonce: String,
        result: Result,
    ) {
        val requestHash = sha256Base64(nonce)
        val req = StandardIntegrityTokenRequest.builder()
            .setRequestHash(requestHash)
            .build()
        provider.request(req)
            .addOnSuccessListener { response ->
                result.success(response.token())
            }
            .addOnFailureListener { e ->
                // If Standard fails at request time, try Classic as a
                // last-ditch fallback — on older Play Services builds,
                // Standard can return transient errors while Classic
                // still works.
                requestClassic(nonce, result, fallbackError = e)
            }
    }

    private fun requestClassic(nonce: String, result: Result, fallbackError: Throwable? = null) {
        val act = activity
        val ctx = appContext
        if (act == null && ctx == null) {
            result.error(
                "NO_CONTEXT",
                "Neither activity nor application context available",
                fallbackError?.message,
            )
            return
        }
        val manager = IntegrityManagerFactory.create(act ?: ctx!!)
        val request = IntegrityTokenRequest.builder()
            .setNonce(nonce)
            .apply { cloudProjectNumber?.let { setCloudProjectNumber(it) } }
            .build()
        manager.requestIntegrityToken(request)
            .addOnSuccessListener { response ->
                result.success(response.token())
            }
            .addOnFailureListener { e ->
                result.error(
                    "PLAY_INTEGRITY_FAILED",
                    e.message ?: "Play Integrity failed",
                    fallbackError?.message,
                )
            }
    }

    @Synchronized
    private fun prepareStandardProviderIfPossible() {
        if (standardProvider != null || preparingProvider) return
        val cpn = cloudProjectNumber ?: return
        val ctx = appContext ?: return
        preparingProvider = true
        val manager = IntegrityManagerFactory.createStandard(ctx)
        val prep = PrepareIntegrityTokenRequest.builder()
            .setCloudProjectNumber(cpn)
            .build()
        manager.prepareIntegrityToken(prep)
            .addOnSuccessListener { provider ->
                synchronized(this) {
                    standardProvider = provider
                    preparingProvider = false
                }
            }
            .addOnFailureListener {
                synchronized(this) { preparingProvider = false }
                // Leave standardProvider null — classic fallback will
                // kick in on every request.
            }
    }

    private fun readCloudProjectNumber(ctx: Context): Long? {
        return try {
            val ai = ctx.packageManager.getApplicationInfo(
                ctx.packageName,
                PackageManager.GET_META_DATA,
            )
            val bundle = ai.metaData ?: return null
            // Manifest values arrive as String or Integer depending on
            // android:value vs android:resource. Be permissive.
            when (val v = bundle.get("io.hazor.shield.cloudProjectNumber")) {
                is Long -> v
                is Int -> v.toLong()
                is String -> v.toLongOrNull()
                else -> null
            }
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
    }

    private fun sha256Base64(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(input.toByteArray())
        return android.util.Base64.encodeToString(
            digest,
            android.util.Base64.NO_WRAP or android.util.Base64.URL_SAFE or android.util.Base64.NO_PADDING,
        )
    }
}
