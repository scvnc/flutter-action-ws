
import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import '../lib/action.dart';
import '../lib/connection_service.dart';


void main() {
  HttpServer server;
  List<String> cookieAuthResults = [];

  setUpAll(() async {
    cookieAuthResults = [];

    runZoned(() async {

    server = await HttpServer.bind('127.0.0.1', 4040);

    await for (var req in server) {
      if (req.uri.path == '/ws') {
        // Upgrade a HttpRequest to a WebSocket connection.
        var socket = await WebSocketTransformer.upgrade(req);

        handleMsg(msg) {
          var action = WsAction.fromBytes(msg);
          var response = WsAction(action.id, action.action);

          cookieAuthResults.add(req.headers['cookie'].first);
          socket.add(response.asBytes());
        }

        socket.listen(handleMsg);
      };
    }

    });

  });

  tearDownAll(() async {
    server.close();
  });

  test('We can connect/disconnect & change cookie login information', () async {

    // Arrange

    WsConnectionService.url = 'ws://localhost:4040/ws';
    WsConnectionService.tokenCookie = 'first_cookie';

    var wsConnectionService = WsConnectionService();

    await wsConnectionService.connect();

    // TODO.. we shouldn't have to delay to make this test pass..
    await Future.delayed(Duration(milliseconds: 100));

    // Act
    await wsConnectionService.actionFut('test', {"id": "anything"});

    // Assert
    expect(cookieAuthResults, equals(['first_cookie']));


    // Arrange (try changing auth token)
    WsConnectionService.tokenCookie = 'second_cookie';
    wsConnectionService = WsConnectionService();

    await wsConnectionService.disconnect();
    await wsConnectionService.connect();

    // TODO.. we shouldn't have to delay to make this test pass..
    await Future.delayed(Duration(milliseconds: 100));

    // Act
    await wsConnectionService.actionFut('test', {"id": "bar"});

    // Assert
    expect(cookieAuthResults, equals(['first_cookie', 'second_cookie']));

  });
}
