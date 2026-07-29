import Flutter
import TwilioVoice
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, CallDelegate {
  private var voiceChannel: FlutterMethodChannel?
  private var activeCall: Call?
  private var activeCallId = ""

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    let channel = FlutterMethodChannel(
      name: "com.azdglobal.powerline/voice",
      binaryMessenger: controller.binaryMessenger
    )
    voiceChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleVoiceMethod(call, result: result)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleVoiceMethod(_ method: FlutterMethodCall, result: @escaping FlutterResult) {
    switch method.method {
    case "initialize":
      result(nil)
    case "placeCall":
      guard
        let args = method.arguments as? [String: Any],
        let token = args["token"] as? String,
        let destination = args["destination"] as? String,
        let callId = args["callId"] as? String
      else {
        result(FlutterError(code: "bad_arguments", message: "Missing call parameters.", details: nil))
        return
      }
      activeCallId = callId
      let options = ConnectOptions(accessToken: token) { builder in
        builder.params = ["To": destination]
      }
      activeCall = TwilioVoiceSDK.connect(options: options, delegate: self)
      result(callId)
    case "hangup":
      activeCall?.disconnect()
      result(nil)
    case "mute":
      let args = method.arguments as? [String: Any]
      activeCall?.isMuted = args?["muted"] as? Bool ?? false
      result(nil)
    case "sendDigits":
      let args = method.arguments as? [String: Any]
      activeCall?.sendDigits(args?["digits"] as? String ?? "")
      result(nil)
    case "dispose":
      activeCall?.disconnect()
      activeCall = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func emitState(_ state: String) {
    voiceChannel?.invokeMethod("state", arguments: [
      "state": state,
      "callId": activeCallId,
    ])
  }

  private func emitError(_ error: Error) {
    voiceChannel?.invokeMethod("error", arguments: [
      "message": error.localizedDescription,
    ])
  }

  func callDidStartRinging(call: Call) {
    emitState("ringing")
  }

  func callDidConnect(call: Call) {
    emitState("connected")
  }

  func callDidFailToConnect(call: Call, error: Error) {
    emitError(error)
    emitState("failed")
    activeCall = nil
  }

  func callDidDisconnect(call: Call, error: Error?) {
    if let error = error {
      emitError(error)
      emitState("failed")
    } else {
      emitState("completed")
    }
    activeCall = nil
  }

  func callIsReconnecting(call: Call, error: Error) {
    emitError(error)
  }

  func callDidReconnect(call: Call) {
    emitState("connected")
  }
}
