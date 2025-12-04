import 'dart:convert';
import 'dart:io';
import 'package:mssql_connection/mssql_connection.dart';
import '../models/login_details.dart';
import '../models/order.dart';
import '../models/hour_registration.dart';
import '../models/hour_registration_order.dart';
import '../services/excel_service.dart';
import 'repository_interface.dart';
import 'excel_repository.dart';

/// Configuration for SQL Server connection
class SqlConfig {
  final String server;
  final int port;
  final String database;
  final String username;
  final String password;
  final bool trustServerCertificate;

  SqlConfig({
    required this.server,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
    this.trustServerCertificate = true,
  });

  factory SqlConfig.fromJson(Map<String, dynamic> json) {
    return SqlConfig(
      server: json['server'] ?? '',
      port: json['port'] ?? 1433,
      database: json['database'] ?? '',
      username: json['username'] ?? '',
      password: json['password'] ?? '',
      trustServerCertificate: json['trustServerCertificate'] ?? true,
    );
  }

  static Future<SqlConfig?> loadFromFile() async {
    try {
      final configPath = await ExcelService.getExcelFilePath('sql_config.json');
      final file = File(configPath);
      if (!await file.exists()) {
        print('[HybridRepository] sql_config.json not found at $configPath');
        return null;
      }
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return SqlConfig.fromJson(json);
    } catch (e) {
      print('[HybridRepository] Error loading SQL config: $e');
      return null;
    }
  }
}

/// Hybrid Repository that uses SQL Server for orders (read-only) 
/// and Excel for hour registrations (read/write)
class HybridRepository implements RepositoryInterface {
  final ExcelRepository _excelRepo;
  MssqlConnection? _sqlConnection;
  SqlConfig? _sqlConfig;
  bool _sqlInitialized = false;
  bool _sqlAvailable = false;

  // Cache for SQL orders
  List<Order>? _sqlOrdersCache;
  DateTime? _sqlOrdersCacheTime;
  static const Duration _cacheDuration = Duration(seconds: 30);

  // Machine name cache
  Map<int, String>? _machineNamesCache;

  // In-progress status IDs based on the SQL database
  static const List<int> _inProgressStatusIds = [2, 3, 4, 10, 11, 18, 19, 20, 21];

  HybridRepository() : _excelRepo = ExcelRepository();

  /// Initialize SQL connection
  Future<bool> _initSql() async {
    if (_sqlInitialized) return _sqlAvailable;
    _sqlInitialized = true;

    try {
      _sqlConfig = await SqlConfig.loadFromFile();
      if (_sqlConfig == null) {
        print('[HybridRepository] No SQL config found, using Excel fallback for orders');
        _sqlAvailable = false;
        return false;
      }

      _sqlConnection = MssqlConnection.getInstance();
      final connected = await _sqlConnection!.connect(
        ip: _sqlConfig!.server,
        port: _sqlConfig!.port.toString(),
        databaseName: _sqlConfig!.database,
        username: _sqlConfig!.username,
        password: _sqlConfig!.password,
      );

      if (connected) {
        print('[HybridRepository] Connected to SQL Server: ${_sqlConfig!.server}/${_sqlConfig!.database}');
        _sqlAvailable = true;
        // Pre-load machine names
        await _loadMachineNames();
        return true;
      } else {
        print('[HybridRepository] Failed to connect to SQL Server');
        _sqlAvailable = false;
        return false;
      }
    } catch (e) {
      print('[HybridRepository] SQL initialization error: $e');
      _sqlAvailable = false;
      return false;
    }
  }

  /// Load machine names from SQL for display
  Future<void> _loadMachineNames() async {
    if (_sqlConnection == null || !_sqlAvailable) return;

    try {
      final resultJson = await _sqlConnection!.getData(
        'SELECT machineid, MachineNaam FROM TBL_ProdMachine',
      );
      
      _machineNamesCache = {};
      if (resultJson.isNotEmpty) {
        final List<dynamic> rows = jsonDecode(resultJson);
        for (final row in rows) {
          final id = row['machineid'];
          final name = row['MachineNaam'] ?? '';
          if (id != null) {
            _machineNamesCache![id as int] = name.toString();
          }
        }
        print('[HybridRepository] Loaded ${_machineNamesCache!.length} machine names');
      }
    } catch (e) {
      print('[HybridRepository] Error loading machine names: $e');
      _machineNamesCache = {};
    }
  }

  String _getMachineName(int? machineId) {
    if (machineId == null || _machineNamesCache == null) return '';
    return _machineNamesCache![machineId] ?? '';
  }

