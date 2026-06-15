import 'package:flutter/material.dart';

class BikeData extends ChangeNotifier {
  static final BikeData instance = BikeData._internal();

  factory BikeData() => instance;

  BikeData._internal();

  int? speed;
  int? rpm;
  double? distance;
  double? avgSpeed;
  int? maxSpeed;

  bool leftIndicator = false;
  bool rightIndicator = false;
  bool hazard = false;

  int? rssi;
  String status = "Disconnected";

  void updateFromJson(Map<String, dynamic> data) {
    speed = data["speed"];
    rpm = data["rpm"];

    distance = (data["distance"] as num?)?.toDouble();
    avgSpeed = (data["avgSpeed"] as num?)?.toDouble();

    maxSpeed = data["maxSpeed"];

    leftIndicator = data["left"] ?? false;
    rightIndicator = data["right"] ?? false;
    hazard = data["hazard"] ?? false;

    notifyListeners();
  }

  void updateRssi(int? value) {
    rssi = value;
    notifyListeners();
  }

  void updateStatus(String value) {
    status = value;
    notifyListeners();
  }

  void clearRideData() {
    speed = null;
    rpm = null;
    distance = null;
    avgSpeed = null;
    maxSpeed = null;

    leftIndicator = false;
    rightIndicator = false;
    hazard = false;

    rssi = null;

    notifyListeners();
  }
}