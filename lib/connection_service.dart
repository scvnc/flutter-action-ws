import 'package:rx_command/rx_command.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:rxdart/rxdart.dart';
import 'dart:async';
import './action.dart';

enum WsStatusType { ERROR, DISCONNECTED, CONNECTED, CONNECTING }

class WsConnectionStatus {
  WsStatusType status;
  String message;
  int queueSize;
  WsConnectionStatus(WsStatusType status, {message: ""}) {
    this.status = status;
    this.message = message;
  }

  @override
  toString() {
    switch(status) {
      case WsStatusType.ERROR:
        return "$status: $message queueSize: $queueSize";
        break;
      default:
        return "$status queueSize: $queueSize";
    }
  }
}

enum ActionRequestStatus { NEW, START, OK, ERROR, TIMEDOUT }

class ActionRequest {
  ActionRequestStatus status;
  WsAction action;
  DateTime requestedOn;
  ActionRequest(this.status, this.action) {
    requestedOn = DateTime.now();
  }

  @override
  toString() {
    return "ActionRequest: ${action.action} id: ${action.id} status: $status";
  }
}
class WsConnectionService {
  // maybe no need for it to be static...
  static Map<int, ActionRequest> queue = new Map();
  static Map<int, RxCommand> replyCommands = new Map();
  static Map<int, void Function(WsAction)> replyFunctions = new Map();
  static Duration timeout = new Duration(seconds: 2);
  static String tokenCookie;
  static String url;

  WebSocket _ws;

  static WsConnectionStatus connectionStatus =
      new WsConnectionStatus(WsStatusType.DISCONNECTED);
  static RxCommand<WsConnectionStatus, WsConnectionStatus>
      _connectionStatusCmd = RxCommand.createSync((s) {
        s.queueSize = queue.length;
    connectionStatus = s;
    return connectionStatus;
  });

  static RxCommand<ActionRequest, ActionRequest> _actionRequestCmd =
      RxCommand.createSync((actionRequest) {
        queue[actionRequest.action.id] = actionRequest;
        return actionRequest;
      });

  Observable<WsConnectionStatus> statusObs() {
    return _connectionStatusCmd.asBroadcastStream();
  }

  Observable<ActionRequest> actionResponseObs() {
    return _actionRequestCmd.asBroadcastStream();
  }

  WsConnectionService() {
    print("WsConnectionService constructor.  Url: $url");
    _connect();
  }

  connect() {
    switch(connectionStatus.status) {
      case WsStatusType.DISCONNECTED:
        _connect();
        break;
      default:
        break;
    }
  }

  _connect() async {
    try {
      Map<String, dynamic> headers = {
        "Cookie": WsConnectionService.tokenCookie,
      };
      print(" ## WsConnectionService.connect url: $url, headers: $headers");
      _connectionStatusCmd(new WsConnectionStatus(WsStatusType.CONNECTING));
      await WebSocket.connect(url, headers: headers).then((c) {
        _connectionStatusCmd(new WsConnectionStatus(WsStatusType.CONNECTED));
        _ws = c;

        _sendAllInQueue();
        checkForTimedoutActions();

        // NOTE: there is optional: onError, onDone, bool: cancelOnError
        _ws.listen((message) {
          if (message is List<int>) {
            try {
              var responseWsAction = WsAction.fromBytes(Uint8List.fromList(message));
              var queuedActionRequest = WsConnectionService._removeFromQueue(responseWsAction.id);
              responseWsAction.payload = queuedActionRequest.action.payload;
              _actionRequestCmd(ActionRequest(ActionRequestStatus.OK, responseWsAction));
              _handleReplyRxCommand(responseWsAction);
              _handleReplyFunction(responseWsAction);
            } catch (e) {
              // TODO
              print("Error decoding action: $e tried: $message");
            }
          } else if (message is String) {
            //print("TODO: decode this: $message");
            _connectionStatusCmd(new WsConnectionStatus(WsStatusType.ERROR,
                    message: "Received a String message which is not supported"));
          } else {
            _connectionStatusCmd(new WsConnectionStatus(WsStatusType.ERROR,
                    message: "Unhandled message type"));
          }
        }, onDone: () {
          _connectionStatusCmd(new WsConnectionStatus(WsStatusType.DISCONNECTED));
        }, onError: (e) {
          _connectionStatusCmd(new WsConnectionStatus(WsStatusType.ERROR, message: "$e"));
        });
      });
    } catch (e) {
      print("WsConnection failed handshake");
      _connectionStatusCmd(new WsConnectionStatus(WsStatusType.DISCONNECTED));
    }
  }

  void _sendAllInQueue() {
    queue.forEach((id, reqAction) {
      if (reqAction.status == ActionRequestStatus.NEW) {
        reqAction.status = ActionRequestStatus.START;
        if (connectionStatus.status == WsStatusType.CONNECTED) {
          _ws.add(reqAction.action.asBytes());
        }
      }
    });
  }

  int _pushAction(String actionName, Map<String, dynamic> payload) {
    var id = _getNextId();
    WsAction m = new WsAction(id, actionName);
    m.payload = payload;
    _actionRequestCmd(ActionRequest(ActionRequestStatus.NEW, m));

    if (connectionStatus.status == WsStatusType.DISCONNECTED) {
      connect();
    } else {
      _sendAllInQueue();
    }
    return id;
  }

  Future<dynamic> actionFut(String actionName, Map<String, dynamic> payload) {
    Completer c = new Completer();
    int id = _pushAction(actionName, payload);
    onResponse(id, (dynamic action) {
      c.complete(action);
    });
    return c.future;
  }

  onResponseCommand(int id, RxCommand rxCommand) {
    if (queue.containsKey(id)) {
      replyCommands[id] = rxCommand;
    }
  }

  onResponse(int id, void Function(WsAction) f) {
    if (queue.containsKey(id)) {
      replyFunctions[id] = f;
    }
  }

  _handleReplyRxCommand(WsAction a) {
    if (replyCommands.containsKey(a.id)) {
      replyCommands[a.id](a);
      replyCommands.remove(a.id);
    }
  }

  _handleReplyFunction(WsAction a) {
    if (replyFunctions.containsKey(a.id)) {
      replyFunctions[a.id](a);
      replyFunctions.remove(a.id);
    }
  }

  _handleReplyFunctionTimeout(ActionRequest ar) {
    print("this function is nono $ar");
  }

  checkForTimedoutActions() {
    var now = new DateTime.now();
    int timeoutSeconds = timeout.inSeconds;
    queue.forEach((int aId, ActionRequest ar) {
      int diff = now.difference(ar.requestedOn).inSeconds;
      if (diff > timeoutSeconds) {
        print("TODO: TIMED OUT HOLY SMOKES!!!");
        ar.status = ActionRequestStatus.TIMEDOUT;
        _handleReplyFunctionTimeout(ar);
      }
    });
  }

  static int _getNextId() {
    int id = 0;
    while (WsConnectionService.queue.containsKey(id)) {
      id++;
    }
    return id;
  }

  static ActionRequest _removeFromQueue(int id) {
    return queue.remove(id);
  }
}
