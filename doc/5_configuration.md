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

The heartbeat is the router's periodic task. It keeps each mesh between `DLow` and `DHigh` peers, refreshes peer scores and expires fanout state.

-   `heartbeatInterval` (default: `1 second`): The time between heartbeats.
-   `heartbeatInitialDelay` (default: `100 ms`): The time from `GossipSubRouter.start()` to the first heartbeat.
-   `opportunisticGraftTicks` (default: `60`): Opportunistic grafting (see below) runs once every this many heartbeats.

These defaults are go-libp2p-pubsub's. All nodes in a network should use the same heartbeat interval.

### Joining and Leaving Topics

When the node subscribes to a topic, the router sends `GRAFT` to up to `D` peers at once. It picks them first from the topic's fanout, then from the other connected peers subscribed to the topic, and leaves out peers with a score below `DScore`. When the node unsubscribes, the router sends `PRUNE` to each of its mesh peers for the topic.

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

### Peer Scoring and Grafting

These parameters control how peer scores affect mesh management.

-   `DScore` (default: `0.0`): The minimum score a peer must have to be included or remain in the mesh. Peers with scores below this are more likely to be pruned.
-   `opportunisticGraftScoreThreshold` (default: `10.0`): During heartbeats, if the mesh is not full, the router can "opportunistically" `GRAFT` onto peers with a score above this threshold. This helps strengthen the mesh with known good actors.

**Tuning Advice**:
*   In a network where you expect malicious actors, you might increase these thresholds to be more selective about who you connect to.
*   Setting these too high can make it difficult to form a mesh in a new or small network.

### Message Validation

-   `seenMessagesTTL` (`GossipSubParams`, default: `2 minutes`): How long the router remembers a message ID. A copy that arrives within this time is dropped as a duplicate without validation.
-   `validatorTimeout` (`PubSub` constructor, default: `5 seconds`): The default time limit for one run of a topic validator. A slower run gives `ignore`. `Duration.zero` means no limit. `registerTopicValidator(..., timeout:)` sets it per topic.
-   `validateThrottle` (`PubSub` constructor, default: `8192`): The maximum number of messages in validation at the same time. More messages are dropped as `ignore`. `registerTopicValidator(..., concurrency:)` sets a per-topic limit (default `1024`).

See [Validating Messages](./2_gossipsub_usage.md#6-validating-messages).

### Invalid-Message Penalty (P3b)

Peer scoring is always on: each `PubSub` uses `PeerScoreParams.defaultParams` unless you pass `scoreParams`. When validation rejects a message, the peer that delivered it gets a penalty on the topic of `invalidMessageDeliveriesWeight * counter^2` (P3b in the GossipSub v1.1 specification). Each rejected message adds 1 to the counter. The penalty applies at once; the counter is multiplied by `invalidMessageDeliveriesDecay` once per `decayInterval` and set to 0 when it falls below `decayToZero`. `ignore` results give no penalty.

-   `invalidMessageDeliveriesWeight` (`TopicScoreParams`, default: `-1.0`): 1 rejected message gives -1, 2 give -4, 4 give -16, 10 give -100 (the default `graylistThreshold`). A peer with a negative score is not chosen for the mesh, fanout or gossip in normal selection. `0` turns the penalty off.
-   `invalidMessageDeliveriesDecay` (`TopicScoreParams`, default: `0.9987`): With the default `decayInterval` of 1 second, the counter for one message decays to zero in about 1 hour (as `ScoreParameterDecay(time.Hour)` in go-libp2p-pubsub). If you change `decayInterval`, change this too.
-   `retainScore` (`PeerScoreParams`, default: `1 hour`): How long the score of a disconnected peer is kept, so that the peer cannot clear its penalties by reconnecting. The score is deleted when the peer has been disconnected for this time. Keep it at least as long as your penalties take to decay.

```dart
final scoreParams = PeerScoreParams(
  defaultTopicParams: TopicScoreParams(
    invalidMessageDeliveriesWeight: -10.0, // stricter: 4 invalid messages => -160
    invalidMessageDeliveriesDecay: 0.9987,
  ),
  topicParamsOverrides: {
    'chat': TopicScoreParams(invalidMessageDeliveriesWeight: -1.0),
  },
);
final pubsub = PubSub(host, router, scoreParams: scoreParams);
```

**Tuning Advice**:
*   The defaults are a moderate starting point. Tune the weight to how much one invalid message on your topic is worth, relative to `graylistThreshold` and `DScore`.
*   Note that `topicParamsOverrides` replaces all the parameters of a topic, so set the P3b fields in each override.

### Prune and Peer Exchange (PX)

-   `prunePeers` (default: `5`): The number of alternative peers (from your own mesh) to include in a `PRUNE` message sent to another peer. This is the Peer Exchange (PX) mechanism, which helps the pruned peer find new connections and maintain network connectivity.

**Tuning Advice**:
*   A higher value can help pruned peers reconnect faster, improving overall network health.
