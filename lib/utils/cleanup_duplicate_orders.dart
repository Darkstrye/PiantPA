import '../repositories/excel_repository.dart';
import '../models/order.dart';

/// Utility to clean up duplicate orders (same orderNumber)
/// Keeps the most recent order and deletes older duplicates
class CleanupDuplicateOrders {
  static Future<void> cleanup() async {
    final repository = ExcelRepository();
    
    try {
      print('Cleaning up duplicate orders...');
      
      // Get all orders
      final allOrders = await repository.getAllOrders();
      
      // Group by orderNumber
      final ordersByNumber = <String, List<Order>>{};
      for (var order in allOrders) {
        if (!ordersByNumber.containsKey(order.orderNumber)) {
          ordersByNumber[order.orderNumber] = [];
        }
        ordersByNumber[order.orderNumber]!.add(order);
      }
      
      // Find duplicates
      final duplicates = <String, List<Order>>{};
      for (var entry in ordersByNumber.entries) {
        if (entry.value.length > 1) {
          duplicates[entry.key] = entry.value;
        }
      }
      
      if (duplicates.isEmpty) {
        print('No duplicate orders found.');
        return;
      }
      
      print('Found ${duplicates.length} order numbers with duplicates:');
      
      int deletedCount = 0;
      final ordersToKeep = <Order>[];
      
      // For each duplicate order number, keep the most recent one
      for (var entry in duplicates.entries) {
        final orders = entry.value;
        // Sort by modifiedOn descending (most recent first)
        orders.sort((a, b) => b.modifiedOn.compareTo(a.modifiedOn));
        
        // Keep the first (most recent)
        final orderToKeep = orders.first;
        ordersToKeep.add(orderToKeep);
        
        print('  Order number "${entry.key}":');
        print('    Keeping: ${orderToKeep.orderId} (modified: ${orderToKeep.modifiedOn})');
        
        // Delete the rest
        for (int i = 1; i < orders.length; i++) {
          final orderToDelete = orders[i];
          print('    Deleting: ${orderToDelete.orderId} (modified: ${orderToDelete.modifiedOn})');
          await repository.deleteOrder(orderToDelete.orderId);
          deletedCount++;
        }
      }
      
      print('');
      print('Cleanup complete!');
      print('  - ${duplicates.length} order numbers had duplicates');
      print('  - $deletedCount duplicate orders deleted');
      print('  - ${ordersToKeep.length} orders kept (most recent of each)');
    } catch (e) {
      print('Error cleaning up duplicates: $e');
      rethrow;
    }
  }
}

