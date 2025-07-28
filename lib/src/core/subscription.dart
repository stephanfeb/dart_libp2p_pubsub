import 'dart:async';

// TODO: Define a proper Message class/interface to be used instead of `dynamic`.
// import 'message.dart'; // Or from pb/rpc.pb.dart

/// Represents a subscription to a PubSub topic.
///
/// It provides a stream of messages for the subscribed topic and a way
/// to cancel the subscription.
class Subscription {
  final String _topic;
  final StreamController<dynamic> _controller; // TODO: Use specific Message type
  final Future<void> Function() _cancelCallback;

  /// The topic this subscription is for.
  String get topic => _topic;

  /// A stream of messages for the subscribed topic.
  ///
  /// TODO: The stream should emit a well-defined Message object.
  Stream<dynamic> get stream => _controller.stream;

  /// Creates a new [Subscription].
  ///
  /// [_topic] is the name of the topic.
  /// [_cancelCallback] is a function that will be called when [cancel] is invoked.
  Subscription(this._topic, this._cancelCallback)
      : _controller = StreamController<dynamic>.broadcast(); // Use broadcast for multiple listeners if needed

  /// Delivers a message to the subscription stream.
  ///
  /// This method is typically called by the PubSub system when a new message
  /// arrives for the topic.
  ///
  /// [message] is the message to deliver.
  /// TODO: Use specific Message type for the parameter.
  void deliver(dynamic message) {
    if (!_controller.isClosed) {
      _controller.add(message);
    }
  }

  /// Cancels the subscription.
  ///
  /// This will close the message stream and execute the cancel callback
  /// provided during construction (e.g., to notify PubSub to remove the subscription).
  Future<void> cancel() async {
    if (!_controller.isClosed) {
      await _controller.close();
      // Only call the external callback if we are the ones performing the cancellation action.
      await _cancelCallback(); 
      print('Subscription to topic "$_topic" cancelled.');
    }
    // If already closed, subsequent calls to cancel will do nothing further
    // with respect to the controller or the callback.
  }

  // Helper to check if the stream is closed, though users should rely on stream events.
  bool get isCancelled => _controller.isClosed;
}
