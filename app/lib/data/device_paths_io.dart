import 'package:path_provider/path_provider.dart';

Future<String> appSupportPath() async {
  return (await getApplicationSupportDirectory()).path;
}
