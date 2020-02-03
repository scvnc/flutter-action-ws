# ws_action

A new Flutter package project.

## Example

```dart
// get the cookie needed to connect to websocket
var c = await requestUrlencoded('$endpoint/auth/gateway/login', 'test-user', '123tree');
WsConnectionService.url = 'wss://promedstaging.parsesoftwaredevelopment.com/ws/';
WsConnectionService.tokenCookie = c;
var wsCon = new WsConnectionService();

// observe the connection status
Observable<WsConnectionStatus> obs = wsCon.statusObs();
obs.forEach((WsConnectionStatus c) {
  print("-- WsConnectionStatus: $c");
});

try {
  dynamic r = await wsCon.actionFut('ListClients', {'arg1': 1});
  print("FUTURE IS DONE!! $r");
} catch (e) {
  print("horrors $e");
}
```
