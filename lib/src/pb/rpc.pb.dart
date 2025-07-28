//
//  Generated code. Do not modify.
//  source: rpc.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

class RPC_SubOpts extends $pb.GeneratedMessage {
  factory RPC_SubOpts() => create();
  RPC_SubOpts._() : super();
  factory RPC_SubOpts.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RPC_SubOpts.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RPC.SubOpts', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'subscribe')
    ..aOS(2, _omitFieldNames ? '' : 'topicid')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RPC_SubOpts clone() => RPC_SubOpts()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RPC_SubOpts copyWith(void Function(RPC_SubOpts) updates) => super.copyWith((message) => updates(message as RPC_SubOpts)) as RPC_SubOpts;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RPC_SubOpts create() => RPC_SubOpts._();
  RPC_SubOpts createEmptyInstance() => create();
  static $pb.PbList<RPC_SubOpts> createRepeated() => $pb.PbList<RPC_SubOpts>();
  @$core.pragma('dart2js:noInline')
  static RPC_SubOpts getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RPC_SubOpts>(create);
  static RPC_SubOpts? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get subscribe => $_getBF(0);
  @$pb.TagNumber(1)
  set subscribe($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSubscribe() => $_has(0);
  @$pb.TagNumber(1)
  void clearSubscribe() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get topicid => $_getSZ(1);
  @$pb.TagNumber(2)
  set topicid($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTopicid() => $_has(1);
  @$pb.TagNumber(2)
  void clearTopicid() => clearField(2);
}

class RPC extends $pb.GeneratedMessage {
  factory RPC() => create();
  RPC._() : super();
  factory RPC.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RPC.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RPC', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..pc<RPC_SubOpts>(1, _omitFieldNames ? '' : 'subscriptions', $pb.PbFieldType.PM, subBuilder: RPC_SubOpts.create)
    ..pc<Message>(2, _omitFieldNames ? '' : 'publish', $pb.PbFieldType.PM, subBuilder: Message.create)
    ..aOM<ControlMessage>(3, _omitFieldNames ? '' : 'control', subBuilder: ControlMessage.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RPC clone() => RPC()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RPC copyWith(void Function(RPC) updates) => super.copyWith((message) => updates(message as RPC)) as RPC;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RPC create() => RPC._();
  RPC createEmptyInstance() => create();
  static $pb.PbList<RPC> createRepeated() => $pb.PbList<RPC>();
  @$core.pragma('dart2js:noInline')
  static RPC getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RPC>(create);
  static RPC? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<RPC_SubOpts> get subscriptions => $_getList(0);

  @$pb.TagNumber(2)
  $core.List<Message> get publish => $_getList(1);

  @$pb.TagNumber(3)
  ControlMessage get control => $_getN(2);
  @$pb.TagNumber(3)
  set control(ControlMessage v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasControl() => $_has(2);
  @$pb.TagNumber(3)
  void clearControl() => clearField(3);
  @$pb.TagNumber(3)
  ControlMessage ensureControl() => $_ensure(2);
}

class Message extends $pb.GeneratedMessage {
  factory Message() => create();
  Message._() : super();
  factory Message.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Message.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Message', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'from', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'seqno', $pb.PbFieldType.OY)
    ..aOS(4, _omitFieldNames ? '' : 'topic')
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'signature', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'key', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  Message clone() => Message()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  Message copyWith(void Function(Message) updates) => super.copyWith((message) => updates(message as Message)) as Message;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Message create() => Message._();
  Message createEmptyInstance() => create();
  static $pb.PbList<Message> createRepeated() => $pb.PbList<Message>();
  @$core.pragma('dart2js:noInline')
  static Message getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Message>(create);
  static Message? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get from => $_getN(0);
  @$pb.TagNumber(1)
  set from($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasFrom() => $_has(0);
  @$pb.TagNumber(1)
  void clearFrom() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get data => $_getN(1);
  @$pb.TagNumber(2)
  set data($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasData() => $_has(1);
  @$pb.TagNumber(2)
  void clearData() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get seqno => $_getN(2);
  @$pb.TagNumber(3)
  set seqno($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSeqno() => $_has(2);
  @$pb.TagNumber(3)
  void clearSeqno() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get topic => $_getSZ(3);
  @$pb.TagNumber(4)
  set topic($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTopic() => $_has(3);
  @$pb.TagNumber(4)
  void clearTopic() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get signature => $_getN(4);
  @$pb.TagNumber(5)
  set signature($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSignature() => $_has(4);
  @$pb.TagNumber(5)
  void clearSignature() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get key => $_getN(5);
  @$pb.TagNumber(6)
  set key($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasKey() => $_has(5);
  @$pb.TagNumber(6)
  void clearKey() => clearField(6);
}

class ControlMessage extends $pb.GeneratedMessage {
  factory ControlMessage() => create();
  ControlMessage._() : super();
  factory ControlMessage.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ControlMessage.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ControlMessage', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..pc<ControlIHave>(1, _omitFieldNames ? '' : 'ihave', $pb.PbFieldType.PM, subBuilder: ControlIHave.create)
    ..pc<ControlIWant>(2, _omitFieldNames ? '' : 'iwant', $pb.PbFieldType.PM, subBuilder: ControlIWant.create)
    ..pc<ControlGraft>(3, _omitFieldNames ? '' : 'graft', $pb.PbFieldType.PM, subBuilder: ControlGraft.create)
    ..pc<ControlPrune>(4, _omitFieldNames ? '' : 'prune', $pb.PbFieldType.PM, subBuilder: ControlPrune.create)
    ..pc<ControlIDontWant>(5, _omitFieldNames ? '' : 'idontwant', $pb.PbFieldType.PM, subBuilder: ControlIDontWant.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ControlMessage clone() => ControlMessage()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ControlMessage copyWith(void Function(ControlMessage) updates) => super.copyWith((message) => updates(message as ControlMessage)) as ControlMessage;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ControlMessage create() => ControlMessage._();
  ControlMessage createEmptyInstance() => create();
  static $pb.PbList<ControlMessage> createRepeated() => $pb.PbList<ControlMessage>();
  @$core.pragma('dart2js:noInline')
  static ControlMessage getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ControlMessage>(create);
  static ControlMessage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<ControlIHave> get ihave => $_getList(0);

  @$pb.TagNumber(2)
  $core.List<ControlIWant> get iwant => $_getList(1);

  @$pb.TagNumber(3)
  $core.List<ControlGraft> get graft => $_getList(2);

  @$pb.TagNumber(4)
  $core.List<ControlPrune> get prune => $_getList(3);

  @$pb.TagNumber(5)
  $core.List<ControlIDontWant> get idontwant => $_getList(4);
}

class ControlIHave extends $pb.GeneratedMessage {
  factory ControlIHave() => create();
  ControlIHave._() : super();
  factory ControlIHave.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ControlIHave.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ControlIHave', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'topicID', protoName: 'topicID')
    ..pPS(2, _omitFieldNames ? '' : 'messageIDs', protoName: 'messageIDs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ControlIHave clone() => ControlIHave()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ControlIHave copyWith(void Function(ControlIHave) updates) => super.copyWith((message) => updates(message as ControlIHave)) as ControlIHave;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ControlIHave create() => ControlIHave._();
  ControlIHave createEmptyInstance() => create();
  static $pb.PbList<ControlIHave> createRepeated() => $pb.PbList<ControlIHave>();
  @$core.pragma('dart2js:noInline')
  static ControlIHave getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ControlIHave>(create);
  static ControlIHave? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get topicID => $_getSZ(0);
  @$pb.TagNumber(1)
  set topicID($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTopicID() => $_has(0);
  @$pb.TagNumber(1)
  void clearTopicID() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.String> get messageIDs => $_getList(1);
}

class ControlIWant extends $pb.GeneratedMessage {
  factory ControlIWant() => create();
  ControlIWant._() : super();
  factory ControlIWant.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ControlIWant.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ControlIWant', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'messageIDs', protoName: 'messageIDs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ControlIWant clone() => ControlIWant()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ControlIWant copyWith(void Function(ControlIWant) updates) => super.copyWith((message) => updates(message as ControlIWant)) as ControlIWant;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ControlIWant create() => ControlIWant._();
  ControlIWant createEmptyInstance() => create();
  static $pb.PbList<ControlIWant> createRepeated() => $pb.PbList<ControlIWant>();
  @$core.pragma('dart2js:noInline')
  static ControlIWant getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ControlIWant>(create);
  static ControlIWant? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.String> get messageIDs => $_getList(0);
}

class ControlGraft extends $pb.GeneratedMessage {
  factory ControlGraft() => create();
  ControlGraft._() : super();
  factory ControlGraft.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ControlGraft.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ControlGraft', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'topicID', protoName: 'topicID')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ControlGraft clone() => ControlGraft()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ControlGraft copyWith(void Function(ControlGraft) updates) => super.copyWith((message) => updates(message as ControlGraft)) as ControlGraft;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ControlGraft create() => ControlGraft._();
  ControlGraft createEmptyInstance() => create();
  static $pb.PbList<ControlGraft> createRepeated() => $pb.PbList<ControlGraft>();
  @$core.pragma('dart2js:noInline')
  static ControlGraft getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ControlGraft>(create);
  static ControlGraft? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get topicID => $_getSZ(0);
  @$pb.TagNumber(1)
  set topicID($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTopicID() => $_has(0);
  @$pb.TagNumber(1)
  void clearTopicID() => clearField(1);
}

class ControlPrune extends $pb.GeneratedMessage {
  factory ControlPrune() => create();
  ControlPrune._() : super();
  factory ControlPrune.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ControlPrune.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ControlPrune', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'topicID', protoName: 'topicID')
    ..pc<PeerInfo>(2, _omitFieldNames ? '' : 'peers', $pb.PbFieldType.PM, subBuilder: PeerInfo.create)
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'backoff', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ControlPrune clone() => ControlPrune()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ControlPrune copyWith(void Function(ControlPrune) updates) => super.copyWith((message) => updates(message as ControlPrune)) as ControlPrune;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ControlPrune create() => ControlPrune._();
  ControlPrune createEmptyInstance() => create();
  static $pb.PbList<ControlPrune> createRepeated() => $pb.PbList<ControlPrune>();
  @$core.pragma('dart2js:noInline')
  static ControlPrune getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ControlPrune>(create);
  static ControlPrune? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get topicID => $_getSZ(0);
  @$pb.TagNumber(1)
  set topicID($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTopicID() => $_has(0);
  @$pb.TagNumber(1)
  void clearTopicID() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<PeerInfo> get peers => $_getList(1);

  @$pb.TagNumber(3)
  $fixnum.Int64 get backoff => $_getI64(2);
  @$pb.TagNumber(3)
  set backoff($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasBackoff() => $_has(2);
  @$pb.TagNumber(3)
  void clearBackoff() => clearField(3);
}

class ControlIDontWant extends $pb.GeneratedMessage {
  factory ControlIDontWant() => create();
  ControlIDontWant._() : super();
  factory ControlIDontWant.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ControlIDontWant.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ControlIDontWant', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'messageIDs', protoName: 'messageIDs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ControlIDontWant clone() => ControlIDontWant()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ControlIDontWant copyWith(void Function(ControlIDontWant) updates) => super.copyWith((message) => updates(message as ControlIDontWant)) as ControlIDontWant;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ControlIDontWant create() => ControlIDontWant._();
  ControlIDontWant createEmptyInstance() => create();
  static $pb.PbList<ControlIDontWant> createRepeated() => $pb.PbList<ControlIDontWant>();
  @$core.pragma('dart2js:noInline')
  static ControlIDontWant getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ControlIDontWant>(create);
  static ControlIDontWant? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.String> get messageIDs => $_getList(0);
}

class PeerInfo extends $pb.GeneratedMessage {
  factory PeerInfo() => create();
  PeerInfo._() : super();
  factory PeerInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PeerInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PeerInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'pubsub.pb'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'peerID', $pb.PbFieldType.OY, protoName: 'peerID')
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'signedPeerRecord', $pb.PbFieldType.OY, protoName: 'signedPeerRecord')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PeerInfo clone() => PeerInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PeerInfo copyWith(void Function(PeerInfo) updates) => super.copyWith((message) => updates(message as PeerInfo)) as PeerInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PeerInfo create() => PeerInfo._();
  PeerInfo createEmptyInstance() => create();
  static $pb.PbList<PeerInfo> createRepeated() => $pb.PbList<PeerInfo>();
  @$core.pragma('dart2js:noInline')
  static PeerInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PeerInfo>(create);
  static PeerInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get peerID => $_getN(0);
  @$pb.TagNumber(1)
  set peerID($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPeerID() => $_has(0);
  @$pb.TagNumber(1)
  void clearPeerID() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get signedPeerRecord => $_getN(1);
  @$pb.TagNumber(2)
  set signedPeerRecord($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSignedPeerRecord() => $_has(1);
  @$pb.TagNumber(2)
  void clearSignedPeerRecord() => clearField(2);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
