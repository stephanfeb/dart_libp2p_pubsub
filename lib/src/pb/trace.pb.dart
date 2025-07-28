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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'trace.pbenum.dart';

export 'trace.pbenum.dart';

class TraceEvent_PublishMessage extends $pb.GeneratedMessage {
  factory TraceEvent_PublishMessage() => create();
  TraceEvent_PublishMessage._() : super();
  factory TraceEvent_PublishMessage.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_PublishMessage.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.PublishMessage', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'messageID', $pb.PbFieldType.OY, protoName: 'messageID')
    ..aOS(2, _omitFieldNames ? '' : 'topic')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_PublishMessage clone() => TraceEvent_PublishMessage()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_PublishMessage copyWith(void Function(TraceEvent_PublishMessage) updates) => super.copyWith((message) => updates(message as TraceEvent_PublishMessage)) as TraceEvent_PublishMessage;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_PublishMessage create() => TraceEvent_PublishMessage._();
  TraceEvent_PublishMessage createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_PublishMessage> createRepeated() => $pb.PbList<TraceEvent_PublishMessage>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_PublishMessage getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_PublishMessage>(create);
  static TraceEvent_PublishMessage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get messageID => $_getN(0);
  @$pb.TagNumber(1)
  set messageID($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMessageID() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessageID() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get topic => $_getSZ(1);
  @$pb.TagNumber(2)
  set topic($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTopic() => $_has(1);
  @$pb.TagNumber(2)
  void clearTopic() => clearField(2);
}

class TraceEvent_RejectMessage extends $pb.GeneratedMessage {
  factory TraceEvent_RejectMessage() => create();
  TraceEvent_RejectMessage._() : super();
  factory TraceEvent_RejectMessage.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_RejectMessage.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.RejectMessage', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'messageID', $pb.PbFieldType.OY, protoName: 'messageID')
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'receivedFrom', $pb.PbFieldType.OY, protoName: 'receivedFrom')
    ..aOS(3, _omitFieldNames ? '' : 'reason')
    ..aOS(4, _omitFieldNames ? '' : 'topic')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_RejectMessage clone() => TraceEvent_RejectMessage()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_RejectMessage copyWith(void Function(TraceEvent_RejectMessage) updates) => super.copyWith((message) => updates(message as TraceEvent_RejectMessage)) as TraceEvent_RejectMessage;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_RejectMessage create() => TraceEvent_RejectMessage._();
  TraceEvent_RejectMessage createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_RejectMessage> createRepeated() => $pb.PbList<TraceEvent_RejectMessage>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_RejectMessage getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_RejectMessage>(create);
  static TraceEvent_RejectMessage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get messageID => $_getN(0);
  @$pb.TagNumber(1)
  set messageID($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMessageID() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessageID() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get receivedFrom => $_getN(1);
  @$pb.TagNumber(2)
  set receivedFrom($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasReceivedFrom() => $_has(1);
  @$pb.TagNumber(2)
  void clearReceivedFrom() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get reason => $_getSZ(2);
  @$pb.TagNumber(3)
  set reason($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasReason() => $_has(2);
  @$pb.TagNumber(3)
  void clearReason() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get topic => $_getSZ(3);
  @$pb.TagNumber(4)
  set topic($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTopic() => $_has(3);
  @$pb.TagNumber(4)
  void clearTopic() => clearField(4);
}

class TraceEvent_DuplicateMessage extends $pb.GeneratedMessage {
  factory TraceEvent_DuplicateMessage() => create();
  TraceEvent_DuplicateMessage._() : super();
  factory TraceEvent_DuplicateMessage.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_DuplicateMessage.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.DuplicateMessage', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'messageID', $pb.PbFieldType.OY, protoName: 'messageID')
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'receivedFrom', $pb.PbFieldType.OY, protoName: 'receivedFrom')
    ..aOS(3, _omitFieldNames ? '' : 'topic')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_DuplicateMessage clone() => TraceEvent_DuplicateMessage()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_DuplicateMessage copyWith(void Function(TraceEvent_DuplicateMessage) updates) => super.copyWith((message) => updates(message as TraceEvent_DuplicateMessage)) as TraceEvent_DuplicateMessage;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_DuplicateMessage create() => TraceEvent_DuplicateMessage._();
  TraceEvent_DuplicateMessage createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_DuplicateMessage> createRepeated() => $pb.PbList<TraceEvent_DuplicateMessage>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_DuplicateMessage getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_DuplicateMessage>(create);
  static TraceEvent_DuplicateMessage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get messageID => $_getN(0);
  @$pb.TagNumber(1)
  set messageID($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMessageID() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessageID() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get receivedFrom => $_getN(1);
  @$pb.TagNumber(2)
  set receivedFrom($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasReceivedFrom() => $_has(1);
  @$pb.TagNumber(2)
  void clearReceivedFrom() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get topic => $_getSZ(2);
  @$pb.TagNumber(3)
  set topic($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTopic() => $_has(2);
  @$pb.TagNumber(3)
  void clearTopic() => clearField(3);
}

class TraceEvent_DeliverMessage extends $pb.GeneratedMessage {
  factory TraceEvent_DeliverMessage() => create();
  TraceEvent_DeliverMessage._() : super();
  factory TraceEvent_DeliverMessage.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_DeliverMessage.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.DeliverMessage', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'messageID', $pb.PbFieldType.OY, protoName: 'messageID')
    ..aOS(2, _omitFieldNames ? '' : 'topic')
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'receivedFrom', $pb.PbFieldType.OY, protoName: 'receivedFrom')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_DeliverMessage clone() => TraceEvent_DeliverMessage()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_DeliverMessage copyWith(void Function(TraceEvent_DeliverMessage) updates) => super.copyWith((message) => updates(message as TraceEvent_DeliverMessage)) as TraceEvent_DeliverMessage;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_DeliverMessage create() => TraceEvent_DeliverMessage._();
  TraceEvent_DeliverMessage createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_DeliverMessage> createRepeated() => $pb.PbList<TraceEvent_DeliverMessage>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_DeliverMessage getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_DeliverMessage>(create);
  static TraceEvent_DeliverMessage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get messageID => $_getN(0);
  @$pb.TagNumber(1)
  set messageID($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMessageID() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessageID() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get topic => $_getSZ(1);
  @$pb.TagNumber(2)
  set topic($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTopic() => $_has(1);
  @$pb.TagNumber(2)
  void clearTopic() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get receivedFrom => $_getN(2);
  @$pb.TagNumber(3)
  set receivedFrom($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasReceivedFrom() => $_has(2);
  @$pb.TagNumber(3)
  void clearReceivedFrom() => clearField(3);
}

class TraceEvent_AddPeer extends $pb.GeneratedMessage {
  factory TraceEvent_AddPeer() => create();
  TraceEvent_AddPeer._() : super();
  factory TraceEvent_AddPeer.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_AddPeer.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.AddPeer', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'peerID', $pb.PbFieldType.OY, protoName: 'peerID')
    ..aOS(2, _omitFieldNames ? '' : 'proto')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_AddPeer clone() => TraceEvent_AddPeer()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_AddPeer copyWith(void Function(TraceEvent_AddPeer) updates) => super.copyWith((message) => updates(message as TraceEvent_AddPeer)) as TraceEvent_AddPeer;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_AddPeer create() => TraceEvent_AddPeer._();
  TraceEvent_AddPeer createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_AddPeer> createRepeated() => $pb.PbList<TraceEvent_AddPeer>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_AddPeer getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_AddPeer>(create);
  static TraceEvent_AddPeer? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get peerID => $_getN(0);
  @$pb.TagNumber(1)
  set peerID($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPeerID() => $_has(0);
  @$pb.TagNumber(1)
  void clearPeerID() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get proto => $_getSZ(1);
  @$pb.TagNumber(2)
  set proto($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasProto() => $_has(1);
  @$pb.TagNumber(2)
  void clearProto() => clearField(2);
}

class TraceEvent_RemovePeer extends $pb.GeneratedMessage {
  factory TraceEvent_RemovePeer() => create();
  TraceEvent_RemovePeer._() : super();
  factory TraceEvent_RemovePeer.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_RemovePeer.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.RemovePeer', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'peerID', $pb.PbFieldType.OY, protoName: 'peerID')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_RemovePeer clone() => TraceEvent_RemovePeer()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_RemovePeer copyWith(void Function(TraceEvent_RemovePeer) updates) => super.copyWith((message) => updates(message as TraceEvent_RemovePeer)) as TraceEvent_RemovePeer;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_RemovePeer create() => TraceEvent_RemovePeer._();
  TraceEvent_RemovePeer createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_RemovePeer> createRepeated() => $pb.PbList<TraceEvent_RemovePeer>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_RemovePeer getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_RemovePeer>(create);
  static TraceEvent_RemovePeer? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get peerID => $_getN(0);
  @$pb.TagNumber(1)
  set peerID($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPeerID() => $_has(0);
  @$pb.TagNumber(1)
  void clearPeerID() => clearField(1);
}

class TraceEvent_RecvRPC extends $pb.GeneratedMessage {
  factory TraceEvent_RecvRPC() => create();
  TraceEvent_RecvRPC._() : super();
  factory TraceEvent_RecvRPC.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_RecvRPC.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.RecvRPC', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'receivedFrom', $pb.PbFieldType.OY, protoName: 'receivedFrom')
    ..aOM<TraceEvent_RPCMeta>(2, _omitFieldNames ? '' : 'meta', subBuilder: TraceEvent_RPCMeta.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_RecvRPC clone() => TraceEvent_RecvRPC()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_RecvRPC copyWith(void Function(TraceEvent_RecvRPC) updates) => super.copyWith((message) => updates(message as TraceEvent_RecvRPC)) as TraceEvent_RecvRPC;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_RecvRPC create() => TraceEvent_RecvRPC._();
  TraceEvent_RecvRPC createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_RecvRPC> createRepeated() => $pb.PbList<TraceEvent_RecvRPC>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_RecvRPC getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_RecvRPC>(create);
  static TraceEvent_RecvRPC? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get receivedFrom => $_getN(0);
  @$pb.TagNumber(1)
  set receivedFrom($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasReceivedFrom() => $_has(0);
  @$pb.TagNumber(1)
  void clearReceivedFrom() => clearField(1);

  @$pb.TagNumber(2)
  TraceEvent_RPCMeta get meta => $_getN(1);
  @$pb.TagNumber(2)
  set meta(TraceEvent_RPCMeta v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasMeta() => $_has(1);
  @$pb.TagNumber(2)
  void clearMeta() => clearField(2);
  @$pb.TagNumber(2)
  TraceEvent_RPCMeta ensureMeta() => $_ensure(1);
}

class TraceEvent_SendRPC extends $pb.GeneratedMessage {
  factory TraceEvent_SendRPC() => create();
  TraceEvent_SendRPC._() : super();
  factory TraceEvent_SendRPC.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_SendRPC.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.SendRPC', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'sendTo', $pb.PbFieldType.OY, protoName: 'sendTo')
    ..aOM<TraceEvent_RPCMeta>(2, _omitFieldNames ? '' : 'meta', subBuilder: TraceEvent_RPCMeta.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_SendRPC clone() => TraceEvent_SendRPC()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_SendRPC copyWith(void Function(TraceEvent_SendRPC) updates) => super.copyWith((message) => updates(message as TraceEvent_SendRPC)) as TraceEvent_SendRPC;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_SendRPC create() => TraceEvent_SendRPC._();
  TraceEvent_SendRPC createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_SendRPC> createRepeated() => $pb.PbList<TraceEvent_SendRPC>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_SendRPC getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_SendRPC>(create);
  static TraceEvent_SendRPC? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get sendTo => $_getN(0);
  @$pb.TagNumber(1)
  set sendTo($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSendTo() => $_has(0);
  @$pb.TagNumber(1)
  void clearSendTo() => clearField(1);

  @$pb.TagNumber(2)
  TraceEvent_RPCMeta get meta => $_getN(1);
  @$pb.TagNumber(2)
  set meta(TraceEvent_RPCMeta v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasMeta() => $_has(1);
  @$pb.TagNumber(2)
  void clearMeta() => clearField(2);
  @$pb.TagNumber(2)
  TraceEvent_RPCMeta ensureMeta() => $_ensure(1);
}

class TraceEvent_DropRPC extends $pb.GeneratedMessage {
  factory TraceEvent_DropRPC() => create();
  TraceEvent_DropRPC._() : super();
  factory TraceEvent_DropRPC.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_DropRPC.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.DropRPC', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'sendTo', $pb.PbFieldType.OY, protoName: 'sendTo')
    ..aOM<TraceEvent_RPCMeta>(2, _omitFieldNames ? '' : 'meta', subBuilder: TraceEvent_RPCMeta.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_DropRPC clone() => TraceEvent_DropRPC()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_DropRPC copyWith(void Function(TraceEvent_DropRPC) updates) => super.copyWith((message) => updates(message as TraceEvent_DropRPC)) as TraceEvent_DropRPC;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_DropRPC create() => TraceEvent_DropRPC._();
  TraceEvent_DropRPC createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_DropRPC> createRepeated() => $pb.PbList<TraceEvent_DropRPC>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_DropRPC getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_DropRPC>(create);
  static TraceEvent_DropRPC? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get sendTo => $_getN(0);
  @$pb.TagNumber(1)
  set sendTo($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSendTo() => $_has(0);
  @$pb.TagNumber(1)
  void clearSendTo() => clearField(1);

  @$pb.TagNumber(2)
  TraceEvent_RPCMeta get meta => $_getN(1);
  @$pb.TagNumber(2)
  set meta(TraceEvent_RPCMeta v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasMeta() => $_has(1);
  @$pb.TagNumber(2)
  void clearMeta() => clearField(2);
  @$pb.TagNumber(2)
  TraceEvent_RPCMeta ensureMeta() => $_ensure(1);
}

class TraceEvent_Join extends $pb.GeneratedMessage {
  factory TraceEvent_Join() => create();
  TraceEvent_Join._() : super();
  factory TraceEvent_Join.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_Join.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.Join', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'topic')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_Join clone() => TraceEvent_Join()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_Join copyWith(void Function(TraceEvent_Join) updates) => super.copyWith((message) => updates(message as TraceEvent_Join)) as TraceEvent_Join;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_Join create() => TraceEvent_Join._();
  TraceEvent_Join createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_Join> createRepeated() => $pb.PbList<TraceEvent_Join>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_Join getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_Join>(create);
  static TraceEvent_Join? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get topic => $_getSZ(0);
  @$pb.TagNumber(1)
  set topic($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTopic() => $_has(0);
  @$pb.TagNumber(1)
  void clearTopic() => clearField(1);
}

class TraceEvent_Leave extends $pb.GeneratedMessage {
  factory TraceEvent_Leave() => create();
  TraceEvent_Leave._() : super();
  factory TraceEvent_Leave.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_Leave.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.Leave', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..aOS(2, _omitFieldNames ? '' : 'topic')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_Leave clone() => TraceEvent_Leave()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_Leave copyWith(void Function(TraceEvent_Leave) updates) => super.copyWith((message) => updates(message as TraceEvent_Leave)) as TraceEvent_Leave;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_Leave create() => TraceEvent_Leave._();
  TraceEvent_Leave createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_Leave> createRepeated() => $pb.PbList<TraceEvent_Leave>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_Leave getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_Leave>(create);
  static TraceEvent_Leave? _defaultInstance;

  @$pb.TagNumber(2)
  $core.String get topic => $_getSZ(0);
  @$pb.TagNumber(2)
  set topic($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(2)
  $core.bool hasTopic() => $_has(0);
  @$pb.TagNumber(2)
  void clearTopic() => clearField(2);
}

class TraceEvent_Graft extends $pb.GeneratedMessage {
  factory TraceEvent_Graft() => create();
  TraceEvent_Graft._() : super();
  factory TraceEvent_Graft.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_Graft.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.Graft', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'peerID', $pb.PbFieldType.OY, protoName: 'peerID')
    ..aOS(2, _omitFieldNames ? '' : 'topic')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_Graft clone() => TraceEvent_Graft()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_Graft copyWith(void Function(TraceEvent_Graft) updates) => super.copyWith((message) => updates(message as TraceEvent_Graft)) as TraceEvent_Graft;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_Graft create() => TraceEvent_Graft._();
  TraceEvent_Graft createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_Graft> createRepeated() => $pb.PbList<TraceEvent_Graft>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_Graft getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_Graft>(create);
  static TraceEvent_Graft? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get peerID => $_getN(0);
  @$pb.TagNumber(1)
  set peerID($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPeerID() => $_has(0);
  @$pb.TagNumber(1)
  void clearPeerID() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get topic => $_getSZ(1);
  @$pb.TagNumber(2)
  set topic($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTopic() => $_has(1);
  @$pb.TagNumber(2)
  void clearTopic() => clearField(2);
}

class TraceEvent_Prune extends $pb.GeneratedMessage {
  factory TraceEvent_Prune() => create();
  TraceEvent_Prune._() : super();
  factory TraceEvent_Prune.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_Prune.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.Prune', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'peerID', $pb.PbFieldType.OY, protoName: 'peerID')
    ..aOS(2, _omitFieldNames ? '' : 'topic')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_Prune clone() => TraceEvent_Prune()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_Prune copyWith(void Function(TraceEvent_Prune) updates) => super.copyWith((message) => updates(message as TraceEvent_Prune)) as TraceEvent_Prune;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_Prune create() => TraceEvent_Prune._();
  TraceEvent_Prune createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_Prune> createRepeated() => $pb.PbList<TraceEvent_Prune>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_Prune getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_Prune>(create);
  static TraceEvent_Prune? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get peerID => $_getN(0);
  @$pb.TagNumber(1)
  set peerID($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPeerID() => $_has(0);
  @$pb.TagNumber(1)
  void clearPeerID() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get topic => $_getSZ(1);
  @$pb.TagNumber(2)
  set topic($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTopic() => $_has(1);
  @$pb.TagNumber(2)
  void clearTopic() => clearField(2);
}

class TraceEvent_RPCMeta extends $pb.GeneratedMessage {
  factory TraceEvent_RPCMeta() => create();
  TraceEvent_RPCMeta._() : super();
  factory TraceEvent_RPCMeta.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_RPCMeta.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.RPCMeta', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..pc<TraceEvent_MessageMeta>(1, _omitFieldNames ? '' : 'messages', $pb.PbFieldType.PM, subBuilder: TraceEvent_MessageMeta.create)
    ..pc<TraceEvent_SubMeta>(2, _omitFieldNames ? '' : 'subscription', $pb.PbFieldType.PM, subBuilder: TraceEvent_SubMeta.create)
    ..aOM<TraceEvent_ControlMeta>(3, _omitFieldNames ? '' : 'control', subBuilder: TraceEvent_ControlMeta.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_RPCMeta clone() => TraceEvent_RPCMeta()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_RPCMeta copyWith(void Function(TraceEvent_RPCMeta) updates) => super.copyWith((message) => updates(message as TraceEvent_RPCMeta)) as TraceEvent_RPCMeta;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_RPCMeta create() => TraceEvent_RPCMeta._();
  TraceEvent_RPCMeta createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_RPCMeta> createRepeated() => $pb.PbList<TraceEvent_RPCMeta>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_RPCMeta getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_RPCMeta>(create);
  static TraceEvent_RPCMeta? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<TraceEvent_MessageMeta> get messages => $_getList(0);

  @$pb.TagNumber(2)
  $core.List<TraceEvent_SubMeta> get subscription => $_getList(1);

  @$pb.TagNumber(3)
  TraceEvent_ControlMeta get control => $_getN(2);
  @$pb.TagNumber(3)
  set control(TraceEvent_ControlMeta v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasControl() => $_has(2);
  @$pb.TagNumber(3)
  void clearControl() => clearField(3);
  @$pb.TagNumber(3)
  TraceEvent_ControlMeta ensureControl() => $_ensure(2);
}

class TraceEvent_MessageMeta extends $pb.GeneratedMessage {
  factory TraceEvent_MessageMeta() => create();
  TraceEvent_MessageMeta._() : super();
  factory TraceEvent_MessageMeta.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_MessageMeta.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.MessageMeta', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'messageID', $pb.PbFieldType.OY, protoName: 'messageID')
    ..aOS(2, _omitFieldNames ? '' : 'topic')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_MessageMeta clone() => TraceEvent_MessageMeta()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_MessageMeta copyWith(void Function(TraceEvent_MessageMeta) updates) => super.copyWith((message) => updates(message as TraceEvent_MessageMeta)) as TraceEvent_MessageMeta;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_MessageMeta create() => TraceEvent_MessageMeta._();
  TraceEvent_MessageMeta createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_MessageMeta> createRepeated() => $pb.PbList<TraceEvent_MessageMeta>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_MessageMeta getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_MessageMeta>(create);
  static TraceEvent_MessageMeta? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get messageID => $_getN(0);
  @$pb.TagNumber(1)
  set messageID($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMessageID() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessageID() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get topic => $_getSZ(1);
  @$pb.TagNumber(2)
  set topic($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTopic() => $_has(1);
  @$pb.TagNumber(2)
  void clearTopic() => clearField(2);
}

class TraceEvent_SubMeta extends $pb.GeneratedMessage {
  factory TraceEvent_SubMeta() => create();
  TraceEvent_SubMeta._() : super();
  factory TraceEvent_SubMeta.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_SubMeta.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.SubMeta', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'subscribe')
    ..aOS(2, _omitFieldNames ? '' : 'topic')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_SubMeta clone() => TraceEvent_SubMeta()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_SubMeta copyWith(void Function(TraceEvent_SubMeta) updates) => super.copyWith((message) => updates(message as TraceEvent_SubMeta)) as TraceEvent_SubMeta;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_SubMeta create() => TraceEvent_SubMeta._();
  TraceEvent_SubMeta createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_SubMeta> createRepeated() => $pb.PbList<TraceEvent_SubMeta>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_SubMeta getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_SubMeta>(create);
  static TraceEvent_SubMeta? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get subscribe => $_getBF(0);
  @$pb.TagNumber(1)
  set subscribe($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSubscribe() => $_has(0);
  @$pb.TagNumber(1)
  void clearSubscribe() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get topic => $_getSZ(1);
  @$pb.TagNumber(2)
  set topic($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTopic() => $_has(1);
  @$pb.TagNumber(2)
  void clearTopic() => clearField(2);
}

class TraceEvent_ControlMeta extends $pb.GeneratedMessage {
  factory TraceEvent_ControlMeta() => create();
  TraceEvent_ControlMeta._() : super();
  factory TraceEvent_ControlMeta.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_ControlMeta.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.ControlMeta', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..pc<TraceEvent_ControlIHaveMeta>(1, _omitFieldNames ? '' : 'ihave', $pb.PbFieldType.PM, subBuilder: TraceEvent_ControlIHaveMeta.create)
    ..pc<TraceEvent_ControlIWantMeta>(2, _omitFieldNames ? '' : 'iwant', $pb.PbFieldType.PM, subBuilder: TraceEvent_ControlIWantMeta.create)
    ..pc<TraceEvent_ControlGraftMeta>(3, _omitFieldNames ? '' : 'graft', $pb.PbFieldType.PM, subBuilder: TraceEvent_ControlGraftMeta.create)
    ..pc<TraceEvent_ControlPruneMeta>(4, _omitFieldNames ? '' : 'prune', $pb.PbFieldType.PM, subBuilder: TraceEvent_ControlPruneMeta.create)
    ..pc<TraceEvent_ControlIDontWantMeta>(5, _omitFieldNames ? '' : 'idontwant', $pb.PbFieldType.PM, subBuilder: TraceEvent_ControlIDontWantMeta.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_ControlMeta clone() => TraceEvent_ControlMeta()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_ControlMeta copyWith(void Function(TraceEvent_ControlMeta) updates) => super.copyWith((message) => updates(message as TraceEvent_ControlMeta)) as TraceEvent_ControlMeta;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_ControlMeta create() => TraceEvent_ControlMeta._();
  TraceEvent_ControlMeta createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_ControlMeta> createRepeated() => $pb.PbList<TraceEvent_ControlMeta>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_ControlMeta getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_ControlMeta>(create);
  static TraceEvent_ControlMeta? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<TraceEvent_ControlIHaveMeta> get ihave => $_getList(0);

  @$pb.TagNumber(2)
  $core.List<TraceEvent_ControlIWantMeta> get iwant => $_getList(1);

  @$pb.TagNumber(3)
  $core.List<TraceEvent_ControlGraftMeta> get graft => $_getList(2);

  @$pb.TagNumber(4)
  $core.List<TraceEvent_ControlPruneMeta> get prune => $_getList(3);

  @$pb.TagNumber(5)
  $core.List<TraceEvent_ControlIDontWantMeta> get idontwant => $_getList(4);
}

class TraceEvent_ControlIHaveMeta extends $pb.GeneratedMessage {
  factory TraceEvent_ControlIHaveMeta() => create();
  TraceEvent_ControlIHaveMeta._() : super();
  factory TraceEvent_ControlIHaveMeta.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_ControlIHaveMeta.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.ControlIHaveMeta', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'topic')
    ..p<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'messageIDs', $pb.PbFieldType.PY, protoName: 'messageIDs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_ControlIHaveMeta clone() => TraceEvent_ControlIHaveMeta()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_ControlIHaveMeta copyWith(void Function(TraceEvent_ControlIHaveMeta) updates) => super.copyWith((message) => updates(message as TraceEvent_ControlIHaveMeta)) as TraceEvent_ControlIHaveMeta;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_ControlIHaveMeta create() => TraceEvent_ControlIHaveMeta._();
  TraceEvent_ControlIHaveMeta createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_ControlIHaveMeta> createRepeated() => $pb.PbList<TraceEvent_ControlIHaveMeta>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_ControlIHaveMeta getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_ControlIHaveMeta>(create);
  static TraceEvent_ControlIHaveMeta? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get topic => $_getSZ(0);
  @$pb.TagNumber(1)
  set topic($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTopic() => $_has(0);
  @$pb.TagNumber(1)
  void clearTopic() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.List<$core.int>> get messageIDs => $_getList(1);
}

class TraceEvent_ControlIWantMeta extends $pb.GeneratedMessage {
  factory TraceEvent_ControlIWantMeta() => create();
  TraceEvent_ControlIWantMeta._() : super();
  factory TraceEvent_ControlIWantMeta.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_ControlIWantMeta.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.ControlIWantMeta', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..p<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'messageIDs', $pb.PbFieldType.PY, protoName: 'messageIDs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_ControlIWantMeta clone() => TraceEvent_ControlIWantMeta()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_ControlIWantMeta copyWith(void Function(TraceEvent_ControlIWantMeta) updates) => super.copyWith((message) => updates(message as TraceEvent_ControlIWantMeta)) as TraceEvent_ControlIWantMeta;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_ControlIWantMeta create() => TraceEvent_ControlIWantMeta._();
  TraceEvent_ControlIWantMeta createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_ControlIWantMeta> createRepeated() => $pb.PbList<TraceEvent_ControlIWantMeta>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_ControlIWantMeta getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_ControlIWantMeta>(create);
  static TraceEvent_ControlIWantMeta? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.List<$core.int>> get messageIDs => $_getList(0);
}

class TraceEvent_ControlGraftMeta extends $pb.GeneratedMessage {
  factory TraceEvent_ControlGraftMeta() => create();
  TraceEvent_ControlGraftMeta._() : super();
  factory TraceEvent_ControlGraftMeta.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_ControlGraftMeta.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.ControlGraftMeta', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'topic')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_ControlGraftMeta clone() => TraceEvent_ControlGraftMeta()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_ControlGraftMeta copyWith(void Function(TraceEvent_ControlGraftMeta) updates) => super.copyWith((message) => updates(message as TraceEvent_ControlGraftMeta)) as TraceEvent_ControlGraftMeta;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_ControlGraftMeta create() => TraceEvent_ControlGraftMeta._();
  TraceEvent_ControlGraftMeta createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_ControlGraftMeta> createRepeated() => $pb.PbList<TraceEvent_ControlGraftMeta>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_ControlGraftMeta getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_ControlGraftMeta>(create);
  static TraceEvent_ControlGraftMeta? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get topic => $_getSZ(0);
  @$pb.TagNumber(1)
  set topic($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTopic() => $_has(0);
  @$pb.TagNumber(1)
  void clearTopic() => clearField(1);
}

class TraceEvent_ControlPruneMeta extends $pb.GeneratedMessage {
  factory TraceEvent_ControlPruneMeta() => create();
  TraceEvent_ControlPruneMeta._() : super();
  factory TraceEvent_ControlPruneMeta.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_ControlPruneMeta.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.ControlPruneMeta', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'topic')
    ..p<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'peers', $pb.PbFieldType.PY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_ControlPruneMeta clone() => TraceEvent_ControlPruneMeta()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_ControlPruneMeta copyWith(void Function(TraceEvent_ControlPruneMeta) updates) => super.copyWith((message) => updates(message as TraceEvent_ControlPruneMeta)) as TraceEvent_ControlPruneMeta;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_ControlPruneMeta create() => TraceEvent_ControlPruneMeta._();
  TraceEvent_ControlPruneMeta createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_ControlPruneMeta> createRepeated() => $pb.PbList<TraceEvent_ControlPruneMeta>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_ControlPruneMeta getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_ControlPruneMeta>(create);
  static TraceEvent_ControlPruneMeta? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get topic => $_getSZ(0);
  @$pb.TagNumber(1)
  set topic($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTopic() => $_has(0);
  @$pb.TagNumber(1)
  void clearTopic() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.List<$core.int>> get peers => $_getList(1);
}

class TraceEvent_ControlIDontWantMeta extends $pb.GeneratedMessage {
  factory TraceEvent_ControlIDontWantMeta() => create();
  TraceEvent_ControlIDontWantMeta._() : super();
  factory TraceEvent_ControlIDontWantMeta.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent_ControlIDontWantMeta.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent.ControlIDontWantMeta', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..p<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'messageIDs', $pb.PbFieldType.PY, protoName: 'messageIDs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent_ControlIDontWantMeta clone() => TraceEvent_ControlIDontWantMeta()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent_ControlIDontWantMeta copyWith(void Function(TraceEvent_ControlIDontWantMeta) updates) => super.copyWith((message) => updates(message as TraceEvent_ControlIDontWantMeta)) as TraceEvent_ControlIDontWantMeta;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent_ControlIDontWantMeta create() => TraceEvent_ControlIDontWantMeta._();
  TraceEvent_ControlIDontWantMeta createEmptyInstance() => create();
  static $pb.PbList<TraceEvent_ControlIDontWantMeta> createRepeated() => $pb.PbList<TraceEvent_ControlIDontWantMeta>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent_ControlIDontWantMeta getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent_ControlIDontWantMeta>(create);
  static TraceEvent_ControlIDontWantMeta? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.List<$core.int>> get messageIDs => $_getList(0);
}

class TraceEvent extends $pb.GeneratedMessage {
  factory TraceEvent() => create();
  TraceEvent._() : super();
  factory TraceEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..e<TraceEvent_Type>(1, _omitFieldNames ? '' : 'type', $pb.PbFieldType.OE, defaultOrMaker: TraceEvent_Type.PUBLISH_MESSAGE, valueOf: TraceEvent_Type.valueOf, enumValues: TraceEvent_Type.values)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'peerID', $pb.PbFieldType.OY, protoName: 'peerID')
    ..aInt64(3, _omitFieldNames ? '' : 'timestamp')
    ..aOM<TraceEvent_PublishMessage>(4, _omitFieldNames ? '' : 'publishMessage', protoName: 'publishMessage', subBuilder: TraceEvent_PublishMessage.create)
    ..aOM<TraceEvent_RejectMessage>(5, _omitFieldNames ? '' : 'rejectMessage', protoName: 'rejectMessage', subBuilder: TraceEvent_RejectMessage.create)
    ..aOM<TraceEvent_DuplicateMessage>(6, _omitFieldNames ? '' : 'duplicateMessage', protoName: 'duplicateMessage', subBuilder: TraceEvent_DuplicateMessage.create)
    ..aOM<TraceEvent_DeliverMessage>(7, _omitFieldNames ? '' : 'deliverMessage', protoName: 'deliverMessage', subBuilder: TraceEvent_DeliverMessage.create)
    ..aOM<TraceEvent_AddPeer>(8, _omitFieldNames ? '' : 'addPeer', protoName: 'addPeer', subBuilder: TraceEvent_AddPeer.create)
    ..aOM<TraceEvent_RemovePeer>(9, _omitFieldNames ? '' : 'removePeer', protoName: 'removePeer', subBuilder: TraceEvent_RemovePeer.create)
    ..aOM<TraceEvent_RecvRPC>(10, _omitFieldNames ? '' : 'recvRPC', protoName: 'recvRPC', subBuilder: TraceEvent_RecvRPC.create)
    ..aOM<TraceEvent_SendRPC>(11, _omitFieldNames ? '' : 'sendRPC', protoName: 'sendRPC', subBuilder: TraceEvent_SendRPC.create)
    ..aOM<TraceEvent_DropRPC>(12, _omitFieldNames ? '' : 'dropRPC', protoName: 'dropRPC', subBuilder: TraceEvent_DropRPC.create)
    ..aOM<TraceEvent_Join>(13, _omitFieldNames ? '' : 'join', subBuilder: TraceEvent_Join.create)
    ..aOM<TraceEvent_Leave>(14, _omitFieldNames ? '' : 'leave', subBuilder: TraceEvent_Leave.create)
    ..aOM<TraceEvent_Graft>(15, _omitFieldNames ? '' : 'graft', subBuilder: TraceEvent_Graft.create)
    ..aOM<TraceEvent_Prune>(16, _omitFieldNames ? '' : 'prune', subBuilder: TraceEvent_Prune.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEvent clone() => TraceEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEvent copyWith(void Function(TraceEvent) updates) => super.copyWith((message) => updates(message as TraceEvent)) as TraceEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEvent create() => TraceEvent._();
  TraceEvent createEmptyInstance() => create();
  static $pb.PbList<TraceEvent> createRepeated() => $pb.PbList<TraceEvent>();
  @$core.pragma('dart2js:noInline')
  static TraceEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEvent>(create);
  static TraceEvent? _defaultInstance;

  @$pb.TagNumber(1)
  TraceEvent_Type get type => $_getN(0);
  @$pb.TagNumber(1)
  set type(TraceEvent_Type v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get peerID => $_getN(1);
  @$pb.TagNumber(2)
  set peerID($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasPeerID() => $_has(1);
  @$pb.TagNumber(2)
  void clearPeerID() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get timestamp => $_getI64(2);
  @$pb.TagNumber(3)
  set timestamp($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTimestamp() => $_has(2);
  @$pb.TagNumber(3)
  void clearTimestamp() => clearField(3);

  @$pb.TagNumber(4)
  TraceEvent_PublishMessage get publishMessage => $_getN(3);
  @$pb.TagNumber(4)
  set publishMessage(TraceEvent_PublishMessage v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasPublishMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearPublishMessage() => clearField(4);
  @$pb.TagNumber(4)
  TraceEvent_PublishMessage ensurePublishMessage() => $_ensure(3);

  @$pb.TagNumber(5)
  TraceEvent_RejectMessage get rejectMessage => $_getN(4);
  @$pb.TagNumber(5)
  set rejectMessage(TraceEvent_RejectMessage v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasRejectMessage() => $_has(4);
  @$pb.TagNumber(5)
  void clearRejectMessage() => clearField(5);
  @$pb.TagNumber(5)
  TraceEvent_RejectMessage ensureRejectMessage() => $_ensure(4);

  @$pb.TagNumber(6)
  TraceEvent_DuplicateMessage get duplicateMessage => $_getN(5);
  @$pb.TagNumber(6)
  set duplicateMessage(TraceEvent_DuplicateMessage v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasDuplicateMessage() => $_has(5);
  @$pb.TagNumber(6)
  void clearDuplicateMessage() => clearField(6);
  @$pb.TagNumber(6)
  TraceEvent_DuplicateMessage ensureDuplicateMessage() => $_ensure(5);

  @$pb.TagNumber(7)
  TraceEvent_DeliverMessage get deliverMessage => $_getN(6);
  @$pb.TagNumber(7)
  set deliverMessage(TraceEvent_DeliverMessage v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasDeliverMessage() => $_has(6);
  @$pb.TagNumber(7)
  void clearDeliverMessage() => clearField(7);
  @$pb.TagNumber(7)
  TraceEvent_DeliverMessage ensureDeliverMessage() => $_ensure(6);

  @$pb.TagNumber(8)
  TraceEvent_AddPeer get addPeer => $_getN(7);
  @$pb.TagNumber(8)
  set addPeer(TraceEvent_AddPeer v) { setField(8, v); }
  @$pb.TagNumber(8)
  $core.bool hasAddPeer() => $_has(7);
  @$pb.TagNumber(8)
  void clearAddPeer() => clearField(8);
  @$pb.TagNumber(8)
  TraceEvent_AddPeer ensureAddPeer() => $_ensure(7);

  @$pb.TagNumber(9)
  TraceEvent_RemovePeer get removePeer => $_getN(8);
  @$pb.TagNumber(9)
  set removePeer(TraceEvent_RemovePeer v) { setField(9, v); }
  @$pb.TagNumber(9)
  $core.bool hasRemovePeer() => $_has(8);
  @$pb.TagNumber(9)
  void clearRemovePeer() => clearField(9);
  @$pb.TagNumber(9)
  TraceEvent_RemovePeer ensureRemovePeer() => $_ensure(8);

  @$pb.TagNumber(10)
  TraceEvent_RecvRPC get recvRPC => $_getN(9);
  @$pb.TagNumber(10)
  set recvRPC(TraceEvent_RecvRPC v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasRecvRPC() => $_has(9);
  @$pb.TagNumber(10)
  void clearRecvRPC() => clearField(10);
  @$pb.TagNumber(10)
  TraceEvent_RecvRPC ensureRecvRPC() => $_ensure(9);

  @$pb.TagNumber(11)
  TraceEvent_SendRPC get sendRPC => $_getN(10);
  @$pb.TagNumber(11)
  set sendRPC(TraceEvent_SendRPC v) { setField(11, v); }
  @$pb.TagNumber(11)
  $core.bool hasSendRPC() => $_has(10);
  @$pb.TagNumber(11)
  void clearSendRPC() => clearField(11);
  @$pb.TagNumber(11)
  TraceEvent_SendRPC ensureSendRPC() => $_ensure(10);

  @$pb.TagNumber(12)
  TraceEvent_DropRPC get dropRPC => $_getN(11);
  @$pb.TagNumber(12)
  set dropRPC(TraceEvent_DropRPC v) { setField(12, v); }
  @$pb.TagNumber(12)
  $core.bool hasDropRPC() => $_has(11);
  @$pb.TagNumber(12)
  void clearDropRPC() => clearField(12);
  @$pb.TagNumber(12)
  TraceEvent_DropRPC ensureDropRPC() => $_ensure(11);

  @$pb.TagNumber(13)
  TraceEvent_Join get join => $_getN(12);
  @$pb.TagNumber(13)
  set join(TraceEvent_Join v) { setField(13, v); }
  @$pb.TagNumber(13)
  $core.bool hasJoin() => $_has(12);
  @$pb.TagNumber(13)
  void clearJoin() => clearField(13);
  @$pb.TagNumber(13)
  TraceEvent_Join ensureJoin() => $_ensure(12);

  @$pb.TagNumber(14)
  TraceEvent_Leave get leave => $_getN(13);
  @$pb.TagNumber(14)
  set leave(TraceEvent_Leave v) { setField(14, v); }
  @$pb.TagNumber(14)
  $core.bool hasLeave() => $_has(13);
  @$pb.TagNumber(14)
  void clearLeave() => clearField(14);
  @$pb.TagNumber(14)
  TraceEvent_Leave ensureLeave() => $_ensure(13);

  @$pb.TagNumber(15)
  TraceEvent_Graft get graft => $_getN(14);
  @$pb.TagNumber(15)
  set graft(TraceEvent_Graft v) { setField(15, v); }
  @$pb.TagNumber(15)
  $core.bool hasGraft() => $_has(14);
  @$pb.TagNumber(15)
  void clearGraft() => clearField(15);
  @$pb.TagNumber(15)
  TraceEvent_Graft ensureGraft() => $_ensure(14);

  @$pb.TagNumber(16)
  TraceEvent_Prune get prune => $_getN(15);
  @$pb.TagNumber(16)
  set prune(TraceEvent_Prune v) { setField(16, v); }
  @$pb.TagNumber(16)
  $core.bool hasPrune() => $_has(15);
  @$pb.TagNumber(16)
  void clearPrune() => clearField(16);
  @$pb.TagNumber(16)
  TraceEvent_Prune ensurePrune() => $_ensure(15);
}

class TraceEventBatch extends $pb.GeneratedMessage {
  factory TraceEventBatch() => create();
  TraceEventBatch._() : super();
  factory TraceEventBatch.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TraceEventBatch.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TraceEventBatch', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..pc<TraceEvent>(1, _omitFieldNames ? '' : 'batch', $pb.PbFieldType.PM, subBuilder: TraceEvent.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TraceEventBatch clone() => TraceEventBatch()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TraceEventBatch copyWith(void Function(TraceEventBatch) updates) => super.copyWith((message) => updates(message as TraceEventBatch)) as TraceEventBatch;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraceEventBatch create() => TraceEventBatch._();
  TraceEventBatch createEmptyInstance() => create();
  static $pb.PbList<TraceEventBatch> createRepeated() => $pb.PbList<TraceEventBatch>();
  @$core.pragma('dart2js:noInline')
  static TraceEventBatch getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TraceEventBatch>(create);
  static TraceEventBatch? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<TraceEvent> get batch => $_getList(0);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
