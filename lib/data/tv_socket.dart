/// Platform-appropriate TradingView WebSocket connector.
///
/// Native (dart:io available): uses IOWebSocketChannel with Origin /
/// User-Agent headers — TradingView refuses the upgrade without them.
/// Web: plain connect; the browser supplies Origin itself and forbids
/// custom handshake headers.
export 'tv_socket_stub.dart' if (dart.library.io) 'tv_socket_io.dart';
