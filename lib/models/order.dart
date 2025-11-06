enum OrderStatus {
  pending,
  inProgress,
  completed;

  String get displayName {
    switch (this) {
      case OrderStatus.pending:
        return 'Pending';
      case OrderStatus.inProgress:
        return 'In Progress';
      case OrderStatus.completed:
        return 'Completed';
    }
  }

  static OrderStatus fromString(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return OrderStatus.pending;
      case 'in progress':
        return OrderStatus.inProgress;
      case 'completed':
        return OrderStatus.completed;
      default:
        return OrderStatus.pending;
    }
  }
}

class Order {
  final String orderId;
  final String orderNumber;
  final String machine;
  final OrderStatus status;
  final DateTime createdOn;
  final DateTime modifiedOn;
  final String? createdBy;
  final String? modifiedBy;

  Order({
    required this.orderId,
    required this.orderNumber,
    required this.machine,
    required this.status,
    required this.createdOn,
    required this.modifiedOn,
    this.createdBy,
    this.modifiedBy,
  });

  Map<String, dynamic> toJson() {
    return {
      'OrderId': orderId,
      'OrderNumber': orderNumber,
      'Machine': machine,
      'Status': status.displayName,
      'CreatedOn': createdOn.toIso8601String(),
      'ModifiedOn': modifiedOn.toIso8601String(),
      'CreatedBy': createdBy ?? '',
      'ModifiedBy': modifiedBy ?? '',
    };
  }

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      orderId: json['OrderId'] ?? '',
      orderNumber: json['OrderNumber'] ?? '',
      machine: json['Machine'] ?? '',
      status: OrderStatus.fromString(json['Status'] ?? 'Pending'),
      createdOn: json['CreatedOn'] != null
          ? DateTime.parse(json['CreatedOn'])
          : DateTime.now(),
      modifiedOn: json['ModifiedOn'] != null
          ? DateTime.parse(json['ModifiedOn'])
          : DateTime.now(),
      createdBy: json['CreatedBy'],
      modifiedBy: json['ModifiedBy'],
    );
  }

  Order copyWith({
    String? orderId,
    String? orderNumber,
    String? machine,
    OrderStatus? status,
    DateTime? createdOn,
    DateTime? modifiedOn,
    String? createdBy,
    String? modifiedBy,
  }) {
    return Order(
      orderId: orderId ?? this.orderId,
      orderNumber: orderNumber ?? this.orderNumber,
      machine: machine ?? this.machine,
      status: status ?? this.status,
      createdOn: createdOn ?? this.createdOn,
      modifiedOn: modifiedOn ?? this.modifiedOn,
      createdBy: createdBy ?? this.createdBy,
      modifiedBy: modifiedBy ?? this.modifiedBy,
    );
  }
}

