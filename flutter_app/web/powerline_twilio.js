(() => {
  let device;
  let activeCall;
  let stateCallback;
  let errorCallback;
  let tokenUrl;

  const emitState = (state, callId) => {
    if (stateCallback) stateCallback(state, callId || "");
  };

  const emitError = (error) => {
    const message = error && error.message ? error.message : String(error);
    if (errorCallback) errorCallback(message);
  };

  async function fetchToken() {
    const response = await fetch(tokenUrl, { cache: "no-store" });
    if (!response.ok) throw new Error(`Token service returned ${response.status}`);
    const payload = await response.json();
    if (!payload.token) throw new Error("Token service did not return a token");
    return payload.token;
  }

  window.powerlineTwilioInitialize = async (url, onState, onError) => {
    tokenUrl = url;
    stateCallback = onState;
    errorCallback = onError;

    if (device) return "ready";

    const token = await fetchToken();
    device = new Twilio.Device(token, {
      closeProtection: true,
      codecPreferences: ["opus", "pcmu"],
    });
    device.on("error", emitError);
    device.on("tokenWillExpire", async () => {
      try {
        device.updateToken(await fetchToken());
      } catch (error) {
        emitError(error);
      }
    });
    return "ready";
  };

  window.powerlineTwilioPlaceCall = async (destination) => {
    if (!device) throw new Error("Twilio device is not initialized");
    if (activeCall) throw new Error("A call is already active");

    const callId = `twilio_${Date.now()}`;
    emitState("dialing", callId);
    const call = await device.connect({ params: { To: destination } });
    activeCall = call;

    call.on("ringing", () => emitState("ringing", callId));
    call.on("accept", () => emitState("connected", callId));
    call.on("disconnect", () => {
      emitState("completed", callId);
      activeCall = undefined;
    });
    call.on("cancel", () => {
      emitState("completed", callId);
      activeCall = undefined;
    });
    call.on("reject", () => {
      emitState("failed", callId);
      activeCall = undefined;
    });
    call.on("error", (error) => {
      emitError(error);
      emitState("failed", callId);
      activeCall = undefined;
    });
    return callId;
  };

  window.powerlineTwilioHangup = () => {
    if (activeCall) activeCall.disconnect();
  };

  window.powerlineTwilioMute = (muted) => {
    if (activeCall) activeCall.mute(Boolean(muted));
  };

  window.powerlineTwilioSendDigits = (digits) => {
    if (activeCall) activeCall.sendDigits(digits);
  };

  window.powerlineTwilioDispose = () => {
    if (device) device.destroy();
    activeCall = undefined;
    device = undefined;
  };
})();