  /// Check if cache is still valid
  bool _isCacheValid() {
    if (_sqlOrdersCache == null || _sqlOrdersCacheTime == null) return false;
    return DateTime.now().difference(_sqlOrdersCacheTime!) < _cacheDuration;
  }

  /// Clear orders cache to force refresh
  void clearOrdersCache() {
    _sqlOrdersCache = null;
    _sqlOrdersCacheTime = null;
    _excelRepo.clearOrdersCache();
  }

  /// Clear all caches
  void clearCache() {
    clearOrdersCache();
    _excelRepo.clearCache();
  }

  /// Clear only registrations cache
  void clearRegistrationsCache() {
    _excelRepo.clearRegistrationsCache();
  }

  // Cache for filters
  Map<int, String>? _statusNamesCache;
  Map<int, String>? _machineGroupsCache;

  /// Get all machines for filtering
  Future<Map<int, String>> getMachines() async {
    await _initSql();
    if (_machineNamesCache != null) return Map.from(_machineNamesCache!);
    await _loadMachineNames();
    return Map.from(_machineNamesCache ?? {});
  }

  /// Get all machine groups for filtering
  Future<Map<int, String>> getMachineGroups() async {
    await _initSql();
    if (_machineGroupsCache != null) return Map.from(_machineGroupsCache!);
    
    if (!_sqlAvailable || _sqlConnection == null) return {};
    
    try {
      final resultJson = await _sqlConnection!.getData(
        'SELECT machinegroepid, MachineGroep FROM Tbl_ProdMachinegroep',
      );
      
      _machineGroupsCache = {};
      if (resultJson.isNotEmpty) {
        final List<dynamic> rows = jsonDecode(resultJson);
        for (final row in rows) {
          final id = row['machinegroepid'];
          final name = row['MachineGroep'] ?? '';
          if (id != null) {
            _machineGroupsCache![id as int] = name.toString();
          }
        }
      }
      return Map.from(_machineGroupsCache!);
    } catch (e) {
      print('[HybridRepository] Error loading machine groups: $e');
      return {};
    }
  }

  /// Get all statuses for filtering
  Future<Map<int, String>> getStatuses() async {
    await _initSql();
    if (_statusNamesCache != null) return Map.from(_statusNamesCache!);
    
    if (!_sqlAvailable || _sqlConnection == null) return {};
    
    try {
      final resultJson = await _sqlConnection!.getData(
        'SELECT statusid, status FROM Tbl_ProdStatus ORDER BY volgorde',
      );
      
      _statusNamesCache = {};
      if (resultJson.isNotEmpty) {
        final List<dynamic> rows = jsonDecode(resultJson);
        for (final row in rows) {
          final id = row['statusid'];
          final name = row['status'] ?? '';
          if (id != null) {
            _statusNamesCache![id as int] = name.toString();
          }
        }
      }
      return Map.from(_statusNamesCache!);
    } catch (e) {
      print('[HybridRepository] Error loading statuses: $e');
      return {};
    }
  }

