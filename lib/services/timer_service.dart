import 'dart:async';
import '../models/hour_registration.dart';
import '../models/hour_registration_order.dart';
import '../models/order.dart';
import '../repositories/repository_interface.dart';
import 'package:flutter/foundation.dart';

class TimerService {
  final RepositoryInterface repository;
  static bool enableVerboseLogging = false;
  void _log(String message) {
    if (kDebugMode && enableVerboseLogging) {
      // ignore: avoid_print
      print(message);
    }
  }
  Timer? _timer;
  Timer? _downtimeTimer;
  HourRegistration? _activeRegistration;
  List<HourRegistrationOrder> _activeOrderLinks = [];
  DateTime? _startTime;
  double _accumulatedElapsedTime = 0.0; // Total elapsed time including pauses
  double _accumulatedDowntime = 0.0; // Total downtime recorded during pauses
  DateTime? _pauseStartTime; // When the timer was paused
  final StreamController<Duration> _elapsedTimeController = StreamController<Duration>.broadcast();
  final StreamController<Duration> _downtimeController = StreamController<Duration>.broadcast();
  Duration? _lastCalculatedDuration; // Store last calculated duration to avoid recalculation issues
  Duration? _lastDowntimeDuration;

  TimerService(this.repository);

  Stream<Duration> get elapsedTimeStream => _elapsedTimeController.stream;
  Stream<Duration> get downtimeStream => _downtimeController.stream;

  bool get isTimerRunning =>
      _activeRegistration != null &&
      _activeRegistration!.isActive &&
      !_activeRegistration!.isPaused;

  bool get isTimerPaused =>
      _activeRegistration != null &&
      _activeRegistration!.isActive &&
      _activeRegistration!.isPaused;

  HourRegistration? get activeRegistration => _activeRegistration;
  Duration? get currentDowntime => _lastDowntimeDuration;
  List<HourRegistrationOrder> get activeOrderLinks =>
      List.unmodifiable(_activeOrderLinks);
  Set<String> get activeOrderIds => _activeOrderLinks
      .where((link) => link.isActive)
      .map((link) => link.orderId)
      .toSet();

  Future<bool> startTimer(String orderId, String userId) {
    return startTimerForOrders([orderId], userId);
  }

