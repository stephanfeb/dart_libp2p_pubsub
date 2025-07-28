//
//  Generated code. Do not modify.
//  source: trace.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent$json = {
  '1': 'TraceEvent',
  '2': [
    {'1': 'type', '3': 1, '4': 1, '5': 14, '6': '.pubsub.pb.TraceEvent.Type', '10': 'type'},
    {'1': 'peerID', '3': 2, '4': 1, '5': 12, '10': 'peerID'},
    {'1': 'timestamp', '3': 3, '4': 1, '5': 3, '10': 'timestamp'},
    {'1': 'publishMessage', '3': 4, '4': 1, '5': 11, '6': '.pubsub.pb.TraceEvent.PublishMessage', '10': 'publishMessage'},
    {'1': 'rejectMessage', '3': 5, '4': 1, '5': 11, '6': '.pubsub.pb.TraceEvent.RejectMessage', '10': 'rejectMessage'},
    {'1': 'duplicateMessage', '3': 6, '4': 1, '5': 11, '6': '.pubsub.pb.TraceEvent.DuplicateMessage', '10': 'duplicateMessage'},
    {'1': 'deliverMessage', '3': 7, '4': 1, '5': 11, '6': '.pubsub.pb.TraceEvent.DeliverMessage', '10': 'deliverMessage'},
    {'1': 'addPeer', '3': 8, '4': 1, '5': 11, '6': '.pubsub.pb.TraceEvent.AddPeer', '10': 'addPeer'},
    {'1': 'removePeer', '3': 9, '4': 1, '5': 11, '6': '.pubsub.pb.TraceEvent.RemovePeer', '10': 'removePeer'},
    {'1': 'recvRPC', '3': 10, '4': 1, '5': 11, '6': '.pubsub.pb.TraceEvent.RecvRPC', '10': 'recvRPC'},
    {'1': 'sendRPC', '3': 11, '4': 1, '5': 11, '6': '.pubsub.pb.TraceEvent.SendRPC', '10': 'sendRPC'},
    {'1': 'dropRPC', '3': 12, '4': 1, '5': 11, '6': '.pubsub.pb.TraceEvent.DropRPC', '10': 'dropRPC'},
    {'1': 'join', '3': 13, '4': 1, '5': 11, '6': '.pubsub.pb.TraceEvent.Join', '10': 'join'},
    {'1': 'leave', '3': 14, '4': 1, '5': 11, '6': '.pubsub.pb.TraceEvent.Leave', '10': 'leave'},
    {'1': 'graft', '3': 15, '4': 1, '5': 11, '6': '.pubsub.pb.TraceEvent.Graft', '10': 'graft'},
    {'1': 'prune', '3': 16, '4': 1, '5': 11, '6': '.pubsub.pb.TraceEvent.Prune', '10': 'prune'},
  ],
  '3': [TraceEvent_PublishMessage$json, TraceEvent_RejectMessage$json, TraceEvent_DuplicateMessage$json, TraceEvent_DeliverMessage$json, TraceEvent_AddPeer$json, TraceEvent_RemovePeer$json, TraceEvent_RecvRPC$json, TraceEvent_SendRPC$json, TraceEvent_DropRPC$json, TraceEvent_Join$json, TraceEvent_Leave$json, TraceEvent_Graft$json, TraceEvent_Prune$json, TraceEvent_RPCMeta$json, TraceEvent_MessageMeta$json, TraceEvent_SubMeta$json, TraceEvent_ControlMeta$json, TraceEvent_ControlIHaveMeta$json, TraceEvent_ControlIWantMeta$json, TraceEvent_ControlGraftMeta$json, TraceEvent_ControlPruneMeta$json, TraceEvent_ControlIDontWantMeta$json],
  '4': [TraceEvent_Type$json],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_PublishMessage$json = {
  '1': 'PublishMessage',
  '2': [
    {'1': 'messageID', '3': 1, '4': 1, '5': 12, '10': 'messageID'},
    {'1': 'topic', '3': 2, '4': 1, '5': 9, '10': 'topic'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_RejectMessage$json = {
  '1': 'RejectMessage',
  '2': [
    {'1': 'messageID', '3': 1, '4': 1, '5': 12, '10': 'messageID'},
    {'1': 'receivedFrom', '3': 2, '4': 1, '5': 12, '10': 'receivedFrom'},
    {'1': 'reason', '3': 3, '4': 1, '5': 9, '10': 'reason'},
    {'1': 'topic', '3': 4, '4': 1, '5': 9, '10': 'topic'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_DuplicateMessage$json = {
  '1': 'DuplicateMessage',
  '2': [
    {'1': 'messageID', '3': 1, '4': 1, '5': 12, '10': 'messageID'},
    {'1': 'receivedFrom', '3': 2, '4': 1, '5': 12, '10': 'receivedFrom'},
    {'1': 'topic', '3': 3, '4': 1, '5': 9, '10': 'topic'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_DeliverMessage$json = {
  '1': 'DeliverMessage',
  '2': [
    {'1': 'messageID', '3': 1, '4': 1, '5': 12, '10': 'messageID'},
    {'1': 'topic', '3': 2, '4': 1, '5': 9, '10': 'topic'},
    {'1': 'receivedFrom', '3': 3, '4': 1, '5': 12, '10': 'receivedFrom'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_AddPeer$json = {
  '1': 'AddPeer',
  '2': [
    {'1': 'peerID', '3': 1, '4': 1, '5': 12, '10': 'peerID'},
    {'1': 'proto', '3': 2, '4': 1, '5': 9, '10': 'proto'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_RemovePeer$json = {
  '1': 'RemovePeer',
  '2': [
    {'1': 'peerID', '3': 1, '4': 1, '5': 12, '10': 'peerID'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_RecvRPC$json = {
  '1': 'RecvRPC',
  '2': [
    {'1': 'receivedFrom', '3': 1, '4': 1, '5': 12, '10': 'receivedFrom'},
    {'1': 'meta', '3': 2, '4': 1, '5': 11, '6': '.pubsub.pb.TraceEvent.RPCMeta', '10': 'meta'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_SendRPC$json = {
  '1': 'SendRPC',
  '2': [
    {'1': 'sendTo', '3': 1, '4': 1, '5': 12, '10': 'sendTo'},
    {'1': 'meta', '3': 2, '4': 1, '5': 11, '6': '.pubsub.pb.TraceEvent.RPCMeta', '10': 'meta'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_DropRPC$json = {
  '1': 'DropRPC',
  '2': [
    {'1': 'sendTo', '3': 1, '4': 1, '5': 12, '10': 'sendTo'},
    {'1': 'meta', '3': 2, '4': 1, '5': 11, '6': '.pubsub.pb.TraceEvent.RPCMeta', '10': 'meta'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_Join$json = {
  '1': 'Join',
  '2': [
    {'1': 'topic', '3': 1, '4': 1, '5': 9, '10': 'topic'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_Leave$json = {
  '1': 'Leave',
  '2': [
    {'1': 'topic', '3': 2, '4': 1, '5': 9, '10': 'topic'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_Graft$json = {
  '1': 'Graft',
  '2': [
    {'1': 'peerID', '3': 1, '4': 1, '5': 12, '10': 'peerID'},
    {'1': 'topic', '3': 2, '4': 1, '5': 9, '10': 'topic'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_Prune$json = {
  '1': 'Prune',
  '2': [
    {'1': 'peerID', '3': 1, '4': 1, '5': 12, '10': 'peerID'},
    {'1': 'topic', '3': 2, '4': 1, '5': 9, '10': 'topic'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_RPCMeta$json = {
  '1': 'RPCMeta',
  '2': [
    {'1': 'messages', '3': 1, '4': 3, '5': 11, '6': '.pubsub.pb.TraceEvent.MessageMeta', '10': 'messages'},
    {'1': 'subscription', '3': 2, '4': 3, '5': 11, '6': '.pubsub.pb.TraceEvent.SubMeta', '10': 'subscription'},
    {'1': 'control', '3': 3, '4': 1, '5': 11, '6': '.pubsub.pb.TraceEvent.ControlMeta', '10': 'control'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_MessageMeta$json = {
  '1': 'MessageMeta',
  '2': [
    {'1': 'messageID', '3': 1, '4': 1, '5': 12, '10': 'messageID'},
    {'1': 'topic', '3': 2, '4': 1, '5': 9, '10': 'topic'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_SubMeta$json = {
  '1': 'SubMeta',
  '2': [
    {'1': 'subscribe', '3': 1, '4': 1, '5': 8, '10': 'subscribe'},
    {'1': 'topic', '3': 2, '4': 1, '5': 9, '10': 'topic'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_ControlMeta$json = {
  '1': 'ControlMeta',
  '2': [
    {'1': 'ihave', '3': 1, '4': 3, '5': 11, '6': '.pubsub.pb.TraceEvent.ControlIHaveMeta', '10': 'ihave'},
    {'1': 'iwant', '3': 2, '4': 3, '5': 11, '6': '.pubsub.pb.TraceEvent.ControlIWantMeta', '10': 'iwant'},
    {'1': 'graft', '3': 3, '4': 3, '5': 11, '6': '.pubsub.pb.TraceEvent.ControlGraftMeta', '10': 'graft'},
    {'1': 'prune', '3': 4, '4': 3, '5': 11, '6': '.pubsub.pb.TraceEvent.ControlPruneMeta', '10': 'prune'},
    {'1': 'idontwant', '3': 5, '4': 3, '5': 11, '6': '.pubsub.pb.TraceEvent.ControlIDontWantMeta', '10': 'idontwant'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_ControlIHaveMeta$json = {
  '1': 'ControlIHaveMeta',
  '2': [
    {'1': 'topic', '3': 1, '4': 1, '5': 9, '10': 'topic'},
    {'1': 'messageIDs', '3': 2, '4': 3, '5': 12, '10': 'messageIDs'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_ControlIWantMeta$json = {
  '1': 'ControlIWantMeta',
  '2': [
    {'1': 'messageIDs', '3': 1, '4': 3, '5': 12, '10': 'messageIDs'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_ControlGraftMeta$json = {
  '1': 'ControlGraftMeta',
  '2': [
    {'1': 'topic', '3': 1, '4': 1, '5': 9, '10': 'topic'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_ControlPruneMeta$json = {
  '1': 'ControlPruneMeta',
  '2': [
    {'1': 'topic', '3': 1, '4': 1, '5': 9, '10': 'topic'},
    {'1': 'peers', '3': 2, '4': 3, '5': 12, '10': 'peers'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_ControlIDontWantMeta$json = {
  '1': 'ControlIDontWantMeta',
  '2': [
    {'1': 'messageIDs', '3': 1, '4': 3, '5': 12, '10': 'messageIDs'},
  ],
};

@$core.Deprecated('Use traceEventDescriptor instead')
const TraceEvent_Type$json = {
  '1': 'Type',
  '2': [
    {'1': 'PUBLISH_MESSAGE', '2': 0},
    {'1': 'REJECT_MESSAGE', '2': 1},
    {'1': 'DUPLICATE_MESSAGE', '2': 2},
    {'1': 'DELIVER_MESSAGE', '2': 3},
    {'1': 'ADD_PEER', '2': 4},
    {'1': 'REMOVE_PEER', '2': 5},
    {'1': 'RECV_RPC', '2': 6},
    {'1': 'SEND_RPC', '2': 7},
    {'1': 'DROP_RPC', '2': 8},
    {'1': 'JOIN', '2': 9},
    {'1': 'LEAVE', '2': 10},
    {'1': 'GRAFT', '2': 11},
    {'1': 'PRUNE', '2': 12},
  ],
};

/// Descriptor for `TraceEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List traceEventDescriptor = $convert.base64Decode(
    'CgpUcmFjZUV2ZW50Ei4KBHR5cGUYASABKA4yGi5wdWJzdWIucGIuVHJhY2VFdmVudC5UeXBlUg'
    'R0eXBlEhYKBnBlZXJJRBgCIAEoDFIGcGVlcklEEhwKCXRpbWVzdGFtcBgDIAEoA1IJdGltZXN0'
    'YW1wEkwKDnB1Ymxpc2hNZXNzYWdlGAQgASgLMiQucHVic3ViLnBiLlRyYWNlRXZlbnQuUHVibG'
    'lzaE1lc3NhZ2VSDnB1Ymxpc2hNZXNzYWdlEkkKDXJlamVjdE1lc3NhZ2UYBSABKAsyIy5wdWJz'
    'dWIucGIuVHJhY2VFdmVudC5SZWplY3RNZXNzYWdlUg1yZWplY3RNZXNzYWdlElIKEGR1cGxpY2'
    'F0ZU1lc3NhZ2UYBiABKAsyJi5wdWJzdWIucGIuVHJhY2VFdmVudC5EdXBsaWNhdGVNZXNzYWdl'
    'UhBkdXBsaWNhdGVNZXNzYWdlEkwKDmRlbGl2ZXJNZXNzYWdlGAcgASgLMiQucHVic3ViLnBiLl'
    'RyYWNlRXZlbnQuRGVsaXZlck1lc3NhZ2VSDmRlbGl2ZXJNZXNzYWdlEjcKB2FkZFBlZXIYCCAB'
    'KAsyHS5wdWJzdWIucGIuVHJhY2VFdmVudC5BZGRQZWVyUgdhZGRQZWVyEkAKCnJlbW92ZVBlZX'
    'IYCSABKAsyIC5wdWJzdWIucGIuVHJhY2VFdmVudC5SZW1vdmVQZWVyUgpyZW1vdmVQZWVyEjcK'
    'B3JlY3ZSUEMYCiABKAsyHS5wdWJzdWIucGIuVHJhY2VFdmVudC5SZWN2UlBDUgdyZWN2UlBDEj'
    'cKB3NlbmRSUEMYCyABKAsyHS5wdWJzdWIucGIuVHJhY2VFdmVudC5TZW5kUlBDUgdzZW5kUlBD'
    'EjcKB2Ryb3BSUEMYDCABKAsyHS5wdWJzdWIucGIuVHJhY2VFdmVudC5Ecm9wUlBDUgdkcm9wUl'
    'BDEi4KBGpvaW4YDSABKAsyGi5wdWJzdWIucGIuVHJhY2VFdmVudC5Kb2luUgRqb2luEjEKBWxl'
    'YXZlGA4gASgLMhsucHVic3ViLnBiLlRyYWNlRXZlbnQuTGVhdmVSBWxlYXZlEjEKBWdyYWZ0GA'
    '8gASgLMhsucHVic3ViLnBiLlRyYWNlRXZlbnQuR3JhZnRSBWdyYWZ0EjEKBXBydW5lGBAgASgL'
    'MhsucHVic3ViLnBiLlRyYWNlRXZlbnQuUHJ1bmVSBXBydW5lGkQKDlB1Ymxpc2hNZXNzYWdlEh'
    'wKCW1lc3NhZ2VJRBgBIAEoDFIJbWVzc2FnZUlEEhQKBXRvcGljGAIgASgJUgV0b3BpYxp/Cg1S'
    'ZWplY3RNZXNzYWdlEhwKCW1lc3NhZ2VJRBgBIAEoDFIJbWVzc2FnZUlEEiIKDHJlY2VpdmVkRn'
    'JvbRgCIAEoDFIMcmVjZWl2ZWRGcm9tEhYKBnJlYXNvbhgDIAEoCVIGcmVhc29uEhQKBXRvcGlj'
    'GAQgASgJUgV0b3BpYxpqChBEdXBsaWNhdGVNZXNzYWdlEhwKCW1lc3NhZ2VJRBgBIAEoDFIJbW'
    'Vzc2FnZUlEEiIKDHJlY2VpdmVkRnJvbRgCIAEoDFIMcmVjZWl2ZWRGcm9tEhQKBXRvcGljGAMg'
    'ASgJUgV0b3BpYxpoCg5EZWxpdmVyTWVzc2FnZRIcCgltZXNzYWdlSUQYASABKAxSCW1lc3NhZ2'
    'VJRBIUCgV0b3BpYxgCIAEoCVIFdG9waWMSIgoMcmVjZWl2ZWRGcm9tGAMgASgMUgxyZWNlaXZl'
    'ZEZyb20aNwoHQWRkUGVlchIWCgZwZWVySUQYASABKAxSBnBlZXJJRBIUCgVwcm90bxgCIAEoCV'
    'IFcHJvdG8aJAoKUmVtb3ZlUGVlchIWCgZwZWVySUQYASABKAxSBnBlZXJJRBpgCgdSZWN2UlBD'
    'EiIKDHJlY2VpdmVkRnJvbRgBIAEoDFIMcmVjZWl2ZWRGcm9tEjEKBG1ldGEYAiABKAsyHS5wdW'
    'JzdWIucGIuVHJhY2VFdmVudC5SUENNZXRhUgRtZXRhGlQKB1NlbmRSUEMSFgoGc2VuZFRvGAEg'
    'ASgMUgZzZW5kVG8SMQoEbWV0YRgCIAEoCzIdLnB1YnN1Yi5wYi5UcmFjZUV2ZW50LlJQQ01ldG'
    'FSBG1ldGEaVAoHRHJvcFJQQxIWCgZzZW5kVG8YASABKAxSBnNlbmRUbxIxCgRtZXRhGAIgASgL'
    'Mh0ucHVic3ViLnBiLlRyYWNlRXZlbnQuUlBDTWV0YVIEbWV0YRocCgRKb2luEhQKBXRvcGljGA'
    'EgASgJUgV0b3BpYxodCgVMZWF2ZRIUCgV0b3BpYxgCIAEoCVIFdG9waWMaNQoFR3JhZnQSFgoG'
    'cGVlcklEGAEgASgMUgZwZWVySUQSFAoFdG9waWMYAiABKAlSBXRvcGljGjUKBVBydW5lEhYKBn'
    'BlZXJJRBgBIAEoDFIGcGVlcklEEhQKBXRvcGljGAIgASgJUgV0b3BpYxrIAQoHUlBDTWV0YRI9'
    'CghtZXNzYWdlcxgBIAMoCzIhLnB1YnN1Yi5wYi5UcmFjZUV2ZW50Lk1lc3NhZ2VNZXRhUghtZX'
    'NzYWdlcxJBCgxzdWJzY3JpcHRpb24YAiADKAsyHS5wdWJzdWIucGIuVHJhY2VFdmVudC5TdWJN'
    'ZXRhUgxzdWJzY3JpcHRpb24SOwoHY29udHJvbBgDIAEoCzIhLnB1YnN1Yi5wYi5UcmFjZUV2ZW'
    '50LkNvbnRyb2xNZXRhUgdjb250cm9sGkEKC01lc3NhZ2VNZXRhEhwKCW1lc3NhZ2VJRBgBIAEo'
    'DFIJbWVzc2FnZUlEEhQKBXRvcGljGAIgASgJUgV0b3BpYxo9CgdTdWJNZXRhEhwKCXN1YnNjcm'
    'liZRgBIAEoCFIJc3Vic2NyaWJlEhQKBXRvcGljGAIgASgJUgV0b3BpYxrPAgoLQ29udHJvbE1l'
    'dGESPAoFaWhhdmUYASADKAsyJi5wdWJzdWIucGIuVHJhY2VFdmVudC5Db250cm9sSUhhdmVNZX'
    'RhUgVpaGF2ZRI8CgVpd2FudBgCIAMoCzImLnB1YnN1Yi5wYi5UcmFjZUV2ZW50LkNvbnRyb2xJ'
    'V2FudE1ldGFSBWl3YW50EjwKBWdyYWZ0GAMgAygLMiYucHVic3ViLnBiLlRyYWNlRXZlbnQuQ2'
    '9udHJvbEdyYWZ0TWV0YVIFZ3JhZnQSPAoFcHJ1bmUYBCADKAsyJi5wdWJzdWIucGIuVHJhY2VF'
    'dmVudC5Db250cm9sUHJ1bmVNZXRhUgVwcnVuZRJICglpZG9udHdhbnQYBSADKAsyKi5wdWJzdW'
    'IucGIuVHJhY2VFdmVudC5Db250cm9sSURvbnRXYW50TWV0YVIJaWRvbnR3YW50GkgKEENvbnRy'
    'b2xJSGF2ZU1ldGESFAoFdG9waWMYASABKAlSBXRvcGljEh4KCm1lc3NhZ2VJRHMYAiADKAxSCm'
    '1lc3NhZ2VJRHMaMgoQQ29udHJvbElXYW50TWV0YRIeCgptZXNzYWdlSURzGAEgAygMUgptZXNz'
    'YWdlSURzGigKEENvbnRyb2xHcmFmdE1ldGESFAoFdG9waWMYASABKAlSBXRvcGljGj4KEENvbn'
    'Ryb2xQcnVuZU1ldGESFAoFdG9waWMYASABKAlSBXRvcGljEhQKBXBlZXJzGAIgAygMUgVwZWVy'
    'cxo2ChRDb250cm9sSURvbnRXYW50TWV0YRIeCgptZXNzYWdlSURzGAEgAygMUgptZXNzYWdlSU'
    'RzIs8BCgRUeXBlEhMKD1BVQkxJU0hfTUVTU0FHRRAAEhIKDlJFSkVDVF9NRVNTQUdFEAESFQoR'
    'RFVQTElDQVRFX01FU1NBR0UQAhITCg9ERUxJVkVSX01FU1NBR0UQAxIMCghBRERfUEVFUhAEEg'
    '8KC1JFTU9WRV9QRUVSEAUSDAoIUkVDVl9SUEMQBhIMCghTRU5EX1JQQxAHEgwKCERST1BfUlBD'
    'EAgSCAoESk9JThAJEgkKBUxFQVZFEAoSCQoFR1JBRlQQCxIJCgVQUlVORRAM');

@$core.Deprecated('Use traceEventBatchDescriptor instead')
const TraceEventBatch$json = {
  '1': 'TraceEventBatch',
  '2': [
    {'1': 'batch', '3': 1, '4': 3, '5': 11, '6': '.pubsub.pb.TraceEvent', '10': 'batch'},
  ],
};

/// Descriptor for `TraceEventBatch`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List traceEventBatchDescriptor = $convert.base64Decode(
    'Cg9UcmFjZUV2ZW50QmF0Y2gSKwoFYmF0Y2gYASADKAsyFS5wdWJzdWIucGIuVHJhY2VFdmVudF'
    'IFYmF0Y2g=');

