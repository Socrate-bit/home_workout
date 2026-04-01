import 'package:flutter/material.dart';

import 'screens/workout_camera_screen.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    const sdkKey = String.fromEnvironment(
      'QUICKPOSE_KEY',
      defaultValue: 'YOUR_QUICKPOSE_SDK_KEY',
    );
    return MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark),
      home: const WorkoutCameraScreen(sdkKey: sdkKey),
    );
  }
}
