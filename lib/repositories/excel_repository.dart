import 'dart:io';
import 'package:excel/excel.dart';
import 'package:uuid/uuid.dart';
import '../models/login_details.dart';
import '../models/order.dart';
import '../models/hour_registration.dart';
import '../services/excel_service.dart';
import 'repository_interface.dart';

class ExcelRepository implements RepositoryInterface {
  static const String _loginDetailsFile = 'login_details.xlsx';
  static const String _ordersFile = 'orders.xlsx';
  static const String _hourRegistrationFile = 'hour_registration.xlsx';
  static const String _sheetName = 'Sheet1';
  static const _uuid = Uuid();

  // LoginDetails operations
  @override
  Future<List<LoginDetails>> getAllLoginDetails() async {
    try {
      final filePath = await ExcelService.getExcelFilePath(_loginDetailsFile);
      final excel = await ExcelService.loadExcelFile(filePath);
      
      if (!excel.sheets.containsKey(_sheetName)) {
        print('Excel sheet not found: $_sheetName');
        return [];
      }

      final data = ExcelService.excelToMapList(excel, _sheetName);
      print('Loaded ${data.length} login details from Excel');
      if (data.isNotEmpty) {
        print('First record keys: ${data.first.keys.toList()}');
        print('First record sample: ${data.first}');
      }
      final loginDetails = data.map((json) {
        try {
          return LoginDetails.fromJson(json);
        } catch (e) {
          print('Error parsing login detail: $e, JSON: $json');
          rethrow;
        }
      }).toList();
      print('Parsed ${loginDetails.length} login details successfully');
      return loginDetails;
    } catch (e) {
      print('Error loading login details: $e');
      return [];
    }
  }

