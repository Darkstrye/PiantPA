import 'dart:io';
import 'package:excel/excel.dart';
import 'package:uuid/uuid.dart';
import '../models/login_details.dart';
import '../models/order.dart';
import '../models/hour_registration.dart';
import '../models/hour_registration_order.dart';
import '../services/excel_service.dart';
import 'repository_interface.dart';

class ExcelRepository implements RepositoryInterface {
  static const String _loginDetailsFile = 'login_details.xlsx';
  static const String _ordersFile = 'orders.xlsx';
  static const String _hourRegistrationFile = 'hour_registration.xlsx';
  static const String _hourRegistrationOrderFile = 'hour_registration_orders.xlsx';
  static const String _sheetName = 'Sheet1';
  static const _uuid = Uuid();

  List<LoginDetails>? _loginDetailsCache;
  List<Order>? _ordersCache;
  List<HourRegistration>? _hourRegistrationsCache;
  List<HourRegistrationOrder>? _hourRegistrationOrdersCache;

  bool _loginDetailsDirty = false;
  bool _ordersDirty = false;
  bool _hourRegistrationsDirty = false;
  bool _hourRegistrationOrdersDirty = false;

  Future<List<LoginDetails>> _loadLoginDetails() async {
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

  Future<List<Order>> _loadOrders() async {
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

  Future<List<HourRegistration>> _loadHourRegistrations() async {
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

  Future<List<HourRegistrationOrder>> _loadHourRegistrationOrders() async {
    try {
      final filePath =
          await ExcelService.getExcelFilePath(_hourRegistrationOrderFile);
      if (!await File(filePath).exists()) {
        return await _buildLegacyRegistrationOrders();
      }

      final excel = await ExcelService.loadExcelFile(filePath);

      if (!excel.sheets.containsKey(_sheetName)) {
        return await _buildLegacyRegistrationOrders();
      }

      final data = ExcelService.excelToMapList(excel, _sheetName);
      final orders =
          data.map((json) => HourRegistrationOrder.fromJson(json)).toList();

      if (orders.isEmpty) {
        return await _buildLegacyRegistrationOrders();
      }

      return orders;
    } catch (e) {
      return await _buildLegacyRegistrationOrders();
    }
  }

  Future<List<LoginDetails>> _getLoginDetailsCache() async {
    _loginDetailsCache ??= await _loadLoginDetails();
    return _loginDetailsCache!;
  }

  Future<List<Order>> _getOrdersCache() async {
    _ordersCache ??= await _loadOrders();
    return _ordersCache!;
  }

  Future<List<HourRegistration>> _getHourRegistrationsCache() async {
    _hourRegistrationsCache ??= await _loadHourRegistrations();
    return _hourRegistrationsCache!;
  }

  Future<List<HourRegistrationOrder>> _getHourRegistrationOrdersCache() async {
    _hourRegistrationOrdersCache ??= await _loadHourRegistrationOrders();
    return _hourRegistrationOrdersCache!;
  }

  Future<void> _persistLoginDetailsCache() async {
    if (_loginDetailsCache == null || !_loginDetailsDirty) return;
    await _saveLoginDetails(_loginDetailsCache!);
    _loginDetailsDirty = false;
  }

  Future<void> _persistOrdersCache() async {
    if (_ordersCache == null || !_ordersDirty) return;
    await _saveOrders(_ordersCache!);
    _ordersDirty = false;
  }

  Future<void> _persistHourRegistrationsCache() async {
    if (_hourRegistrationsCache == null || !_hourRegistrationsDirty) return;
    await _saveHourRegistrations(_hourRegistrationsCache!);
    _hourRegistrationsDirty = false;
  }

  Future<void> _persistHourRegistrationOrdersCache() async {
    if (_hourRegistrationOrdersCache == null || !_hourRegistrationOrdersDirty) return;
    await _saveHourRegistrationOrders(_hourRegistrationOrdersCache!);
    _hourRegistrationOrdersDirty = false;
  }

  // LoginDetails operations
  @override
  Future<List<LoginDetails>> getAllLoginDetails() async {
    final cache = await _getLoginDetailsCache();
    return List<LoginDetails>.from(cache);
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
    final all = await _getLoginDetailsCache();
    final newLoginDetails = loginDetails.copyWith(
      loginDetailsId: loginDetails.loginDetailsId.isEmpty 
          ? _uuid.v4() 
          : loginDetails.loginDetailsId,
      createdOn: DateTime.now(),
      modifiedOn: DateTime.now(),
    );
    
    all.add(newLoginDetails);
    _loginDetailsDirty = true;
    await _persistLoginDetailsCache();
    return newLoginDetails;
  }

  @override
  Future<LoginDetails> updateLoginDetails(LoginDetails loginDetails) async {
    final all = await _getLoginDetailsCache();
    final index = all.indexWhere((item) => item.loginDetailsId == loginDetails.loginDetailsId);
    
    if (index != -1) {
      all[index] = loginDetails.copyWith(modifiedOn: DateTime.now());
      _loginDetailsDirty = true;
      await _persistLoginDetailsCache();
      return all[index];
    }
    
    return await createLoginDetails(loginDetails);
  }

  @override
  Future<bool> deleteLoginDetails(String id) async {
    final all = await _getLoginDetailsCache();
    final initialLength = all.length;
    all.removeWhere((item) => item.loginDetailsId == id);
    
    if (all.length < initialLength) {
      _loginDetailsDirty = true;
      await _persistLoginDetailsCache();
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
    final cache = await _getOrdersCache();
    return List<Order>.from(cache);
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
    final all = await _getOrdersCache();
    
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
    _ordersDirty = true;
    await _persistOrdersCache();
    return newOrder;
  }

  @override
  Future<Order> updateOrder(Order order) async {
    final all = await _getOrdersCache();
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
      _ordersDirty = true;
      await _persistOrdersCache();
      return all[index];
    }
    
    return await createOrder(order);
  }

  @override
  Future<bool> deleteOrder(String id) async {
    final all = await _getOrdersCache();
    final initialLength = all.length;
    all.removeWhere((item) => item.orderId == id);
    
    if (all.length < initialLength) {
      _ordersDirty = true;
      await _persistOrdersCache();
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
    final cache = await _getHourRegistrationsCache();
    return List<HourRegistration>.from(cache);
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
    final mappings = await getHourRegistrationOrdersByOrderId(orderId);
    if (mappings.isEmpty) {
      return [];
    }
    final registrations = await getAllHourRegistrations();
    final ids = mappings
        .map((mapping) => mapping.hourRegistrationId)
        .toSet();
    return registrations
        .where((registration) => ids.contains(registration.hourRegistrationId))
        .toList();
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
    final all = await _getHourRegistrationsCache();
    final newRegistration = registration.copyWith(
      hourRegistrationId: registration.hourRegistrationId.isEmpty 
          ? _uuid.v4() 
          : registration.hourRegistrationId,
      createdOn: DateTime.now(),
      modifiedOn: DateTime.now(),
    );
    
    all.add(newRegistration);
    _hourRegistrationsDirty = true;
    await _persistHourRegistrationsCache();
    return newRegistration;
  }

  @override
  Future<({HourRegistration registration, List<HourRegistrationOrder> orderLinks})>
      createHourRegistrationWithOrders(
    HourRegistration registration,
    List<String> orderIds,
  ) async {
    final normalizedIds = orderIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    final now = DateTime.now();

    final registrations = await _getHourRegistrationsCache();
    final orders = await _getHourRegistrationOrdersCache();

    final newRegistration = registration.copyWith(
      hourRegistrationId: registration.hourRegistrationId.isEmpty
          ? _uuid.v4()
          : registration.hourRegistrationId,
      createdOn: now,
      modifiedOn: now,
    );
    registrations.add(newRegistration);
    _hourRegistrationsDirty = true;

    final List<HourRegistrationOrder> createdLinks = [];

    for (final orderId in normalizedIds) {
      final newLink = HourRegistrationOrder(
        hourRegistrationOrderId: _uuid.v4(),
        hourRegistrationId: newRegistration.hourRegistrationId,
        orderId: orderId,
        isActive: true,
        elapsedTime: 0.0,
        elapsedOffset: 0.0,
        downtimeElapsedTime: 0.0,
        downtimeOffset: 0.0,
        createdOn: now,
        modifiedOn: now,
      );
      orders.add(newLink);
      createdLinks.add(newLink);
    }

    if (createdLinks.isNotEmpty) {
      _hourRegistrationOrdersDirty = true;
    }

    await _persistHourRegistrationsCache();
    await _persistHourRegistrationOrdersCache();

    return (registration: newRegistration, orderLinks: createdLinks);
  }

  @override
  Future<HourRegistration> updateHourRegistration(HourRegistration registration) async {
    final all = await _getHourRegistrationsCache();
    final index = all.indexWhere((item) => item.hourRegistrationId == registration.hourRegistrationId);
    
    if (index != -1) {
      final computedElapsed = registration.elapsedTime ?? registration.calculateElapsedTime();
      final updated = registration.copyWith(
        modifiedOn: DateTime.now(),
        elapsedTime: computedElapsed,
      );
      all[index] = updated;
      _hourRegistrationsDirty = true;
      await _persistHourRegistrationsCache();
      return all[index];
    }
    
    return await createHourRegistration(registration);
  }

  @override
  Future<bool> deleteHourRegistration(String id) async {
    final all = await _getHourRegistrationsCache();
    final initialLength = all.length;
    all.removeWhere((item) => item.hourRegistrationId == id);
    
    if (all.length < initialLength) {
      _hourRegistrationsDirty = true;
      await _persistHourRegistrationsCache();
      await deleteHourRegistrationOrdersByRegistrationId(id);
      return true;
    }
    return false;
  }

  Future<void> _saveHourRegistrations(List<HourRegistration> registrations) async {
    final headers = [
      'HourRegistrationId',
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

  // HourRegistrationOrder operations
  @override
  Future<List<HourRegistrationOrder>> getAllHourRegistrationOrders() async {
    final cache = await _getHourRegistrationOrdersCache();
    return List<HourRegistrationOrder>.from(cache);
  }

  @override
  Future<List<HourRegistrationOrder>>
      getHourRegistrationOrdersByRegistrationId(
          String hourRegistrationId) async {
    final all = await getAllHourRegistrationOrders();
    return all
        .where((item) =>
            item.hourRegistrationId.toLowerCase() ==
            hourRegistrationId.toLowerCase())
        .toList();
  }

  @override
  Future<List<HourRegistrationOrder>> getHourRegistrationOrdersByOrderId(
      String orderId) async {
    final all = await getAllHourRegistrationOrders();
    return all
        .where((item) => item.orderId.toLowerCase() == orderId.toLowerCase())
        .toList();
  }

  @override
  Future<HourRegistrationOrder?> getActiveHourRegistrationOrderForUser(
      String orderId, String userId) async {
    final activeRegistration = await getActiveHourRegistrationByUserId(userId);
    if (activeRegistration == null) {
      return null;
    }
    final mappings = await getHourRegistrationOrdersByRegistrationId(
        activeRegistration.hourRegistrationId);
    try {
      return mappings.firstWhere(
        (mapping) =>
            mapping.orderId.toLowerCase() == orderId.toLowerCase() &&
            mapping.isActive,
      );
    } catch (e) {
      return null;
    }
  }

  @override
  Future<HourRegistrationOrder> createHourRegistrationOrder(
      HourRegistrationOrder registrationOrder) async {
    final all = await _getHourRegistrationOrdersCache();
    final now = DateTime.now();
    final newOrder = registrationOrder.copyWith(
      hourRegistrationOrderId: registrationOrder.hourRegistrationOrderId.isEmpty
          ? _uuid.v4()
          : registrationOrder.hourRegistrationOrderId,
      createdOn: now,
      modifiedOn: now,
    );

    all.add(newOrder);
    _hourRegistrationOrdersDirty = true;
    await _persistHourRegistrationOrdersCache();
    return newOrder;
  }

  @override
  Future<HourRegistrationOrder> updateHourRegistrationOrder(
      HourRegistrationOrder registrationOrder) async {
    final all = await _getHourRegistrationOrdersCache();
    final index = all.indexWhere((item) =>
        item.hourRegistrationOrderId == registrationOrder.hourRegistrationOrderId);

    if (index != -1) {
      final updated = registrationOrder.copyWith(
        modifiedOn: DateTime.now(),
      );
      all[index] = updated;
      _hourRegistrationOrdersDirty = true;
      await _persistHourRegistrationOrdersCache();
      return updated;
    }

    return await createHourRegistrationOrder(registrationOrder);
  }

  @override
  Future<bool> deleteHourRegistrationOrder(String id) async {
    final all = await _getHourRegistrationOrdersCache();
    final initialLength = all.length;
    all.removeWhere((item) => item.hourRegistrationOrderId == id);

    if (all.length < initialLength) {
      _hourRegistrationOrdersDirty = true;
      await _persistHourRegistrationOrdersCache();
      return true;
    }
    return false;
  }

  @override
  Future<void> deleteHourRegistrationOrdersByRegistrationId(
      String hourRegistrationId) async {
    final all = await _getHourRegistrationOrdersCache();
    final filtered = all
        .where(
          (item) =>
              item.hourRegistrationId.toLowerCase() !=
              hourRegistrationId.toLowerCase(),
        )
        .toList();
    if (filtered.length != all.length) {
      _hourRegistrationOrdersCache = filtered;
      _hourRegistrationOrdersDirty = true;
      await _persistHourRegistrationOrdersCache();
    }
  }

  Future<void> _saveHourRegistrationOrders(
      List<HourRegistrationOrder> registrations) async {
    final headers = [
      'HourRegistrationOrderId',
      'HourRegistrationId',
      'OrderId',
      'IsActive',
      'ElapsedTime',
      'ElapsedOffset',
      'DowntimeElapsedTime',
      'DowntimeOffset',
      'CreatedOn',
      'ModifiedOn',
      'CompletedOn',
    ];

    final filePath =
        await ExcelService.getExcelFilePath(_hourRegistrationOrderFile);

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

  Future<List<HourRegistrationOrder>> _buildLegacyRegistrationOrders() async {
    final registrations = await getAllHourRegistrations();
    final now = DateTime.now();
    return registrations
        .where((reg) => reg.legacyOrderId != null && reg.legacyOrderId!.isNotEmpty)
        .map(
          (reg) => HourRegistrationOrder(
            hourRegistrationOrderId: _uuid.v4(),
            hourRegistrationId: reg.hourRegistrationId,
            orderId: reg.legacyOrderId!,
            isActive: reg.isActive,
            elapsedTime: reg.elapsedTime,
            elapsedOffset: null,
            downtimeElapsedTime: reg.downtimeElapsedTime,
            downtimeOffset: null,
            createdOn: reg.createdOn,
            modifiedOn: reg.modifiedOn,
            completedOn: reg.endTime,
          ),
        )
        .toList();
  }
}

