import 'package:flutter/material.dart';

import 'today_screen.dart';

// The app starts here.
void main() {
  runApp(const MarathonApp());
}

class MarathonApp extends StatelessWidget {
  const MarathonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Marathon App',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      // The Today screen is the home page (checks weather, shows today's pace).
      home: const TodayScreen(),
    );
  }
}
