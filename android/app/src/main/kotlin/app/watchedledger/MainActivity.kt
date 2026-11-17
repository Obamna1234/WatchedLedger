package app.watchedledger

import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity is required by local_auth (fingerprint / face unlock).
class MainActivity : FlutterFragmentActivity() {
    private var shareChannel: MethodChannel? = null
    private var pendingShare: String? = null
    private var widgetChannel: MethodChannel? = null
    private var pendingQuickAdd = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Only a fresh launch carries a share; a restored activity would
        // replay the old one.
        if (savedInstanceState == null) {
            pendingShare = sharedText(intent)
            pendingQuickAdd = intent?.action == NextUpWidget.ACTION_QUICK_ADD
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == NextUpWidget.ACTION_QUICK_ADD) {
            pendingQuickAdd = true
            widgetChannel?.invokeMethod("quickAdd", null)
            return
        }
        val text = sharedText(intent) ?: return
        pendingShare = text
        shareChannel?.invokeMethod("shared", null)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // "Hide in recent apps": FLAG_SECURE blanks the app-switcher preview
        // and blocks screenshots while the app lock is on.
        MethodChannel(messenger, "watchedledger/window")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        widgetChannel = MethodChannel(messenger, "watchedledger/widget").apply {
            setMethodCallHandler(widgetHandler())
        }

        // Share-to-app: Dart asks for the text shared from another app.
        shareChannel = MethodChannel(messenger, "watchedledger/share").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeShared" -> {
                        result.success(pendingShare)
                        pendingShare = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun widgetHandler() = MethodChannel.MethodCallHandler { call, result ->
        when (call.method) {
            "update" -> {
                val args = call.arguments as? Map<*, *>
                val lines = (args?.get("lines") as? List<*>)?.filterIsInstance<String>() ?: emptyList()
                val locked = args?.get("locked") == true
                if (NextUpWidget.hasWidgets(this)) {
                    NextUpWidget.save(this, lines, locked)
                } else {
                    // No widget on the home screen: keep no titles outside the database.
                    getSharedPreferences(NextUpWidget.PREFS, MODE_PRIVATE).edit().clear().apply()
                }
                result.success(null)
            }
            "takeQuickAdd" -> {
                result.success(pendingQuickAdd)
                pendingQuickAdd = false
            }
            else -> result.notImplemented()
        }
    }

    /** Plain text from a "Share" intent (capped), or null. */
    private fun sharedText(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND) return null
        if (intent.type?.startsWith("text/") != true) return null
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        val combined = listOfNotNull(subject, text).joinToString("\n").take(4000)
        return combined.ifBlank { null }
    }
}
