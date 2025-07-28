import '../pb/trace.pb.dart' as pb; // For pb.TraceEvent

/// Interface for a PubSub event tracer.
///
/// Implementations of this interface can be used to record and export
/// PubSub trace events for debugging, monitoring, or analysis.
abstract class EventTracer {
  /// Records a trace event.
  ///
  /// [event] is the protobuf TraceEvent to be recorded.
  void trace(pb.TraceEvent event);

  /// Starts the tracer, preparing it for recording events.
  /// This might involve opening files, network connections, etc.
  Future<void> start();

  /// Stops the tracer, finalizing any ongoing operations.
  /// This might involve flushing buffers, closing connections, etc.
  Future<void> stop();

  /// Disposes of the tracer, releasing all associated resources.
  /// After dispose is called, the tracer should not be used anymore.
  Future<void> dispose();
}

/// A no-op implementation of [EventTracer] that does nothing.
/// This can be used as a default if no specific tracer is configured.
class NoOpEventTracer implements EventTracer {
  const NoOpEventTracer();

  @override
  void trace(pb.TraceEvent event) {
    // Does nothing.
  }

  @override
  Future<void> start() async {
    // Does nothing.
  }

  @override
  Future<void> stop() async {
    // Does nothing.
  }

  @override
  Future<void> dispose() async {
    // Does nothing.
  }
}
