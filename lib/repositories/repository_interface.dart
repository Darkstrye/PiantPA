import '../models/login_details.dart';
import '../models/order.dart';
import '../models/hour_registration.dart';
import '../models/hour_registration_order.dart';

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
  Future<Map<String, Order>> getOrdersByIds(List<String> ids);
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
  Future<List<HourRegistration>> getHourRegistrationsByIds(List<String> ids);
  Future<HourRegistration> createHourRegistration(HourRegistration registration);
  Future<HourRegistration> updateHourRegistration(HourRegistration registration);
  Future<bool> deleteHourRegistration(String id);
  Future<({HourRegistration registration, List<HourRegistrationOrder> orderLinks})>
      createHourRegistrationWithOrders(
    HourRegistration registration,
    List<String> orderIds,
  );

  // HourRegistrationOrder operations
  Future<List<HourRegistrationOrder>> getAllHourRegistrationOrders();
  Future<List<HourRegistrationOrder>> getHourRegistrationOrdersByRegistrationId(
      String hourRegistrationId);
  Future<List<HourRegistrationOrder>> getHourRegistrationOrdersByOrderId(
      String orderId);
  Future<Map<String, List<HourRegistrationOrder>>> getHourRegistrationOrdersByOrderIds(
      List<String> orderIds);
  Future<HourRegistrationOrder?> getActiveHourRegistrationOrderForUser(
      String orderId, String userId);
  Future<HourRegistrationOrder> createHourRegistrationOrder(
      HourRegistrationOrder registrationOrder);
  Future<HourRegistrationOrder> updateHourRegistrationOrder(
      HourRegistrationOrder registrationOrder);
  Future<bool> deleteHourRegistrationOrder(String id);
  Future<void> deleteHourRegistrationOrdersByRegistrationId(
      String hourRegistrationId);
}

