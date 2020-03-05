import 'package:typed_data/typed_data.dart';
import 'dart:typed_data';
import 'package:cbor/cbor.dart' as cbor;

class ActionResponseException implements Exception {
  WsAction action;
  String cause;
  ActionResponseException(this.action, this.cause);

  @override
  String toString() {
    return "ActionResponseException: ${this.cause}.  Action: ${this.action.action}";
  }
}

class WsAction {
  final String action;
  int id;
  Map<String, dynamic> payload;
  dynamic result;
  String error;

  WsAction(this.id, this.action) {
    payload = {};
    result = null;
    error = null;
  }

  static WsAction fromMap(Map<String, dynamic> m) {
    var msg = new WsAction(m['id'] as int, m['action'] as String);
    msg.payload = m['payload'];
    if (m.containsKey('error')) {
      msg.error = m['error'];
    }
    return msg;
  }

  /// Converts this message into cbor bytes
  Uint8Buffer asBytes() {
    cbor.Cbor inst = new cbor.Cbor();
    cbor.Encoder encoder = inst.encoder;
    encoder.writeMap({
      'id': id,
      'action': action,
      'payload': payload,
    });
    inst.decodeFromInput();
    Uint8Buffer data = inst.output.getData();
    return data;
  }

  /// construct this message from cbor bytes
  static WsAction fromBytes(Uint8List b) {
    Uint8Buffer buf = new Uint8Buffer();
    b.forEach((e) => buf.add(e));
    cbor.Cbor inst = new cbor.Cbor();
    inst.decodeFromBuffer(buf);
    var msg = inst.getDecodedData()[0];

    WsAction m = new WsAction(msg['id'] as int, msg['action'] as String);
    if (msg.containsKey('error')) {
      m.error = msg['error'] as String;
      throw new ActionResponseException(m, msg['error'] as String);
    } else if (msg.containsKey('result')) {
      m.result = msg['result'] as dynamic;
    }
    return m;
  }

  @override
  String toString() {
    if (this.error != null) {
    return "WsAction id: ${this.id} action: ${this.action} payload: ${this.payload} error: ${this.error}";
    } else {
    return "WsAction id: ${this.id} action: ${this.action} payload: ${this.payload} result: ${this.result}";
    }
  }
}
