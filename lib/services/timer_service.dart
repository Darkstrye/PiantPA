import 'dart:async';
import '../models/hour_registration.dart';
import '../models/order.dart';
import '../repositories/repository_interface.dart';

class TimerService {
  final RepositoryInterface repository;
  Timer? _timer;
  HourRegistration? _activeRegistration;
  DateTime? _startTime;
  double _accumulatedElapsedTime = 0.0; // Total elapsed time including pauses
  DateTime? _pauseStartTime; // When the timer was paused
  final StreamController<Duration> _elapsedTimeController = StreamController<Duration>.broadcast();
  Duration? _lastCalculatedDuration; // Store last calculated duration to avoid recalculation issues

  TimerService(this.repository);

  Stream<Duration> get elapsedTimeStream => _elapsedTimeController.stream;

  bool get isTimerRunning => _activeRegistration != null && _activeRegistration!.isActive && !_activeRegistration!.isPaused;

  bool get isTimerPaused => _activeRegistration != null && _activeRegistration!.isActive && _activeRegistration!.isPaused;

  HourRegistration? get activeRegistration => _activeRegistration;

  Future<bool> startTimer(String orderId, String userId) async {
    try {
      // Check if there's already a completed hour registration for this order
      // BUT also check the order status - if order is inProgress, allow starting
      final allRegistrations = await repository.getHourRegistrationsByOrderId(orderId);
      final order = await repository.getOrderById(orderId);
      
      // Only block if order is completed AND there's a completed registration
      // If order is inProgress (even after reset), allow starting
      if (order != null && order.status == OrderStatus.completed) {
        final hasCompletedRegistration = allRegistrations.any((reg) => !reg.isActive && reg.elapsedTime != null && reg.elapsedTime! > 0);
        if (hasCompletedRegistration) {
          return false; // Order is completed and has completed timer, can't start
        }
      }
      // If order is inProgress, allow starting even if there are old registrations
      // (they should have been deleted by reset, but if not, we'll create a new one)

      // Check if there's already an active timer for this user
      final existingActive = await repository.getActiveHourRegistrationByUserId(userId);
      
      // If there's an active timer for a different order, don't allow starting a new one
      if (existingActive != null && !existingActive.isPaused && existingActive.orderId != orderId) {
        return false; // User already has an active timer for a different order
      }

      final now = DateTime.now();
      
      // If resuming from pause for the same order, use existing registration
      if (existingActive != null && existingActive.isPaused && existingActive.orderId == orderId) {
        _activeRegistration = existingActive;
        _accumulatedElapsedTime = existingActive.pausedElapsedTime ?? 0.0;
        // Don't set _startTime here - we'll set it right before sending initial value
      } else if (existingActive == null || existingActive.orderId != orderId) {
        // Check if there's already an active registration for this order (shouldn't happen, but check anyway)
        final activeForThisOrder = allRegistrations.where((reg) => reg.isActive).toList();
        if (activeForThisOrder.isNotEmpty) {
          // There's already an active timer for this order
          _activeRegistration = activeForThisOrder.first;
          if (_activeRegistration!.isPaused) {
            _accumulatedElapsedTime = _activeRegistration!.pausedElapsedTime ?? 0.0;
            // Don't set _startTime here - we'll set it right before sending initial value
          } else {
            // Timer already running
            return false;
          }
        } else {
          // Create new hour registration
          _activeRegistration = HourRegistration(
            hourRegistrationId: '',
            orderId: orderId,
            userId: userId,
            startTime: now,
            isActive: true,
            isPaused: false,
            createdOn: now,
            modifiedOn: now,
          );
          _activeRegistration = await repository.createHourRegistration(_activeRegistration!);
          _accumulatedElapsedTime = 0.0;
          // Don't set _startTime here - we'll set it right before sending initial value
        }
      } else {
        // Timer already running for this order
        return false;
      }

      // Update to unpaused state (keep pausedElapsedTime as accumulated base)
      _activeRegistration = _activeRegistration!.copyWith(
        isPaused: false,
        modifiedOn: now,
      );
      await repository.updateHourRegistration(_activeRegistration!);

      // Get base time before starting timer
      final baseTime = _activeRegistration!.pausedElapsedTime ?? 0.0;
      
      // CRITICAL: Set _startTime to NOW, synchronized exactly with when we send initial value
      // This ensures the first timer update calculates correctly
      final resumeTime = DateTime.now();
      _startTime = resumeTime;
      
      // Send initial elapsed time immediately (exactly baseTime, no session time yet)
      // This must happen immediately after setting _startTime to prevent any jump
      final initialDuration = Duration(seconds: (baseTime * 3600).toInt());
      _elapsedTimeController.add(initialDuration);

      // Start periodic updates - use a small delay for first update to ensure smooth transition
      // First update after 100ms to catch any timing issues, then every 1 second
      _timer = Timer(const Duration(milliseconds: 100), () {
        // First update after 100ms to ensure smooth transition
        if (_activeRegistration != null && _startTime != null && !_activeRegistration!.isPaused) {
          final baseTime = _activeRegistration!.pausedElapsedTime ?? 0.0;
          final currentSessionTime = DateTime.now().difference(_startTime!);
          final totalElapsed = baseTime + currentSessionTime.inSeconds / 3600.0;
          final duration = Duration(seconds: (totalElapsed * 3600).toInt());
          _lastCalculatedDuration = duration; // Store for use in finishTimer
          _elapsedTimeController.add(duration);
        }
        
        // Then continue with regular 1-second updates
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (_activeRegistration != null && _startTime != null && !_activeRegistration!.isPaused) {
            // Calculate from the synchronized _startTime
            final baseTime = _activeRegistration!.pausedElapsedTime ?? 0.0;
            final currentSessionTime = DateTime.now().difference(_startTime!);
            final totalElapsed = baseTime + currentSessionTime.inSeconds / 3600.0;
            final duration = Duration(seconds: (totalElapsed * 3600).toInt());
            _lastCalculatedDuration = duration; // Store for use in finishTimer
            _elapsedTimeController.add(duration);
          }
        });
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> pauseTimer() async {
    try {
      if (_activeRegistration == null || _activeRegistration!.isPaused) {
        return false;
      }

      _timer?.cancel();
      _timer = null;

      // Calculate and store accumulated elapsed time
      // Base time from previous pauses (if any)
      final baseTime = _activeRegistration!.pausedElapsedTime ?? 0.0;
      double totalElapsed = baseTime;
      
      if (_startTime != null) {
        final currentSessionTime = DateTime.now().difference(_startTime!);
        final sessionHours = currentSessionTime.inSeconds / 3600.0;
        totalElapsed += sessionHours;
        print('PauseTimer: baseTime: ${baseTime.toStringAsFixed(4)}h, sessionTime: ${sessionHours.toStringAsFixed(4)}h, total: ${totalElapsed.toStringAsFixed(4)}h');
      } else {
        print('PauseTimer: _startTime is null, using only baseTime: ${totalElapsed.toStringAsFixed(4)}h');
      }
      
      _accumulatedElapsedTime = totalElapsed;

      final now = DateTime.now();
      _activeRegistration = _activeRegistration!.copyWith(
        isPaused: true,
        pausedElapsedTime: _accumulatedElapsedTime,
        modifiedOn: now,
      );

      await repository.updateHourRegistration(_activeRegistration!);
      
      // Send final elapsed time
      final duration = Duration(seconds: (_accumulatedElapsedTime * 3600).toInt());
      _lastCalculatedDuration = duration; // Store for consistency
      _elapsedTimeController.add(duration);

      _pauseStartTime = now;

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> finishTimer() async {
    try {
      if (_activeRegistration == null) {
        return false;
      }

      _timer?.cancel();
      _timer = null;

      final endTime = DateTime.now();
      
      // Calculate final elapsed time - this correctly accounts for pause time
      double finalElapsed;
      
      if (_activeRegistration!.isPaused) {
        // Timer is paused, use stored paused time (already accumulated correctly)
        finalElapsed = _activeRegistration!.pausedElapsedTime ?? 0.0;
        print('FinishTimer: Timer was paused, using pausedElapsedTime: ${finalElapsed.toStringAsFixed(4)} hours');
      } else {
        // Timer is running - calculate fresh at finish time
        // Use pausedElapsedTime as base + time since last resume
        final baseTime = _activeRegistration!.pausedElapsedTime ?? 0.0;
        if (_startTime != null) {
          // Calculate at the exact moment finishTimer is called
          final currentSessionTime = endTime.difference(_startTime!);
          final sessionHours = currentSessionTime.inSeconds / 3600.0;
          finalElapsed = baseTime + sessionHours;
          print('FinishTimer: Timer running, baseTime: ${baseTime.toStringAsFixed(4)}h, sessionTime: ${sessionHours.toStringAsFixed(4)}h (${currentSessionTime.inSeconds}s), total: ${finalElapsed.toStringAsFixed(4)}h');
        } else {
          // Fallback: if _startTime is null, use pausedElapsedTime
          if (_activeRegistration!.pausedElapsedTime != null && _activeRegistration!.pausedElapsedTime! > 0) {
            finalElapsed = _activeRegistration!.pausedElapsedTime!;
            print('FinishTimer: _startTime is null but pausedElapsedTime exists: ${finalElapsed.toStringAsFixed(4)}h');
          } else {
            // No pause time recorded, calculate from original start
            finalElapsed = endTime.difference(_activeRegistration!.startTime).inSeconds / 3600.0;
            print('FinishTimer: No pause time, calculating from startTime: ${finalElapsed.toStringAsFixed(4)}h');
          }
        }
      }
      
      // Validate: only check if elapsed time is reasonable (not negative)
      // Don't compare with directCalculation because that includes pause time
      if (finalElapsed < 0) {
        print('Warning: Elapsed time is negative, setting to 0.');
        finalElapsed = 0.0;
      }
      
      print('FinishTimer: Final elapsed time: ${finalElapsed.toStringAsFixed(4)} hours (${(finalElapsed * 3600).toStringAsFixed(0)} seconds)');

      _activeRegistration = _activeRegistration!.copyWith(
        endTime: endTime,
        elapsedTime: finalElapsed,
        isActive: false,
        isPaused: false,
        modifiedOn: endTime,
      );

      await repository.updateHourRegistration(_activeRegistration!);
      
      final duration = Duration(seconds: (finalElapsed * 3600).toInt());
      _elapsedTimeController.add(duration);

      _activeRegistration = null;
      _startTime = null;
      _accumulatedElapsedTime = 0.0;
      _pauseStartTime = null;
      _lastCalculatedDuration = null; // Clear stored duration

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> loadActiveTimer(String userId) async {
    try {
      final active = await repository.getActiveHourRegistrationByUserId(userId);
      if (active != null && active.isActive) {
        _activeRegistration = active;
        
        if (active.isPaused) {
          // Timer is paused, use accumulated time
          _accumulatedElapsedTime = active.pausedElapsedTime ?? 0.0;
          _startTime = null;
          final duration = Duration(seconds: (_accumulatedElapsedTime * 3600).toInt());
          _elapsedTimeController.add(duration);
        } else {
          // Timer is running - calculate from original start time
          // If there's paused elapsed time, use it as base, otherwise calculate from start
          if (active.pausedElapsedTime != null && active.pausedElapsedTime! > 0) {
            // Timer was paused and resumed - use paused time as base
            _accumulatedElapsedTime = active.pausedElapsedTime!;
            _startTime = DateTime.now(); // Reset for current session
          } else {
            // Timer was never paused - calculate from original start
            _accumulatedElapsedTime = DateTime.now().difference(active.startTime).inSeconds / 3600.0;
            _startTime = active.startTime;
          }
          
          // Start timer updates
          _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (_activeRegistration != null && !_activeRegistration!.isPaused) {
              Duration duration;
              if (_startTime != null && _activeRegistration!.pausedElapsedTime != null && _activeRegistration!.pausedElapsedTime! > 0) {
                // Was paused before - use accumulated + current session
                final currentSessionTime = DateTime.now().difference(_startTime!);
                final totalElapsed = _accumulatedElapsedTime + currentSessionTime.inSeconds / 3600.0;
                duration = Duration(seconds: (totalElapsed * 3600).toInt());
              } else {
                // Never paused - calculate from original start
                final totalElapsed = DateTime.now().difference(_activeRegistration!.startTime).inSeconds / 3600.0;
                duration = Duration(seconds: (totalElapsed * 3600).toInt());
              }
              _elapsedTimeController.add(duration);
            }
          });
        }
      }
    } catch (e) {
      // No active timer
    }
  }

  void dispose() {
    _timer?.cancel();
    _elapsedTimeController.close();
  }

  String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Calculate total elapsed time for an order from all hour registrations
  Future<Duration> getTotalElapsedTimeForOrder(String orderId) async {
    try {
      final registrations = await repository.getHourRegistrationsByOrderId(orderId);
      double totalHours = 0.0;

      for (var reg in registrations) {
        print('getTotalElapsedTimeForOrder: reg=${reg.hourRegistrationId}, status active=${reg.isActive}, paused=${reg.isPaused}, elapsed=${reg.elapsedTime}, pausedElapsed=${reg.pausedElapsedTime}');
        if (reg.isActive && !reg.isPaused) {
          // Active running timer - calculate current elapsed time
          final baseTime = reg.pausedElapsedTime ?? 0.0;
          final currentRunning = DateTime.now().difference(reg.startTime).inSeconds / 3600.0;
          totalHours += baseTime + currentRunning;
          print('  -> active running: base=$baseTime, current=$currentRunning, subtotal=${totalHours}');
        } else if (reg.isActive && reg.isPaused) {
          // Active paused timer - use paused elapsed time
          totalHours += reg.pausedElapsedTime ?? 0.0;
          print('  -> active paused: add=${reg.pausedElapsedTime ?? 0.0}, subtotal=$totalHours');
        } else if (!reg.isActive) {
          // Completed timer - use stored elapsedTime which correctly accounts for pause time
          // This was calculated correctly in finishTimer() using pausedElapsedTime
          if (reg.elapsedTime != null && reg.elapsedTime! >= 0) {
            totalHours += reg.elapsedTime!;
            print('  -> completed (elapsedTime): add=${reg.elapsedTime}, subtotal=$totalHours');
          } else if (reg.endTime != null) {
            // Fallback: only if elapsedTime is missing, calculate from start/end
            // Note: This will include pause time, but it's better than nothing
            final elapsed = reg.endTime!.difference(reg.startTime).inSeconds / 3600.0;
            totalHours += elapsed;
            print('  -> completed (calc fallback): add=$elapsed, subtotal=$totalHours');
          }
        }
      }

      print('getTotalElapsedTimeForOrder: totalHours=$totalHours -> ${Duration(seconds: (totalHours * 3600).toInt())}');
      return Duration(seconds: (totalHours * 3600).toInt());
    } catch (e) {
      return Duration.zero;
    }
  }
}

