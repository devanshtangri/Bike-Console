class AppDisplaySettings {
  const AppDisplaySettings({required this.liteModeEnabled});

  final bool liteModeEnabled;

  factory AppDisplaySettings.defaults() {
    return const AppDisplaySettings(liteModeEnabled: false);
  }

  AppDisplaySettings copyWith({bool? liteModeEnabled}) {
    return AppDisplaySettings(
      liteModeEnabled: liteModeEnabled ?? this.liteModeEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "liteModeEnabled": liteModeEnabled,
    };
  }

  factory AppDisplaySettings.fromJson(Map<String, dynamic> json) {
    return AppDisplaySettings(
      liteModeEnabled: json["liteModeEnabled"] == true,
    );
  }
}