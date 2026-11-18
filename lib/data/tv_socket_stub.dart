import 'package:web_socket_channel/web_socket_channel.dart';

/// Opens the TradingView socket on platforms without dart:io (web).
/// Browsers forbid custom handshake headers and already send an Origin
/// header of their own, so a plain connect is all we can (and need to) do.
WebSocketChannel connectTvSocket(Uri uri) => WebSocketChannel.connect(uri);
