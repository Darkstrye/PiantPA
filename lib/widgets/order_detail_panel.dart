import 'package:flutter/material.dart';
import '../models/order.dart';
import 'timer_display.dart';

class OrderDetailPanel extends StatelessWidget {
  final Order? order;
  final bool isTimerRunning;
  final bool isTimerPaused;
  final bool hasActiveTimer;
  final bool isTimerForSelectedOrder;
  final Duration? elapsedTime;
  final VoidCallback? onStartTimer;
  final VoidCallback? onPauseTimer;
  final VoidCallback? onFinishOrder;

  const OrderDetailPanel({
    super.key,
    this.order,
    this.isTimerRunning = false,
    this.isTimerPaused = false,
    this.hasActiveTimer = false,
    this.isTimerForSelectedOrder = false,
    this.elapsedTime,
    this.onStartTimer,
    this.onPauseTimer,
    this.onFinishOrder,
  });

  @override
  Widget build(BuildContext context) {
    if (order == null) {
      return const Center(
        child: Text(
          'Select an order to view details',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    Color getStatusColor() {
      switch (order!.status) {
        case OrderStatus.pending:
          return Colors.orange;
        case OrderStatus.inProgress:
          return Colors.blue;
        case OrderStatus.completed:
          return Colors.green;
      }
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order Details',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 24),
          _buildDetailRow('Order Number', order!.orderNumber),
          const SizedBox(height: 16),
          _buildDetailRow('Machine', order!.machine.isNotEmpty ? order!.machine : 'N/A'),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Status: ',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: getStatusColor().withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  order!.status.displayName,
                  style: TextStyle(
                    color: getStatusColor(),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          if (order!.status != OrderStatus.completed) ...[
            // Show timer if it's running or paused (for this order or any order)
            if (hasActiveTimer && elapsedTime != null) ...[
              TimerDisplay(duration: elapsedTime!),
              if (!isTimerForSelectedOrder) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Timer is running for another order',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // Pause/Resume button (only if timer is for this order)
              if (isTimerForSelectedOrder) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isTimerPaused ? onStartTimer : onPauseTimer,
                    icon: Icon(
                      isTimerPaused ? Icons.play_arrow : Icons.pause,
                      size: 24,
                    ),
                    label: Text(
                      isTimerPaused ? 'Resume Timer' : 'Pause Timer',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isTimerPaused ? Colors.green.shade700 : Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Finish Order button (only if timer is for this order)
              if (isTimerForSelectedOrder) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onFinishOrder,
                    icon: const Icon(Icons.check_circle, size: 24),
                    label: const Text(
                      'Finish Order',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ] else ...[
              // No active timer - show Start Timer button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onStartTimer,
                  icon: const Icon(Icons.play_arrow, size: 24),
                  label: const Text(
                    'Start Timer',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ] else ...[
            const Center(
              child: Text(
                'This order is completed',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

