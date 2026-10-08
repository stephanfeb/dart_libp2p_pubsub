# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

### Tracing
- **The tracers write go-libp2p-pubsub's formats**, so Go's trace tools can read their files. `PbEventTracer` prefixes each event with its length as a varint, where it wrote 4 bytes. `JsonEventTracer` writes one JSON object per line with the fields named as in `trace.proto`, bytes in base64, and the type and timestamp as numbers, where it wrote field numbers as keys.
- **Every event carries the local peer ID and a timestamp** (nanoseconds since the Unix epoch), as in Go. The router used to set `peerID` to the remote peer, and no event had a timestamp. Routers now send events through the new `PubSub.traceEvent`, which stamps them.
- `RECV_RPC` events carry the summary of the RPC (`meta`), and the RPC summaries list the subscriptions, as in Go.
- Tracing after `dispose()` no longer throws: the event is dropped. `stop()` and `dispose()` can be called again.

### Added for applications
- **`GossipSubRouter.setTopicScoreParams(topic, params)`** sets or changes a topic's score parameters after the router is created, as go-libp2p-pubsub's `Topic.SetScoreParams`: a topic created later can use the built-in penalties (such as P4 for invalid messages). Lowering the delivery caps caps the peers' counters, as in Go. `PeerScore.topicScoreParams(topic)` reads them. The scorer is now created with the router rather than when it is attached.
- **`PubSub(peerOutboundQueueSize: n)`** sets the number of RPCs queued per peer before more are dropped, as go-libp2p-pubsub's `WithPeerOutboundQueueSize` (default 32).

### Discovery
- **Topic discovery works, as go-libp2p-pubsub's `WithDiscovery`.** `PubSub(discovery: ...)` takes a dart_libp2p `Discovery` service. PubSub advertises each subscribed topic, every second looks up the peers of the subscribed topics that the router has not enough peers on, and dials them through a backoff connector (`discoveryConnector`, default Go's). `discoveryOptions` are passed to the service. Before, the discovery helper was not connected to `PubSub`.
- **Topics are advertised under Go's namespace, `floodsub:<topic>`**, so Dart and Go nodes find each other. The helper used `gossipsub_topic:<topic>`.
- `publish(topic, data, ready: minTopicSize(n), readyTimeout: ...)` waits until the router has enough peers on the topic before publishing, looking them up while it waits, as Go's `WithReadiness`.
- **Breaking for custom routers:** `Router` has a new method, `enoughPeers(topic, suggested)`, as Go's `EnoughPeers`. The built-in routers implement it with Go's rules.
- Removed `PubSubDiscovery`'s old API (`addDiscoveryListener`, `discoverTopic`, `DEFAULT_GENERAL_PUBSUB_SERVICE_TAG`, `TOPIC_DISCOVERY_PREFIX`). The class was not exported.

### Messages
- **Messages for topics the node does not subscribe to are ignored**, before validation, as in go-libp2p-pubsub. They used to be validated, scored, cached and forwarded, which cost validation work on topics the node had no interest in.

### Peer gater
- **Added go-libp2p-pubsub's peer gater** (`WithPeerGater`): `GossipSubRouter(peerGaterParams: PeerGaterParams())`. When validation is throttled, it handles only the control messages of peers whose messages are mostly not delivered, at random. Off by default, as in Go.
- `PubSub.validateMessage` takes `onReject`, called with the reason a message was dropped.
- Removed `lib/src/core/peer_gater.dart`, a connection gater that nothing used and was not exported.

### Seen messages
- **The seen-message cache has no size limit, as in go-libp2p-pubsub.** It held at most 2^17 IDs and evicted the oldest beyond that, so under a high message rate a message could be validated and forwarded again within `seenMessagesTTL`.
- The cache uses a monotonic clock, so a change to the system clock no longer expires IDs early or keeps them too long.
- `seenMessagesStrategy` (`GossipSubParams`, `FloodSubRouter`, `RandomSubRouter`) chooses Go's first-seen (default) or last-seen expiry, as `WithSeenMessagesStrategy`.
- Removed `lib/src/util/backoff.dart`, which nothing used and was not exported.

