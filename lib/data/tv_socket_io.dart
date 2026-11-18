import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Opens the TradingView socket on native platforms (Android/iOS/desktop).
///
/// TradingView's edge rejects native WebSocket handshakes that arrive
/// without browser-like headers — the upgrade is refused with
/// "Connection … was not upgraded to websocket". Browsers send these
/// automatically (which is why the web build worked), but dart:io sends
/// neither Origin nor a browser User-Agent, so we must supply them via
/// IOWebSocketChannel. On Android this requires the INTERNET permission
/// (added to the main AndroidManifest in PR #7).
WebSocketChannel connectTvSocket(Uri uri) => IOWebSocketChannel.connect(
      uri,
      headers: const <String, dynamic>{
        'Origin': 'https://www.tradingview.com',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      },
      connectTimeout: const Duration(seconds: 15),
    );