  /// Get orders with filters
  Future<List<Order>> getOrdersWithFilters({
    int? machineId,
    int? machineGroupId,
    int? statusId,
  }) async {
    await _initSql();
    
    if (!_sqlAvailable || _sqlConnection == null) {
      return _excelRepo.getAllOrders();
    }

    try {
      final conditions = <String>[];
      conditions.add('(o.productie_startdatum >= DATEADD(day, -30, GETDATE()) OR o.leverdatum >= DATEADD(day, -30, GETDATE()))');
      
      if (machineId != null) {
        conditions.add('o.machineid = $machineId');
      }
      if (machineGroupId != null) {
        conditions.add('o.machinegroepid = $machineGroupId');
      }
      if (statusId != null) {
        conditions.add('o.statusid = $statusId');
      }
      
      final whereClause = conditions.join(' AND ');
      
      // Query with JOINs to get machine name, machine group, and status directly
      // Totaalbedrag: Aantal * PrijsEX
      final query = '''
        SELECT 
          CAST(o.Orderregel AS VARCHAR) + '-' + CAST(o.Ordernummer AS VARCHAR) as orderId,
          CAST(o.Orderregel AS VARCHAR) + '-' + CAST(o.Ordernummer AS VARCHAR) as orderNumber,
          CAST(o.Ordernummer AS VARCHAR) as ordernummer,
          CAST(o.Orderregel AS VARCHAR) as orderregel,
          m.MachineNaam as machineName,
          mg.MachineGroep as machineGroupName,
          s.status as statusName,
          (
            (ISNULL(o.productietijdsec, 0) + ISNULL(o.buitmachtijdsec, 0)) 
            * ISNULL(o.geproduceerd, 0)
            + (ISNULL(o.insteltijd, 0) * 60)
          ) / 3600.0 as totalVoca,
          ISNULL(o.geproduceerd, 0) as geproduceerd,
          ISNULL(o.Aantal, 0) * ISNULL(o.PrijsEX, 0) as totaalBedrag,
          o.productie_startdatum as startDate,
          o.productie_leverdatum as endDate,
          o.leverdatum as leverdatum,
          o.Omschrijving as omschrijving
        FROM tbl_Orderregels o
        LEFT JOIN TBL_ProdMachine m ON o.machineid = m.machineid
        LEFT JOIN Tbl_ProdMachinegroep mg ON o.machinegroepid = mg.machinegroepid
        LEFT JOIN Tbl_ProdStatus s ON o.statusid = s.statusid
        WHERE $whereClause
        ORDER BY o.Ordernummer, o.Orderregel
      ''';

      final resultJson = await _sqlConnection!.getData(query);
      
      final orders = <Order>[];
      final now = DateTime.now();

      if (resultJson.isEmpty) {
        return orders;
      }

      final List<dynamic> rows = jsonDecode(resultJson);
      for (final row in rows) {
        final orderId = row['orderId']?.toString() ?? '';
        final orderNumber = row['orderNumber']?.toString() ?? '';
        final ordernummer = row['ordernummer']?.toString();
        final orderregel = row['orderregel']?.toString();
        final machineName = row['machineName']?.toString() ?? '';
        final statusName = row['statusName']?.toString();
        final omschrijving = row['omschrijving']?.toString();
        final voca = (row['totalVoca'] as num?)?.toDouble();
        final geproduceerd = (row['geproduceerd'] as num?)?.toDouble();
        final totaalBedrag = (row['totaalBedrag'] as num?)?.toDouble();
        
        // Parse leverdatum
        DateTime? leverdatum;
        if (row['leverdatum'] != null) {
          leverdatum = DateTime.tryParse(row['leverdatum'].toString());
        }

        if (orderId.isEmpty) continue;

        orders.add(Order(
          orderId: orderId,
          orderNumber: orderNumber,
          ordernummer: ordernummer,
          orderregel: orderregel,
          machine: machineName,
          vocaInUur: voca,
          geproduceerd: geproduceerd,
          totaalBedrag: totaalBedrag,
          omschrijving: omschrijving,
          leverdatum: leverdatum,
          statusNaam: statusName,
          status: OrderStatus.inProgress,
          createdOn: now,
          modifiedOn: now,
        ));
      }

      return orders;
    } catch (e) {
      print('[HybridRepository] Error loading filtered orders: $e');
      return [];
    }
  }

  // ============== ORDER OPERATIONS (SQL, READ-ONLY) ==============

