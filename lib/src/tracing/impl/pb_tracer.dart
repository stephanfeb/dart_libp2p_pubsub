import 'dart:io'; // For IOSink, File, FileMode
import 'dart:typed_data'; // For Uint8List, ByteData, Endian

import '../../pb/trace.pb.dart' as pb; // For pb.TraceEvent
import '../tracer.dart'; // For EventTracer interface

/// An [EventTracer] implementation that serializes trace events into their
/// binary protobuf format.
///
/// It can write to an [IOSink] (e.g., a file) or print a confirmation to the
/// console if no sink is provided. When writing to a sink, events are
/// length-prefixed (4-byte Big Endian).
class PbEventTracer implements EventTracer {
  final IOSink? _outputSink;
  bool _shouldCloseSink = false; // Flag to indicate if this instance owns the sink closing

  /// Creates a new [PbEventTracer].
  ///
  /// If [outputSink] is provided, traces will be written to it.
  /// If [filePath] is provided, an [IOSink] will be created for that file.
  /// Note: [outputSink] and [filePath] are mutually exclusive. If both are provided, [outputSink] takes precedence.
  PbEventTracer({
    IOSink? outputSink,
    String? filePath,
  }) : _outputSink = outputSink ?? (filePath != null ? File(filePath).openWrite(mode: FileMode.append) : null) {
    if (filePath != null && outputSink == null) {
      _shouldCloseSink = true; // This instance created the sink, so it should close it.
    }
  }

  String _getTraceEventType(pb.TraceEvent event) {
    if (event.hasType()) {
      return event.type.toString(); // Relies on enum's toString()
    }
    // Basic fallback if type is not set, can be expanded if needed.
    if (event.hasPublishMessage()) return "PublishMessage (inferred)";
    if (event.hasRejectMessage()) return "RejectMessage (inferred)";
    if (event.hasDuplicateMessage()) return "DuplicateMessage (inferred)";
    if (event.hasDeliverMessage()) return "DeliverMessage (inferred)";
    if (event.hasAddPeer()) return "AddPeer (inferred)";
    if (event.hasRemovePeer()) return "RemovePeer (inferred)";
    if (event.hasRecvRPC()) return "RecvRPC (inferred)";
    if (event.hasSendRPC()) return "SendRPC (inferred)";
    if (event.hasDropRPC()) return "DropRPC (inferred)";
    if (event.hasJoin()) return "Join (inferred)";
    if (event.hasLeave()) return "Leave (inferred)";
    if (event.hasGraft()) return "Graft (inferred)";
    if (event.hasPrune()) return "Prune (inferred)";
    return "UnknownType (type field not set)";
  }

  @override
  void trace(pb.TraceEvent event) {
    try {
      final Uint8List eventBytes = event.writeToBuffer();

      if (_outputSink != null) {
        // Write length prefix (4-byte BigEndian length)
        final lengthBytes = Uint8List(4);
        ByteData.view(lengthBytes.buffer).setUint32(0, eventBytes.lengthInBytes, Endian.big);
        _outputSink!.add(lengthBytes);
        _outputSink!.add(eventBytes);
      } else {
        // For console, just print a confirmation and byte length.
        print('PbEventTracer: Serialized TraceEvent (${eventBytes.lengthInBytes} bytes). Type: ${_getTraceEventType(event)}');
      }
    } catch (e, s) {
      final errorMessage = 'PbEventTracer: Error serializing event to protobuf bytes or writing: $e\n$s';
      if (_outputSink != null) {
        // Attempt to write error to sink, might fail if sink is the issue.
        try {
          _outputSink!.writeln(errorMessage); // Assuming sink can handle strings for errors
        } catch (_) {} // Ignore error during error reporting
      } else {
        print(errorMessage);
      }
      // Fallback: print the event's toString() representation
      final fallbackMessage = 'PbEventTracer: Event (toString): ${event.toString()}';
      if (_outputSink != null) {
        try {
          _outputSink!.writeln(fallbackMessage);
        } catch (_) {}
      } else {
        print(fallbackMessage);
      }
    }
  }

  @override
  Future<void> start() async {
    if (_outputSink != null) {
      print('PbEventTracer: Started. Outputting to sink.');
    } else {
      print('PbEventTracer: Started. Outputting to console (confirmations only).');
    }
  }

  @override
  Future<void> stop() async {
    await _outputSink?.flush();
    if (_outputSink != null) {
      print('PbEventTracer: Stopped. Sink flushed.');
    } else {
      print('PbEventTracer: Stopped.');
    }
  }

  @override
  Future<void> dispose() async {
    await stop(); // Ensure everything is flushed.
    if (_shouldCloseSink && _outputSink != null) {
      await _outputSink!.close();
      print('PbEventTracer: Disposed. Owned sink closed.');
    } else if (_outputSink != null) {
      print('PbEventTracer: Disposed. External sink not closed by this instance.');
    } else {
      print('PbEventTracer: Disposed.');
    }
  }
}
