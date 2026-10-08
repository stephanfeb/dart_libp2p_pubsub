//
//  Generated code. Do not modify.
//  source: rpc.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use rPCDescriptor instead')
const RPC$json = {
  '1': 'RPC',
  '2': [
    {'1': 'subscriptions', '3': 1, '4': 3, '5': 11, '6': '.pubsub.pb.RPC.SubOpts', '10': 'subscriptions'},
    {'1': 'publish', '3': 2, '4': 3, '5': 11, '6': '.pubsub.pb.Message', '10': 'publish'},
    {'1': 'control', '3': 3, '4': 1, '5': 11, '6': '.pubsub.pb.ControlMessage', '10': 'control'},
    {'1': 'testExtension', '3': 6492434, '4': 1, '5': 11, '6': '.pubsub.pb.TestExtension', '10': 'testExtension'},
  ],
  '3': [RPC_SubOpts$json],
};

@$core.Deprecated('Use rPCDescriptor instead')
const RPC_SubOpts$json = {
  '1': 'SubOpts',
  '2': [
    {'1': 'subscribe', '3': 1, '4': 1, '5': 8, '10': 'subscribe'},
    {'1': 'topicid', '3': 2, '4': 1, '5': 9, '10': 'topicid'},
  ],
};

/// Descriptor for `RPC`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rPCDescriptor = $convert.base64Decode(
    'CgNSUEMSPAoNc3Vic2NyaXB0aW9ucxgBIAMoCzIWLnB1YnN1Yi5wYi5SUEMuU3ViT3B0c1INc3'
    'Vic2NyaXB0aW9ucxIsCgdwdWJsaXNoGAIgAygLMhIucHVic3ViLnBiLk1lc3NhZ2VSB3B1Ymxp'
    'c2gSMwoHY29udHJvbBgDIAEoCzIZLnB1YnN1Yi5wYi5Db250cm9sTWVzc2FnZVIHY29udHJvbB'
    'JBCg10ZXN0RXh0ZW5zaW9uGJKijAMgASgLMhgucHVic3ViLnBiLlRlc3RFeHRlbnNpb25SDXRl'
    'c3RFeHRlbnNpb24aQQoHU3ViT3B0cxIcCglzdWJzY3JpYmUYASABKAhSCXN1YnNjcmliZRIYCg'
    'd0b3BpY2lkGAIgASgJUgd0b3BpY2lk');

@$core.Deprecated('Use messageDescriptor instead')
const Message$json = {
  '1': 'Message',
  '2': [
    {'1': 'from', '3': 1, '4': 1, '5': 12, '10': 'from'},
    {'1': 'data', '3': 2, '4': 1, '5': 12, '10': 'data'},
    {'1': 'seqno', '3': 3, '4': 1, '5': 12, '10': 'seqno'},
    {'1': 'topic', '3': 4, '4': 1, '5': 9, '10': 'topic'},
    {'1': 'signature', '3': 5, '4': 1, '5': 12, '10': 'signature'},
    {'1': 'key', '3': 6, '4': 1, '5': 12, '10': 'key'},
  ],
};

/// Descriptor for `Message`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List messageDescriptor = $convert.base64Decode(
    'CgdNZXNzYWdlEhIKBGZyb20YASABKAxSBGZyb20SEgoEZGF0YRgCIAEoDFIEZGF0YRIUCgVzZX'
    'FubxgDIAEoDFIFc2Vxbm8SFAoFdG9waWMYBCABKAlSBXRvcGljEhwKCXNpZ25hdHVyZRgFIAEo'
    'DFIJc2lnbmF0dXJlEhAKA2tleRgGIAEoDFIDa2V5');

@$core.Deprecated('Use controlMessageDescriptor instead')
const ControlMessage$json = {
  '1': 'ControlMessage',
  '2': [
    {'1': 'ihave', '3': 1, '4': 3, '5': 11, '6': '.pubsub.pb.ControlIHave', '10': 'ihave'},
    {'1': 'iwant', '3': 2, '4': 3, '5': 11, '6': '.pubsub.pb.ControlIWant', '10': 'iwant'},
    {'1': 'graft', '3': 3, '4': 3, '5': 11, '6': '.pubsub.pb.ControlGraft', '10': 'graft'},
    {'1': 'prune', '3': 4, '4': 3, '5': 11, '6': '.pubsub.pb.ControlPrune', '10': 'prune'},
    {'1': 'idontwant', '3': 5, '4': 3, '5': 11, '6': '.pubsub.pb.ControlIDontWant', '10': 'idontwant'},
    {'1': 'extensions', '3': 6, '4': 1, '5': 11, '6': '.pubsub.pb.ControlExtensions', '10': 'extensions'},
  ],
};

/// Descriptor for `ControlMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List controlMessageDescriptor = $convert.base64Decode(
    'Cg5Db250cm9sTWVzc2FnZRItCgVpaGF2ZRgBIAMoCzIXLnB1YnN1Yi5wYi5Db250cm9sSUhhdm'
    'VSBWloYXZlEi0KBWl3YW50GAIgAygLMhcucHVic3ViLnBiLkNvbnRyb2xJV2FudFIFaXdhbnQS'
    'LQoFZ3JhZnQYAyADKAsyFy5wdWJzdWIucGIuQ29udHJvbEdyYWZ0UgVncmFmdBItCgVwcnVuZR'
    'gEIAMoCzIXLnB1YnN1Yi5wYi5Db250cm9sUHJ1bmVSBXBydW5lEjkKCWlkb250d2FudBgFIAMo'
    'CzIbLnB1YnN1Yi5wYi5Db250cm9sSURvbnRXYW50UglpZG9udHdhbnQSPAoKZXh0ZW5zaW9ucx'
    'gGIAEoCzIcLnB1YnN1Yi5wYi5Db250cm9sRXh0ZW5zaW9uc1IKZXh0ZW5zaW9ucw==');

