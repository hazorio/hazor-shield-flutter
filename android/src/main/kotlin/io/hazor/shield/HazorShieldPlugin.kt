package io.hazor.shield

import android.app.Activity
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class HazorShieldPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "io.hazor.shield/attestation")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

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
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "Activity not available", null)
            return
        }
        val manager = IntegrityManagerFactory.create(act)
        val request = IntegrityTokenRequest.builder()
            .setNonce(nonce)
            .build()
        manager.requestIntegrityToken(request)
            .addOnSuccessListener { response ->
                result.success(response.token())
            }
            .addOnFailureListener { e ->
                result.error("PLAY_INTEGRITY_FAILED", e.message, null)
            }
    }
}
