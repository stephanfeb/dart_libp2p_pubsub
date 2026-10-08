import 'dart:convert'; // For jsonEncode
import 'dart:io'; // For IOSink

import '../../pb/trace.pb.dart' as pb; // For pb.TraceEvent
import '../tracer.dart'; // For EventTracer interface
import 'package:logging/logging.dart';

final _log = Logger('JsonEventTracer');

/// An [EventTracer] implementation that outputs trace events as JSON strings.
/// It can write to an [IOSink] (e.g., a file) or to the console if no sink is provided.
///
/// The output is newline-delimited JSON in the form go-libp2p-pubsub's
/// JSONTracer writes: fields named as in trace.proto, bytes in base64, and
/// the event type and timestamp as numbers. Events traced after [dispose]
/// are dropped.
class JsonEventTracer implements EventTracer {
  final bool _prettyPrint;
  final IOSink? _outputSink;
  bool _shouldCloseSink = false; // Flag to indicate if this instance owns the sink closing
  bool _disposed = false;

  /// Creates a new [JsonEventTracer].
  ///
  /// If [_prettyPrint] is true, the JSON output will be formatted with an indent.
  /// If [outputSink] is provided, traces will be written to it. Otherwise, they print to console.
  /// If [filePath] is provided, an [IOSink] will be created for that file.
  /// Note: [outputSink] and [filePath] are mutually exclusive. If both are provided, [outputSink] takes precedence.
  JsonEventTracer({
    bool prettyPrint = false,
    IOSink? outputSink,
    String? filePath,
  })  : _prettyPrint = prettyPrint,
        _outputSink = outputSink ?? (filePath != null ? File(filePath).openWrite(mode: FileMode.append) : null) {
    if (filePath != null && outputSink == null) {
      _shouldCloseSink = true; // This instance created the sink, so it should close it.
    }
  }

  /// [event] as go-libp2p-pubsub encodes it to JSON. Proto3 JSON already
  /// names the fields and encodes the bytes as Go does, but writes enums as
  /// names and 64-bit integers as strings, where Go writes numbers.
  static Map<String, dynamic> toGoJson(pb.TraceEvent event) {
    final json = event.toProto3Json() as Map<String, dynamic>;
    if (event.hasType()) json['type'] = event.type.value;
    if (event.hasTimestamp()) json['timestamp'] = event.timestamp.toInt();
    return json;
  }

  @override
  void trace(pb.TraceEvent event) {
    if (_disposed) return;
    try {
      final json = toGoJson(event);
      final outputString = _prettyPrint ? const JsonEncoder.withIndent('  ').convert(json) : jsonEncode(json);

      if (_outputSink != null) {
        _outputSink.writeln(outputString);
      } else {
        print(outputString);
      }
    } catch (e, s) {
      final errorMessage = 'JsonEventTracer: Error serializing event to JSON or writing: $e\n$s';
      if (_outputSink != null) {
        _outputSink.writeln(errorMessage);
      } else {
        _log.warning(errorMessage);
      }
      // Fallback: print the event's toString() representation
      final fallbackMessage = 'JsonEventTracer: Event (toString): ${event.toString()}';
      if (_outputSink != null) {
        _outputSink.writeln(fallbackMessage);
      } else {
        print(fallbackMessage);
      }
    }
  }

  @override
  Future<void> start() async {
    // If _outputSink is a file sink created by this instance, it's opened in the constructor.
    // Otherwise, if an external sink is provided, it's assumed to be ready.
    if (_outputSink != null) {
      _log.fine('JsonEventTracer: Started. Outputting to sink.');
    } else {
      _log.fine('JsonEventTracer: Started. Outputting to console.');
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    // Flush the sink if it exists.
    await _outputSink?.flush();
    if (_outputSink != null) {
      _log.fine('JsonEventTracer: Stopped. Sink flushed.');
    } else {
      _log.fine('JsonEventTracer: Stopped.');
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await stop(); // Ensure everything is flushed.
    _disposed = true;
    if (_shouldCloseSink && _outputSink != null) {
      await _outputSink.close();
      _log.fine('JsonEventTracer: Disposed. Owned sink closed.');
    } else if (_outputSink != null) {
      _log.fine('JsonEventTracer: Disposed. External sink not closed by this instance.');
    } else {
      _log.fine('JsonEventTracer: Disposed.');
    }
  }
}