@$core.Deprecated('Use controlIHaveDescriptor instead')
const ControlIHave$json = {
  '1': 'ControlIHave',
  '2': [
    {'1': 'topicID', '3': 1, '4': 1, '5': 9, '10': 'topicID'},
    {'1': 'messageIDs', '3': 2, '4': 3, '5': 12, '10': 'messageIDs'},
  ],
};

/// Descriptor for `ControlIHave`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List controlIHaveDescriptor = $convert.base64Decode(
    'CgxDb250cm9sSUhhdmUSGAoHdG9waWNJRBgBIAEoCVIHdG9waWNJRBIeCgptZXNzYWdlSURzGA'
    'IgAygMUgptZXNzYWdlSURz');

@$core.Deprecated('Use controlIWantDescriptor instead')
const ControlIWant$json = {
  '1': 'ControlIWant',
  '2': [
    {'1': 'messageIDs', '3': 1, '4': 3, '5': 12, '10': 'messageIDs'},
  ],
};

/// Descriptor for `ControlIWant`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List controlIWantDescriptor = $convert.base64Decode(
    'CgxDb250cm9sSVdhbnQSHgoKbWVzc2FnZUlEcxgBIAMoDFIKbWVzc2FnZUlEcw==');

@$core.Deprecated('Use controlGraftDescriptor instead')
const ControlGraft$json = {
  '1': 'ControlGraft',
  '2': [
    {'1': 'topicID', '3': 1, '4': 1, '5': 9, '10': 'topicID'},
  ],
};

/// Descriptor for `ControlGraft`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List controlGraftDescriptor = $convert.base64Decode(
    'CgxDb250cm9sR3JhZnQSGAoHdG9waWNJRBgBIAEoCVIHdG9waWNJRA==');

@$core.Deprecated('Use controlPruneDescriptor instead')
const ControlPrune$json = {
  '1': 'ControlPrune',
  '2': [
    {'1': 'topicID', '3': 1, '4': 1, '5': 9, '10': 'topicID'},
    {'1': 'peers', '3': 2, '4': 3, '5': 11, '6': '.pubsub.pb.PeerInfo', '10': 'peers'},
    {'1': 'backoff', '3': 3, '4': 1, '5': 4, '10': 'backoff'},
  ],
};

/// Descriptor for `ControlPrune`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List controlPruneDescriptor = $convert.base64Decode(
    'CgxDb250cm9sUHJ1bmUSGAoHdG9waWNJRBgBIAEoCVIHdG9waWNJRBIpCgVwZWVycxgCIAMoCz'
    'ITLnB1YnN1Yi5wYi5QZWVySW5mb1IFcGVlcnMSGAoHYmFja29mZhgDIAEoBFIHYmFja29mZg==');

@$core.Deprecated('Use controlIDontWantDescriptor instead')
const ControlIDontWant$json = {
  '1': 'ControlIDontWant',
  '2': [
    {'1': 'messageIDs', '3': 1, '4': 3, '5': 12, '10': 'messageIDs'},
  ],
};

/// Descriptor for `ControlIDontWant`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List controlIDontWantDescriptor = $convert.base64Decode(
    'ChBDb250cm9sSURvbnRXYW50Eh4KCm1lc3NhZ2VJRHMYASADKAxSCm1lc3NhZ2VJRHM=');

@$core.Deprecated('Use controlExtensionsDescriptor instead')
const ControlExtensions$json = {
  '1': 'ControlExtensions',
  '2': [
    {'1': 'testExtension', '3': 6492434, '4': 1, '5': 8, '10': 'testExtension'},
  ],
};

/// Descriptor for `ControlExtensions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List controlExtensionsDescriptor = $convert.base64Decode(
    'ChFDb250cm9sRXh0ZW5zaW9ucxInCg10ZXN0RXh0ZW5zaW9uGJKijAMgASgIUg10ZXN0RXh0ZW'
    '5zaW9u');

@$core.Deprecated('Use peerInfoDescriptor instead')
const PeerInfo$json = {
  '1': 'PeerInfo',
  '2': [
    {'1': 'peerID', '3': 1, '4': 1, '5': 12, '10': 'peerID'},
    {'1': 'signedPeerRecord', '3': 2, '4': 1, '5': 12, '10': 'signedPeerRecord'},
  ],
};

/// Descriptor for `PeerInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List peerInfoDescriptor = $convert.base64Decode(
    'CghQZWVySW5mbxIWCgZwZWVySUQYASABKAxSBnBlZXJJRBIqChBzaWduZWRQZWVyUmVjb3JkGA'
    'IgASgMUhBzaWduZWRQZWVyUmVjb3Jk');

@$core.Deprecated('Use testExtensionDescriptor instead')
const TestExtension$json = {
  '1': 'TestExtension',
};

/// Descriptor for `TestExtension`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List testExtensionDescriptor = $convert.base64Decode(
    'Cg1UZXN0RXh0ZW5zaW9u');

