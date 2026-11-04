import 'package:phonolite_native_build/phonolite_native_build.dart';

Future<void> main(List<String> arguments) =>
    buildMacOSLibrary(arguments, rustCrate: 'quic_client');
