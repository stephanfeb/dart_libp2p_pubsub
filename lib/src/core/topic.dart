/// Represents a PubSub topic.
///
/// A topic is a channel for messages. Clients can subscribe to topics to receive
/// messages published to them, and publish messages to topics they are interested in.
class Topic {
  /// The name of the topic.
  final String name;

  // TODO: Consider what other properties or methods a Topic object should have.
  // For example, it might manage its own list of [Subscription] objects,
  // or provide methods to join/leave the topic which interact with the PubSub instance.

  /// Creates a new [Topic] instance.
  Topic(this.name);

  // Placeholder for potential methods like:
  // Future<void> publish(dynamic data) async { ... }
  // Subscription subscribe() { ... }
  // Future<void> close() async { ... } // To leave the topic

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Topic && runtimeType == other.runtimeType && name == other.name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() {
    return 'Topic{name: $name}';
  }
}
