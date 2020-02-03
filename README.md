# ws_action

A new Flutter package project.

## Example

```dart
// get the cookie needed to connect to websocket
var c = await requestUrlencoded('https://$domain/auth/gateway/login', 'some-iser', 'somepw');
WsConnectionService.url = 'wss://$domain/ws/';
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
