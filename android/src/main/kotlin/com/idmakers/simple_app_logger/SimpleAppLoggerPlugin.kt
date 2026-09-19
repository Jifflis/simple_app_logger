package com.idmakers.simple_app_logger

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

class SimpleAppLoggerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var previousHandler: Thread.UncaughtExceptionHandler? = null
    private var installed = false

    external fun installSignalHandler(path: String)
    external fun uninstallSignalHandler()

    companion object {
        init { System.loadLibrary("simple_app_logger_crash") }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "simple_app_logger/native_crashes")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "acknowledge") {
            journalFile().writeText("")
            signalFile().writeBytes(byteArrayOf())
            result.success(null)
            return
        }
        if (call.method != "configure") {
            result.notImplemented()
            return
        }
        val reports = recoverReports()
        val enabled = call.argument<Boolean>("enabled") ?: false
        if (enabled) installHandlers() else uninstallHandlers()
        result.success(reports)
    }

    private fun installHandlers() {
        if (installed) return
        installed = true
        previousHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                val report = JSONObject()
                    .put("tag", "native_crash")
                    .put("message", "Android uncaught exception: ${error.javaClass.name}: ${error.message}")
                    .put("stack_trace", error.stackTraceToString())
                    .toString()
                journalFile().appendText("$report\n")
            } catch (_: Throwable) { }
            previousHandler?.uncaughtException(thread, error)
        }
        installSignalHandler(signalFile().absolutePath)
    }

    private fun uninstallHandlers() {
        if (!installed) return
        Thread.setDefaultUncaughtExceptionHandler(previousHandler)
        previousHandler = null
        uninstallSignalHandler()
        installed = false
    }

    private fun recoverReports(): List<Map<String, Any>> {
        val reports = mutableListOf<Map<String, Any>>()
        val journal = journalFile()
        if (journal.exists()) {
            journal.forEachLine { line ->
                try {
                    val json = JSONObject(line)
                    reports.add(
                        mapOf(
                            "tag" to json.optString("tag", "native_crash"),
                            "message" to json.optString("message", "Android native crash"),
                            "stack_trace" to json.optString("stack_trace", ""),
                        )
                    )
                } catch (_: Throwable) { }
            }
        }
        val signals = signalFile()
        if (signals.exists()) {
            val bytes = signals.readBytes()
            val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.nativeOrder())
            while (buffer.remaining() >= Int.SIZE_BYTES) {
                reports.add(
                    mapOf(
                        "tag" to "native_crash",
                        "message" to "Android native signal ${buffer.int}",
                        "stack_trace" to "",
                    )
                )
            }
        }
        return reports
    }

    private fun journalFile() = File(context.filesDir, "simple_app_logger_native_crashes.jsonl")
    private fun signalFile() = File(context.filesDir, "simple_app_logger_native_signals.bin")

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
