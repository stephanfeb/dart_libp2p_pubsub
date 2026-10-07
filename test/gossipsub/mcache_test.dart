import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p_pubsub/src/gossipsub/mcache.dart';
import 'package:dart_libp2p_pubsub/src/pb/rpc.pb.dart' as pb;
import 'package:test/test.dart';

pb.Message _msg(int n, [String topic = 'test']) => pb.Message()
  ..from = [1, 2, 3]
  ..seqno = [n]
  ..topic = topic
  ..data = [n];

void main() {
  // As go-libp2p-pubsub's mcache_test.go.
  group('MessageCache', () {
    test('put, get and gossip IDs over the shifts', () {
      final mc = MessageCache(historyGossip: 3, historyLength: 5);
      final ids = [for (var i = 0; i < 60; i++) 'm$i'];

      for (var i = 0; i < 10; i++) {
        mc.put(ids[i], _msg(i));
      }
      for (var i = 0; i < 10; i++) {
        expect(mc.getMessage(ids[i])!.seqno, [i]);
      }
      expect(mc.getGossipIds('test'), ids.sublist(0, 10));

      mc.shift();
      for (var i = 10; i < 20; i++) {
        mc.put(ids[i], _msg(i));
      }
      expect(mc.getGossipIds('test'), [...ids.sublist(10, 20), ...ids.sublist(0, 10)]);

      for (var w = 2; w < 6; w++) {
        mc.shift();
        for (var i = w * 10; i < w * 10 + 10; i++) {
          mc.put(ids[i], _msg(i));
        }
      }
      // 6 windows were filled; the history keeps 5, so the first is gone.
      expect(mc.getMessage(ids[0]), isNull);
      expect(mc.seen(ids[9]), isFalse);
      expect(mc.getMessage(ids[10]), isNotNull);
      // Gossip covers the last 3 windows: 50-59, 40-49, 30-39.
      expect(mc.getGossipIds('test'),
          [...ids.sublist(50, 60), ...ids.sublist(40, 50), ...ids.sublist(30, 40)]);
    });

    test('gossip IDs are per topic', () {
      final mc = MessageCache();
      mc.put('a', _msg(1, 'A'));
      mc.put('b', _msg(2, 'B'));
      expect(mc.getGossipIds('A'), ['a']);
      expect(mc.getGossipIds('B'), ['b']);
      expect(mc.getGossipIds('C'), isEmpty);
    });

    test('getForPeer counts the requests of each peer until the message leaves', () {
      final mc = MessageCache(historyGossip: 1, historyLength: 2);
      final a = PeerId.fromString('12D3KooWNVJVohNejPeDRpVTKXDhYd2BuKstxAwDHMMdg22uZaye');
      mc.put('m', _msg(1));
      expect(mc.getForPeer('m', a)!.$2, 1);
      expect(mc.getForPeer('m', a)!.$2, 2);
      expect(mc.getForPeer('missing', a), isNull);
      mc.shift();
      expect(mc.getForPeer('m', a)!.$2, 3);
      mc.shift();
      expect(mc.getForPeer('m', a), isNull);
    });

    test('more gossip windows than history windows is refused', () {
      expect(() => MessageCache(historyGossip: 6, historyLength: 5), throwsArgumentError);
    });
  });
}
