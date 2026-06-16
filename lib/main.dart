import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ble_service.dart';
import 'controllers/bike_console_controller.dart';
import 'screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await BleService.instance.init();

  final bikeConsoleController = BikeConsoleController();
  await bikeConsoleController.initialize();

  runApp(
    BikeConsoleApp(
      bikeConsoleController: bikeConsoleController,
    ),
  );
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