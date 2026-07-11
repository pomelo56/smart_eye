import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // CVE-STYLE-014: release模式下禁用debugPrint输出到logcat，防止信息泄露
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // Lock orientation to portrait only
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const SmartEyeApp());
}

/// Root application widget for smart_eye.
class SmartEyeApp extends StatelessWidget {
  const SmartEyeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '慧眼 SmartEye',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
