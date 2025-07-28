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

### Prune and Peer Exchange (PX)

-   `prunePeers` (default: `5`): The number of alternative peers (from your own mesh) to include in a `PRUNE` message sent to another peer. This is the Peer Exchange (PX) mechanism, which helps the pruned peer find new connections and maintain network connectivity.

**Tuning Advice**:
*   A higher value can help pruned peers reconnect faster, improving overall network health.