  Future<List<Order>> _loadOrdersFromSql() async {
    if (!_sqlAvailable || _sqlConnection == null) {
      return [];
    }

    try {
      // Query with JOINs to get machine name directly from related tables
      // VOCA formula: ((productietijdsec + buitmachtijdsec) * geproduceerd + (insteltijd * 60)) / 3600
      // Totaalbedrag: Aantal * PrijsEX
      final query = '''
        SELECT 
          CAST(o.Orderregel AS VARCHAR) + '-' + CAST(o.Ordernummer AS VARCHAR) as orderId,
          CAST(o.Orderregel AS VARCHAR) + '-' + CAST(o.Ordernummer AS VARCHAR) as orderNumber,
          CAST(o.Ordernummer AS VARCHAR) as ordernummer,
          CAST(o.Orderregel AS VARCHAR) as orderregel,
          m.MachineNaam as machineName,
          mg.MachineGroep as machineGroupName,
          s.status as statusName,
          (
            (ISNULL(o.productietijdsec, 0) + ISNULL(o.buitmachtijdsec, 0)) 
            * ISNULL(o.geproduceerd, 0)
            + (ISNULL(o.insteltijd, 0) * 60)
          ) / 3600.0 as totalVoca,
          ISNULL(o.geproduceerd, 0) as geproduceerd,
          ISNULL(o.Aantal, 0) * ISNULL(o.PrijsEX, 0) as totaalBedrag,
          o.productie_startdatum as startDate,
          o.productie_leverdatum as endDate,
          o.leverdatum as leverdatum,
          o.Omschrijving as omschrijving
        FROM tbl_Orderregels o
        LEFT JOIN TBL_ProdMachine m ON o.machineid = m.machineid
        LEFT JOIN Tbl_ProdMachinegroep mg ON o.machinegroepid = mg.machinegroepid
        LEFT JOIN Tbl_ProdStatus s ON o.statusid = s.statusid
        WHERE o.productie_startdatum >= DATEADD(day, -30, GETDATE())
           OR o.leverdatum >= DATEADD(day, -30, GETDATE())
        ORDER BY o.Ordernummer, o.Orderregel
      ''';

      final resultJson = await _sqlConnection!.getData(query);
      
      final orders = <Order>[];
      final now = DateTime.now();

      if (resultJson.isEmpty) {
        print('[HybridRepository] No orders found in SQL');
        return orders;
      }

      final List<dynamic> rows = jsonDecode(resultJson);
      
      // Debug: print first few rows to see actual values
      if (rows.isNotEmpty) {
        print('[HybridRepository] DEBUG - First row keys: ${rows[0].keys.toList()}');
        for (int i = 0; i < 3 && i < rows.length; i++) {
          final r = rows[i];
          print('[HybridRepository] DEBUG - Row $i: ordernummer=${r['ordernummer']}, orderregel=${r['orderregel']}, machine=${r['machineName']}');
        }
      }
      
      for (final row in rows) {
        final orderId = row['orderId']?.toString() ?? '';
        final orderNumber = row['orderNumber']?.toString() ?? '';
        final ordernummer = row['ordernummer']?.toString();
        final orderregel = row['orderregel']?.toString();
        final machineName = row['machineName']?.toString() ?? '';
        final statusName = row['statusName']?.toString();
        final omschrijving = row['omschrijving']?.toString();
        final voca = (row['totalVoca'] as num?)?.toDouble();
        final geproduceerd = (row['geproduceerd'] as num?)?.toDouble();
        final totaalBedrag = (row['totaalBedrag'] as num?)?.toDouble();
        
        // Parse leverdatum
        DateTime? leverdatum;
        if (row['leverdatum'] != null) {
          leverdatum = DateTime.tryParse(row['leverdatum'].toString());
        }

        if (orderId.isEmpty) continue;

        orders.add(Order(
          orderId: orderId,
          orderNumber: orderNumber,
          ordernummer: ordernummer,
          orderregel: orderregel,
          machine: machineName,
          vocaInUur: voca,
          geproduceerd: geproduceerd,
          totaalBedrag: totaalBedrag,
          omschrijving: omschrijving,
          leverdatum: leverdatum,
          statusNaam: statusName,
          status: OrderStatus.inProgress,
          createdOn: now,
          modifiedOn: now,
        ));
      }

      print('[HybridRepository] Loaded ${orders.length} orders from SQL');
      return orders;
    } catch (e) {
      print('[HybridRepository] Error loading orders from SQL: $e');
      return [];
    }
  }

