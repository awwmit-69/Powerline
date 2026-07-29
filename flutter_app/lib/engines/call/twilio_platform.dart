import 'twilio_platform_contract.dart';
import 'twilio_platform_stub.dart'
    if (dart.library.io) 'twilio_platform_native.dart'
    if (dart.library.html) 'twilio_platform_web.dart'
    as implementation;

TwilioPlatform createTwilioPlatform() => implementation.createTwilioPlatform();
