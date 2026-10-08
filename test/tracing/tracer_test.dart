import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_libp2p/core/crypto/ed25519.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p_pubsub/dart_libp2p_pubsub.dart';
import 'package:dart_libp2p_pubsub/src/pb/trace.pb.dart' as pb;
import 'package:dart_libp2p_pubsub/src/tracing/impl/json_tracer.dart';
import 'package:dart_libp2p_pubsub/src/tracing/impl/pb_tracer.dart';
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

import '../integration/message_propagation_test.dart' show MockHost, MockNetwork, TestNetworkManager;

class _CapturingTracer implements EventTracer {
  final events = <pb.TraceEvent>[];
  @override
  void trace(pb.TraceEvent event) => events.add(event);
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

/// A REJECT_MESSAGE event, and its encodings by go-libp2p-pubsub v0.15.0's
/// JSONTracer and PBTracer.
final _event = pb.TraceEvent()
  ..type = pb.TraceEvent_Type.REJECT_MESSAGE
  ..peerID = [1, 2, 3]
  ..timestamp = Int64(1700000000123456000)
  ..rejectMessage = (pb.TraceEvent_RejectMessage()
    ..messageID = [9, 9]
    ..receivedFrom = [4, 5]
    ..reason = 'validation failed'
    ..topic = 't');
const _goJson = '{"type":1,"peerID":"AQID","timestamp":1700000000123456000,'
    '"rejectMessage":{"messageID":"CQk=","receivedFrom":"BAU=","reason":"validation failed","topic":"t"}}';
const _goPbHex = '310801120301020318809497ece39fe7cb172a1e0a020909120204051a1176616c69646174696f6e206661696c6564220174';

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('tracer_test'));
  tearDown(() async => dir.delete(recursive: true));

  group('JsonEventTracer, as go-libp2p-pubsub JSONTracer', () {
    test('writes an event as Go does', () async {
      final path = '${dir.path}/trace.json';
      final tracer = JsonEventTracer(filePath: path);
      tracer.trace(_event);
      await tracer.dispose();
      expect(await File(path).readAsString(), '$_goJson\n');
    });

    test('drops events traced after dispose', () async {
      final path = '${dir.path}/trace.json';
      final tracer = JsonEventTracer(filePath: path);
      await tracer.dispose();
      tracer.trace(_event);
      await tracer.stop();
      await tracer.dispose();
      expect(await File(path).readAsString(), isEmpty);
    });
  });

  group('PbEventTracer, as go-libp2p-pubsub PBTracer', () {
    test('writes varint-delimited events as Go does', () async {
      final path = '${dir.path}/trace.pb';
      final tracer = PbEventTracer(filePath: path);
      tracer.trace(_event);
      tracer.trace(_event);
      await tracer.dispose();
      expect(_hex(await File(path).readAsBytes()), _goPbHex * 2);
    });

    test('writes a varint length of more than one byte', () async {
      final path = '${dir.path}/trace.pb';
      final tracer = PbEventTracer(filePath: path);
      final big = pb.TraceEvent()..peerID = List.filled(300, 7);
      tracer.trace(big);
      await tracer.dispose();
      final bytes = await File(path).readAsBytes();
      final length = big.writeToBuffer().length; // 303
      expect(bytes.sublist(0, 2), [(length & 0x7f) | 0x80, length >> 7]);
      expect(bytes.length, 2 + length);
    });

    test('drops events traced after dispose', () async {
      final path = '${dir.path}/trace.pb';
      final tracer = PbEventTracer(filePath: path);
      await tracer.dispose();
      tracer.trace(_event);
      expect(await File(path).readAsBytes(), isEmpty);
    });
  });

  test('events carry the local peer ID and a timestamp, as go-libp2p-pubsub', () async {
    final manager = TestNetworkManager();
    final tracers = <_CapturingTracer>[];
    final pubsubs = <PubSub>[];
    for (var i = 0; i < 2; i++) {
      final keyPair = await generateEd25519KeyPair();
      final peerId = PeerId.fromPublicKey(keyPair.publicKey);
      final host = MockHost(peerId, keyPair.privateKey);
      (host.network as MockNetwork).manager = manager;
      manager.registerNetwork(peerId, host.network as MockNetwork);
      final tracer = _CapturingTracer();
      tracers.add(tracer);
      pubsubs.add(PubSub(host, GossipSubRouter(), privateKey: keyPair.privateKey, tracer: tracer));
    }
    addTearDown(() async {
      for (final p in pubsubs) {
        await p.stop();
      }
    });

    final before = DateTime.now().microsecondsSinceEpoch * 1000;
    for (final p in pubsubs) {
      await p.start();
      p.subscribe('traced');
    }
    await Future.delayed(const Duration(milliseconds: 300));
    await pubsubs[0].publish('traced', Uint8List.fromList([1]));
    await Future.delayed(const Duration(milliseconds: 300));
    final after = DateTime.now().microsecondsSinceEpoch * 1000;

    for (var i = 0; i < 2; i++) {
      final events = tracers[i].events;
      expect(events, isNotEmpty);
      for (final e in events) {
        expect(e.peerID, pubsubs[i].host.id.toBytes(), reason: '${e.type}');
        expect(e.timestamp.toInt(), inInclusiveRange(before, after), reason: '${e.type}');
      }
    }

    final types = tracers[1].events.map((e) => e.type).toSet();
    expect(types, containsAll([pb.TraceEvent_Type.ADD_PEER, pb.TraceEvent_Type.JOIN, pb.TraceEvent_Type.DELIVER_MESSAGE]));
    final recv = tracers[1].events.where((e) => e.type == pb.TraceEvent_Type.RECV_RPC);
    expect(recv.expand((e) => e.recvRPC.meta.subscription.map((s) => s.topic)), contains('traced'));
    expect(recv.expand((e) => e.recvRPC.meta.messages.map((m) => m.topic)), contains('traced'));
    expect(recv.first.recvRPC.receivedFrom, pubsubs[0].host.id.toBytes());
  });
}
