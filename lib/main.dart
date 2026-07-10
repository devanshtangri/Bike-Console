import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'controllers/bike_console_controller.dart';
import 'screens/dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final bikeConsoleController = BikeConsoleController();

  runApp(
    BikeConsoleApp(
      bikeConsoleController: bikeConsoleController,
    ),
  );

  // Storage restoration and BLE reconnection must not delay the first frame.
  unawaited(bikeConsoleController.initialize());
}

class BikeConsoleApp extends StatelessWidget {
  const BikeConsoleApp({
    super.key,
    required this.bikeConsoleController,
  });

  final BikeConsoleController bikeConsoleController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bike Console',
      debugShowCheckedModeBanner: false,
      locale: const Locale('en', 'US'),
      supportedLocales: const [
        Locale('en', 'US'),
      ],
      theme: ThemeData(
        fontFamily: GoogleFonts.inter().fontFamily,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.greenAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: DashboardScreen(
        bikeConsoleController: bikeConsoleController,
      ),
    );
  }
}
