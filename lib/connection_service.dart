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
  static Map<int, void Function(ActionRequest)> replyFunctions = new Map();
  static Duration timeout = new Duration(seconds: 30);
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

    _connect();
  }

  connect() async {
    switch(connectionStatus.status) {
      case WsStatusType.DISCONNECTED:
        await _connect();
        break;
      default:
        break;
    }
  }

  Future<void> disconnect() async {
    if(_ws == null) {
      return;
    }

    _connectionStatusCmd(new WsConnectionStatus(WsStatusType.DISCONNECTED));
    await _ws.close();
  }

  _connect() async {
    try {
      Map<String, dynamic> headers = {
        "Cookie": WsConnectionService.tokenCookie,
      };

      _connectionStatusCmd(new WsConnectionStatus(WsStatusType.CONNECTING));
      var c = await WebSocket.connect(url, headers: headers);

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
            _handleReplyFunction(ActionRequest(ActionRequestStatus.OK, responseWsAction));
          } catch (e) {
            // TODO
            if (e is ActionResponseException) {
              _handleReplyFunction(ActionRequest(ActionRequestStatus.ERROR, e.action));
            } else {

            }
          }
        } else if (message is String) {


          /*
          _connectionStatusCmd(new WsConnectionStatus(WsStatusType.ERROR,
                  message: "Received a String message which is not supported"));
                  */
        } else {
          _connectionStatusCmd(new WsConnectionStatus(WsStatusType.ERROR,
                  message: "Unhandled message type"));
        }
      }, onDone: () {
        _connectionStatusCmd(new WsConnectionStatus(WsStatusType.DISCONNECTED));
      }, onError: (e) {
        _connectionStatusCmd(new WsConnectionStatus(WsStatusType.ERROR, message: "$e"));
      });

    } catch (e) {
      _connectionStatusCmd(new WsConnectionStatus(WsStatusType.DISCONNECTED));
    }
  }

  void _sendAllInQueue() {
    queue.forEach((id, reqAction) {
      if (reqAction.status == ActionRequestStatus.NEW) {
        if (connectionStatus.status == WsStatusType.CONNECTED) {
          reqAction.status = ActionRequestStatus.START;
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

    if (connectionStatus.status == WsStatusType.DISCONNECTED || connectionStatus.status == WsStatusType.ERROR) {
      connect();
    } else {
      _sendAllInQueue();
    }
    return id;
  }

  Future<WsAction> actionFut(String actionName, Map<String, dynamic> payload) {
    Completer c = new Completer<WsAction>();
    int id = _pushAction(actionName, payload);
    /// TODO: this should be changed to ActionResponse instead of ActionRequest
    onResponse(id, (ActionRequest ar) {
      if (ar.status == ActionRequestStatus.OK) {
        c.complete(ar.action);
      } else if (ar.status == ActionRequestStatus.ERROR) {
        c.completeError(ActionResponseException(ar.action, ar.action.error));
      } else {
        c.completeError("Unhandled ActionRequestStatus");
      }
    });
    return c.future;
  }

  onResponseCommand(int id, RxCommand rxCommand) {
    if (queue.containsKey(id)) {
      replyCommands[id] = rxCommand;
    }
  }

  onResponse(int id, void Function(ActionRequest) f) {
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

  //_handleReplyFunction(WsAction a) {
  _handleReplyFunction(ActionRequest ar) {
    int aid = ar.action.id;
    if (replyFunctions.containsKey(aid)) {
      replyFunctions[aid](ar);
      replyFunctions.remove(aid);
    }
  }

  _handleReplyFunctionTimeout(ActionRequest ar) {

  }

  checkForTimedoutActions() {
    var now = new DateTime.now();
    int timeoutSeconds = timeout.inSeconds;
    queue.forEach((int aId, ActionRequest ar) {
      int diff = now.difference(ar.requestedOn).inSeconds;
      if (diff > timeoutSeconds) {

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
