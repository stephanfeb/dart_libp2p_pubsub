# 3. GossipSub Deep Dive

While the basic pub/sub operations are straightforward, understanding the underlying mechanics of GossipSub can help you build more efficient and resilient applications. This section explores the core concepts that make GossipSub robust.

The implementation details can be found primarily in `lib/src/gossipsub/gossipsub.dart`.

## The Two-Tiered Network Structure

GossipSub operates on a two-tiered structure for each topic:

1.  **The Mesh**: A small, tightly-connected group of peers that receive the full content of every message immediately.
2.  **The Gossip Network**: A larger, loosely-connected group of peers that only receive message metadata (gossip) initially.

This structure is the key to GossipSub's efficiency: it avoids flooding the entire network with every message, while still ensuring that messages are eventually propagated to everyone interested.

The following diagram illustrates this concept:

```mermaid
graph TD
    subgraph Topic: "news-alerts"
        A((Node A))
        B((Node B))
        C((Node C))
        D((Node D))
        E((Node E))
        F((Node F))

        subgraph Mesh (Full Messages)
            A --- B
            B --- C
            C --- A
        end

        subgraph Gossip (Metadata Only)
            A -.-> D
            B -.-> E
            C -.-> F
        end
    end

    style Mesh fill:#f9f,stroke:#333,stroke-width:2px
    style Gossip fill:#ccf,stroke:#333,stroke-width:2px
```

### The Mesh (`mesh` map)

For every topic a node is subscribed to, it aims to maintain a connection to a small number of other peers who are also subscribed to that topic. This group is its "mesh".

-   **Full Message Propagation**: When a peer in the mesh receives a new message, it immediately forwards the full message content to all other peers in its mesh for that topic.
-   **Building and Maintaining the Mesh**: The mesh is dynamic. It's built and maintained using two primary control messages:
    -   `GRAFT`: A peer sends a `GRAFT` message to another peer to request being added to their mesh for a specific topic. This typically happens when a node subscribes to a new topic and needs to find peers to receive messages from.
    -   `PRUNE`: A peer sends a `PRUNE` message to remove another peer from its mesh. This can happen if the mesh has grown too large or if the peer is misbehaving.

### Gossip and Lazy Propagation (`fanout` map)

Peers that are not in the mesh for a topic still participate in gossip.

-   **Gossip Propagation**: When a node receives a new message, it doesn't forward the full message to its non-mesh peers. Instead, it waits a short period and then "gossips" about the message by sending an `IHAVE` control message to a random selection of its peers in the topic (its "fanout" group).
-   **Requesting Full Messages**: A peer receiving an `IHAVE` message for a message it hasn't seen yet can then request the full message by sending back an `IWANT` message.

This "lazy" propagation ensures that messages spread throughout the network without the high overhead of sending the full content to every single peer.

## Heartbeats: Keeping the Mesh Healthy

The `GossipSubRouter` periodically sends heartbeat messages to all of its connected peers. These heartbeats serve several purposes:

-   **Mesh Maintenance**: Heartbeats give peers an opportunity to `GRAFT` or `PRUNE` connections, ensuring the mesh stays healthy and within its configured size limits.
-   **Gossip Exchange**: The heartbeat mechanism is also used to piggyback and send `IHAVE` gossip to other peers.
-   **Peer Discovery**: It helps in discovering other peers and their topic subscriptions.

The heartbeat is a fundamental background process in `GossipSubRouter` that runs continuously.

## Message Caching (`mcache`)

To prevent processing and propagating the same message multiple times, GossipSub maintains a `MessageCache`.

-   **Deduplication**: When a message is received, its ID is checked against the cache. If the ID is already in the cache, the message is dropped.
-   **History for `IHAVE`/`IWANT`**: The cache also stores the full message content for a short period. This allows the node to respond to `IWANT` requests from other peers who have only received the gossip (`IHAVE`) for that message.

The `mcache` is a crucial component for network efficiency, implemented in `lib/src/gossipsub/mcache.dart`.

## Peer Scoring

To protect the network from malicious behavior (like spamming or withholding messages), GossipSub includes a peer scoring mechanism. Each peer maintains a score for its connected peers based on their behavior.

-   **Positive Scores**: Awarded for good behavior, such as forwarding messages promptly.
-   **Negative Scores**: Given for misbehavior, such as sending invalid messages or failing to connect.

If a peer's score drops below a certain threshold, it can be blacklisted, and connections to it may be dropped. This system, detailed in `lib/src/gossipsub/score.dart`, makes the network more resilient to attacks.

---

**Next**: [4. Testing Your Application](./4_testing.md)
