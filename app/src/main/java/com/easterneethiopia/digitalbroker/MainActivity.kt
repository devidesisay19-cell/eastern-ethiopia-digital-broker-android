package com.easterneethiopia.digitalbroker

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.webkit.WebViewAssetLoader
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging

class MainActivity : AppCompatActivity() {
    private lateinit var webView: WebView
    private var filePathCallback: ValueCallback<Array<Uri>>? = null

    private val filePicker = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        val callback = filePathCallback ?: return@registerForActivityResult
        filePathCallback = null

        val uris: Array<Uri>? = if (result.resultCode == RESULT_OK) {
            val data = result.data
            val clip = data?.clipData
            when {
                clip != null && clip.itemCount > 0 ->
                    Array(clip.itemCount) { clip.getItemAt(it).uri }
                data?.data != null -> arrayOf(data.data!!)
                else -> null
            }
        } else null

        callback.onReceiveValue(uris)
    }

    private val notificationPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { }

    private val linkRegex = Regex("^[a-z0-9_-]+\\.html(\\?[A-Za-z0-9=&_-]*)?\$")

    private val assetLoader by lazy {
        WebViewAssetLoader.Builder()
            .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(this))
            .build()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        webView = WebView(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                databaseEnabled = true
                allowFileAccess = false
                allowContentAccess = true
                cacheMode = WebSettings.LOAD_DEFAULT
                mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                builtInZoomControls = false
                displayZoomControls = false
                mediaPlaybackRequiresUserGesture = false
                userAgentString = "$userAgentString EasternEthiopiaDigitalBroker/6.0"
                setSupportMultipleWindows(false)
            }

            setLayerType(View.LAYER_TYPE_HARDWARE, null)

            CookieManager.getInstance().setAcceptCookie(true)
            CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)

            webChromeClient = object : WebChromeClient() {
                override fun onShowFileChooser(
                    webView: WebView?,
                    filePathCallback: ValueCallback<Array<Uri>>?,
                    fileChooserParams: FileChooserParams?
                ): Boolean {
                    this@MainActivity.filePathCallback?.onReceiveValue(null)
                    this@MainActivity.filePathCallback = filePathCallback

                    val multiple = fileChooserParams?.mode == FileChooserParams.MODE_OPEN_MULTIPLE
                    val accept = fileChooserParams?.acceptTypes
                        ?.map { it.trim() }?.filter { it.isNotEmpty() } ?: emptyList()
                    val imagesOnly = accept.isNotEmpty() && accept.all { it.startsWith("image/") }

                    val intent: Intent = if (imagesOnly) {
                        // Simple, widely supported picker for photos (works with Gallery,
                        // Google Photos, Files). Avoids EXTRA_MIME_TYPES problems.
                        Intent.createChooser(
                            Intent(Intent.ACTION_GET_CONTENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "image/*"
                                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, multiple)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            },
                            "Select photos"
                        )
                    } else {
                        // PDFs / documents (job CV upload etc.)
                        (fileChooserParams?.createIntent() ?: Intent(Intent.ACTION_GET_CONTENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                        }).apply {
                            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, multiple)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                    }

                    return runCatching {
                        filePicker.launch(intent)
                        true
                    }.getOrElse {
                        this@MainActivity.filePathCallback = null
                        filePathCallback?.onReceiveValue(null)
                        false
                    }
                }
            }

            webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(
                    view: WebView?,
                    request: WebResourceRequest?
                ): WebResourceResponse? {
                    val url = request?.url ?: return null
                    cachedSupabaseScript(url)?.let { return it }
                    if (url.scheme == "https" && url.host == "appassets.androidplatform.net") {
                        return assetLoader.shouldInterceptRequest(url)
                    }
                    return super.shouldInterceptRequest(view, request)
                }

                override fun shouldOverrideUrlLoading(
                    view: WebView,
                    request: WebResourceRequest
                ): Boolean = handleUri(request.url)

                @Deprecated("Deprecated in Java")
                override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean =
                    handleUri(Uri.parse(url))

                override fun onPageFinished(view: WebView?, url: String?) {
                    super.onPageFinished(view, url)
                    injectPushToken(view)
                }

                override fun onRenderProcessGone(
                    view: WebView,
                    detail: android.webkit.RenderProcessGoneDetail
                ): Boolean {
                    view.destroy()
                    recreate()
                    return true
                }
            }
        }

        setContentView(webView)
        webView.loadUrl(pageUrl(intent?.getStringExtra("link")))
        requestNotificationPermission()
        fetchPushToken()

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (webView.canGoBack()) webView.goBack() else finish()
            }
        })
    }


    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = intent.getStringExtra("link")
        if (!link.isNullOrEmpty() && linkRegex.matches(link)) {
            webView.loadUrl(pageUrl(link))
        }
    }

    private fun pageUrl(link: String?): String =
        if (link != null && linkRegex.matches(link)) {
            "https://appassets.androidplatform.net/assets/web/" + link
        } else {
            "https://appassets.androidplatform.net/assets/web/index.html"
        }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    /** Push is active only when the Firebase values were added (see FIREBASE_SETUP.md); otherwise this does nothing. */
    private fun fetchPushToken() {
        try {
            if (FirebaseApp.getApps(this).isEmpty()) return
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                if (task.isSuccessful) {
                    val token = task.result
                    if (!token.isNullOrEmpty()) {
                        getSharedPreferences("eedb_push", MODE_PRIVATE).edit().putString("token", token).apply()
                        injectPushToken(webView)
                    }
                }
            }
        } catch (e: Exception) {
            // Firebase not configured - the app keeps working with in-app notifications only
        }
    }

    private fun injectPushToken(view: WebView?) {
        val token = getSharedPreferences("eedb_push", MODE_PRIVATE).getString("token", null) ?: return
        if (!Regex("^[A-Za-z0-9:_.-]{20,4096}\$").matches(token)) return
        view?.evaluateJavascript(
            "window.EEDB_FCM_TOKEN='" + token + "';window.dispatchEvent(new Event('eedb-fcm-token'));",
            null
        )
    }

    /**
     * The web pages load supabase-js from a pinned CDN URL. Download it once, keep it in app storage
     * and serve it from disk afterwards: faster start and it also works without internet after the first run.
     */
    private fun cachedSupabaseScript(url: Uri): WebResourceResponse? {
        val full = url.toString()
        if (!full.startsWith("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@")) return null
        // Bundled copy inside the APK (the CI build downloads it): instant, no network needed
        try {
            val bundled = assets.open("web/vendor/supabase-js.js")
            return WebResourceResponse(
                "application/javascript",
                "UTF-8",
                200,
                "OK",
                mapOf("Access-Control-Allow-Origin" to "*", "Cache-Control" to "max-age=31536000"),
                bundled
            )
        } catch (e: java.io.IOException) {
            // not bundled: fall back to the disk cache / CDN below
        }
        return try {
            val file = java.io.File(filesDir, "supabase-js-" + full.hashCode() + ".js")
            if (!file.exists() || file.length() < 1000L) {
                val conn = java.net.URL(full).openConnection() as java.net.HttpURLConnection
                conn.connectTimeout = 8000
                conn.readTimeout = 15000
                if (conn.responseCode != 200) {
                    conn.disconnect()
                    return null
                }
                val tmp = java.io.File(filesDir, file.name + ".tmp")
                conn.inputStream.use { input -> tmp.outputStream().use { out -> input.copyTo(out) } }
                conn.disconnect()
                if (tmp.length() >= 1000L) {
                    tmp.renameTo(file)
                } else {
                    tmp.delete()
                }
            }
            if (!file.exists() || file.length() < 1000L) return null
            WebResourceResponse(
                "application/javascript",
                "UTF-8",
                200,
                "OK",
                mapOf("Access-Control-Allow-Origin" to "*", "Cache-Control" to "max-age=31536000"),
                file.inputStream()
            )
        } catch (e: Exception) {
            null
        }
    }

    private fun handleUri(uri: Uri): Boolean {
        val scheme = uri.scheme?.lowercase() ?: return false
        if (scheme == "https" && uri.host == "appassets.androidplatform.net") return false

        if (scheme == "http" || scheme == "https" || scheme == "whatsapp" || scheme == "mailto" || scheme == "tel") {
            runCatching { startActivity(Intent(Intent.ACTION_VIEW, uri)) }
            return true
        }
        return false
    }

    override fun onDestroy() {
        filePathCallback?.onReceiveValue(null)
        filePathCallback = null
        if (::webView.isInitialized) {
            webView.stopLoading()
            webView.webChromeClient = null
            webView.destroy()
        }
        super.onDestroy()
    }
}