  Future<bool> startTimerForOrders(List<String> orderIds, String userId) async {
    final totalStopwatch = Stopwatch()..start();
    Future<T> measureAsync<T>(String label, Future<T> Function() action) async {
      final sw = Stopwatch()..start();
      try {
        return await action();
      } finally {
        _log('[TimerService][Perf] startTimerForOrders::$label took ${sw.elapsedMilliseconds}ms');
      }
    }

    try {
      final normalizedOrderIds = orderIds
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (normalizedOrderIds.isEmpty) {
        return false;
      }

      final now = DateTime.now();
      HourRegistration? existingRegistration;
      if (_activeRegistration != null &&
          _activeRegistration!.isActive &&
          _activeRegistration!.userId == userId) {
        existingRegistration = _activeRegistration;
      } else {
        existingRegistration = await measureAsync(
          'getActiveHourRegistrationByUserId',
          () => repository.getActiveHourRegistrationByUserId(userId),
        );
      }

      if (existingRegistration == null) {
        _log('[TimerService] startTimerForOrders -> creating new session for orders: $normalizedOrderIds');
        final conflictedOrder = await measureAsync(
          'findConflictingOrder',
          () => _findConflictingOrder(normalizedOrderIds, userId),
        );
        if (conflictedOrder != null) {
          return false;
        }

        final registration = HourRegistration(
          hourRegistrationId: '',
          userId: userId,
          startTime: now,
          isActive: true,
          isPaused: false,
          pausedElapsedTime: 0.0,
          downtimeElapsedTime: 0.0,
          createdOn: now,
          modifiedOn: now,
        );
        final sessionResult = await measureAsync(
          'createHourRegistrationWithOrders',
          () => repository.createHourRegistrationWithOrders(
            registration,
            normalizedOrderIds,
          ),
        );
        final savedRegistration = sessionResult.registration;
        final savedLinks = sessionResult.orderLinks;
        _activeRegistration = savedRegistration;
        _accumulatedElapsedTime = 0.0;
        _accumulatedDowntime = 0.0;
        _activeOrderLinks = List.of(savedLinks);
      } else {
        final nonNullRegistration = existingRegistration!;
        final links = await measureAsync(
          'getHourRegistrationOrdersByRegistrationId',
          () => repository.getHourRegistrationOrdersByRegistrationId(
              nonNullRegistration.hourRegistrationId),
        );
        final sessionActiveIds = links
            .where((link) => link.isActive)
            .map((link) => link.orderId)
            .toSet();

        if (sessionActiveIds.isEmpty) {
          return false;
        }

        final requestedIds = normalizedOrderIds.toSet();
        if (requestedIds.isNotEmpty && requestedIds != sessionActiveIds) {
          return false;
        }

        _activeRegistration = nonNullRegistration;
        _activeOrderLinks = List.of(links);
        _accumulatedElapsedTime = nonNullRegistration.pausedElapsedTime ??
            nonNullRegistration.elapsedTime ??
            0.0;
        _accumulatedDowntime = nonNullRegistration.downtimeElapsedTime ?? 0.0;
        _log('[TimerService] resume existing registration ${nonNullRegistration.hourRegistrationId} -> pausedElapsed=${nonNullRegistration.pausedElapsedTime}, elapsed=${nonNullRegistration.elapsedTime}, accumulatedElapsed=$_accumulatedElapsedTime, accumulatedDowntime=$_accumulatedDowntime');
      }

      await _resumeActiveRegistration(now);
      _log('[TimerService] startTimerForOrders -> after resume: accumulatedElapsed=$_accumulatedElapsedTime accumulatedDowntime=$_accumulatedDowntime isPaused=${_activeRegistration?.isPaused}');
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('[TimerService][Perf] startTimerForOrders -> error: $e');
      return false;
    } finally {
      totalStopwatch.stop();
      _log('[TimerService][Perf] startTimerForOrders::total took ${totalStopwatch.elapsedMilliseconds}ms');
    }
  }

