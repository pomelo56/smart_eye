package com.example.smart_eye

import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var lastSpeakStatus = -999
    private var lastUtteranceDone = false
    private var pendingInitResult: MethodChannel.Result? = null
    private val channel = "com.smart_eye/tts"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> {
                    pendingInitResult = result
                    initTts()
                }
                "speak" -> {
                    val text = call.argument<String>("text") ?: ""
                    speak(text, result)
                }
                "stop" -> {
                    tts?.stop()
                    result.success(null)
                }
                "getDiagnostics" -> {
                    result.success(mapOf(
                        "ttsReady" to ttsReady,
                        "lastSpeakStatus" to lastSpeakStatus,
                        "lastUtteranceDone" to lastUtteranceDone
                    ))
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun initTts() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        ttsReady = false

        tts = TextToSpeech(this) { status ->
            android.util.Log.d("SmartEye", "onInit status=$status (0=SUCCESS,-1=ERROR)")

            // Try to set language
            var langResult = -1
            val locales = listOf(
                Triple("zh-CN", "zh", "CN"),
                Triple("CHINESE", "", ""),
                Triple("zh-TW", "zh", "TW")
            )
            for ((name, lang, country) in locales) {
                val loc = if (country.isNotEmpty()) Locale(lang, country) else Locale.CHINESE
                langResult = tts?.setLanguage(loc) ?: -999
                android.util.Log.d("SmartEye", "setLanguage($name) = $langResult")
                if (langResult == TextToSpeech.LANG_AVAILABLE ||
                    langResult == TextToSpeech.LANG_COUNTRY_AVAILABLE ||
                    langResult == TextToSpeech.LANG_COUNTRY_VAR_AVAILABLE) {
                    break
                }
            }

            // Log available voices
            tts?.voices?.forEach { voice ->
                android.util.Log.d("SmartEye", "Voice: ${voice.name} locale=${voice.locale}")
            }

            tts?.setSpeechRate(1.0f)
            tts?.setPitch(1.0f)

            // Set utterance progress listener to detect if speech actually plays
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    android.util.Log.d("SmartEye", "Utterance START: $utteranceId")
                    runOnUiThread {
                        lastUtteranceDone = false
                    }
                }
                override fun onDone(utteranceId: String?) {
                    android.util.Log.d("SmartEye", "Utterance DONE: $utteranceId")
                    runOnUiThread {
                        lastUtteranceDone = true
                    }
                }
                override fun onError(utteranceId: String?) {
                    android.util.Log.d("SmartEye", "Utterance ERROR: $utteranceId")
                    runOnUiThread {
                        lastUtteranceDone = false
                    }
                }
            })

            ttsReady = true

            // Return diagnostic info
            runOnUiThread {
                pendingInitResult?.success(mapOf(
                    "status" to status,
                    "langResult" to langResult,
                    "ready" to true
                ))
                pendingInitResult = null
            }
        }
    }

    private fun speak(text: String, result: MethodChannel.Result) {
        if (!ttsReady || tts == null) {
            result.success(mapOf("speakResult" to -1, "ttsReady" to false))
            return
        }
        lastUtteranceDone = false
        // Use utteranceId so we can track progress
        val r = tts!!.speak(text, TextToSpeech.QUEUE_FLUSH, null, "smarteye_diag")
        lastSpeakStatus = r
        android.util.Log.d("SmartEye", "speak('$text') = $r (0=SUCCESS)")
        result.success(mapOf("speakResult" to r, "ttsReady" to true))
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }
}
