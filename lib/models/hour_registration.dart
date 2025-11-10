class HourRegistration {
  final String hourRegistrationId;
  final String orderId;
  final String userId;
  final DateTime startTime;
  final DateTime? endTime;
  final double? elapsedTime;
  final bool isActive;
  final bool isPaused;
  final double? pausedElapsedTime; // Accumulated productive time when paused
  final double? downtimeElapsedTime; // Accumulated downtime while paused
  final DateTime? downtimeStartTime; // When downtime tracking started
  final DateTime createdOn;
  final DateTime modifiedOn;

  HourRegistration({
    required this.hourRegistrationId,
    required this.orderId,
    required this.userId,
    required this.startTime,
    this.endTime,
    this.elapsedTime,
    required this.isActive,
    this.isPaused = false,
    this.pausedElapsedTime,
    this.downtimeElapsedTime,
    this.downtimeStartTime,
    required this.createdOn,
    required this.modifiedOn,
  });

  Map<String, dynamic> toJson() {
    return {
      'HourRegistrationId': hourRegistrationId,
      'OrderId': orderId,
      'UserId': userId,
      'StartTime': startTime.toIso8601String(),
      'EndTime': endTime?.toIso8601String() ?? '',
      'ElapsedTime': elapsedTime ?? 0.0,
      'IsActive': isActive ? 1 : 0,
      'IsPaused': isPaused ? 1 : 0,
      'PausedElapsedTime': pausedElapsedTime ?? 0.0,
      'DowntimeElapsedTime': downtimeElapsedTime ?? 0.0,
      'DowntimeStartTime': downtimeStartTime?.toIso8601String() ?? '',
      'CreatedOn': createdOn.toIso8601String(),
      'ModifiedOn': modifiedOn.toIso8601String(),
    };
  }

  factory HourRegistration.fromJson(Map<String, dynamic> json) {
    bool parseBool(dynamic value) {
      if (value == null) return false;
      if (value is bool) return value;
      if (value is int) return value == 1;
      if (value is String) {
        final str = value.toLowerCase().trim();
        return str == '1' || str == 'true';
      }
      return false;
    }

    return HourRegistration(
      hourRegistrationId: json['HourRegistrationId']?.toString() ?? '',
      orderId: json['OrderId']?.toString() ?? '',
      userId: json['UserId']?.toString() ?? '',
      startTime: json['StartTime'] != null
          ? DateTime.parse(json['StartTime'].toString())
          : DateTime.now(),
      endTime: json['EndTime'] != null && json['EndTime'].toString().isNotEmpty
          ? DateTime.parse(json['EndTime'].toString())
          : null,
      elapsedTime: json['ElapsedTime'] != null
          ? (json['ElapsedTime'] is double
              ? json['ElapsedTime']
              : double.tryParse(json['ElapsedTime'].toString()) ?? 0.0)
          : null,
      isActive: parseBool(json['IsActive']),
      isPaused: parseBool(json['IsPaused']),
      pausedElapsedTime: json['PausedElapsedTime'] != null
          ? (json['PausedElapsedTime'] is double
              ? json['PausedElapsedTime']
              : double.tryParse(json['PausedElapsedTime'].toString()))
          : null,
      downtimeElapsedTime: json['DowntimeElapsedTime'] != null
          ? (json['DowntimeElapsedTime'] is double
              ? json['DowntimeElapsedTime']
              : double.tryParse(json['DowntimeElapsedTime'].toString()))
          : null,
      downtimeStartTime: json['DowntimeStartTime'] != null &&
              json['DowntimeStartTime'].toString().isNotEmpty
          ? DateTime.parse(json['DowntimeStartTime'].toString())
          : null,
      createdOn: json['CreatedOn'] != null
          ? DateTime.parse(json['CreatedOn'].toString())
          : DateTime.now(),
      modifiedOn: json['ModifiedOn'] != null
          ? DateTime.parse(json['ModifiedOn'].toString())
          : DateTime.now(),
    );
  }

  HourRegistration copyWith({
    String? hourRegistrationId,
    String? orderId,
    String? userId,
    DateTime? startTime,
    DateTime? endTime,
    double? elapsedTime,
    bool? isActive,
    bool? isPaused,
    double? pausedElapsedTime,
    double? downtimeElapsedTime,
    DateTime? downtimeStartTime,
    DateTime? createdOn,
    DateTime? modifiedOn,
  }) {
    return HourRegistration(
      hourRegistrationId: hourRegistrationId ?? this.hourRegistrationId,
      orderId: orderId ?? this.orderId,
      userId: userId ?? this.userId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      elapsedTime: elapsedTime ?? this.elapsedTime,
      isActive: isActive ?? this.isActive,
      isPaused: isPaused ?? this.isPaused,
      pausedElapsedTime: pausedElapsedTime ?? this.pausedElapsedTime,
      downtimeElapsedTime: downtimeElapsedTime ?? this.downtimeElapsedTime,
      downtimeStartTime: downtimeStartTime ?? this.downtimeStartTime,
      createdOn: createdOn ?? this.createdOn,
      modifiedOn: modifiedOn ?? this.modifiedOn,
    );
  }

  double calculateElapsedTime() {
    if (endTime != null) {
      return endTime!.difference(startTime).inSeconds / 3600.0;
    }
    // If paused, return the paused elapsed time
    if (isPaused && pausedElapsedTime != null) {
      return pausedElapsedTime!;
    }
    // If we have accumulated paused time, add current running time
    final baseTime = pausedElapsedTime ?? 0.0;
    final currentRunning = DateTime.now().difference(startTime).inSeconds / 3600.0;
    return baseTime + currentRunning;
  }

  double calculateDowntime() {
    final baseDowntime = downtimeElapsedTime ?? 0.0;
    if (isPaused && downtimeStartTime != null) {
      final currentDowntime =
          DateTime.now().difference(downtimeStartTime!).inSeconds / 3600.0;
      return baseDowntime + currentDowntime;
    }
    return baseDowntime;
  }
}

