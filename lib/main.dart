import 'package:flutter/material.dart';

import 'ble_service.dart';
import 'screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await BleService.instance.init();

  runApp(const BikeConsoleApp());
}

class BikeConsoleApp extends StatelessWidget {
  const BikeConsoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bike Console',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const DashboardScreen(),
    );
  }
}

//AIzaSyCyeO150bR12aXE22JNeKVnKKxN5WTWaLw