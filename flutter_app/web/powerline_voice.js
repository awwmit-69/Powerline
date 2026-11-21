// Self-hosted PowerLine voice bridge (neutral filename avoids browser blocking).
//
// Security model:
// - The agent signs in with a one-time code sent by Twilio Verify to the phone
//   on file for that agent (server: /auth-start, /auth-verify).
// - The resulting session is kept in sessionStorage (cleared when the tab
//   closes) and exchanged for short-lived Twilio voice tokens (/voice-token).
// - No Twilio secrets ever reach the browser.
//
// POWERLINE_VOICE_TOKEN_URL must be https://<service>.twil.io/voice-token;
// the auth endpoints are resolved relative to it.
(() => {
  const SESSION_KEY = "powerline.agentSession";

  let device;
  let tokenUrl;
  let apiBase;
  let stateCallback;
  let errorCallback;
  let incomingCallback;
  const calls = new Map(); // callId -> Twilio Call
  let activeCallId;

  const emitState = (state, callId) => {
    if (stateCallback) stateCallback(state, callId || "");
  };

  const emitError = (error) => {
    const message = error && error.message ? error.message : String(error);
    if (errorCallback) errorCallback(message);
  };

  // ---------- session ----------
  function loadSession() {
    try {
      const raw = sessionStorage.getItem(SESSION_KEY);
      if (!raw) return null;
      const s = JSON.parse(raw);
      if (!s.session || !s.expiresAt || s.expiresAt * 1000 < Date.now() + 60000) return null;
      return s;
    } catch (_) {
      return null;
    }
  }

  function saveSession(s) {
    try {
      sessionStorage.setItem(SESSION_KEY, JSON.stringify(s));
    } catch (_) {
      // Storage unavailable: session lives only in memory for this page.
    }
    memorySession = s;
  }

  function clearSession() {
    memorySession = null;
    try {
      sessionStorage.removeItem(SESSION_KEY);
    } catch (_) {}
  }

  let memorySession = null;
  const currentSession = () => loadSession() || memorySession;

  async function post(path, fields) {
    const body = new URLSearchParams(fields);
    // Form-encoded body + no custom headers = simple CORS request (no preflight).
    const res = await fetch(`${apiBase}/${path}`, { method: "POST", body, cache: "no-store" });
    let payload = {};
    try {
      payload = await res.json();
    } catch (_) {}
    return { ok: res.ok, status: res.status, payload };
  }

  // ---------- sign-in dialog ----------
  function signInDialog() {
    return new Promise((resolve, reject) => {
      const css = {
        overlay: "position:fixed;inset:0;background:rgba(11,27,43,.78);display:flex;align-items:center;justify-content:center;z-index:2147483647;font-family:Manrope,system-ui,sans-serif",
        card: "background:#102A40;border:1px solid #243444;border-radius:16px;padding:24px;width:min(360px,92vw);color:#F4F2EC;box-shadow:0 20px 60px rgba(0,0,0,.45)",
        input: "width:100%;box-sizing:border-box;margin:6px 0 14px;padding:11px 12px;border-radius:10px;border:1px solid #243444;background:#0B1B2B;color:#F4F2EC;font-size:15px",
        primary: "width:100%;padding:11px;border:0;border-radius:10px;background:#2C6BFF;color:#fff;font-weight:700;font-size:15px;cursor:pointer",
        link: "background:none;border:0;color:#AEB9C7;cursor:pointer;margin-top:10px;font-size:13px",
      };
      const overlay = document.createElement("div");
      overlay.setAttribute("style", css.overlay);
      overlay.innerHTML = `
        <form style="${css.card}" autocomplete="off">
          <div style="font-weight:800;font-size:18px;margin-bottom:4px">PowerLine agent sign-in</div>
          <div data-k="hint" style="color:#AEB9C7;font-size:13px;margin-bottom:14px">Enter your agent ID. We'll text a one-time code to the phone on file.</div>
          <label style="font-size:12px;color:#AEB9C7">Agent ID</label>
          <input data-k="agent" style="${css.input}" autocapitalize="off" spellcheck="false" required>
          <div data-k="codeRow" style="display:none">
            <label style="font-size:12px;color:#AEB9C7">6-digit code</label>
            <input data-k="code" style="${css.input}" inputmode="numeric" autocomplete="one-time-code" maxlength="10">
          </div>
          <div data-k="err" style="color:#E5675A;font-size:13px;min-height:18px;margin-bottom:8px"></div>
          <button data-k="go" type="submit" style="${css.primary}">Send code</button>
          <button data-k="cancel" type="button" style="${css.link}">Cancel</button>
        </form>`;
      document.body.appendChild(overlay);
      const $ = (k) => overlay.querySelector(`[data-k="${k}"]`);
      let step = "agent";
      const close = () => overlay.remove();

      $("cancel").onclick = () => {
        close();
        reject(new Error("Sign-in cancelled"));
      };
      overlay.querySelector("form").onsubmit = async (e) => {
        e.preventDefault();
        $("err").textContent = "";
        $("go").disabled = true;
        const agent = $("agent").value.trim().toLowerCase();
        try {
          if (step === "agent") {
            const r = await post("auth-start", { agent });
            if (!r.ok) throw new Error("Could not send a code. Try again shortly.");
            step = "code";
            $("agent").readOnly = true;
            $("codeRow").style.display = "block";
            $("hint").textContent = "If that agent ID exists, a code was texted to its phone.";
            $("go").textContent = "Sign in";
            $("code").focus();
          } else {
            const r = await post("auth-verify", { agent, code: $("code").value.trim() });
            if (!r.ok || !r.payload.session) throw new Error("That code didn't work.");
            saveSession(r.payload);
            close();
            resolve(r.payload);
          }
        } catch (err) {
          $("err").textContent = err.message;
        } finally {
          $("go").disabled = false;
        }
      };
      $("agent").focus();
    });
  }

  async function ensureSession() {
    return currentSession() || (await signInDialog());
  }

  async function fetchToken() {
    let s = await ensureSession();
    let r = await post("voice-token", { session: s.session });
    if (r.status === 401) {
      clearSession();
      s = await signInDialog();
      r = await post("voice-token", { session: s.session });
    }
    if (!r.ok || !r.payload.token) throw new Error(`Token service returned ${r.status}`);
    return r.payload.token;
  }

  // ---------- call wiring ----------
  function wireCall(call, callId) {
    calls.set(callId, call);
    const done = (state) => {
      emitState(state, callId);
      calls.delete(callId);
      if (activeCallId === callId) activeCallId = undefined;
    };
    call.on("ringing", () => emitState("ringing", callId));
    call.on("accept", () => {
      activeCallId = callId;
      emitState("connected", callId);
    });
    call.on("disconnect", () => done("completed"));
    call.on("cancel", () => done("completed"));
    call.on("reject", () => done("failed"));
    call.on("error", (error) => {
      emitError(error);
      done("failed");
    });
  }

  window.powerlineTwilioInitialize = async (url, onState, onError, onIncoming) => {
    tokenUrl = url;
    apiBase = String(url).replace(/\/voice-token\/?$/, "");
    stateCallback = onState;
    errorCallback = onError;
    incomingCallback = onIncoming;

    if (device) return "ready";
    if (typeof Twilio === "undefined" || !Twilio.Device) {
      throw new Error("Twilio Voice SDK failed to load");
    }

    const token = await fetchToken();
    device = new Twilio.Device(token, {
      closeProtection: true,
      codecPreferences: ["opus", "pcmu"],
      // Nearest edges first for agents in South Asia, then US East.
      edge: ["singapore", "ashburn"],
    });
    device.on("error", emitError);
    device.on("tokenWillExpire", async () => {
      try {
        device.updateToken(await fetchToken());
      } catch (error) {
        emitError(error);
      }
    });
    device.on("incoming", (call) => {
      const callId = `twilio_in_${Date.now()}`;
      if (activeCallId) {
        call.reject(); // busy: let other devices / voicemail take it
        return;
      }
      wireCall(call, callId);
      const from = (call.parameters && call.parameters.From) || "unknown";
      if (incomingCallback) incomingCallback(callId, from);
    });
    await device.register();
    return "ready";
  };

  window.powerlineTwilioPlaceCall = async (destination) => {
    if (!device) throw new Error("Twilio device is not initialized");
    if (activeCallId) throw new Error("A call is already active");

    const callId = `twilio_${Date.now()}`;
    emitState("dialing", callId);
    const call = await device.connect({ params: { To: destination } });
    activeCallId = callId;
    wireCall(call, callId);
    return callId;
  };

  window.powerlineTwilioAccept = (callId) => {
    const call = calls.get(callId);
    if (call) call.accept();
  };

  window.powerlineTwilioReject = (callId) => {
    const call = calls.get(callId);
    if (call) call.reject();
  };

  const active = () => (activeCallId ? calls.get(activeCallId) : undefined);

  window.powerlineTwilioHangup = () => {
    const call = active();
    if (call) call.disconnect();
  };

  window.powerlineTwilioMute = (muted) => {
    const call = active();
    if (call) call.mute(Boolean(muted));
  };

  window.powerlineTwilioSendDigits = (digits) => {
    const call = active();
    if (call) call.sendDigits(digits);
  };

  window.powerlineTwilioSignOut = () => {
    clearSession();
    window.powerlineTwilioDispose();
  };

  window.powerlineTwilioDispose = () => {
    if (device) device.destroy();
    calls.clear();
    activeCallId = undefined;
    device = undefined;
  };
})();
