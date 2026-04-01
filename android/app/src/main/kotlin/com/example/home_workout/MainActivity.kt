package com.example.home_workout

import com.example.home_workout.quickpose.QuickPoseFlutterBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    QuickPoseFlutterBridge.register(flutterEngine, this)
  }
}
