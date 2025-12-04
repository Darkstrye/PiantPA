enum OrderStatus {
  inProgress,
  completed;

  String get displayName {
    switch (this) {
      case OrderStatus.inProgress:
        return 'In Progress';
      case OrderStatus.completed:
        return 'Completed';
    }
  }

  static OrderStatus fromString(String status) {
    switch (status.toLowerCase()) {
      case 'in progress':
        return OrderStatus.inProgress;
      case 'completed':
        return OrderStatus.completed;
      default:
        return OrderStatus.inProgress;
    }
  }
}

class Order {
  final String orderId;
  final String orderNumber;
  final String? ordernummer;  // Separate field for ordernummer
  final String? orderregel;   // Separate field for orderregel
  final String machine;
  final double? vocaInUur;
  final double? geproduceerd;
  final double? totaalBedrag;
  final String? omschrijving;  // Order description
  final DateTime? leverdatum;   // Delivery date
  final String? statusNaam;     // Status name from SQL
  final OrderStatus status;
  final DateTime createdOn;
  final DateTime modifiedOn;
  final String? createdBy;
  final String? modifiedBy;

  Order({
    required this.orderId,
    required this.orderNumber,
    this.ordernummer,
    this.orderregel,
    required this.machine,
    this.vocaInUur,
    this.geproduceerd,
    this.totaalBedrag,
    this.omschrijving,
    this.leverdatum,
    this.statusNaam,
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
      'Ordernummer': ordernummer,
      'Orderregel': orderregel,
      'Machine': machine,
      'VocaInUur': vocaInUur,
      'Geproduceerd': geproduceerd,
      'TotaalBedrag': totaalBedrag,
      'Omschrijving': omschrijving,
      'Leverdatum': leverdatum?.toIso8601String(),
      'StatusNaam': statusNaam,
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
      ordernummer: json['Ordernummer'],
      orderregel: json['Orderregel'],
      machine: json['Machine'] ?? '',
      vocaInUur: json['VocaInUur'] != null
          ? (json['VocaInUur'] is String
              ? double.tryParse((json['VocaInUur'] as String).replaceAll(',', '.'))
              : (json['VocaInUur'] as num).toDouble())
          : null,
      geproduceerd: json['Geproduceerd'] != null
          ? (json['Geproduceerd'] is String
              ? double.tryParse((json['Geproduceerd'] as String).replaceAll(',', '.'))
              : (json['Geproduceerd'] as num).toDouble())
          : null,
      totaalBedrag: json['TotaalBedrag'] != null
          ? (json['TotaalBedrag'] is String
              ? double.tryParse((json['TotaalBedrag'] as String).replaceAll(',', '.'))
              : (json['TotaalBedrag'] as num).toDouble())
          : null,
      omschrijving: json['Omschrijving'],
      leverdatum: json['Leverdatum'] != null
          ? DateTime.tryParse(json['Leverdatum'].toString())
          : null,
      statusNaam: json['StatusNaam'],
      status: OrderStatus.fromString(json['Status'] ?? 'In Progress'),
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
    String? ordernummer,
    String? orderregel,
    String? machine,
    double? vocaInUur,
    double? geproduceerd,
    double? totaalBedrag,
    String? omschrijving,
    DateTime? leverdatum,
    String? statusNaam,
    OrderStatus? status,
    DateTime? createdOn,
    DateTime? modifiedOn,
    String? createdBy,
    String? modifiedBy,
  }) {
    return Order(
      orderId: orderId ?? this.orderId,
      orderNumber: orderNumber ?? this.orderNumber,
      ordernummer: ordernummer ?? this.ordernummer,
      orderregel: orderregel ?? this.orderregel,
      machine: machine ?? this.machine,
      vocaInUur: vocaInUur ?? this.vocaInUur,
      geproduceerd: geproduceerd ?? this.geproduceerd,
      totaalBedrag: totaalBedrag ?? this.totaalBedrag,
      omschrijving: omschrijving ?? this.omschrijving,
      leverdatum: leverdatum ?? this.leverdatum,
      statusNaam: statusNaam ?? this.statusNaam,
      status: status ?? this.status,
      createdOn: createdOn ?? this.createdOn,
      modifiedOn: modifiedOn ?? this.modifiedOn,
      createdBy: createdBy ?? this.createdBy,
      modifiedBy: modifiedBy ?? this.modifiedBy,
    );
  }
}

