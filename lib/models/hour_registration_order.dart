class HourRegistrationOrder {
  final String hourRegistrationOrderId;
  final String hourRegistrationId;
  final String orderId;
  final bool isActive;
  final double? elapsedTime;
  final double? elapsedOffset;
  final double? downtimeElapsedTime;
  final double? downtimeOffset;
  final DateTime createdOn;
  final DateTime modifiedOn;
  final DateTime? completedOn;

  HourRegistrationOrder({
    required this.hourRegistrationOrderId,
    required this.hourRegistrationId,
    required this.orderId,
    this.isActive = true,
    this.elapsedTime,
    this.elapsedOffset,
    this.downtimeElapsedTime,
    this.downtimeOffset,
    DateTime? createdOn,
    DateTime? modifiedOn,
    this.completedOn,
  })  : createdOn = createdOn ?? DateTime.now(),
        modifiedOn = modifiedOn ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'HourRegistrationOrderId': hourRegistrationOrderId,
      'HourRegistrationId': hourRegistrationId,
      'OrderId': orderId,
      'IsActive': isActive ? 1 : 0,
      'ElapsedTime': elapsedTime ?? 0.0,
      'ElapsedOffset': elapsedOffset ?? 0.0,
      'DowntimeElapsedTime': downtimeElapsedTime ?? 0.0,
      'DowntimeOffset': downtimeOffset ?? 0.0,
      'CreatedOn': createdOn.toIso8601String(),
      'ModifiedOn': modifiedOn.toIso8601String(),
      'CompletedOn': completedOn?.toIso8601String() ?? '',
    };
  }

  factory HourRegistrationOrder.fromJson(Map<String, dynamic> json) {
    bool parseBool(dynamic value) {
      if (value == null) return false;
      if (value is bool) return value;
      if (value is int) return value == 1;
      if (value is String) {
        final lowered = value.toLowerCase().trim();
        return lowered == '1' || lowered == 'true';
      }
      return false;
    }

    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is double) return value;
      return double.tryParse(value.toString());
    }

    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      final stringValue = value.toString();
      if (stringValue.isEmpty) return null;
      return DateTime.tryParse(stringValue);
    }

    return HourRegistrationOrder(
      hourRegistrationOrderId:
          json['HourRegistrationOrderId']?.toString() ?? '',
      hourRegistrationId: json['HourRegistrationId']?.toString() ?? '',
      orderId: json['OrderId']?.toString() ?? '',
      isActive: parseBool(json['IsActive']),
      elapsedTime: parseDouble(json['ElapsedTime']),
      elapsedOffset: parseDouble(json['ElapsedOffset']),
      downtimeElapsedTime: parseDouble(json['DowntimeElapsedTime']),
      downtimeOffset: parseDouble(json['DowntimeOffset']),
      createdOn: parseDate(json['CreatedOn']) ?? DateTime.now(),
      modifiedOn: parseDate(json['ModifiedOn']) ?? DateTime.now(),
      completedOn: parseDate(json['CompletedOn']),
    );
  }

  HourRegistrationOrder copyWith({
    String? hourRegistrationOrderId,
    String? hourRegistrationId,
    String? orderId,
    bool? isActive,
    double? elapsedTime,
    double? elapsedOffset,
    double? downtimeElapsedTime,
    double? downtimeOffset,
    DateTime? createdOn,
    DateTime? modifiedOn,
    DateTime? completedOn,
  }) {
    return HourRegistrationOrder(
      hourRegistrationOrderId:
          hourRegistrationOrderId ?? this.hourRegistrationOrderId,
      hourRegistrationId:
          hourRegistrationId ?? this.hourRegistrationId,
      orderId: orderId ?? this.orderId,
      isActive: isActive ?? this.isActive,
      elapsedTime: elapsedTime ?? this.elapsedTime,
      elapsedOffset: elapsedOffset ?? this.elapsedOffset,
      downtimeElapsedTime: downtimeElapsedTime ?? this.downtimeElapsedTime,
      downtimeOffset: downtimeOffset ?? this.downtimeOffset,
      createdOn: createdOn ?? this.createdOn,
      modifiedOn: modifiedOn ?? this.modifiedOn,
      completedOn: completedOn ?? this.completedOn,
    );
  }
}

