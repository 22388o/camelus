import 'dart:async';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';

class SocketControl {
  late WebSocketChannel socket;
  String id;
  String connectionUrl;
  Map<String, dynamic> requestInFlight = {};
  Map<String, Completer> completers = {};
  Map<String, StreamController> streamControllers = {};
  Map<String, Map> additionalData = {};
  bool socketIsRdy = false;
  bool socketIsFailing = false;
  int socketFailingAttempts = 0;
  int socketReceivedEventsCount = 0;
  SocketControl(this.id, this.connectionUrl);
}