  @override
  Future<LoginDetails?> getLoginDetailsById(String id) async {
    final all = await getAllLoginDetails();
    try {
      return all.firstWhere((item) => item.loginDetailsId == id);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<LoginDetails?> getLoginDetailsByUsername(String username) async {
    final all = await getAllLoginDetails();
    print('Searching for username: "$username" in ${all.length} users');
    for (var user in all) {
      print('  Found user: ${user.username} (display: ${user.displayName}, active: ${user.isActive})');
    }
    try {
      final found = all.firstWhere((item) => item.username.toLowerCase().trim() == username.toLowerCase().trim());
      print('Found user: ${found.username}');
      return found;
    } catch (e) {
      print('User not found: $username');
      return null;
    }
  }

  @override
  Future<LoginDetails> createLoginDetails(LoginDetails loginDetails) async {
    final all = await getAllLoginDetails();
    final newLoginDetails = loginDetails.copyWith(
      loginDetailsId: loginDetails.loginDetailsId.isEmpty 
          ? _uuid.v4() 
          : loginDetails.loginDetailsId,
      createdOn: DateTime.now(),
      modifiedOn: DateTime.now(),
    );
    
    all.add(newLoginDetails);
    await _saveLoginDetails(all);
    return newLoginDetails;
  }

  @override
  Future<LoginDetails> updateLoginDetails(LoginDetails loginDetails) async {
    final all = await getAllLoginDetails();
    final index = all.indexWhere((item) => item.loginDetailsId == loginDetails.loginDetailsId);
    
    if (index != -1) {
      all[index] = loginDetails.copyWith(modifiedOn: DateTime.now());
      await _saveLoginDetails(all);
      return all[index];
    }
    
    return await createLoginDetails(loginDetails);
  }

  @override
  Future<bool> deleteLoginDetails(String id) async {
    final all = await getAllLoginDetails();
    final initialLength = all.length;
    all.removeWhere((item) => item.loginDetailsId == id);
    
    if (all.length < initialLength) {
      await _saveLoginDetails(all);
      return true;
    }
    return false;
  }

  Future<void> _saveLoginDetails(List<LoginDetails> loginDetails) async {
    final headers = ['LoginDetailsId', 'Username', 'Password', 'DisplayName', 'IsActive', 'CreatedOn', 'ModifiedOn'];
    final filePath = await ExcelService.getExcelFilePath(_loginDetailsFile);
    
    Excel excel;
    if (await File(filePath).exists()) {
      excel = await ExcelService.loadExcelFile(filePath);
    } else {
      excel = ExcelService.createExcelWithHeaders(headers, _sheetName);
    }

    final data = loginDetails.map((item) => item.toJson()).toList();
    ExcelService.mapListToExcel(excel, _sheetName, data, headers);
    await ExcelService.saveExcelFile(excel, filePath);
  }

  // Order operations
  @override
  Future<List<Order>> getAllOrders() async {
    try {
      final filePath = await ExcelService.getExcelFilePath(_ordersFile);
      final excel = await ExcelService.loadExcelFile(filePath);
      
      if (!excel.sheets.containsKey(_sheetName)) {
        return [];
      }

      final data = ExcelService.excelToMapList(excel, _sheetName);
      return data.map((json) => Order.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<Order?> getOrderById(String id) async {
    final all = await getAllOrders();
    try {
      return all.firstWhere((item) => item.orderId == id);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<Order?> getOrderByOrderNumber(String orderNumber) async {
    final all = await getAllOrders();
    try {
      return all.firstWhere((item) => item.orderNumber == orderNumber);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<Order> createOrder(Order order) async {
    final all = await getAllOrders();
    
    // Check if order number already exists
    final existingOrder = all.firstWhere(
      (item) => item.orderNumber == order.orderNumber,
      orElse: () => Order(
        orderId: '',
        orderNumber: '',
        machine: '',
        status: OrderStatus.inProgress,
        createdOn: DateTime.now(),
        modifiedOn: DateTime.now(),
      ),
    );
    
    if (existingOrder.orderNumber.isNotEmpty && existingOrder.orderId != order.orderId) {
      throw Exception('Order number "${order.orderNumber}" already exists. Each order number must be unique.');
    }
    
    final newOrder = order.copyWith(
      orderId: order.orderId.isEmpty ? _uuid.v4() : order.orderId,
      createdOn: DateTime.now(),
      modifiedOn: DateTime.now(),
    );
    
    all.add(newOrder);
    await _saveOrders(all);
    return newOrder;
  }

  @override
  Future<Order> updateOrder(Order order) async {
    final all = await getAllOrders();
    final index = all.indexWhere((item) => item.orderId == order.orderId);
    
    if (index != -1) {
      // Check if the new order number conflicts with another order
      final existingOrderWithSameNumber = all.firstWhere(
        (item) => item.orderNumber == order.orderNumber && item.orderId != order.orderId,
        orElse: () => Order(
          orderId: '',
          orderNumber: '',
          machine: '',
          status: OrderStatus.inProgress,
          createdOn: DateTime.now(),
          modifiedOn: DateTime.now(),
        ),
      );
      
      if (existingOrderWithSameNumber.orderNumber.isNotEmpty) {
        throw Exception('Order number "${order.orderNumber}" already exists for another order. Each order number must be unique.');
      }
      
      all[index] = order.copyWith(modifiedOn: DateTime.now());
      await _saveOrders(all);
      return all[index];
    }
    
    return await createOrder(order);
  }

  @override
  Future<bool> deleteOrder(String id) async {
    final all = await getAllOrders();
    final initialLength = all.length;
    all.removeWhere((item) => item.orderId == id);
    
    if (all.length < initialLength) {
      await _saveOrders(all);
      return true;
    }
    return false;
  }

  Future<void> _saveOrders(List<Order> orders) async {
    final headers = ['OrderId', 'OrderNumber', 'Machine', 'Status', 'CreatedOn', 'ModifiedOn', 'CreatedBy', 'ModifiedBy'];
    final filePath = await ExcelService.getExcelFilePath(_ordersFile);
    
    Excel excel;
    if (await File(filePath).exists()) {
      excel = await ExcelService.loadExcelFile(filePath);
    } else {
      excel = ExcelService.createExcelWithHeaders(headers, _sheetName);
    }

    final data = orders.map((item) => item.toJson()).toList();
    ExcelService.mapListToExcel(excel, _sheetName, data, headers);
    await ExcelService.saveExcelFile(excel, filePath);
  }

  // HourRegistration operations
  @override
  Future<List<HourRegistration>> getAllHourRegistrations() async {
    try {
      final filePath = await ExcelService.getExcelFilePath(_hourRegistrationFile);
      final excel = await ExcelService.loadExcelFile(filePath);
      
      if (!excel.sheets.containsKey(_sheetName)) {
        return [];
      }

      final data = ExcelService.excelToMapList(excel, _sheetName);
      return data.map((json) => HourRegistration.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<HourRegistration?> getHourRegistrationById(String id) async {
    final all = await getAllHourRegistrations();
    try {
      return all.firstWhere((item) => item.hourRegistrationId == id);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<HourRegistration>> getHourRegistrationsByOrderId(String orderId) async {
    final all = await getAllHourRegistrations();
    return all.where((item) => item.orderId == orderId).toList();
  }

  @override
  Future<List<HourRegistration>> getHourRegistrationsByUserId(String userId) async {
    final all = await getAllHourRegistrations();
    return all.where((item) => item.userId == userId).toList();
  }

  @override
  Future<HourRegistration?> getActiveHourRegistrationByUserId(String userId) async {
    final all = await getAllHourRegistrations();
    try {
      return all.firstWhere((item) => item.userId == userId && item.isActive);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<HourRegistration> createHourRegistration(HourRegistration registration) async {
    final all = await getAllHourRegistrations();
    final newRegistration = registration.copyWith(
      hourRegistrationId: registration.hourRegistrationId.isEmpty 
          ? _uuid.v4() 
          : registration.hourRegistrationId,
      createdOn: DateTime.now(),
      modifiedOn: DateTime.now(),
    );
    
    all.add(newRegistration);
    await _saveHourRegistrations(all);
    return newRegistration;
  }

  @override
  Future<HourRegistration> updateHourRegistration(HourRegistration registration) async {
    final all = await getAllHourRegistrations();
    final index = all.indexWhere((item) => item.hourRegistrationId == registration.hourRegistrationId);
    
    if (index != -1) {
      final computedElapsed = registration.elapsedTime ?? registration.calculateElapsedTime();
      final updated = registration.copyWith(
        modifiedOn: DateTime.now(),
        elapsedTime: computedElapsed,
      );
      all[index] = updated;
      await _saveHourRegistrations(all);
      return all[index];
    }
    
    return await createHourRegistration(registration);
  }

  @override
  Future<bool> deleteHourRegistration(String id) async {
    final all = await getAllHourRegistrations();
    final initialLength = all.length;
    all.removeWhere((item) => item.hourRegistrationId == id);
    
    if (all.length < initialLength) {
      await _saveHourRegistrations(all);
      return true;
    }
    return false;
  }

  Future<void> _saveHourRegistrations(List<HourRegistration> registrations) async {
    final headers = [
      'HourRegistrationId',
      'OrderId',
      'UserId',
      'StartTime',
      'EndTime',
      'ElapsedTime',
      'IsActive',
      'IsPaused',
      'PausedElapsedTime',
      'DowntimeElapsedTime',
      'DowntimeStartTime',
      'CreatedOn',
      'ModifiedOn'
    ];
    final filePath = await ExcelService.getExcelFilePath(_hourRegistrationFile);
    
    Excel excel;
    if (await File(filePath).exists()) {
      excel = await ExcelService.loadExcelFile(filePath);
    } else {
      excel = ExcelService.createExcelWithHeaders(headers, _sheetName);
    }

    final data = registrations.map((item) => item.toJson()).toList();
    ExcelService.mapListToExcel(excel, _sheetName, data, headers);
    await ExcelService.saveExcelFile(excel, filePath);
  }
}

