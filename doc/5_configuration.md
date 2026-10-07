# 5. Configuration and Tuning

GossipSub is highly configurable, allowing you to tune its behavior to suit your application's specific needs. These parameters are managed through the `GossipSubParams` class, which can be passed to the `GossipSubRouter` constructor.

Understanding these parameters is key to optimizing for different network conditions, whether you need high throughput, low latency, or resilience in a hostile environment.

```dart
// Example of creating a router with custom parameters
final customParams = GossipSubParams(
  D: 8,
  DHigh: 16,
  DLow: 6,
  fanoutTTL: Duration(seconds: 30),
);

final router = GossipSubRouter(params: customParams);
```

## Key Parameters

The following are the most important parameters you can configure in `GossipSubParams`.

### Mesh Size Control

These parameters control the number of peers in your node's mesh for any given topic. The mesh is the set of peers to which you forward full messages immediately.

-   `D` (default: `6`): The **desired** number of peers in the mesh. This is the target number the router will try to maintain.
-   `DLow` (default: `4`): The **minimum** number of peers in the mesh. If the number of mesh peers drops below this, the router will actively seek out new peers to `GRAFT`.
-   `DHigh` (default: `12`): The **maximum** number of peers in the mesh. If the number of mesh peers exceeds this, the router will `PRUNE` connections to bring it back towards `D`.

**Tuning Advice**:
*   A larger `D` increases robustness (more paths for messages to flow) at the cost of increased bandwidth, as you are sending full messages to more peers.
*   For topics with high message rates, a slightly larger `D` might be beneficial.
*   The gap between `DLow` and `DHigh` prevents the network from constantly grafting and pruning, a behavior known as "churn".

### Gossip Propagation (`DLazy`)

-   `DLazy` (default: `6`): The number of non-mesh peers to whom you will send `IHAVE` gossip messages. This controls how widely your messages are announced to the broader network.

**Tuning Advice**:
*   Increasing `DLazy` can speed up message propagation to peers outside your immediate mesh, at the cost of more control message overhead.

### Heartbeat

The heartbeat is the router's periodic task, as in go-libp2p-pubsub. It keeps each mesh between `DLow` and `DHigh` peers, prunes mesh peers with a negative score, maintains the fanouts, gossips the IDs of recent messages (`IHAVE`) and penalises peers that did not deliver messages they advertised.

-   `heartbeatInterval` (default: `1 second`): The time between heartbeats.
-   `heartbeatInitialDelay` (default: `100 ms`): The time from `GossipSubRouter.start()` to the first heartbeat.
-   `opportunisticGraftTicks` (default: `60`): Opportunistic grafting (see below) runs once every this many heartbeats.

These defaults are go-libp2p-pubsub's. All nodes in a network should use the same heartbeat interval.

### Joining and Leaving Topics

When the node subscribes to a topic, the router sends `GRAFT` to up to `D` peers at once. It picks them first from the topic's fanout, then from the other connected peers subscribed to the topic, and leaves out peers with a negative score or in a backoff. When the node unsubscribes, the router sends `PRUNE` to each of its mesh peers for the topic.

-   `unsubscribeBackoff` (default: `10 seconds`): The backoff in the `PRUNE` messages sent on unsubscribe. It asks the pruned peers not to `GRAFT` the node again for this time.

### Backoff

Every `PRUNE` carries a backoff: the time during which the two peers must not `GRAFT` each other again for the topic. The router keeps the backoff of the `PRUNE` messages it sends and receives, and does not `GRAFT` a peer during one.

-   `pruneBackoff` (default: `1 minute`): The backoff in the `PRUNE` messages that the heartbeat sends, and the backoff applied when a received `PRUNE` has none.
-   `graftFloodThreshold` (default: `10 seconds`): A peer that sends `GRAFT` during a backoff gets a `PRUNE` and a behaviour penalty (P6); it gets a second penalty if it sends the `GRAFT` within this time of the `PRUNE`.

### Fanout Control

The "fanout" is the set of peers you send full messages to for a topic you are **not** subscribed to but have published to. This ensures your message gets into the network.

-   `fanoutTTL` (default: `1-minute`): The duration for which a fanout map is maintained for a topic after you last published to it.

**Tuning Advice**:
*   If your application publishes infrequently to many topics, a shorter `fanoutTTL` can reduce memory usage.

### Mesh Degree and Gossip

The defaults are go-libp2p-pubsub's.

