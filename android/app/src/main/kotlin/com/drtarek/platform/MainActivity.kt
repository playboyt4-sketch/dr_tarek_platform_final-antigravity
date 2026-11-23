package com.drtarek.platform

import io.flutter.embedding.android.FlutterActivity
import android.os.Bundle
import android.view.WindowManager

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Strictly prevent screen capture, screen recording, and task-switcher previews
        // for protected educational video and PDF content on the OS level.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
