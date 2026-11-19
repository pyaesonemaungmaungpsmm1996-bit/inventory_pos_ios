import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventory_pos/cloud_proxy_client.dart';

void main(){
 test('proxy retains encoded query, auth headers and POST body',()async{
  final client=CloudProxyClient(inner:MockClient((r)async{
   expect(r.url.host,'rainbow-trifle-8aa5a1.netlify.app');
   expect(r.url.query,'select=id&code=eq.a%2Bb');
   expect(r.headers['authorization'],'Bearer test-token');
   expect(r.headers['apikey'],'test-public');
   expect(r.body,'{"amount":123}');
   return http.Response('{}',200);
  }));
  await client.post(Uri.parse('${CloudProxyClient.upstream}/rest/v1/rpc/test?select=id&code=eq.a%2Bb'),headers:{'authorization':'Bearer test-token','apikey':'test-public'},body:'{"amount":123}');
  client.close();
 });
 test('multipart boundary and binary upload survive forwarding',()async{
  final client=CloudProxyClient(inner:MockClient((r)async{
   expect(r.headers['content-type'],contains('multipart/form-data; boundary='));
   expect(r.bodyBytes,containsAllInOrder([0,1,255,10]));
   return http.Response('{}',200);
  }));
  final upload=http.MultipartRequest('POST',Uri.parse('${CloudProxyClient.upstream}/storage/v1/object/test'))
   ..files.add(http.MultipartFile.fromBytes('file',[0,1,255,10],filename:'test.bin'));
  await client.send(upload);client.close();
 });
 test('unrelated origins and realtime are not rerouted',()async{
  final seen=<String>[];
  final client=CloudProxyClient(inner:MockClient((r)async{seen.add(r.url.host);return http.Response('{}',200);}));
  await client.get(Uri.parse('https://example.com/auth/v1/user'));
  await client.get(Uri.parse('${CloudProxyClient.upstream}/realtime/v1/'));
  expect(seen,['example.com','hylxyyzwsppaufzmqcbg.supabase.co']);client.close();
 });
}
