import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/multiaddr.dart';
import 'package:dart_libp2p/core/network/rcmgr.dart';
import 'package:dart_libp2p/core/peer/addr_info.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/p2p/host/eventbus/basic.dart' as p2p_event_bus;
import 'package:dart_libp2p/p2p/transport/connection_manager.dart' as p2p_conn_mgr;
import 'package:dart_libp2p_pubsub/dart_libp2p_pubsub.dart';
import 'package:dart_udx/dart_udx.dart';
import 'package:logging/logging.dart';

// Note: To run this example, you would need to copy or import the `createLibp2pNode`
// function from `test/real_net_stack.dart`. For simplicity, this example assumes
// it's available in a file named `real_net_stack.dart` in the same directory.
// As this is a standalone example, we will include a simplified version of it here.

// A simplified node creation helper for the example.
Future<Host> createNode() async {
  final udxInstance = UDX();
  final resourceManager = NullResourceManager();
  final connManager = p2p_conn_mgr.ConnectionManager();
  final eventBus = p2p_event_bus.BasicBus();

  // This is a simplified version of the function in `test/real_net_stack.dart`
  // In a real application, you would use the full version.
  final nodeDetails = await createLibp2pNode(
    udxInstance: udxInstance,
    resourceManager: resourceManager,
    connManager: connManager,
    hostEventBus: eventBus,
    userAgentPrefix: 'p2p-chat-example',
  );
  return nodeDetails.host;
}


/// A simple command-line chat application using libp2p PubSub.
///
/// To run this example:
/// 1. Open two terminal windows.
/// 2. In the first terminal, run: `dart example/chat.dart`
/// 3. The first terminal will print its listen address. Copy it.
/// 4. In the second terminal, run: `dart example/chat.dart <address_from_terminal_1>`
/// 5. The two nodes will connect, and you can type messages in either terminal.
void main(List<String> args) async {
  // Configure logging
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  final log = Logger('ChatExample');

  // --- 1. Create and start the libp2p node ---
  log.info('Starting libp2p node...');
  final host = await createNode();
  log.info('Node started with PeerId: ${host.id.toBase58()}');
  log.info('Listen addresses: ${host.addrs}');

  // --- 2. Set up PubSub with GossipSub ---
  log.info('Initializing GossipSub...');
  final router = GossipSubRouter();
  final pubsub = PubSub(host, router);
  await pubsub.start();
  log.info('GossipSub started.');

  // --- 3. Connect to a peer if an address is provided ---
  if (args.isNotEmpty) {
    try {
      final remoteAddrStr = args[0];
      final remoteAddr = MultiAddr(remoteAddrStr);
      
      final parts = remoteAddrStr.split('/');
      final p2pIndex = parts.indexOf('p2p');
      if (p2pIndex == -1 || p2pIndex + 1 >= parts.length) {
        throw Exception('Provided address does not contain a PeerId: $remoteAddrStr');
      }
      final remotePeerIdStr = parts[p2pIndex + 1];
      final remotePeerId = PeerId.fromString(remotePeerIdStr);
      log.info('Connecting to peer: $remoteAddr');
      await host.connect(AddrInfo(remotePeerId, [remoteAddr]));
      log.info('Connected to ${remotePeerId.toBase58()}');
    } catch (e) {
      log.severe('Failed to connect to peer: $e');
      exit(1);
    }
  } else {
    log.info('No peer address provided. Running as the first node.');
    log.info('Run another instance with one of the listen addresses to connect.');
  }

  // Allow time for GossipSub mesh to form
  log.info('Waiting for GossipSub mesh to form...');
  await Future.delayed(Duration(seconds: 5));

  // --- 4. Subscribe to the chat topic ---
  const topic = '/libp2p-chat/1.0.0';
  log.info('Subscribing to topic: $topic');
  final subscription = pubsub.subscribe(topic);

  // --- 5. Listen for and print incoming messages ---
  subscription.stream.listen((message) {
    // Don't print our own messages
    if (message.from == host.id) {
      return;
    }
    final sender = message.from.toBase58().substring(0, 6);
    final text = utf8.decode(message.data);
    // Clear the current line, print the message, and redraw the prompt
    stdout.write('\r');
    print('[$sender]: $text');
    stdout.write('> ');
  });

  log.info('Chat started! Type a message and press Enter to send.');

  // --- 6. Read from stdin and publish messages ---
  stdout.write('> ');
  stdin.transform(utf8.decoder).transform(LineSplitter()).listen((line) async {
    final messageData = Uint8List.fromList(utf8.encode(line));
    await pubsub.publish(topic, messageData);
    stdout.write('> ');
  });

  // Clean up on exit
  await ProcessSignal.sigint.watch().first;
  log.info('Shutting down...');
  await pubsub.stop();
  await host.close();
  exit(0);
}

// Dummy createLibp2pNode for standalone example.
// In a real project, this would be the full implementation from `test/real_net_stack.dart`.
// This is a placeholder and will not run without the actual implementation.
Future<({Host host, PeerId peerId, List<MultiAddr> listenAddrs})> createLibp2pNode({
  required UDX udxInstance,
  required ResourceManager resourceManager,
  required p2p_conn_mgr.ConnectionManager connManager,
  required p2p_event_bus.BasicBus hostEventBus,
  String? userAgentPrefix,
}) async {
  // This function needs the full implementation from `test/real_net_stack.dart`
  // to be runnable. This is a structural placeholder.
  throw UnimplementedError(
      'This example requires the full createLibp2pNode implementation.');
}
