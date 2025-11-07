import 'dart:io';
import '../repositories/excel_repository.dart';
import '../models/order.dart';
import 'cleanup_duplicate_orders.dart';

/// Utility to reset all completed orders and their time registrations
class ResetCompletedOrders {
  static Future<void> resetAll() async {
    final repository = ExcelRepository();
    
    try {
      print('Resetting all completed orders and their time registrations...');
      
      // First, clean up any duplicate orders
      print('');
      print('Step 1: Cleaning up duplicate orders...');
      try {
        await CleanupDuplicateOrders.cleanup();
      } catch (e) {
        print('Warning: Error during cleanup: $e');
        print('Continuing with reset...');
      }
      
      print('');
      print('Step 2: Resetting completed orders...');
      
      // Get all orders (after cleanup)
      final allOrders = await repository.getAllOrders();
      
      // Find completed orders
      final completedOrders = allOrders.where((order) => order.status == OrderStatus.completed).toList();
      
      print('Found ${completedOrders.length} completed orders to reset');
      
      if (completedOrders.isEmpty) {
        print('No completed orders to reset.');
        return;
      }
      
      int resetCount = 0;
      int deletedRegistrations = 0;
      
      // Reset each completed order
      for (var order in completedOrders) {
        // Reset order status to inProgress
        final resetOrder = order.copyWith(
          status: OrderStatus.inProgress,
          modifiedOn: DateTime.now(),
        );
        await repository.updateOrder(resetOrder);
        print('  Reset order: ${order.orderNumber}');
        resetCount++;
        
        // Delete all hour registrations for this order
        final registrations = await repository.getHourRegistrationsByOrderId(order.orderId);
        int deletedCount = 0;
        for (var reg in registrations) {
          try {
            final deleted = await repository.deleteHourRegistration(reg.hourRegistrationId);
            if (deleted) {
              deletedCount++;
              deletedRegistrations++;
            } else {
              print('    Warning: Failed to delete hour registration: ${reg.hourRegistrationId}');
            }
          } catch (e) {
            print('    Error deleting hour registration ${reg.hourRegistrationId}: $e');
            // Continue with other registrations even if one fails
          }
        }
        if (registrations.isNotEmpty) {
          print('    Deleted $deletedCount of ${registrations.length} hour registrations');
        }
      }
      
      print('');
      print('Reset complete!');
      print('  - $resetCount orders reset to In Progress');
      print('  - $deletedRegistrations hour registrations deleted');
    } on FileSystemException catch (e) {
      // Handle file access errors
      if (e.osError?.errorCode == 32 || e.message.contains('being used by another process')) {
        throw Exception(
          'Cannot access Excel files. Please close any Excel files that are open in the data folder:\n'
          'C:\\Dart App\\PiantPA\\data\\\n\n'
          'Close Excel and try again.'
        );
      }
      rethrow;
    } catch (e) {
      print('Error resetting orders: $e');
      // Check if it's a file lock error
      final errorString = e.toString();
      if (errorString.contains('Cannot open file') || 
          errorString.contains('being used by another process') ||
          errorString.contains('errno = 32')) {
        throw Exception(
          'Cannot access Excel files. Please close any Excel files that are open in the data folder:\n'
          'C:\\Dart App\\PiantPA\\data\\\n\n'
          'Close Excel and try again.'
        );
      }
      rethrow;
    }
  }
}
