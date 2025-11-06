import '../models/login_details.dart';
import '../models/order.dart';
import '../models/hour_registration.dart';

abstract class RepositoryInterface {
  // LoginDetails operations
  Future<List<LoginDetails>> getAllLoginDetails();
  Future<LoginDetails?> getLoginDetailsById(String id);
  Future<LoginDetails?> getLoginDetailsByUsername(String username);
  Future<LoginDetails> createLoginDetails(LoginDetails loginDetails);
  Future<LoginDetails> updateLoginDetails(LoginDetails loginDetails);
  Future<bool> deleteLoginDetails(String id);

  // Order operations
  Future<List<Order>> getAllOrders();
  Future<Order?> getOrderById(String id);
  Future<Order?> getOrderByOrderNumber(String orderNumber);
  Future<Order> createOrder(Order order);
  Future<Order> updateOrder(Order order);
  Future<bool> deleteOrder(String id);

  // HourRegistration operations
  Future<List<HourRegistration>> getAllHourRegistrations();
  Future<HourRegistration?> getHourRegistrationById(String id);
  Future<List<HourRegistration>> getHourRegistrationsByOrderId(String orderId);
  Future<List<HourRegistration>> getHourRegistrationsByUserId(String userId);
  Future<HourRegistration?> getActiveHourRegistrationByUserId(String userId);
  Future<HourRegistration> createHourRegistration(HourRegistration registration);
  Future<HourRegistration> updateHourRegistration(HourRegistration registration);
  Future<bool> deleteHourRegistration(String id);
}

