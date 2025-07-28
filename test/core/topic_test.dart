import 'package:test/test.dart';
import 'package:dart_libp2p_pubsub/src/core/topic.dart';

void main() {
  group('Topic Class Tests', () {
    test('should store and retrieve the topic name correctly', () {
      const topicName = 'test-topic-alpha';
      final topic = Topic(topicName);
      expect(topic.name, equals(topicName));
    });

    test('toString() should return a sensible representation', () {
      const topicName = 'another-topic';
      final topic = Topic(topicName);
      expect(topic.toString(), equals('Topic{name: $topicName}'));
    });

    test('equality and hashCode should be based on name', () {
      const topicName1 = 'topic-A';
      const topicName2 = 'topic-B';

      final topicA1 = Topic(topicName1);
      final topicA2 = Topic(topicName1); // Same name
      final topicB1 = Topic(topicName2);

      // Equality
      expect(topicA1, equals(topicA2));
      expect(topicA1, isNot(equals(topicB1)));
      expect(topicA2, isNot(equals(topicB1)));

      // HashCode
      expect(topicA1.hashCode, equals(topicA2.hashCode));
      expect(topicA1.hashCode, isNot(equals(topicB1.hashCode)));

      // Reflexivity
      expect(topicA1, equals(topicA1));

      // Symmetry
      expect(topicA2, equals(topicA1));

      // Transitivity (not easily testable with just two, but implied by consistent name check)

      // Non-nullity
      expect(topicA1, isNot(equals(null)));
    });
  });
}
