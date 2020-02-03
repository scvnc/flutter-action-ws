import 'package:typed_data/typed_data.dart';
import 'dart:typed_data';
import 'package:cbor/cbor.dart' as cbor;

class WsAction {
  final String action;
  int id;
  Map<String, dynamic> payload;
  dynamic result;
  WsAction(this.id, this.action) {
    payload = {};
    result = null;
  }

  static WsAction fromMap(Map<String, dynamic> m) {
    var msg = new WsAction(m['id'] as int, m['action'] as String);
    msg.payload = m['payload'];
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
    //print("############# AS BYTES #############");
    //print("Message.asBytes");
    //inst.output.pause();
    inst.decodeFromInput();
    //print(inst.decodedPrettyPrint(true));
    //print(inst.decodedToJSON());
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
    bool containskey = msg.containsKey('result');
    if (containskey) {
      m.result = msg['result'] as dynamic;
    }
    return m;
  }

  @override
  String toString() {
    return "WsAction id: ${this.id} action: ${this.action} payload: ${this.payload} result: ${this.result}";
  }
}
