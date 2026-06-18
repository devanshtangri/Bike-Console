class AppDisplaySettings {
  const AppDisplaySettings({
    required this.liteModeEnabled,
    required this.hapticFeedbackEnabled,
  });

  final bool liteModeEnabled;
  final bool hapticFeedbackEnabled;

  factory AppDisplaySettings.defaults() {
    return const AppDisplaySettings(
      liteModeEnabled: false,
      hapticFeedbackEnabled: true,
    );
  }

  AppDisplaySettings copyWith({
    bool? liteModeEnabled,
    bool? hapticFeedbackEnabled,
  }) {
    return AppDisplaySettings(
      liteModeEnabled: liteModeEnabled ?? this.liteModeEnabled,
      hapticFeedbackEnabled:
          hapticFeedbackEnabled ?? this.hapticFeedbackEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "liteModeEnabled": liteModeEnabled,
      "hapticFeedbackEnabled": hapticFeedbackEnabled,
    };
  }

  factory AppDisplaySettings.fromJson(Map<String, dynamic> json) {
    return AppDisplaySettings(
      liteModeEnabled: json["liteModeEnabled"] == true,
      hapticFeedbackEnabled: json["hapticFeedbackEnabled"] != false,
    );
  }
}
