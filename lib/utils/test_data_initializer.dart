import '../repositories/excel_repository.dart';
import '../models/login_details.dart';
import '../models/order.dart';
import 'package:uuid/uuid.dart';

/// Helper class to initialize test data
/// This can be called on first app launch or manually
class TestDataInitializer {
  static const _uuid = Uuid();

  static Future<void> initializeTestData() async {
    final repository = ExcelRepository();

    // Check if data already exists
    final existingUsers = await repository.getAllLoginDetails();
    print('Test data check: Found ${existingUsers.length} existing users');
    if (existingUsers.isNotEmpty) {
      print('Test data already exists, skipping creation');
      return; // Data already exists
    }

    print('Creating test data...');
    // Create test users
    final now = DateTime.now();
    final admin = await repository.createLoginDetails(
      LoginDetails(
        loginDetailsId: _uuid.v4(),
        username: 'admin',
        password: 'admin123',
        displayName: 'Administrator',
        isActive: true,
        createdOn: now,
        modifiedOn: now,
      ),
    );
    print('Created admin user: ${admin.username}');

    final user1 = await repository.createLoginDetails(
      LoginDetails(
        loginDetailsId: _uuid.v4(),
        username: 'user1',
        password: 'user123',
        displayName: 'User One',
        isActive: true,
        createdOn: now,
        modifiedOn: now,
      ),
    );
    print('Created user1: ${user1.username}');

    final user2 = await repository.createLoginDetails(
      LoginDetails(
        loginDetailsId: _uuid.v4(),
        username: 'user2',
        password: 'user123',
        displayName: 'User Two',
        isActive: true,
        createdOn: now,
        modifiedOn: now,
      ),
    );
    print('Created user2: ${user2.username}');
    print('Test data creation complete');

    // Create test orders
    await repository.createOrder(
      Order(
        orderId: _uuid.v4(),
        orderNumber: 'ORD-001',
        machine: 'Machine A',
        status: OrderStatus.pending,
        createdOn: now,
        modifiedOn: now,
      ),
    );

    await repository.createOrder(
      Order(
        orderId: _uuid.v4(),
        orderNumber: 'ORD-002',
        machine: 'Machine B',
        status: OrderStatus.pending,
        createdOn: now,
        modifiedOn: now,
      ),
    );

    await repository.createOrder(
      Order(
        orderId: _uuid.v4(),
        orderNumber: 'ORD-003',
        machine: 'Machine C',
        status: OrderStatus.inProgress,
        createdOn: now,
        modifiedOn: now,
      ),
    );

    await repository.createOrder(
      Order(
        orderId: _uuid.v4(),
        orderNumber: 'ORD-004',
        machine: 'Machine A',
        status: OrderStatus.pending,
        createdOn: now,
        modifiedOn: now,
      ),
    );
  }
}

