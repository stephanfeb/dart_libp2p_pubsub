import 'dart:typed_data';

import 'package:dart_libp2p_pubsub/src/pb/rpc.pb.dart' as pb;
import 'package:dart_libp2p_pubsub/src/util/midgen.dart';
import 'package:test/test.dart';

void main() {
  group('message IDs', () {
    test('the default ID is the bytes of from followed by seqno, as Go DefaultMsgIdFn', () {
      final msg = pb.Message()
        ..from = [0x00, 0x24, 0x08, 0x01, 0xff]
        ..seqno = [0x18, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01];
      expect(messageIdToBytes(defaultMessageIdFn(msg)),
          equals([0x00, 0x24, 0x08, 0x01, 0xff, 0x18, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01]));
    });

    test('IDs that are not valid UTF-8 survive the wire unchanged', () {
      final id = messageIdFromBytes([0x00, 0xff, 0x80, 0xc3, 0x28]);
      final rpc = pb.RPC()
        ..control = (pb.ControlMessage()
          ..ihave.add(pb.ControlIHave()
            ..topicID = 't'
            ..messageIDs.add(messageIdToBytes(id)))
          ..iwant.add(pb.ControlIWant()..messageIDs.add(messageIdToBytes(id)))
          ..idontwant.add(pb.ControlIDontWant()..messageIDs.add(messageIdToBytes(id))));
      final decoded = pb.RPC.fromBuffer(rpc.writeToBuffer());
      expect(messageIdFromBytes(decoded.control.ihave.single.messageIDs.single), equals(id));
      expect(messageIdFromBytes(decoded.control.iwant.single.messageIDs.single), equals(id));
      expect(messageIdFromBytes(decoded.control.idontwant.single.messageIDs.single), equals(id));
    });

    test('messageIDs is wire-compatible with a proto string field', () {
      // An IHAVE whose messageIDs field holds the raw bytes, as Go's
      // `repeated string` field is encoded: tag 2, wire type 2.
      final raw = Uint8List.fromList([0x0a, 0x01, 0x74, 0x12, 0x02, 0xff, 0x00]);
      final ihave = pb.ControlIHave.fromBuffer(raw);
      expect(ihave.topicID, 't');
      expect(ihave.messageIDs.single, equals([0xff, 0x00]));
      expect(ihave.writeToBuffer(), equals(raw));
    });

    test('an ID with characters above 0xff is UTF-8 encoded', () {
      expect(normalizeMessageId('é'), equals('é')); // U+00E9 is one byte
      expect(messageIdToBytes('€'), equals([0xe2, 0x82, 0xac]));
    });
  });
}
