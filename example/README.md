# PubSub Chat Example

This directory contains a simple command-line chat application that demonstrates the core features of the `dart-libp2p-pubsub` library.

## Features Demonstrated

-   Creating a libp2p Host.
-   Initializing the `PubSub` service with `GossipSubRouter`.
-   Connecting to a peer using a `MultiAddr`.
-   Subscribing to a topic.
-   Publishing messages from standard input.
-   Receiving and displaying messages from the network.
-   Graceful shutdown.

## How to Run

### Prerequisites

You need to have the Dart SDK installed.

The example code in `chat.dart` relies on a helper function, `createLibp2pNode`, which is fully implemented in the project's test suite at `test/real_net_stack.dart`. To make this example runnable, you would need to:

1.  Copy `test/real_net_stack.dart` into the `example/` directory.
2.  Update `example/chat.dart` to import it: `import 'real_net_stack.dart';`.
3.  Replace the dummy `createLibp2pNode` function at the bottom of `chat.dart` with the actual implementation.

### Running the Chat

After setting up the `createLibp2pNode` function, you can run the chat application.

1.  **Open two terminal windows.**

2.  **In the first terminal**, start the first chat node:
    ```sh
    dart run example/chat.dart
    ```
    The application will start and print its listen address, which includes its unique PeerId. It will look something like this:
    ```
    INFO: 2023-10-27 10:30:00: ChatExample: Listen addresses: [/ip4/127.0.0.1/udp/54321/udx/p2p/12D3KooW...somePeerId]
    ```

3.  **Copy the full listen address** from the first terminal.

4.  **In the second terminal**, start the second node and pass the first node's address as an argument:
    ```sh
    dart run example/chat.dart <paste_address_from_first_terminal_here>
    ```
    For example:
    ```sh
    dart run example/chat.dart /ip4/127.0.0.1/udp/54321/udx/p2p/12D3KooW...somePeerId
    ```

5.  The two nodes will connect. You can now type a message in either terminal and press `Enter` to send it. The message will appear on the other node's screen.

6.  To exit, press `Ctrl+C` in either terminal.
