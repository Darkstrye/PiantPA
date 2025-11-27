import 'package:flutter/material.dart';
import '../models/order.dart';
import '../models/hour_registration_order.dart';
import 'timer_display.dart';

class OrderDetailPanel extends StatelessWidget {
  final Order? order;
  final bool isTimerRunning;
  final bool isTimerPaused;
  final bool hasActiveTimer;
  final bool isTimerForSelectedOrder;
  final Duration? elapsedTime;
  final Duration? downtime;
  final List<HourRegistrationOrder> activeOrderLinks;
  final Set<String> pendingOrderIds;
  final Map<String, Order>? ordersById;
  final bool selectionLocked;
  final bool isSelectedForSession;
  final VoidCallback? onStartTimer;
  final VoidCallback? onPauseTimer;
  final VoidCallback? onFinishOrder;
  final ValueChanged<bool>? onToggleSessionSelection;
  final ValueChanged<String>? onFinishIndividualOrder;

  const OrderDetailPanel({
    super.key,
    this.order,
    this.isTimerRunning = false,
    this.isTimerPaused = false,
    this.hasActiveTimer = false,
    this.isTimerForSelectedOrder = false,
    this.elapsedTime,
    this.downtime,
    this.activeOrderLinks = const [],
    this.pendingOrderIds = const {},
    this.ordersById,
    this.selectionLocked = false,
    this.isSelectedForSession = false,
    this.onStartTimer,
    this.onPauseTimer,
    this.onFinishOrder,
    this.onToggleSessionSelection,
    this.onFinishIndividualOrder,
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
        case OrderStatus.inProgress:
          return Colors.blue;
        case OrderStatus.completed:
          return Colors.green;
      }
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
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
          if (order!.vocaInUur != null) ...[
            const SizedBox(height: 16),
            _buildDetailRow(
              'Voca in uur',
              _formatDutchDouble(order!.vocaInUur!),
            ),
          ],
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
            if (!hasActiveTimer) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                value: isSelectedForSession,
                onChanged: selectionLocked || onToggleSessionSelection == null
                    ? null
                    : (value) =>
                        onToggleSessionSelection?.call(value ?? false),
                title: const Text('Opnemen in volgende sessie'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              if (pendingOrderIds.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: pendingOrderIds.map((id) {
                    final label = ordersById?[id]?.orderNumber ?? id;
                    return Chip(
                      label: Text(label),
                      avatar: const Icon(Icons.assignment_outlined, size: 16),
                    );
                  }).toList(),
                ),
              ],
            ],
            // Show timer if it's running or paused (for this order or any order)
            if (hasActiveTimer && elapsedTime != null) ...[
              TimerDisplay(duration: elapsedTime!),
              if (isTimerForSelectedOrder && downtime != null) ...[
                const SizedBox(height: 12),
                TimerDisplay(
                  duration: downtime!,
                  title: 'Downtime',
                  accentColor: Colors.orange.shade700,
                ),
              ],
            ] else if (!hasActiveTimer && elapsedTime != null) ...[
              // Show elapsed time even if no active timer (for orders with previous registrations)
              const Text(
                'Total Time:',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              TimerDisplay(duration: elapsedTime!),
              if (downtime != null && downtime! > Duration.zero) ...[
                const SizedBox(height: 16),
                const Text(
                  'Total Downtime:',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TimerDisplay(
                  duration: downtime!,
                  title: 'Downtime',
                  accentColor: Colors.orange.shade700,
                ),
              ],
            ],
            if (hasActiveTimer && activeOrderLinks.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Actieve orders in deze sessie:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Column(
                  children: activeOrderLinks.map((link) {
                    final label =
                        ordersById?[link.orderId]?.orderNumber ?? link.orderId;
                    final isActiveLink = link.isActive;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: Icon(
                          isActiveLink
                              ? Icons.play_circle_fill
                              : Icons.check_circle,
                          color: isActiveLink ? Colors.green : Colors.grey,
                        ),
                        title: Text(label),
                        subtitle: isActiveLink
                            ? null
                            : const Text('Afgerond in deze sessie'),
                        trailing: isActiveLink &&
                                onFinishIndividualOrder != null &&
                                hasActiveTimer
                            ? ElevatedButton(
                                onPressed: () =>
                                    onFinishIndividualOrder!(link.orderId),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade600,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Finish'),
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
              if (hasActiveTimer && !isTimerForSelectedOrder) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                      onPressed: onStartTimer,
                      icon: const Icon(Icons.playlist_add, size: 20),
                      label: const Text('Add to Active Session'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                      ),
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
              // No active timer - show Start Timer button (if order hasn't been completed and timer is not for this order)
              if (!hasActiveTimer && !isTimerForSelectedOrder) ...[
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
            // Completed order - show total elapsed time if available
            if (elapsedTime != null) ...[
              const Text(
                'Total Time:',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              TimerDisplay(duration: elapsedTime!),
              if (downtime != null) ...[
                const SizedBox(height: 16),
                const Text(
                  'Total Downtime:',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TimerDisplay(
                  duration: downtime!,
                  title: 'Downtime',
                  accentColor: Colors.orange.shade700,
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
        ],
      ),
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

  String _formatDutchDouble(double value) {
    final text = value.toStringAsFixed(2).replaceAll('.', ',');
    return text;
  }
}

