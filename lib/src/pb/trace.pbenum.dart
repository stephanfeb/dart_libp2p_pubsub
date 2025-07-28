//
//  Generated code. Do not modify.
//  source: trace.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class TraceEvent_Type extends $pb.ProtobufEnum {
  static const TraceEvent_Type PUBLISH_MESSAGE = TraceEvent_Type._(0, _omitEnumNames ? '' : 'PUBLISH_MESSAGE');
  static const TraceEvent_Type REJECT_MESSAGE = TraceEvent_Type._(1, _omitEnumNames ? '' : 'REJECT_MESSAGE');
  static const TraceEvent_Type DUPLICATE_MESSAGE = TraceEvent_Type._(2, _omitEnumNames ? '' : 'DUPLICATE_MESSAGE');
  static const TraceEvent_Type DELIVER_MESSAGE = TraceEvent_Type._(3, _omitEnumNames ? '' : 'DELIVER_MESSAGE');
  static const TraceEvent_Type ADD_PEER = TraceEvent_Type._(4, _omitEnumNames ? '' : 'ADD_PEER');
  static const TraceEvent_Type REMOVE_PEER = TraceEvent_Type._(5, _omitEnumNames ? '' : 'REMOVE_PEER');
  static const TraceEvent_Type RECV_RPC = TraceEvent_Type._(6, _omitEnumNames ? '' : 'RECV_RPC');
  static const TraceEvent_Type SEND_RPC = TraceEvent_Type._(7, _omitEnumNames ? '' : 'SEND_RPC');
  static const TraceEvent_Type DROP_RPC = TraceEvent_Type._(8, _omitEnumNames ? '' : 'DROP_RPC');
  static const TraceEvent_Type JOIN = TraceEvent_Type._(9, _omitEnumNames ? '' : 'JOIN');
  static const TraceEvent_Type LEAVE = TraceEvent_Type._(10, _omitEnumNames ? '' : 'LEAVE');
  static const TraceEvent_Type GRAFT = TraceEvent_Type._(11, _omitEnumNames ? '' : 'GRAFT');
  static const TraceEvent_Type PRUNE = TraceEvent_Type._(12, _omitEnumNames ? '' : 'PRUNE');

  static const $core.List<TraceEvent_Type> values = <TraceEvent_Type> [
    PUBLISH_MESSAGE,
    REJECT_MESSAGE,
    DUPLICATE_MESSAGE,
    DELIVER_MESSAGE,
    ADD_PEER,
    REMOVE_PEER,
    RECV_RPC,
    SEND_RPC,
    DROP_RPC,
    JOIN,
    LEAVE,
    GRAFT,
    PRUNE,
  ];

  static final $core.Map<$core.int, TraceEvent_Type> _byValue = $pb.ProtobufEnum.initByValue(values);
  static TraceEvent_Type? valueOf($core.int value) => _byValue[value];

  const TraceEvent_Type._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
