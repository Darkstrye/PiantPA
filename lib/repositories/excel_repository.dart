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
  static const String _orderregelsCsvFile = 'Orderregels.csv';
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
    // Load only from CSV Orderregels source
    final csvPath = await ExcelService.getExcelFilePath(_orderregelsCsvFile);
    if (await File(csvPath).exists()) {
      return await _loadOrdersFromCsv(csvPath);
    }
    // If CSV is missing, return empty list (no legacy fallback)
    return [];
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
    await _saveOrdersCsvStatuses(_ordersCache!);
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

  // Public method to clear all caches and force reload from disk
  void clearCache() {
    print('[ExcelRepository] Clearing all caches');
    _loginDetailsCache = null;
    _ordersCache = null;
    _hourRegistrationsCache = null;
    _hourRegistrationOrdersCache = null;
    _loginDetailsDirty = false;
    _ordersDirty = false;
    _hourRegistrationsDirty = false;
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

  // -------- CSV (Orderregels) support --------
  Future<List<Order>> _loadOrdersFromCsv(String filePath) async {
    try {
      final raw = await File(filePath).readAsString();
      final rows = _parseCsv(raw);
      if (rows.isEmpty) return [];
      final header = rows.first.map((h) => h.trim()).toList();
      int idxOrderregel = _findOrderregelHeaderIndex(header);
      int idxMachine = _findMachineHeaderIndex(header);
      int idxVoca = _findVocaHeaderIndex(header);
      int idxStatus = _findExactOrFuzzy(header, ['status']);

      // Aggregate by orderregel: sum voca, pick latest non-empty machine, and status (Completed if any row is Completed)
      final Map<String, double> vocaByOrder = {};
      final Map<String, String> machineByOrder = {};
      final Map<String, OrderStatus> statusByOrder = {};

      DateTime now = DateTime.now();
      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty) continue;
        final orderregel = idxOrderregel >= 0 && idxOrderregel < row.length
            ? row[idxOrderregel].trim()
            : '';
        if (orderregel.isEmpty) continue;
        final machine = idxMachine >= 0 && idxMachine < row.length ? row[idxMachine].trim() : '';
        final vocaRaw =
            idxVoca >= 0 && idxVoca < row.length ? row[idxVoca].trim() : '';
        final statusRaw =
            idxStatus >= 0 && idxStatus < row.length ? row[idxStatus].trim() : 'InProgress';

        final double? vocaInUur = _tryParseDutchDouble(vocaRaw);
        final status = _mapCsvStatus(statusRaw);

        // sum voca
        final current = vocaByOrder[orderregel] ?? 0.0;
        if (vocaInUur != null) {
          vocaByOrder[orderregel] = current + vocaInUur;
        } else {
          vocaByOrder[orderregel] = current + 0.0;
        }

        // latest non-empty machine
        if (machine.isNotEmpty) {
          machineByOrder[orderregel] = machine;
        } else {
          machineByOrder.putIfAbsent(orderregel, () => '');
        }

        // status completed if any row completed, else inProgress
        final prev = statusByOrder[orderregel];
        if (prev == null) {
          statusByOrder[orderregel] = status;
        } else {
          if (status == OrderStatus.completed) {
            statusByOrder[orderregel] = OrderStatus.completed;
          }
        }
      }

      final List<Order> orders = [];
      for (final entry in vocaByOrder.entries) {
        final orderId = entry.key;
        final machine = machineByOrder[orderId] ?? '';
        final status = statusByOrder[orderId] ?? OrderStatus.inProgress;
        orders.add(Order(
          orderId: orderId,
          orderNumber: orderId,
          machine: machine,
          vocaInUur: entry.value,
          status: status,
          createdOn: now,
          modifiedOn: now,
          createdBy: null,
          modifiedBy: null,
        ));
      }
      return orders;
    } catch (e) {
      // ignore: avoid_print
      print('Error loading Orderregels.csv: $e');
      return [];
    }
  }

  int _indexOfHeader(List<String> header, String name) {
    final ln = name.toLowerCase();
    for (int i = 0; i < header.length; i++) {
      if (header[i].toLowerCase() == ln) return i;
    }
    return -1;
  }

  // Header detection helpers (robust to different labels)
  String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  int _findExactOrFuzzy(List<String> header, List<String> names) {
    // try exact first
    for (final n in names) {
      final idx = _indexOfHeader(header, n);
      if (idx >= 0) return idx;
    }
    // then normalized equality
    final normTargets = names.map(_norm).toSet();
    for (int i = 0; i < header.length; i++) {
      final hn = _norm(header[i]);
      if (normTargets.contains(hn)) return i;
    }
    return -1;
  }

  int _findOrderregelHeaderIndex(List<String> header) {
    final idx = _findExactOrFuzzy(header, ['orderregel', 'order regel', 'ordernummer', 'ordernr', 'order']);
    if (idx >= 0) return idx;
    // fallback: contains the word order and digits in sample rows will be there; we keep simple
    for (int i = 0; i < header.length; i++) {
      final h = _norm(header[i]);
      if (h.contains('order') || h.contains('orderregel')) return i;
    }
    return -1;
  }

  int _findMachineHeaderIndex(List<String> header) {
    final idx = _findExactOrFuzzy(header, ['machinenaam', 'machine', 'machinen', 'machinena', 'machinens']);
    if (idx >= 0) return idx;
    for (int i = 0; i < header.length; i++) {
      final h = _norm(header[i]);
      if (h.contains('machine')) return i;
    }
    return -1;
  }

  int _findVocaHeaderIndex(List<String> header) {
    // Accept 'voca in uur', 'voca', 'sum of voca in uur', etc.
    final idx = _findExactOrFuzzy(header, ['voca in uur', 'voca']);
    if (idx >= 0) return idx;
    for (int i = 0; i < header.length; i++) {
      final h = _norm(header[i]);
      final hasVoca = h.contains('voca');
      final hasUurOrHours = h.contains('uur') || h.contains('hours');
      if (hasVoca && (hasUurOrHours || true)) {
        // If the column contains 'voca' at all, treat as voca
        return i;
      }
      if (h.startsWith('sumofvoca')) return i;
    }
    return -1;
  }

  double? _tryParseDutchDouble(String input) {
    if (input.isEmpty) return null;
    final s = input.trim();
    final hasComma = s.contains(',');
    final hasDot = s.contains('.');
    String normalized;
    if (hasComma && !hasDot) {
      // e.g., 1,50  -> 1.50
      normalized = s.replaceAll('.', '').replaceAll(',', '.');
    } else if (hasDot && !hasComma) {
      // e.g., 1.50  -> 1.50
      normalized = s;
    } else if (hasDot && hasComma) {
      // Mixed: decide by last separator as decimal; drop the other as thousands
      final lastComma = s.lastIndexOf(',');
      final lastDot = s.lastIndexOf('.');
      if (lastComma > lastDot) {
        // 1.234,56 -> remove dots, comma as decimal
        normalized = s.replaceAll('.', '').replaceAll(',', '.');
      } else {
        // 1,234.56 -> remove commas, dot as decimal
        normalized = s.replaceAll(',', '');
      }
    } else {
      normalized = s;
    }
    return double.tryParse(normalized);
  }

  OrderStatus _mapCsvStatus(String status) {
    switch (status.trim().toLowerCase()) {
      case 'inprogress':
      case 'in progress':
        return OrderStatus.inProgress;
      case 'completed':
        return OrderStatus.completed;
      default:
        return OrderStatus.inProgress;
    }
  }

  String _statusToCsv(OrderStatus status) {
    switch (status) {
      case OrderStatus.inProgress:
        return 'InProgress';
      case OrderStatus.completed:
        return 'Completed';
    }
  }

  List<List<String>> _parseCsv(String content) {
    final List<List<String>> rows = [];
    List<String> currentRow = [];
    final StringBuffer current = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < content.length; i++) {
      final char = content[i];
      if (inQuotes) {
        if (char == '"') {
          // Lookahead for escaped quote
          if (i + 1 < content.length && content[i + 1] == '"') {
            current.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          current.write(char);
        }
      } else {
        if (char == '"') {
          inQuotes = true;
        } else if (char == ',') {
          currentRow.add(current.toString());
          current.clear();
        } else if (char == '\n') {
          currentRow.add(current.toString());
          rows.add(currentRow);
          currentRow = [];
          current.clear();
        } else if (char == '\r') {
          // ignore CR (handle CRLF)
        } else {
          current.write(char);
        }
      }
    }
    // Last cell
    currentRow.add(current.toString());
    if (currentRow.isNotEmpty) {
      rows.add(currentRow);
    }
    return rows;
  }

  String _escapeCsv(String input) {
    final needsQuotes = input.contains(',') || input.contains('"') || input.contains('\n') || input.contains('\r');
    var value = input.replaceAll('"', '""');
    return needsQuotes ? '"$value"' : value;
  }

  Future<void> _saveOrdersCsvStatuses(List<Order> orders) async {
    final path = await ExcelService.getExcelFilePath(_orderregelsCsvFile);
    if (!await File(path).exists()) {
      // If CSV doesn't exist, create minimal CSV with known columns
      final header = ['orderregel', 'Machinenaam', 'voca in uur', 'Status'];
      final lines = <String>[];
      lines.add(header.join(','));
      for (final o in orders) {
        final voca = o.vocaInUur != null
            ? o.vocaInUur!.toString().replaceAll('.', ',')
            : '';
        lines.add([
          _escapeCsv(o.orderNumber),
          _escapeCsv(o.machine),
          _escapeCsv(voca),
          _escapeCsv(_statusToCsv(o.status)),
        ].join(','));
      }
      await File(path).writeAsString(lines.join('\r\n'));
      return;
    }

    // Read existing CSV and update Status column for known orders
    final raw = await File(path).readAsString();
    final rows = _parseCsv(raw);
    if (rows.isEmpty) return;
    final header = rows.first.toList();
    int idxOrderregel = _indexOfHeader(header, 'orderregel');
    if (idxOrderregel < 0) {
      header.add('Status');
      idxOrderregel = 0; // attempt to map by first column if missing
    }
    int idxStatus = _indexOfHeader(header, 'status');
    if (idxStatus < 0) {
      header.add('Status');
      idxStatus = header.length - 1;
    }

    final byOrder = {
      for (final o in orders) o.orderNumber.toLowerCase(): o,
    };

    // Update rows
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < header.length) {
        row.addAll(List.filled(header.length - row.length, ''));
      }
      final key = idxOrderregel < row.length ? row[idxOrderregel].toLowerCase() : '';
      if (byOrder.containsKey(key)) {
        row[idxStatus] = _statusToCsv(byOrder[key]!.status);
      }
    }

    // Write back
    final out = StringBuffer();
    out.writeln(header.map(_escapeCsv).join(','));
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      // Ensure row length equals header length
      if (row.length < header.length) {
        row.addAll(List.filled(header.length - row.length, ''));
      }
      out.writeln(row.map(_escapeCsv).join(','));
    }
    await File(path).writeAsString(out.toString());
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
  Future<List<HourRegistration>> getHourRegistrationsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final idSet = ids.map((e) => e.toLowerCase()).toSet();
    final all = await getAllHourRegistrations();
    return all.where((r) => idSet.contains(r.hourRegistrationId.toLowerCase())).toList();
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
  Future<Map<String, List<HourRegistrationOrder>>> getHourRegistrationOrdersByOrderIds(
      List<String> orderIds) async {
    final result = <String, List<HourRegistrationOrder>>{};
    if (orderIds.isEmpty) return result;
    final set = orderIds.map((e) => e.toLowerCase()).toSet();
    final all = await getAllHourRegistrationOrders();
    for (final order in all) {
      final key = order.orderId.toLowerCase();
      if (!set.contains(key)) continue;
      (result[order.orderId] ??= []).add(order);
    }
    return result;
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

