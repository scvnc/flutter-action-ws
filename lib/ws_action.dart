library ws_action;

export './action.dart';
export './connection_service.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:async';

/// TODO: need to return a matched cookie, not hard coded to the very first one
Future<String> requestUrlencoded(String url, String username, String password) async {
  HttpClient httpClient = new HttpClient();
  HttpClientRequest request = await httpClient.postUrl(Uri.parse(url));
  request.headers.set('content-type', 'application/x-www-form-urlencoded');
  //print("post url: $url");
  String formBody = "username=${Uri.encodeQueryComponent(username)}&password=${Uri.encodeQueryComponent(password)}";
  //print(formBody);
  List<int> bodyBytes = utf8.encode(formBody);
  request.headers.set('Content-Length', bodyBytes.length.toString());
  request.add(bodyBytes);
  HttpClientResponse response = await request.close();
  //print("response ${response.cookies[0]}");
  //print("response code ${response.statusCode}");
  // todo - you should check the response.statusCode
  //String reply = await response.transform(utf8.decoder).join();
  httpClient.close();
  //print("response body $reply");
  return "${response.cookies[0]}".split(";")[0];
}
