import 'dart:async';
import '../models/hour_registration.dart';
import '../repositories/repository_interface.dart';

class TimerService {
  final RepositoryInterface repository;
  Timer? _timer;
  HourRegistration? _activeRegistration;
  DateTime? _startTime;
  double _accumulatedElapsedTime = 0.0; // Total elapsed time including pauses
  DateTime? _pauseStartTime; // When the timer was paused
  final StreamController<Duration> _elapsedTimeController = StreamController<Duration>.broadcast();

  TimerService(this.repository);

  Stream<Duration> get elapsedTimeStream => _elapsedTimeController.stream;

  bool get isTimerRunning => _activeRegistration != null && _activeRegistration!.isActive && !_activeRegistration!.isPaused;

  bool get isTimerPaused => _activeRegistration != null && _activeRegistration!.isActive && _activeRegistration!.isPaused;

  HourRegistration? get activeRegistration => _activeRegistration;

  Future<bool> startTimer(String orderId, String userId) async {
    try {
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
        _startTime = now; // Reset start time for current session
      } else if (existingActive == null || existingActive.orderId != orderId) {
        // Create new hour registration (no existing timer or different order)
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
        _startTime = now;
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

      // Start periodic updates
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_activeRegistration != null && _startTime != null && !_activeRegistration!.isPaused) {
          Duration duration;
          // If we have paused elapsed time, it's the base accumulated time
          final baseTime = _activeRegistration!.pausedElapsedTime ?? 0.0;
          final currentSessionTime = DateTime.now().difference(_startTime!);
          final totalElapsed = baseTime + currentSessionTime.inSeconds / 3600.0;
          duration = Duration(seconds: (totalElapsed * 3600).toInt());
          _elapsedTimeController.add(duration);
        }
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
        totalElapsed += currentSessionTime.inSeconds / 3600.0;
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
      
      // Calculate final elapsed time
      double finalElapsed;
      if (_activeRegistration!.isPaused) {
        // Timer is paused, use stored paused time
        finalElapsed = _activeRegistration!.pausedElapsedTime ?? 0.0;
      } else {
        // Timer is running, calculate from base + current session
        final baseTime = _activeRegistration!.pausedElapsedTime ?? 0.0;
        if (_startTime != null) {
          final currentSessionTime = DateTime.now().difference(_startTime!);
          finalElapsed = baseTime + currentSessionTime.inSeconds / 3600.0;
        } else {
          finalElapsed = baseTime;
        }
      }

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
}

