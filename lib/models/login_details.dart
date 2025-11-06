class LoginDetails {
  final String loginDetailsId;
  final String username;
  final String password;
  final String displayName;
  final bool isActive;
  final DateTime createdOn;
  final DateTime modifiedOn;

  LoginDetails({
    required this.loginDetailsId,
    required this.username,
    required this.password,
    required this.displayName,
    required this.isActive,
    required this.createdOn,
    required this.modifiedOn,
  });

  Map<String, dynamic> toJson() {
    return {
      'LoginDetailsId': loginDetailsId,
      'Username': username,
      'Password': password,
      'DisplayName': displayName,
      'IsActive': isActive ? 1 : 0,
      'CreatedOn': createdOn.toIso8601String(),
      'ModifiedOn': modifiedOn.toIso8601String(),
    };
  }

  factory LoginDetails.fromJson(Map<String, dynamic> json) {
    // Handle IsActive field - can be 1, 0, true, false, "1", "0", "True", "False"
    bool parseIsActive(dynamic value) {
      print('Parsing IsActive: value=$value, type=${value.runtimeType}');
      if (value == null) {
        print('IsActive is null, defaulting to true');
        return true;
      }
      if (value is bool) {
        print('IsActive is bool: $value');
        return value;
      }
      if (value is int) {
        final result = value == 1;
        print('IsActive is int: $value -> $result');
        return result;
      }
      if (value is double) {
        final result = value == 1.0;
        print('IsActive is double: $value -> $result');
        return result;
      }
      if (value is String) {
        final str = value.toLowerCase().trim();
        final result = str == '1' || str == 'true' || str == 'yes';
        print('IsActive is String: "$str" -> $result');
        return result;
      }
      print('IsActive unknown type, defaulting to true');
      return true; // Default to active
    }

    final isActiveValue = json['IsActive'];
    final isActive = parseIsActive(isActiveValue);

    return LoginDetails(
      loginDetailsId: json['LoginDetailsId']?.toString() ?? '',
      username: json['Username']?.toString() ?? '',
      password: json['Password']?.toString() ?? '',
      displayName: json['DisplayName']?.toString() ?? '',
      isActive: isActive,
      createdOn: json['CreatedOn'] != null && json['CreatedOn'].toString().isNotEmpty
          ? DateTime.tryParse(json['CreatedOn'].toString()) ?? DateTime.now()
          : DateTime.now(),
      modifiedOn: json['ModifiedOn'] != null && json['ModifiedOn'].toString().isNotEmpty
          ? DateTime.tryParse(json['ModifiedOn'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  LoginDetails copyWith({
    String? loginDetailsId,
    String? username,
    String? password,
    String? displayName,
    bool? isActive,
    DateTime? createdOn,
    DateTime? modifiedOn,
  }) {
    return LoginDetails(
      loginDetailsId: loginDetailsId ?? this.loginDetailsId,
      username: username ?? this.username,
      password: password ?? this.password,
      displayName: displayName ?? this.displayName,
      isActive: isActive ?? this.isActive,
      createdOn: createdOn ?? this.createdOn,
      modifiedOn: modifiedOn ?? this.modifiedOn,
    );
  }
}

