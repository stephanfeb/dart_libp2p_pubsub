import 'dart:convert'; // For jsonEncode
import 'dart:io'; // For IOSink

import '../../pb/trace.pb.dart' as pb; // For pb.TraceEvent
import '../tracer.dart'; // For EventTracer interface

/// An [EventTracer] implementation that outputs trace events as JSON strings.
/// It can write to an [IOSink] (e.g., a file) or to the console if no sink is provided.
class JsonEventTracer implements EventTracer {
  final bool _prettyPrint;
  final IOSink? _outputSink;
  bool _shouldCloseSink = false; // Flag to indicate if this instance owns the sink closing

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

  @override
  void trace(pb.TraceEvent event) {
    try {
      final jsonString = event.writeToJson();
      String outputString;

      if (_prettyPrint) {
        final jsonObject = jsonDecode(jsonString);
        final encoder = JsonEncoder.withIndent('  ');
        outputString = encoder.convert(jsonObject);
      } else {
        outputString = jsonString;
      }

      if (_outputSink != null) {
        _outputSink!.writeln(outputString);
      } else {
        print(outputString);
      }
    } catch (e, s) {
      final errorMessage = 'JsonEventTracer: Error serializing event to JSON or writing: $e\n$s';
      if (_outputSink != null) {
        _outputSink!.writeln(errorMessage);
      } else {
        print(errorMessage);
      }
      // Fallback: print the event's toString() representation
      final fallbackMessage = 'JsonEventTracer: Event (toString): ${event.toString()}';
      if (_outputSink != null) {
        _outputSink!.writeln(fallbackMessage);
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
      print('JsonEventTracer: Started. Outputting to sink.');
    } else {
      print('JsonEventTracer: Started. Outputting to console.');
    }
  }

  @override
  Future<void> stop() async {
    // Flush the sink if it exists.
    await _outputSink?.flush();
    if (_outputSink != null) {
      print('JsonEventTracer: Stopped. Sink flushed.');
    } else {
      print('JsonEventTracer: Stopped.');
    }
  }

  @override
  Future<void> dispose() async {
    await stop(); // Ensure everything is flushed.
    if (_shouldCloseSink && _outputSink != null) {
      await _outputSink!.close();
      print('JsonEventTracer: Disposed. Owned sink closed.');
    } else if (_outputSink != null) {
      print('JsonEventTracer: Disposed. External sink not closed by this instance.');
    } else {
      print('JsonEventTracer: Disposed.');
    }
  }
}
