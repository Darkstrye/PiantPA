import 'package:flutter/material.dart';
import '../models/order.dart';
import 'timer_display.dart';

class OrderDetailPanel extends StatelessWidget {
  final Order? order;
  final bool isTimerRunning;
  final Duration? elapsedTime;
  final VoidCallback? onStartTimer;
  final VoidCallback? onStopTimer;

  const OrderDetailPanel({
    super.key,
    this.order,
    this.isTimerRunning = false,
    this.elapsedTime,
    this.onStartTimer,
    this.onStopTimer,
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
            if (isTimerRunning && elapsedTime != null) ...[
              TimerDisplay(duration: elapsedTime!),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onStopTimer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Stop Timer',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onStartTimer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Start Timer',
                    style: TextStyle(fontSize: 16),
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

