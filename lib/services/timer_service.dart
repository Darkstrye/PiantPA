import 'dart:async';
import '../models/hour_registration.dart';
import '../repositories/repository_interface.dart';

class TimerService {
  final RepositoryInterface repository;
  Timer? _timer;
  HourRegistration? _activeRegistration;
  DateTime? _startTime;
  final StreamController<Duration> _elapsedTimeController = StreamController<Duration>.broadcast();

  TimerService(this.repository);

  Stream<Duration> get elapsedTimeStream => _elapsedTimeController.stream;

  bool get isTimerRunning => _activeRegistration != null && _activeRegistration!.isActive;

  HourRegistration? get activeRegistration => _activeRegistration;

  Future<bool> startTimer(String orderId, String userId) async {
    try {
      // Check if there's already an active timer for this user
      final existingActive = await repository.getActiveHourRegistrationByUserId(userId);
      if (existingActive != null) {
        return false; // User already has an active timer
      }

      // Create new hour registration
      final now = DateTime.now();
      _activeRegistration = HourRegistration(
        hourRegistrationId: '',
        orderId: orderId,
        userId: userId,
        startTime: now,
        isActive: true,
        createdOn: now,
        modifiedOn: now,
      );

      _activeRegistration = await repository.createHourRegistration(_activeRegistration!);
      _startTime = now;

      // Start periodic updates
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_activeRegistration != null && _startTime != null) {
          final elapsed = DateTime.now().difference(_startTime!);
          _elapsedTimeController.add(elapsed);
        }
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> stopTimer() async {
    try {
      if (_activeRegistration == null) {
        return false;
      }

      _timer?.cancel();
      _timer = null;

      final endTime = DateTime.now();
      final elapsed = endTime.difference(_startTime!).inSeconds / 3600.0;

      _activeRegistration = _activeRegistration!.copyWith(
        endTime: endTime,
        elapsedTime: elapsed,
        isActive: false,
        modifiedOn: endTime,
      );

      await repository.updateHourRegistration(_activeRegistration!);
      
      final finalElapsed = Duration(
        hours: elapsed.toInt(),
        minutes: ((elapsed - elapsed.toInt()) * 60).toInt(),
        seconds: ((elapsed - elapsed.toInt()) * 60 % 1 * 60).toInt(),
      );
      _elapsedTimeController.add(finalElapsed);

      _activeRegistration = null;
      _startTime = null;

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
        _startTime = active.startTime;

        // Resume timer updates
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (_activeRegistration != null && _startTime != null) {
            final elapsed = DateTime.now().difference(_startTime!);
            _elapsedTimeController.add(elapsed);
          }
        });
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