  @override
  Future<List<Order>> getAllOrders() async {
    await _initSql();

    if (_sqlAvailable) {
      // Check cache first
      if (_isCacheValid()) {
        return List<Order>.from(_sqlOrdersCache!);
      }

      // Load from SQL
      _sqlOrdersCache = await _loadOrdersFromSql();
      _sqlOrdersCacheTime = DateTime.now();
      return List<Order>.from(_sqlOrdersCache!);
    }

    // Fallback to Excel if SQL not available
    return _excelRepo.getAllOrders();
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
  Future<Map<String, Order>> getOrdersByIds(List<String> ids) async {
    if (ids.isEmpty) return {};
    final idSet = ids.map((e) => e.toLowerCase()).toSet();
    final all = await getAllOrders();
    final result = <String, Order>{};
    for (final order in all) {
      if (idSet.contains(order.orderId.toLowerCase())) {
        result[order.orderId] = order;
      }
    }
    return result;
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

  // READ-ONLY: These operations are not supported for SQL orders
  @override
  Future<Order> createOrder(Order order) async {
    throw UnsupportedError(
      'Cannot create orders - SQL connection is read-only. '
      'Orders must be created in the main system.'
    );
  }

  @override
  Future<Order> updateOrder(Order order) async {
    throw UnsupportedError(
      'Cannot update orders - SQL connection is read-only. '
      'Orders must be updated in the main system.'
    );
  }

  @override
  Future<bool> deleteOrder(String id) async {
    throw UnsupportedError(
      'Cannot delete orders - SQL connection is read-only. '
      'Orders must be deleted in the main system.'
    );
  }

  // ============== DELEGATED OPERATIONS (EXCEL) ==============

  // LoginDetails - delegate to Excel
  @override
  Future<List<LoginDetails>> getAllLoginDetails() => 
    _excelRepo.getAllLoginDetails();

  @override
  Future<LoginDetails?> getLoginDetailsById(String id) => 
    _excelRepo.getLoginDetailsById(id);

  @override
  Future<LoginDetails?> getLoginDetailsByUsername(String username) => 
    _excelRepo.getLoginDetailsByUsername(username);

  @override
  Future<LoginDetails> createLoginDetails(LoginDetails loginDetails) => 
    _excelRepo.createLoginDetails(loginDetails);

  @override
  Future<LoginDetails> updateLoginDetails(LoginDetails loginDetails) => 
    _excelRepo.updateLoginDetails(loginDetails);

  @override
  Future<bool> deleteLoginDetails(String id) => 
    _excelRepo.deleteLoginDetails(id);

  // HourRegistration - delegate to Excel
  @override
  Future<List<HourRegistration>> getAllHourRegistrations() => 
    _excelRepo.getAllHourRegistrations();

  @override
  Future<HourRegistration?> getHourRegistrationById(String id) => 
    _excelRepo.getHourRegistrationById(id);

  @override
  Future<List<HourRegistration>> getHourRegistrationsByOrderId(String orderId) => 
    _excelRepo.getHourRegistrationsByOrderId(orderId);

  @override
  Future<List<HourRegistration>> getHourRegistrationsByUserId(String userId) => 
    _excelRepo.getHourRegistrationsByUserId(userId);

  @override
  Future<List<HourRegistration>> getHourRegistrationsByIds(List<String> ids) => 
    _excelRepo.getHourRegistrationsByIds(ids);

  @override
  Future<HourRegistration?> getActiveHourRegistrationByUserId(String userId) => 
    _excelRepo.getActiveHourRegistrationByUserId(userId);

  @override
  Future<HourRegistration> createHourRegistration(HourRegistration registration) => 
    _excelRepo.createHourRegistration(registration);

  @override
  Future<({HourRegistration registration, List<HourRegistrationOrder> orderLinks})>
      createHourRegistrationWithOrders(
    HourRegistration registration,
    List<String> orderIds,
  ) => _excelRepo.createHourRegistrationWithOrders(registration, orderIds);

  @override
  Future<HourRegistration> updateHourRegistration(HourRegistration registration) => 
    _excelRepo.updateHourRegistration(registration);

  @override
  Future<bool> deleteHourRegistration(String id) => 
    _excelRepo.deleteHourRegistration(id);

  // HourRegistrationOrder - delegate to Excel
  @override
  Future<List<HourRegistrationOrder>> getAllHourRegistrationOrders() => 
    _excelRepo.getAllHourRegistrationOrders();

  @override
  Future<List<HourRegistrationOrder>> getHourRegistrationOrdersByRegistrationId(
    String hourRegistrationId,
  ) => _excelRepo.getHourRegistrationOrdersByRegistrationId(hourRegistrationId);

  @override
  Future<List<HourRegistrationOrder>> getHourRegistrationOrdersByOrderId(
    String orderId,
  ) => _excelRepo.getHourRegistrationOrdersByOrderId(orderId);

  @override
  Future<Map<String, List<HourRegistrationOrder>>> getHourRegistrationOrdersByOrderIds(
    List<String> orderIds,
  ) => _excelRepo.getHourRegistrationOrdersByOrderIds(orderIds);

  @override
  Future<HourRegistrationOrder?> getActiveHourRegistrationOrderForUser(
    String orderId,
    String userId,
  ) => _excelRepo.getActiveHourRegistrationOrderForUser(orderId, userId);

  @override
  Future<HourRegistrationOrder> createHourRegistrationOrder(
    HourRegistrationOrder registrationOrder,
  ) => _excelRepo.createHourRegistrationOrder(registrationOrder);

  @override
  Future<HourRegistrationOrder> updateHourRegistrationOrder(
    HourRegistrationOrder registrationOrder,
  ) => _excelRepo.updateHourRegistrationOrder(registrationOrder);

  @override
  Future<bool> deleteHourRegistrationOrder(String id) => 
    _excelRepo.deleteHourRegistrationOrder(id);

  @override
  Future<void> deleteHourRegistrationOrdersByRegistrationId(
    String hourRegistrationId,
  ) => _excelRepo.deleteHourRegistrationOrdersByRegistrationId(hourRegistrationId);
}

