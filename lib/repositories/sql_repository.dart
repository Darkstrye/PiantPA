import 'repository_interface.dart';
import '../models/login_details.dart';
import '../models/order.dart';
import '../models/hour_registration.dart';
import '../models/hour_registration_order.dart';

/// SQL Repository implementation for production
/// This is a placeholder that will be implemented when switching to SQL backend
class SqlRepository implements RepositoryInterface {
  // TODO: Implement SQL backend connection and operations
  
  @override
  Future<List<LoginDetails>> getAllLoginDetails() async {
    throw UnimplementedError('SQL repository not yet implemented');
  }

  @override
  Future<LoginDetails?> getLoginDetailsById(String id) async {
    throw UnimplementedError('SQL repository not yet implemented');
  }

  @override
  Future<LoginDetails?> getLoginDetailsByUsername(String username) async {
    throw UnimplementedError('SQL repository not yet implemented');
  }

  @override
  Future<LoginDetails> createLoginDetails(LoginDetails loginDetails) async {
    throw UnimplementedError('SQL repository not yet implemented');
  }

  @override
  Future<LoginDetails> updateLoginDetails(LoginDetails loginDetails) async {
    throw UnimplementedError('SQL repository not yet implemented');
  }

  @override
  Future<bool> deleteLoginDetails(String id) async {
    throw UnimplementedError('SQL repository not yet implemented');
  }

  @override
  Future<List<Order>> getAllOrders() async {
    throw UnimplementedError('SQL repository not yet implemented');
  }

  @override
  Future<Order?> getOrderById(String id) async {
    throw UnimplementedError('SQL repository not yet implemented');
  }

  @override
  Future<Order?> getOrderByOrderNumber(String orderNumber) async {
    throw UnimplementedError('SQL repository not yet implemented');
  }

  @override
  Future<Order> createOrder(Order order) async {
    throw UnimplementedError('SQL repository not yet implemented');
  }

  @override
  Future<Order> updateOrder(Order order) async {
    throw UnimplementedError('SQL repository not yet implemented');
  }

  @override
  Future<bool> deleteOrder(String id) async {
    throw UnimplementedError('SQL repository not yet implemented');
  }

  @override
  Future<List<HourRegistration>> getAllHourRegistrations() async {
    throw UnimplementedError('SQL repository not yet implemented');
  }

  @override
  Future<HourRegistration?> getHourRegistrationById(String id) async {
    throw UnimplementedError('SQL repository not yet implemented');
  }

  @override
  Future<List<HourRegistration>> getHourRegistrationsByOrderId(String orderId) async {
    throw UnimplementedError('SQL repository not yet implemented');
  }

  @override
  Future<List<HourRegistration>> getHourRegistrationsByUserId(String userId) async {
    throw UnimplementedError('SQL repository not yet implemented');
  }

  @override
  Future<HourRegistration?> getActiveHourRegistrationByUserId(String userId) async {
    throw UnimplementedError('SQL repository not yet implemented');
  }

  @override
  Future<HourRegistration> createHourRegistration(HourRegistration registration) async {
    throw UnimplementedError('SQL repository not yet implemented');
  }

  @override
  Future<HourRegistration> updateHourRegistration(HourRegistration registration) async {
    throw UnimplementedError('SQL repository not yet implemented');
  }

  @override
  Future<bool> deleteHourRegistration(String id) async {
    throw UnimplementedError('SQL repository not yet implemented');
  }

  @override
  Future<({HourRegistration registration, List<HourRegistrationOrder> orderLinks})>
      createHourRegistrationWithOrders(
    HourRegistration registration,
    List<String> orderIds,
  ) async {
    throw UnimplementedError('SQL repository not yet implemented');
  }
}