-   `D` (6), `DLow` (5), `DHigh` (12): the target mesh size and its bounds. The heartbeat GRAFTs peers below `DLow` and PRUNEs back to `D` at `DHigh` or more.
-   `DScore` (4): when pruning an oversized mesh, the number of peers kept for their score; the rest are kept at random.
-   `DOut` (2): the number of outbound peers (connections the node dialed) kept in each mesh, against Sybils that connect to the node. Must be below `DLow` and `D/2`.
-   `DLazy` (6) and `gossipFactor` (0.25): each heartbeat gossips to `max(DLazy, gossipFactor * peers)` topic peers outside the mesh.
-   `historyLength` (5) and `historyGossip` (3): messages stay in the message cache for 5 heartbeats, for `IWANT`; the last 3 are gossiped.
-   `maxIHaveLength` (5000), `maxIHaveMessages` (10), `iwantFollowupTime` (3 s), `gossipRetransmission` (3): limits on gossip from and to a peer. A peer that does not deliver a message it advertised within `iwantFollowupTime` gets a behaviour penalty.
-   `floodPublish` (true): the node's own messages go to every topic peer with a score of at least `publishThreshold`, not only to the mesh.
-   `opportunisticGraftTicks` (60) and `opportunisticGraftPeers` (2): when the median score of a mesh is below `opportunisticGraftThreshold`, the heartbeat GRAFTs up to 2 peers that score above the median.
-   IDONTWANT (GossipSub v1.2): for a received message of at least `idontwantMessageThreshold` (1 KiB) bytes, the node tells its v1.2 mesh peers not to send it a copy.

`D = DLow = DHigh = DOut = DScore = 0` is the bootstrapper setting: no mesh.

### Protocols

`GossipSubRouter` speaks `/meshsub/1.2.0`, `/meshsub/1.1.0`, `/meshsub/1.0.0` and `/floodsub/1.0.0`, in that order of preference, and uses the features of the protocol negotiated with each peer. FloodSub peers get every message of their topics. `FloodSubRouter` and `RandomSubRouter` are also available.

### Message Validation

-   `seenMessagesTTL` (`GossipSubParams`, default: `2 minutes`): How long the router remembers a message ID. A copy that arrives within this time is dropped as a duplicate without validation.
-   `validatorTimeout` (`PubSub` constructor, default: `5 seconds`): The default time limit for one run of a topic validator. A slower run gives `ignore`. `Duration.zero` means no limit. `registerTopicValidator(..., timeout:)` sets it per topic.
-   `validateThrottle` (`PubSub` constructor, default: `8192`): The maximum number of messages in validation at the same time. More messages are dropped as `ignore`. `registerTopicValidator(..., concurrency:)` sets a per-topic limit (default `1024`).

See [Validating Messages](./2_gossipsub_usage.md#6-validating-messages).

### Peer Scoring

Peer scoring is off by default, as in go-libp2p-pubsub. Turn it on by giving the router both score parameters and thresholds (go-libp2p-pubsub's `WithPeerScore`):

```dart
final router = GossipSubRouter(
  scoreParams: PeerScoreParams(
    topics: {
      'chat': TopicScoreParams(
        topicWeight: 1,
        invalidMessageDeliveriesWeight: -10, // P4: weight * count^2
        invalidMessageDeliveriesDecay: scoreParameterDecay(const Duration(hours: 1)),
      ),
    },
    behaviourPenaltyWeight: -10, // P7
    behaviourPenaltyDecay: scoreParameterDecay(const Duration(hours: 1)),
  ),
  scoreThresholds: const PeerScoreThresholds(
    gossipThreshold: -10,
    publishThreshold: -50,
    graylistThreshold: -80,
    acceptPXThreshold: 10,
    opportunisticGraftThreshold: 5,
  ),
);
```

The score follows go-libp2p-pubsub's `score.go`: per scored topic, P1 (time in mesh), P2 (first deliveries), P3 (mesh delivery deficit), P3b (mesh failure penalty) and P4 (invalid messages), weighted by `topicWeight` and capped by `topicScoreCap`; then P5 (application-specific), P6 (IP colocation) and P7 (behaviour penalty). Only the topics in `topics` are scored. Both parameter sets are validated with go-libp2p-pubsub's rules. `router.score` gives each peer's score and its components (`snapshot`).

The thresholds: below `gossipThreshold` a peer gets no gossip and its gossip is ignored; below `publishThreshold` it gets none of our published messages; below `graylistThreshold` its RPCs are ignored. With all thresholds at 0, any negative score graylists a peer.

-   `retainScore` (`PeerScoreParams`, default: `1 hour`): how long the score of a disconnected peer with a score of 0 or less is kept, so that the peer cannot clear its penalties by reconnecting.

### Prune and Peer Exchange (PX)

Peer Exchange is off by default, as in go-libp2p-pubsub (`WithPeerExchange`); `GossipSubRouter(doPX: true)` turns it on, for bootstrappers and other well-connected nodes.

-   `prunePeers` (default: `16`): The number of other topic peers with a score of 0 or more to include in a `PRUNE`, with their signed peer records when the address book has them. No PX is sent to a peer pruned for a negative score. It is also the most peers connected to from one received `PRUNE`.

Whatever `doPX` is, the router connects to the PX peers of a received `PRUNE` if the sender's score is at least `acceptPXThreshold` (`PeerScoreThresholds`, default `0`), as go-libp2p-pubsub does. A signed peer record must be about the peer and signed by its key; its addresses are stored in the address book for two minutes, then the peer is dialed at the addresses known for it.

-   `connectors` (default: `8`): the PX connections attempted at once.
-   `maxPendingConnections` (default: `128`): the PX peers waiting to be connected to; more are ignored.
-   `connectionTimeout` (default: `30 seconds`): how long a PX connection attempt may take.

**Tuning Advice**:
*   A higher value can help pruned peers reconnect faster, improving overall network health.
