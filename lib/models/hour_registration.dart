class HourRegistration {
  final String hourRegistrationId;
  final String orderId;
  final String userId;
  final DateTime startTime;
  final DateTime? endTime;
  final double? elapsedTime;
  final bool isActive;
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
      'CreatedOn': createdOn.toIso8601String(),
      'ModifiedOn': modifiedOn.toIso8601String(),
    };
  }

  factory HourRegistration.fromJson(Map<String, dynamic> json) {
    return HourRegistration(
      hourRegistrationId: json['HourRegistrationId'] ?? '',
      orderId: json['OrderId'] ?? '',
      userId: json['UserId'] ?? '',
      startTime: json['StartTime'] != null
          ? DateTime.parse(json['StartTime'])
          : DateTime.now(),
      endTime: json['EndTime'] != null && json['EndTime'].toString().isNotEmpty
          ? DateTime.parse(json['EndTime'])
          : null,
      elapsedTime: json['ElapsedTime'] != null
          ? (json['ElapsedTime'] is double
              ? json['ElapsedTime']
              : double.tryParse(json['ElapsedTime'].toString()) ?? 0.0)
          : null,
      isActive: json['IsActive'] == 1 || json['IsActive'] == true,
      createdOn: json['CreatedOn'] != null
          ? DateTime.parse(json['CreatedOn'])
          : DateTime.now(),
      modifiedOn: json['ModifiedOn'] != null
          ? DateTime.parse(json['ModifiedOn'])
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
      createdOn: createdOn ?? this.createdOn,
      modifiedOn: modifiedOn ?? this.modifiedOn,
    );
  }

  double calculateElapsedTime() {
    if (endTime != null) {
      return endTime!.difference(startTime).inSeconds / 3600.0;
    }
    return DateTime.now().difference(startTime).inSeconds / 3600.0;
  }
}

