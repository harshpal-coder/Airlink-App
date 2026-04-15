import 'package:event_bus/event_bus.dart';

/// Centralized Event Bus for cross-service communication.
/// This decouples services from direct dependencies on each other.
final EventBus appEventBus = EventBus();