  Future<bool> resumeTimer() async {
    try {
      if (_activeRegistration == null ||
          !_activeRegistration!.isActive ||
          !_activeRegistration!.isPaused) {
        return false;
      }

      final now = DateTime.now();
      await _resumeActiveRegistration(now);
      _log('[TimerService] resumeTimer -> after resume: accumulatedElapsed=$_accumulatedElapsedTime accumulatedDowntime=$_accumulatedDowntime isPaused=${_activeRegistration?.isPaused}');
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<String?> _findConflictingOrder(
      List<String> orderIds, String userId) async {
    for (final orderId in orderIds) {
      final mappings =
          await repository.getHourRegistrationOrdersByOrderId(orderId);
      for (final mapping in mappings.where((m) => m.isActive)) {
        final registration =
            await repository.getHourRegistrationById(mapping.hourRegistrationId);
        if (registration != null &&
            registration.isActive &&
            registration.userId != userId) {
          return orderId;
        }
      }
    }
    return null;
  }

  Future<void> _resumeActiveRegistration(DateTime resumeTime) async {
    if (_activeRegistration == null) {
      return;
    }

    double totalDowntime = _activeRegistration!.downtimeElapsedTime ?? 0.0;
    if (_activeRegistration!.downtimeStartTime != null) {
      final resumedDowntime = resumeTime
              .difference(_activeRegistration!.downtimeStartTime!)
              .inSeconds /
          3600.0;
      totalDowntime += resumedDowntime;
    }

    _accumulatedDowntime = totalDowntime;
    _pauseStartTime = null;

    final updatedRegistration = _activeRegistration!.copyWith(
      isPaused: false,
      pausedElapsedTime: _accumulatedElapsedTime,
      modifiedOn: resumeTime,
      downtimeElapsedTime: totalDowntime,
      downtimeStartTime: null,
    );
    _activeRegistration = await repository.updateHourRegistration(
      updatedRegistration,
    );
    _log('[TimerService] _resumeActiveRegistration -> stored pausedElapsed=${_activeRegistration?.pausedElapsedTime}, elapsed=${_activeRegistration?.elapsedTime}');

    await _refreshOrderOffsets();

    _emitDowntime(Duration(seconds: (_accumulatedDowntime * 3600).toInt()));
    _stopDowntimeTimer();

    _startTime = resumeTime;

    final baseTime = _accumulatedElapsedTime;
    _log('[TimerService] resume -> baseElapsed=$baseTime, accumulatedDowntime=$_accumulatedDowntime');
    final initialDuration = Duration(seconds: (baseTime * 3600).toInt());
    _elapsedTimeController.add(initialDuration);

    _scheduleElapsedUpdates();
  }

  Future<void> _refreshOrderOffsets() async {
    if (_activeRegistration == null) {
      return;
    }

    final baseElapsed = _activeRegistration!.pausedElapsedTime ?? 0.0;
    final baseDowntime = _accumulatedDowntime;
    final now = DateTime.now();

    final List<HourRegistrationOrder> updatedLinks = [];
    for (final link in _activeOrderLinks) {
      if (!link.isActive) {
        updatedLinks.add(link);
        continue;
      }

      final updated = link.copyWith(
        elapsedOffset: baseElapsed,
        downtimeOffset: baseDowntime,
        modifiedOn: now,
      );
      updatedLinks.add(updated);
      await repository.updateHourRegistrationOrder(updated);
    }
    _activeOrderLinks = updatedLinks;
  }

  void _scheduleElapsedUpdates() {
    _timer?.cancel();
    final base = _accumulatedElapsedTime;
    _log('[TimerService] _scheduleElapsedUpdates -> scheduling with baseElapsed=$base');
    _timer = Timer(const Duration(milliseconds: 100), () {
      _emitElapsedTick();
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _emitElapsedTick(),
      );
    });
  }

  void _emitElapsedTick() {
    if (_activeRegistration == null ||
        _startTime == null ||
        _activeRegistration!.isPaused) {
      return;
    }
    final totalElapsed = _currentElapsedHours();
    _log('[TimerService] _emitElapsedTick -> totalElapsed=$totalElapsed, startTime=$_startTime');
    final duration = Duration(seconds: (totalElapsed * 3600).toInt());
    _lastCalculatedDuration = duration;
    _elapsedTimeController.add(duration);
  }

  double _currentElapsedHours() {
    if (_activeRegistration == null) {
      return 0.0;
    }
    final base = _activeRegistration!.pausedElapsedTime ?? 0.0;
    if (_activeRegistration!.isPaused || _startTime == null) {
      return base;
    }
    final session =
        DateTime.now().difference(_startTime!).inSeconds / 3600.0;
    return base + session;
  }

  double _currentDowntimeHours() {
    if (_activeRegistration == null) {
      return 0.0;
    }
    final base = _accumulatedDowntime;
    if (_activeRegistration!.isPaused && _pauseStartTime != null) {
      final paused =
          DateTime.now().difference(_pauseStartTime!).inSeconds / 3600.0;
      return base + paused;
    }
    return base;
  }

  Future<void> _captureOrderProgress({Iterable<String>? orderIds}) async {
    if (_activeRegistration == null) {
      return;
    }

    final targetIds = orderIds?.toSet();
    final elapsed = _currentElapsedHours();
    final downtime = _currentDowntimeHours();
    final now = DateTime.now();
    final List<HourRegistrationOrder> updatedLinks = [];

    for (final link in _activeOrderLinks) {
      if (!link.isActive ||
          (targetIds != null && !targetIds.contains(link.orderId))) {
        updatedLinks.add(link);
        continue;
      }

      final baseElapsed = link.elapsedTime ?? 0.0;
      final offsetElapsed = link.elapsedOffset ?? elapsed;
      final incrementElapsed = elapsed - offsetElapsed;
      final nextElapsed =
          incrementElapsed > 0 ? baseElapsed + incrementElapsed : baseElapsed;

      final baseDowntime = link.downtimeElapsedTime ?? 0.0;
      final offsetDowntime = link.downtimeOffset ?? downtime;
      final incrementDowntime = downtime - offsetDowntime;
      final nextDowntime = incrementDowntime > 0
          ? baseDowntime + incrementDowntime
          : baseDowntime;

      final updated = link.copyWith(
        elapsedTime: nextElapsed,
        elapsedOffset: elapsed,
        downtimeElapsedTime: nextDowntime,
        downtimeOffset: downtime,
        modifiedOn: now,
      );
      updatedLinks.add(updated);
      await repository.updateHourRegistrationOrder(updated);
    }

    _activeOrderLinks = updatedLinks;
  }

  Future<bool> pauseTimer() async {
    try {
      if (_activeRegistration == null || _activeRegistration!.isPaused) {
        return false;
      }

      _timer?.cancel();
      _timer = null;

      final totalElapsed = _currentElapsedHours();
      _accumulatedElapsedTime = totalElapsed;
    _log('[TimerService] pause -> totalElapsed=$totalElapsed, accumulatedDowntime=$_accumulatedDowntime');

      final now = DateTime.now();
      final updatedRegistration = _activeRegistration!.copyWith(
        isPaused: true,
        pausedElapsedTime: totalElapsed,
        downtimeElapsedTime: _accumulatedDowntime,
        downtimeStartTime: now,
        modifiedOn: now,
      );

      _activeRegistration =
          await repository.updateHourRegistration(updatedRegistration);
      _accumulatedDowntime =
          _activeRegistration!.downtimeElapsedTime ?? _accumulatedDowntime;

      await _captureOrderProgress();

      final duration =
          Duration(seconds: (_accumulatedElapsedTime * 3600).toInt());
      _lastCalculatedDuration = duration;
      _elapsedTimeController.add(duration);

      _pauseStartTime = now;
      _startDowntimeTimer();
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
      final finalElapsed = _currentElapsedHours();
      final finalDowntime = _currentDowntimeHours();
      _log('[TimerService] finish -> finalElapsed=$finalElapsed, finalDowntime=$finalDowntime');

      await _captureOrderProgress();

      final List<HourRegistrationOrder> updatedLinks = [];
      for (final link in _activeOrderLinks) {
        if (!link.isActive) {
          updatedLinks.add(link);
          continue;
        }

        // Use the maximum of stored value and final calculated value to ensure accuracy
        // This handles cases where _captureOrderProgress may have already updated the value
        final storedElapsed = link.elapsedTime ?? 0.0;
        final storedDowntime = link.downtimeElapsedTime ?? 0.0;
        final finalElapsedValue = finalElapsed > storedElapsed ? finalElapsed : storedElapsed;
        final finalDowntimeValue = finalDowntime > storedDowntime ? finalDowntime : storedDowntime;

        final updated = link.copyWith(
          isActive: false,
          elapsedTime: finalElapsedValue,
          elapsedOffset: finalElapsed,
          downtimeElapsedTime: finalDowntimeValue,
          downtimeOffset: finalDowntime,
          completedOn: endTime,
          modifiedOn: endTime,
        );
        _log('[TimerService] Saving completed order link: orderId=${link.orderId}, elapsedTime=$finalElapsedValue, downtime=$finalDowntimeValue');
        updatedLinks.add(updated);
        await repository.updateHourRegistrationOrder(updated);
      }
      _activeOrderLinks = updatedLinks;

      _emitDowntime(Duration(seconds: (finalDowntime * 3600).toInt()));
      _stopDowntimeTimer();

      _activeRegistration = _activeRegistration!.copyWith(
        endTime: endTime,
        elapsedTime: finalElapsed,
        isActive: false,
        isPaused: false,
        pausedElapsedTime: finalElapsed,
        downtimeElapsedTime: finalDowntime,
        downtimeStartTime: null,
        modifiedOn: endTime,
      );

      await repository.updateHourRegistration(_activeRegistration!);

      final duration = Duration(seconds: (finalElapsed * 3600).toInt());
      _elapsedTimeController.add(duration);

      _activeRegistration = null;
      _activeOrderLinks = [];
      _startTime = null;
      _accumulatedElapsedTime = 0.0;
      _accumulatedDowntime = 0.0;
      _pauseStartTime = null;
      _lastCalculatedDuration = null; // Clear stored duration
      _lastDowntimeDuration = null;

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> finishOrder(String orderId) async {
    try {
      if (_activeRegistration == null) {
        return false;
      }

      final activeLinkIndex = _activeOrderLinks.indexWhere(
        (link) => link.orderId == orderId && link.isActive,
      );

      if (activeLinkIndex == -1) {
        return false;
      }

      await _captureOrderProgress(orderIds: {orderId});

      final finalElapsed =
          _activeRegistration!.isPaused ? _accumulatedElapsedTime : _currentElapsedHours();
      final finalDowntime = _currentDowntimeHours();
      final now = DateTime.now();

      final link = _activeOrderLinks[activeLinkIndex];
      // Use the maximum of stored value and final calculated value to ensure accuracy
      final storedElapsed = link.elapsedTime ?? 0.0;
      final storedDowntime = link.downtimeElapsedTime ?? 0.0;
      final finalElapsedValue = finalElapsed > storedElapsed ? finalElapsed : storedElapsed;
      final finalDowntimeValue = finalDowntime > storedDowntime ? finalDowntime : storedDowntime;

      final updated = link.copyWith(
        isActive: false,
        elapsedTime: finalElapsedValue,
        elapsedOffset: finalElapsed,
        downtimeElapsedTime: finalDowntimeValue,
        downtimeOffset: finalDowntime,
        completedOn: now,
        modifiedOn: now,
      );
      _activeOrderLinks[activeLinkIndex] = updated;
      await repository.updateHourRegistrationOrder(updated);

      if (_activeOrderLinks.every((item) => !item.isActive)) {
        return await finishTimer();
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> loadActiveTimer(String userId) async {
    try {
      final active = await repository.getActiveHourRegistrationByUserId(userId);
      if (active == null || !active.isActive) {
        return;
      }

      _activeRegistration = active;
      _activeOrderLinks = await repository
          .getHourRegistrationOrdersByRegistrationId(
              active.hourRegistrationId);

      _accumulatedElapsedTime = active.pausedElapsedTime ?? 0.0;
      _accumulatedDowntime = active.downtimeElapsedTime ?? 0.0;

      if (active.isPaused) {
        _startTime = null;
        final elapsedDuration =
            Duration(seconds: (_accumulatedElapsedTime * 3600).toInt());
        _elapsedTimeController.add(elapsedDuration);

        final downtimeDuration =
            Duration(seconds: (_accumulatedDowntime * 3600).toInt());
        _emitDowntime(downtimeDuration);

        _pauseStartTime = active.downtimeStartTime;
        if (_pauseStartTime != null) {
          _startDowntimeTimer();
        }
      } else {
        _pauseStartTime = null;
        _startTime = active.modifiedOn;
        if (_startTime == null) {
          _startTime = DateTime.now();
        }

        final downtimeDuration =
            Duration(seconds: (_accumulatedDowntime * 3600).toInt());
        _emitDowntime(downtimeDuration);
        _scheduleElapsedUpdates();
      }

      _activeOrderLinks = _activeOrderLinks
          .map(
            (link) => link.isActive
                ? link.copyWith(
                    elapsedOffset: _accumulatedElapsedTime,
                    downtimeOffset: _accumulatedDowntime,
                  )
                : link,
          )
          .toList();
    } catch (e) {
      // ignore
    }
  }

  void dispose() {
    _timer?.cancel();
    _downtimeTimer?.cancel();
    _elapsedTimeController.close();
    _downtimeController.close();
  }

  String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Calculate total elapsed time for an order from all hour registrations
  /// Set includeOrphanedMappings=true to count stored mapping values when the
  /// underlying registration record is missing (useful for completed orders).
  Future<Duration> getTotalElapsedTimeForOrder(
    String orderId, {
    bool includeOrphanedMappings = false,
  }) async {
    try {
      final mappings =
          await repository.getHourRegistrationOrdersByOrderId(orderId);
      _log('[TimerService] getTotalElapsedTimeForOrder for $orderId: found ${mappings.length} mappings');
      double totalHours = 0.0;

      // Prefetch registrations to avoid per-item awaits (N+1)
      final registrationIds = mappings
          .map((m) => m.hourRegistrationId)
          .toSet()
          .toList();
      final registrations = await repository.getHourRegistrationsByIds(registrationIds);
      final regById = {
        for (final r in registrations) r.hourRegistrationId: r,
      };

      for (final mapping in mappings) {
        _log('[TimerService]   Mapping: isActive=${mapping.isActive}, elapsedTime=${mapping.elapsedTime}, regId=${mapping.hourRegistrationId}');
        final registration = regById[mapping.hourRegistrationId];
        if (registration == null) {
          // Registration was deleted - this is orphaned data
          if (includeOrphanedMappings) {
            final orphaned = mapping.elapsedTime ?? 0.0;
            _log('[TimerService]   Registration not found, including orphaned mapping.elapsedTime=$orphaned (includeOrphanedMappings)');
            totalHours += orphaned;
            continue;
          } else {
            _log('[TimerService]   Registration not found (orphaned mapping), skipping');
            continue;
          }
        }
        _log('[TimerService]   Registration: isActive=${registration.isActive}, elapsedTime=${registration.elapsedTime}, pausedElapsedTime=${registration.pausedElapsedTime}');

        if (registration.isActive && mapping.isActive) {
          // Active registration - calculate current elapsed time
          final registrationElapsed =
              _calculateRegistrationElapsed(registration);
          final base = mapping.elapsedTime ?? 0.0;
          final offset = mapping.elapsedOffset ?? registrationElapsed;
          final increment = registrationElapsed - offset;
          final added = base + (increment > 0 ? increment : 0.0);
          _log('[TimerService]   Active: adding $added hours');
          totalHours += added;
        } else {
          // Completed/inactive registration - use stored values
          // Priority: mapping.elapsedTime > registration.elapsedTime > registration.pausedElapsedTime > calculated
          if (mapping.elapsedTime != null) {
            // Use the stored elapsed time from the mapping (most accurate for completed orders)
            _log('[TimerService]   Completed: using mapping.elapsedTime=${mapping.elapsedTime}');
            totalHours += mapping.elapsedTime!;
          } else if (registration.elapsedTime != null) {
            // Fallback to registration's elapsed time
            _log('[TimerService]   Completed: using registration.elapsedTime=${registration.elapsedTime}');
            totalHours += registration.elapsedTime!;
          } else if (registration.pausedElapsedTime != null) {
            // Fallback to paused elapsed time
            _log('[TimerService]   Completed: using registration.pausedElapsedTime=${registration.pausedElapsedTime}');
            totalHours += registration.pausedElapsedTime!;
          } else if (!registration.isActive && registration.endTime != null) {
            // For completed registrations with endTime, calculate from start to end
            final calculated = _calculateRegistrationElapsed(registration);
            _log('[TimerService]   Completed: calculated from endTime=$calculated');
            totalHours += calculated;
          } else {
            // Last resort: calculate from registration
            final calculated = _calculateRegistrationElapsed(registration);
            _log('[TimerService]   Completed: calculated fallback=$calculated');
            totalHours += calculated;
          }
        }
      }

      _log('[TimerService] getTotalElapsedTimeForOrder result: $totalHours hours = ${(totalHours * 3600).toInt()} seconds');
      return Duration(seconds: (totalHours * 3600).toInt());
    } catch (e) {
      // ignore: avoid_print
      print('[TimerService] getTotalElapsedTimeForOrder error for order $orderId: $e');
      return Duration.zero;
    }
  }

  /// Calculate total downtime for an order from all hour registrations
  /// Set includeOrphanedMappings=true to count stored mapping values when the
  /// underlying registration record is missing (useful for completed orders).
  Future<Duration> getTotalDowntimeForOrder(
    String orderId, {
    bool includeOrphanedMappings = false,
  }) async {
    try {
      final mappings =
          await repository.getHourRegistrationOrdersByOrderId(orderId);
      double totalHours = 0.0;

      // Prefetch registrations to avoid per-item awaits (N+1)
      final registrationIds = mappings
          .map((m) => m.hourRegistrationId)
          .toSet()
          .toList();
      final registrations = await repository.getHourRegistrationsByIds(registrationIds);
      final regById = {
        for (final r in registrations) r.hourRegistrationId: r,
      };

      for (final mapping in mappings) {
        final registration = regById[mapping.hourRegistrationId];
        if (registration == null) {
          // Registration was deleted - this is orphaned data
          if (includeOrphanedMappings) {
            totalHours += (mapping.downtimeElapsedTime ?? 0.0);
            continue;
          } else {
            continue;
          }
        }

        if (registration.isActive && mapping.isActive) {
          // Active registration - calculate current downtime
          final registrationDowntime =
              _calculateRegistrationDowntime(registration);
          final base = mapping.downtimeElapsedTime ?? 0.0;
          final offset = mapping.downtimeOffset ?? registrationDowntime;
          final increment = registrationDowntime - offset;
          totalHours += base + (increment > 0 ? increment : 0.0);
        } else {
          // Completed/inactive registration - use stored values
          // Priority: mapping.downtimeElapsedTime > registration.downtimeElapsedTime
          if (mapping.downtimeElapsedTime != null) {
            // Use the stored downtime from the mapping (most accurate for completed orders)
            totalHours += mapping.downtimeElapsedTime!;
          } else if (registration.downtimeElapsedTime != null) {
            // Fallback to registration's downtime
            totalHours += registration.downtimeElapsedTime!;
          }
          // Note: If both are null, downtime is 0 for this registration
        }
      }

      return Duration(seconds: (totalHours * 3600).toInt());
    } catch (e) {
      print('[TimerService] getTotalDowntimeForOrder error for order $orderId: $e');
      return Duration.zero;
    }
  }

  double _calculateRegistrationElapsed(HourRegistration registration) {
    if (!registration.isActive) {
      return registration.elapsedTime ??
          registration.pausedElapsedTime ??
          registration.calculateElapsedTime();
    }

    if (_activeRegistration != null &&
        registration.hourRegistrationId == _activeRegistration!.hourRegistrationId) {
      return _currentElapsedHours();
    }

    final base = registration.pausedElapsedTime ?? 0.0;
    if (registration.isPaused) {
      return base;
    }

    final resumeReference = registration.modifiedOn;
    if (resumeReference != null) {
      final sessionHours =
          DateTime.now().difference(resumeReference).inSeconds / 3600.0;
      return base + sessionHours;
    }

    final sessionHours =
        DateTime.now().difference(registration.startTime).inSeconds / 3600.0;
    return base + sessionHours;
  }

  double _calculateRegistrationDowntime(HourRegistration registration) {
    final base = registration.downtimeElapsedTime ?? 0.0;
    if (!registration.isActive) {
      return base;
    }

    if (_activeRegistration != null &&
        registration.hourRegistrationId == _activeRegistration!.hourRegistrationId) {
      return _currentDowntimeHours();
    }

    if (registration.isPaused && registration.downtimeStartTime != null) {
      final pausedHours =
          DateTime.now().difference(registration.downtimeStartTime!).inSeconds /
              3600.0;
      return base + pausedHours;
    }

    return base;
  }

  void _emitDowntime(Duration duration) {
    _lastDowntimeDuration = duration;
    _downtimeController.add(duration);
  }

  void _startDowntimeTimer() {
    _downtimeTimer?.cancel();
    _emitDowntime(Duration(seconds: ((_activeRegistration?.downtimeElapsedTime ?? 0.0) * 3600).toInt()));

    _downtimeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_activeRegistration == null ||
          !_activeRegistration!.isPaused ||
          _activeRegistration!.downtimeStartTime == null) {
        return;
      }

      final base = _activeRegistration!.downtimeElapsedTime ?? 0.0;
      final current = DateTime.now().difference(_activeRegistration!.downtimeStartTime!).inSeconds / 3600.0;
      final total = base + current;
      _emitDowntime(Duration(seconds: (total * 3600).toInt()));
    });
  }

  void _stopDowntimeTimer() {
    _downtimeTimer?.cancel();
    _downtimeTimer = null;
  }
}