### GossipSub v1.3
- **`GossipSubRouter` speaks `/meshsub/1.3.0`** (`gossipSubIDv13`), first, as go-libp2p-pubsub v0.15.0, and negotiates it with Go nodes. With a v1.3 peer, each side announces its extensions in its first RPC; a peer that announces them again gets a behaviour penalty of 10, as in Go. v1.3 peers get IDONTWANT and PX as v1.2 peers.
- The experimental test extension, as Go's `WithTestExtension`: `GossipSubRouter(testExtension: TestExtensionConfig(...))`. Unlike Go, the callback runs only for RPCs that carry a `TestExtension` message.
- The protobuf gains `ControlMessage.extensions`, `ControlExtensions` and `RPC.testExtension`, encoded as Go encodes them.
- `PubSubProtocol.onFirstRpc` lets a router rewrite the first RPC on each new stream.

### Tests
- Peer Exchange is tested on a real network: peers pruned by a bootstrapper with PX connect to each other, build a mesh and exchange messages. The test stores the signed peer records in the bootstrapper's address book itself, as dart_libp2p 4.0.1's identify does not.

## 2.0.0 - 2026-10-08

A review against go-libp2p-pubsub v0.15.0 found remote denial-of-service holes, a crash, interop bugs and a peer-scoring model that did not work. This release fixes them and aligns the router with Go.

### Upgrading from 1.x
- **Peer scoring moved to the router and is opt-in.** Pass `scoreParams:` and `scoreThresholds:` (both, together) to `GossipSubRouter`. `PubSub` no longer has `scoreParams`, `getPeerScore`, `getPeerScoreObject`, `peerScores` or `refreshScores`; use `router.score`.
- **Message IDs changed** to Go's default (`from` bytes followed by `seqno`). Nodes on 1.x and 2.0.0 compute different IDs for the same message, so upgrade a network together.
- **`GossipSubParams`** uses Go's defaults and validation rules (see Router below).
- **Peer Exchange** is off by default (`GossipSubRouter(doPX: true)`).
- **`PubSub.stop()`** no longer disposes the tracer (dispose it yourself), keeps subscriptions, and can be followed by `start()`.
- **`Router`** gained `protocols` and `acceptFrom`; custom routers must implement them.
- **`dart_libp2p` >=4.0.1 <5.0.0** is required (was `>=1.0.0`); this release is tested only against 4.0.1.

