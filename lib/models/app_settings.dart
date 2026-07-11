class AppDisplaySettings {
  const AppDisplaySettings({
    required this.liteModeEnabled,
    required this.hapticFeedbackEnabled,
    required this.threeDimensionalBuildingsEnabled,
  });

  final bool liteModeEnabled;
  final bool hapticFeedbackEnabled;
  final bool threeDimensionalBuildingsEnabled;

  factory AppDisplaySettings.defaults() {
    return const AppDisplaySettings(
      liteModeEnabled: false,
      hapticFeedbackEnabled: true,
      threeDimensionalBuildingsEnabled: false,
    );
  }

  AppDisplaySettings copyWith({
    bool? liteModeEnabled,
    bool? hapticFeedbackEnabled,
    bool? threeDimensionalBuildingsEnabled,
  }) {
    return AppDisplaySettings(
      liteModeEnabled: liteModeEnabled ?? this.liteModeEnabled,
      hapticFeedbackEnabled:
          hapticFeedbackEnabled ?? this.hapticFeedbackEnabled,
      threeDimensionalBuildingsEnabled:
          threeDimensionalBuildingsEnabled ??
          this.threeDimensionalBuildingsEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "liteModeEnabled": liteModeEnabled,
      "hapticFeedbackEnabled": hapticFeedbackEnabled,
      "threeDimensionalBuildingsEnabled": threeDimensionalBuildingsEnabled,
    };
  }

  factory AppDisplaySettings.fromJson(Map<String, dynamic> json) {
    return AppDisplaySettings(
      liteModeEnabled: json["liteModeEnabled"] == true,
      hapticFeedbackEnabled: json["hapticFeedbackEnabled"] != false,
      threeDimensionalBuildingsEnabled:
          json["threeDimensionalBuildingsEnabled"] == true,
    );
  }
}