### Security
- **A failed stream open crashed the process.** A peer that connected without speaking pubsub made the per-peer stream lock complete with an error nobody listened to, which terminated the isolate. It no longer does.
- **Inbound RPC size was unbounded.** A peer could announce a huge frame and make the node buffer it. Frames above `maxMessageSize` (default 1 MiB, `PubSub(maxMessageSize:)`) now reset the stream before being read. Outgoing RPCs are split to fit (as Go's `RPC.split`), and an oversized message is dropped.
- **IWANT replies could be amplified.** Requested IDs were not de-duplicated and could be requested without limit. Each message is now sent once per IWANT, at most `gossipRetransmission` (3) times per peer, and only to peers above the gossip threshold.
- **A PRUNE with a huge backoff aborted RPC handling.** Backoffs are now capped to `maxPruneBackoff` (24 h).
- **Messages were marked seen before their signature was checked**, so a forged copy blocked the genuine message and got honest forwarders penalised. As in Go, a message is marked seen once its signature is verified, and messages failing signature checks are not tracked.
- **IHAVE handling had no limits.** `maxIHaveMessages`, `maxIHaveLength` and IWANT promises (a peer that does not deliver an advertised message is penalised) now apply, and IHAVEs for topics not joined are ignored.
- **Graylisted peers** (score below `graylistThreshold`) have their RPCs ignored (`Router.acceptFrom`).
- **The outgoing RPC queue was unbounded** and could keep failed RPCs forever. It now holds 32 RPCs per peer with a priority lane, drops RPCs when full (traced as DROP_RPC; dropped GRAFT/PRUNEs are retried with the next RPC), and drops an RPC that fails to send.
- **Concurrent writes could interleave frames** on a stream; writes are now serialised per stream.
- A message that claims to come from this node but arrives from a peer is rejected.
- **The blacklist is enforced**, as go-libp2p-pubsub's `WithBlacklist` and `BlacklistPeer`. `PubSub(blacklist:)` takes a `Blacklist` (now exported) and `PubSub.blacklistPeer` adds a peer, removing it from the router if connected. A blacklisted peer is not added or greeted, its RPCs are ignored, and messages it forwards or wrote are dropped before validation (traced as `blacklisted peer` / `blacklisted source`) without being marked seen. Before, `Blacklist` was not used by anything.

### Interop
- **Message IDs now match Go.** The default ID is the bytes of `from` followed by `seqno` (Go's `DefaultMsgIdFn`), and `messageIDs` in IHAVE/IWANT/IDONTWANT are `bytes` (wire-compatible with Go's `string`). IDs are Dart strings with one byte per code unit (`messageIdFromBytes`, `messageIdToBytes`). `PubSub(messageIdFn:)` sets a custom ID function.
- **Protocols.** GossipSub speaks `/meshsub/1.2.0`, `1.1.0`, `1.0.0` and `/floodsub/1.0.0` and negotiates one per peer (`Router.protocols`); features follow the protocol (PX from v1.1, IDONTWANT from v1.2). FloodSub peers get every message of their topics.
- **IDONTWANT (v1.2)** is sent for large messages and honoured.
- **Signature policies**: `PubSub(signaturePolicy:)` takes `strictSign` (default), `strictNoSign`, `laxSign` or `laxNoSign`, and `noAuthor` omits `from`/`seqno`, as Go's `WithMessageSignaturePolicy` and `WithNoAuthor`.
- **Heartbeat gossip**: the heartbeat now emits IHAVE gossip for recent messages to `max(DLazy, gossipFactor * peers)` peers, so lost messages are repaired; IHAVE is no longer sent at publish time. The message cache keeps `historyLength` heartbeats and gossips the last `historyGossip`, as Go's.
- **FloodSub and RandomSub** work: they register their protocols, keep a seen cache, validate messages, and skip the source and the author. RandomSub sends to `max(RandomSubD, sqrt(networkSize))` peers.

### Peer scoring (breaking)
- Scoring was rebuilt on go-libp2p-pubsub's `score.go`: decaying counters per peer and topic, a score computed on demand from P1–P7, delivery records, IP colocation and the behaviour penalty. Before, the score accumulated on each refresh and one penalty pinned a peer near -1000.
- Scoring moved from `PubSub` to the router and is opt-in, as in Go: `GossipSubRouter(scoreParams:, scoreThresholds:)`, both required together. `PubSub` no longer has `scoreParams`, `getPeerScore`, `getPeerScoreObject`, `peerScores` or `refreshScores`; use `router.score`.
- `PeerScoreParams`, `TopicScoreParams` and `PeerScoreThresholds` have Go's fields and `validate()` rules (`topics`, `topicScoreCap`, `appSpecificWeight`, `ipColocationFactorWeight`, `behaviourPenaltyThreshold`, `gossipThreshold`, `publishThreshold`, `graylistThreshold`, `acceptPXThreshold`, `opportunisticGraftThreshold`, ...). `scoreParameterDecay` is Go's `ScoreParameterDecay`.

### Peer Exchange and lifecycle
- **The router now connects to the peers offered in a received PRUNE (Peer Exchange)**, as Go's `pxConnect`: when the sender's score is at least `acceptPXThreshold`, up to `prunePeers` of them, through `connectors` (8) concurrent attempts with at most `maxPendingConnections` (128) queued and a `connectionTimeout` (30 s). A signed peer record must be about the peer and signed by its key; its addresses are stored in the certified address book. Our PX now carries the signed records the address book has (dart_libp2p 4.0.1's identify does not store remote records, so these are mostly records learned from PX).
- **`stop()` then `start()` works**, and a peer that restarts its pubsub is picked up again:
  - `PubSub.stop()` removes all peers from the router and closes all pubsub streams; the router forgets its meshes, fanouts, backoffs and queues. `start()` registers the protocol handlers again, rejoins the subscribed topics and greets the connected peers again. Subscriptions and validators are kept across a restart.
  - `stop()` no longer disposes the tracer, which it could not reopen (as in Go, the owner of the tracer closes it).
  - As Go's `handlePeerDead`, a peer that ends our stream to it (it stopped its pubsub) is removed from the router; if it is still connected, it is greeted again with Go's dead-peer backoff (at most 4 attempts in 10 minutes), so it is added back when it restarts.
- **`PubSub.stop()` could hang forever.** Closing a stream waits for its FIN to be sent behind any data queued for a peer, and `PubSubProtocol.close()` waited for every stream with no limit, so one slow or stalled peer could block `stop()` indefinitely (reported on 1.5.0 after a burst of 100 messages). Each stream close is now bounded by `streamCloseTimeout` (default 2 s) and the stream is reset when it expires. This applies to `close()`, `closePeerStream` and the stream cleanup in `sendRpc`, whose wait stalled that peer's send queue. `close()` now also closes inbound streams, ending their read loops.

### Router (breaking)
- The heartbeat follows Go: prunes mesh peers with a negative score, keeps `DOut` outbound peers, keeps the `DScore` best peers when pruning, grafts opportunistically only when the mesh median is below `opportunisticGraftThreshold`, filters fanout by `publishThreshold`, and keeps backoffs two heartbeats past their end.
- GRAFTs from peers with a negative score, or from inbound peers when the mesh has `DHigh` peers, are refused with a PRUNE.
- Flood publish is on by default (`floodPublish`), and forwarded messages skip their author.
- Peer Exchange is off by default (`GossipSubRouter(doPX: true)`).
- `GossipSubParams`: `DScore` is now a peer count (default 4), `DLow` defaults to 5, new `DOut`, `gossipFactor`, `historyLength`, `historyGossip`, `maxIHaveLength`, `maxIHaveMessages`, `iwantFollowupTime`, `opportunisticGraftPeers`, IDONTWANT parameters; `opportunisticGraftScoreThreshold` was removed; `prunePeers` defaults to 16. `validate()` uses Go's rules.
- `Router` has `protocols` and `acceptFrom`; `PubSub` now calls `Router.addPeer` for each pubsub peer, sends its hello to every connected peer (including peers connected before `start()`), and announces subscription changes to peers being greeted.
- Validation no longer blocks reading a peer's stream.

### Also
- The public library exports the routers, `Router`, `Topic`, the protocol IDs, the message ID helpers and the tracers.
- README links point to `doc/`.

### Known limitations
- The PRUNEs we send rarely carry signed peer records: dart_libp2p 4.0.1's identify checks the records of remote peers but does not store them, so we offer mostly records learned through PX. Peer Exchange is tested with mocks, not yet on a real network.
- The tracers do not yet write Go's format (the protobuf tracer frames events with 4 bytes where Go uses a varint; the JSON tracer writes field numbers, no timestamps, and the remote peer as `peerID`).
- Topic discovery uses the namespace `gossipsub_topic:` (Go: `floodsub:`) and is not wired into `PubSub`.
- Messages for topics the node neither subscribes to nor relays are still validated.
- GossipSub v1.3 extensions are not supported.

## 1.6.0 - 2026-10-08

### Fixed
- **The heartbeat ran once a minute.** The router ran its heartbeat every `fanoutTTL` (1 minute by default), so a mesh below `DLow` waited up to a minute for new peers. The heartbeat now runs every `GossipSubParams.heartbeatInterval` (1 s), the first one `heartbeatInitialDelay` (100 ms) after `start()`, as in go-libp2p-pubsub.
- **Subscribing and unsubscribing did not join or leave the topic.** `PubSub.subscribe` and `unsubscribe` never called `Router.join` or `Router.leave`, and peers were never told of an unsubscription. `GossipSubRouter.join` only created an empty mesh, which the next heartbeat filled, and `leave` removed the mesh locally only, so the remote peers kept the node in their mesh. As in go-libp2p-pubsub, the first subscription to a topic now joins it: the router sends `GRAFT` to up to `D` connected peers with a score of at least `DScore`, first the topic's fanout peers, then other peers subscribed to the topic, and removes the topic's fanout. Cancelling the last subscription announces the unsubscription to the connected peers and leaves the topic: the router sends `PRUNE` to each mesh peer, with a backoff of `unsubscribeBackoff`.
- **Peers did not exchange subscriptions when they connected.** A node sent its subscriptions only when it subscribed, or to a peer that opened a stream to it, so two nodes that subscribed before they connected did not learn of each other's topics and built no mesh. `PubSub` now sends its subscriptions to each peer that connects, as in go-libp2p-pubsub.
- **The router kept disconnected peers.** Nothing told the router that a peer had disconnected, so the peer stayed in its meshes, fanouts and record of subscriptions. `PubSub` now calls `GossipSubRouter.removePeer` when the last connection to a peer closes, and the heartbeat removes the peers that are no longer connected, because dart_libp2p does not report every disconnect.
- **The heartbeat grafted peers that were not subscribed to the topic.** To fill a mesh below `DLow`, and for opportunistic grafting, the heartbeat picked from all connected peers. It now picks only from connected peers subscribed to the topic, as in go-libp2p-pubsub.
- **Fanout and IHAVE gossip went to peers that were not subscribed to the topic.** The heartbeat filled a topic's fanout, and `publish` chose its `IHAVE` recipients, from all connected peers. Both now pick only from connected peers subscribed to the topic, as in go-libp2p-pubsub.
- **A SUBSCRIBE added the peer to the mesh.** When a peer announced a subscription to a topic the node had joined, the router added the peer to its mesh without a `GRAFT`, so the peer did not know it was a mesh peer and the mesh could grow past `DHigh` until the next heartbeat. As in go-libp2p-pubsub, a peer now joins the mesh only through `GRAFT`; the heartbeat GRAFTs subscribed peers when the mesh is below `DLow`.
- **A GRAFT for a topic the node had not joined was accepted.** The router added the peer to a mesh for the topic. As in go-libp2p-pubsub, such a `GRAFT` is now ignored.
- **PRUNE backoffs were ignored.** The router sent `PRUNE` without a backoff from the heartbeat, ignored the backoff in the `PRUNE` messages it received, and could GRAFT a peer again at once. As in go-libp2p-pubsub, every `PRUNE` now carries a backoff (`pruneBackoff`, or `unsubscribeBackoff` on `leave`), the router does not GRAFT a peer on a topic during a backoff in either direction, and a received `PRUNE` without a backoff gives `pruneBackoff`. A peer that GRAFTs during a backoff gets a `PRUNE` and a behaviour penalty, twice if it GRAFTs within `graftFloodThreshold` of the `PRUNE`.

### Added
- `PeerScoreParams.retainScore` (default 1 hour): how long the score of a disconnected peer is kept.
- `GossipSubParams.heartbeatInterval` (default 1 s), `heartbeatInitialDelay` (default 100 ms), `opportunisticGraftTicks` (default 60), `unsubscribeBackoff` (default 10 s), `pruneBackoff` (default 1 minute) and `graftFloodThreshold` (default 10 s), with go-libp2p-pubsub's defaults.

### Changed
- Opportunistic grafting runs once every `opportunisticGraftTicks` heartbeats (once a minute by default), as in go-libp2p-pubsub. It used to run on every heartbeat, which was also once a minute.
- `PubSub.removePeer` no longer deletes the peer's score, so a peer cannot clear its penalties by reconnecting. As in go-libp2p-pubsub, the score of a disconnected peer is now kept for `PeerScoreParams.retainScore` (default 1 hour), then deleted; before, scores were never deleted.
- Peers that the router grafts are protected in the connection manager (tag `gossipsub-mesh`), as peers that graft the node already were.

## 1.5.0 - 2026-10-08

### Fixed
- **The application could not control which messages a node relays.** `registerMessageValidator` stored validators that nothing called, and the router forwarded every message with a valid signature to its mesh before the application saw it. Validation now runs before forwarding and delivery: a message is forwarded to the mesh and delivered to subscribers only when it is accepted. `registerMessageValidator((topic, message) => bool)` now works for all topics: `true` accepts and `false` rejects.
- **Duplicates were validated again.** The router verified the signature of each copy of a message before its duplicate check. The duplicate check is now first, and a message is marked seen before validation, whatever the result, so each message is validated once. The seen cache keeps message IDs for `GossipSubParams.seenMessagesTTL` (2 minutes, as in go-libp2p-pubsub), not only for the 5-second message-cache window.
- **Rejected messages cost the sender nothing.** The router treated reject and ignore alike, and the invalid-message penalty (P3b) had weight 0 and no decay. Now a rejected message penalises the peer that delivered it (not the author) on the topic; ignore gives no penalty. A peer that sends a copy of a rejected message is penalised too. P3b follows go-libp2p-pubsub: the penalty is `invalidMessageDeliveriesWeight * counter^2`, it applies at once, and the counter decays by `invalidMessageDeliveriesDecay` per `decayInterval` and is set to 0 below `decayToZero`.

### Added
- `PubSub.registerTopicValidator(topic, validator, {timeout, concurrency})` and `PubSub.unregisterTopicValidator(topic)`, as in go-libp2p-pubsub. A `TopicValidator` can be async and returns `ValidationResult.accept`, `reject` or `ignore`. A run that takes longer than `timeout` gives `ignore`; when more than `concurrency` runs (default 1024) are active for the topic, new messages are dropped as `ignore`. A validator that throws gives `ignore`.
- `PubSub` constructor arguments `validatorTimeout` (default 5 s; `Duration.zero` means no limit) and `validateThrottle` (default 8192 concurrent validations, as in go-libp2p-pubsub; more messages are dropped as `ignore`).
- `GossipSubParams.seenMessagesTTL` (default 2 minutes).
- `TopicScoreStats.decayedInvalidMessageDeliveries`, the decayed P3b counter.
- `ValidationResult`, `PeerScoreParams` and `TopicScoreParams` are now exported from `package:dart_libp2p_pubsub/dart_libp2p_pubsub.dart`.
- Dropped messages are traced as `REJECT_MESSAGE` with go-libp2p-pubsub's reasons (`validation failed`, `validation ignored`, `validation throttled`, `invalid signature`, plus `validation timeout` and `invalid message`).

### Changed
- **`invalidMessageDeliveriesWeight` now defaults to -1.0 and `invalidMessageDeliveriesDecay` to 0.9987** (was 0 and 1.0). 1 rejected message gives -1, 2 give -4, 10 give -100 (the default `graylistThreshold`); with the default 1 s `decayInterval`, the counter for one message decays to zero in about 1 hour. Applications should tune these values (see doc/5_configuration.md). Set the weight to 0 to keep the old behaviour.
- Validators registered with `registerMessageValidator` now also run on messages that the node publishes, as topic validators do. A rejected local message is dropped with a warning.
- `REJECT_MESSAGE` is now traced by `PubSub.validateMessage`, not by `GossipSubRouter.handleRpc`, and its `reason` is one of the strings above (was `reject` or `ignore`).
- The messages of one RPC are validated concurrently; the RPC's subscriptions and control messages are handled while validation runs.

## 1.4.2 - 2026-10-04

### Fixed
- **Library code wrote debug output to stdout with `print`.** A GossipSub node printed several lines for every message and RPC, which buried an application's own output. The library now logs through `package:logging`, with one named logger per component (`PubSub`, `PubSubComm`, `GossipSubRouter`, `RpcQueue`, `Validation`, `Sign`, and so on). Applications control the output with `Logger.root.level` or hierarchical logging. Routine traffic and problems caused by remote peers log at `FINE` (per-RPC queue chatter at `FINEST`); local faults, such as an error in an application callback, log at `WARNING`. `JsonEventTracer` and `PbEventTracer` still print their trace output when no sink is given, as documented.

## 1.4.1 - 2026-10-04

### Fixed
- **PubSub without a `privateKey` dropped every message it published** (#2). Messages were signed only when a `privateKey` was passed, but validation requires a signature, so `PubSub(host, router)` (as in `example/chat.dart`) rejected its own messages as unsigned. Messages are now signed with the host's own key from its peerstore when no `privateKey` is given, as go-libp2p-pubsub does. A host whose peerstore holds no private key now fails `publish` with a `StateError` instead of dropping the message silently.

## 1.4.0 - 2026-10-04

### Changed
- **Works with dart_libp2p 3.x and 4.x**: `dart_libp2p` is now `>=1.0.0 <5.0.0` and `dart_udx` is `>=2.0.1 <5.0.0`. Neither release changes an API this package uses. All 163 tests and the Go interop test pass against dart_libp2p 4.0.0 with dart_libp2p_kad_dht 1.4.0, which is the first kad-dht release that accepts dart_libp2p 4.x. The upper bounds had made this package unresolvable alongside dart_libp2p 3.0.0 or later.
- **A fresh clone builds from published packages.** The local path overrides moved out of `pubspec.yaml` into a git-ignored `pubspec_overrides.yaml` (see README).
- The Go GossipSub interop test moved here from dart_libp2p. It builds the go-libp2p peer from a dart_libp2p checkout (`GO_PEER_DIR`, or `../dart-libp2p/interop/go-peer`).

## 1.3.0 - 2026-09-23

### Changed
- **Dependency constraints widened so this package works with dart_libp2p 2.x**: `dart_libp2p` is now `>=1.0.0 <3.0.0`, `dart_libp2p_kad_dht` is `>=1.3.0 <2.0.0` and `dart_udx` is `>=2.0.1 <4.0.0`. dart_libp2p 2.0.0 changes no API used here; it requires dart_udx 3.0.0, whose wire protocol v3 does not interoperate with v2. The previous pins made this package unresolvable alongside dart_libp2p 2.x, so a consumer could not upgrade either.

## 1.2.1 - 2026-02-22

### Fixed
- Go interop: Extract public key from PeerId when key field is absent (Ed25519 inline keys)
- `verifyMessageSignature()` now falls back to peer ID key extraction instead of rejecting, matching go-libp2p-pubsub behavior

## 1.2.0 - 2026-02-21

### Changed
- Router `handleRpc` now returns accepted message IDs (`Set<String>`) so PubSub only delivers messages the router actually accepted, preventing double-delivery
- Signature verification strictly requires an embedded public key (reject messages without one)

### Fixed
- FloodSub and RandomSub double-delivery of messages to local subscribers
- GossipSub publish to topics without mesh peers now builds fanout from known subscribed peers
- Test mocks updated to match new Router interface and Network requirements

## 1.1.0 - 2026-02-17

### Added
- Go-libp2p GossipSub interop compatibility
- Strict signature validation with key-PeerId consistency check
- IdentifyTimeoutException handling to prevent crashes
- Stream re-use for RPC message sending
- Connection protection for critical peers

### Fixed
- Test failures in gossipsub and validation tests
- Network errors crashing host app

### Changed
- Updated `dart_libp2p` dependency to `^1.0.0`
- Updated `dart_libp2p_kad_dht` dependency to `^1.2.0`
- Updated `dart_udx` dependency to `^2.0.1`

## 1.0.1

### Features

#### Core PubSub System
- **Complete PubSub Implementation**: Full publish-subscribe pattern with topic-based messaging
- **Message Handling**: Robust message routing, delivery, and subscription management
- **Topic Management**: Dynamic topic creation, subscription, and unsubscription
- **Message Validation**: Custom validator support for topic-specific message validation
- **Peer Management**: Comprehensive peer discovery, connection, and lifecycle management

#### Multiple PubSub Protocols
- **GossipSub v1.1**: Production-ready mesh-based pubsub protocol with efficient message propagation
  - Two-tiered network structure (mesh + gossip network)
  - Dynamic mesh maintenance with GRAFT/PRUNE control messages
  - Heartbeat-based network health monitoring
  - Message caching (MCache) for deduplication and IHAVE/IWANT support
  - Configurable mesh parameters (D, DLow, DHigh, DScore)
  - Fanout management for non-subscribed topic publishing
  - Opportunistic grafting for mesh strengthening
  - Peer Exchange (PX) mechanism for network connectivity

- **FloodSub**: Simple flooding protocol for development and testing
- **RandomSub**: Randomized message propagation for research and experimentation

#### Security & Network Health
- **Peer Scoring System**: Comprehensive scoring mechanism to protect against malicious behavior
  - Behavior-based scoring with configurable parameters
  - Automatic peer blacklisting for misbehaving nodes
  - Score decay and threshold management
  - Opportunistic grafting based on peer scores

- **Message Validation**: Topic-specific message validation with custom validators
- **Cryptographic Support**: Message signing and verification capabilities

#### Monitoring & Debugging
- **Event Tracing**: Comprehensive tracing system for debugging and monitoring
  - JSON tracer for human-readable trace output
  - Protocol Buffer tracer for efficient binary trace format
  - Trace event types for different pubsub operations
  - Configurable tracing levels and output formats

- **Built-in Logging**: Integrated logging system with configurable levels
- **Metrics Support**: Performance and network health metrics

#### Performance & Optimization
- **Message Caching**: Efficient MCache implementation for message deduplication
- **RPC Queue Management**: Optimized outgoing RPC queue management
- **Configurable Parameters**: Extensive configuration options for different use cases
  - Mesh size control (D, DLow, DHigh)
  - Gossip propagation settings (DLazy)
  - Fanout TTL configuration
  - Peer scoring thresholds
  - Prune and Peer Exchange settings

#### Developer Experience
- **Comprehensive Documentation**: Complete documentation suite covering:
  - Network setup and configuration
  - Basic pub/sub operations
  - GossipSub deep dive and advanced concepts
  - Testing strategies and examples
  - Configuration and tuning guidelines
  - Best practices and common pitfalls

- **Example Applications**: Working chat application demonstrating real-world usage
- **Integration Tests**: Comprehensive test suite with real network integration
- **Mock Support**: Mockito-based testing support for isolated unit tests

### Technical Implementation
- **Protocol Buffer Support**: Full protobuf integration for RPC messages and tracing
- **Async/Await Support**: Modern Dart async programming patterns throughout
- **Stream-based API**: Reactive programming with Dart streams for message handling
- **Resource Management**: Proper cleanup and resource management
- **Error Handling**: Comprehensive error handling and recovery mechanisms

### Dependencies
- **dart_libp2p**: Core libp2p networking stack integration
- **dart_libp2p_kad_dht**: Kademlia DHT support for peer discovery
- **dcid**: Content identifier support
- **Cryptography**: Advanced cryptographic operations
- **Protobuf**: Protocol buffer serialization
- **Logging**: Structured logging support

## 1.0.0

- Initial version.
