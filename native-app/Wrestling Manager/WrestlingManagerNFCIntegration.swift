import SwiftUI
import WebKit
import UIKit
import Combine
#if canImport(CoreNFC) && !targetEnvironment(macCatalyst)
import CoreNFC
#endif

// Both readers use the existing request-ID based web credential contract.
// The web app remains responsible for user/team/session authorization and
// resolving the credential. A UID or a 5003 presence event is never an athlete.
@MainActor
final class WrestlingManagerNfcBridge: NSObject, WKScriptMessageHandler {
    // Refresh native hardware state before a user-requested read. The existing
    // web click handlers keep all account, session, scale and kiosk guards.
    static let script = #"""
    (() => {
      const u = new URL(location.href);
      const trusted = u.protocol === 'https:' && (!u.port || u.port === '443') && !u.username && !u.password &&
        ((u.hostname === 'theteammanager.app' && ['/', '/index.html'].includes(u.pathname)) ||
         (u.hostname === 'meleman35.github.io' && (u.pathname === '/wrestling-weight-manager-public' || u.pathname.startsWith('/wrestling-weight-manager-public/'))));
      if (window.top !== window || !trusted || window.wmNFCReaderPromptInstalled) return;
      const bridge = window.webkit?.messageHandlers?.athleteNfc;
      const sheet = document.getElementById('weighInConsoleSheet');
      const help = document.getElementById('kioskScanHelp');
      if (!bridge || !sheet || !help) return;
      window.wmNFCReaderPromptInstalled = true;
      const css = document.createElement('style');
      css.id = 'wm-native-kiosk-layout';
      css.textContent = `
        body.kiosk-locked #weighInConsoleSheet > .sheet-returnbar{display:none!important}
        #wmReaderStatus{font-size:12px;font-weight:700;line-height:1.3;display:block;margin-top:4px;overflow-wrap:anywhere}
        #wmReaderStatus[data-ready="true"]{color:#b8f2d4}
        #wmReaderStatus[data-ready="false"]{color:#ffe0a3}
        #wmReaderStatus[data-battery-low="true"]{color:#ffe0a3}
        body.kiosk-locked #weighInConsoleSheet .kiosk-control-bar{padding:10px 14px;gap:10px;flex-shrink:0}
        body.kiosk-locked #weighInConsoleSheet .kiosk-control-actions{flex-wrap:wrap;justify-content:flex-end;gap:8px}
        body.kiosk-locked #weighInConsoleSheet .kiosk-control-actions button{min-height:44px}
        @media(min-width:760px) and (orientation:landscape){
          body.kiosk-locked #weighInConsoleSheet[data-mode="team_kiosk"]{
            display:grid!important;grid-template-columns:minmax(280px,1fr) minmax(0,1.15fr);
            grid-template-rows:auto minmax(220px,1fr) auto;gap:12px;
            padding:0 14px max(12px,env(safe-area-inset-bottom))!important;
            box-sizing:border-box;align-content:stretch;
          }
          body.kiosk-locked #weighInConsoleSheet[data-mode="team_kiosk"] > .kiosk-control-bar{
            grid-column:1 / -1;grid-row:1;margin:0 -14px;position:relative;
          }
          body.kiosk-locked #weighInConsoleSheet[data-mode="team_kiosk"] #kioskScanPanel,
          body.kiosk-locked #weighInConsoleSheet[data-mode="team_kiosk"] #weighIdentityCard{
            grid-column:1;grid-row:2;margin:0;min-width:0;padding:20px;
            display:flex;flex-direction:column;justify-content:center;gap:12px;
          }
          body.kiosk-locked #weighInConsoleSheet[data-mode="team_kiosk"] #kioskScanPanel[hidden],
          body.kiosk-locked #weighInConsoleSheet[data-mode="team_kiosk"] #weighIdentityCard.hidden{display:none!important}
          body.kiosk-locked #weighInConsoleSheet[data-mode="team_kiosk"] #kioskScanTitle{font-size:clamp(24px,3vw,34px);margin:0}
          body.kiosk-locked #weighInConsoleSheet[data-mode="team_kiosk"] #kioskScanHelp{font-size:16px;line-height:1.4;margin:0}
          body.kiosk-locked #weighInConsoleSheet[data-mode="team_kiosk"] #kioskScanCountdown{margin:0}
          body.kiosk-locked #weighInConsoleSheet[data-mode="team_kiosk"] #kioskScanChoices{grid-template-columns:1fr;gap:10px}
          body.kiosk-locked #weighInConsoleSheet[data-mode="team_kiosk"] #kioskScanPanel button{min-height:56px;font-size:18px}
          body.kiosk-locked #weighInConsoleSheet[data-mode="team_kiosk"] #weighScanRow,
          body.kiosk-locked #weighInConsoleSheet[data-mode="team_kiosk"] #changeWeighAthleteBtn{
            grid-column:1;grid-row:3;margin:0;min-width:0;align-self:end;
          }
          body.kiosk-locked #weighInConsoleSheet[data-mode="team_kiosk"] #weighScanRow{
            display:grid;grid-template-columns:minmax(0,1fr) auto;gap:6px;
          }
          body.kiosk-locked #weighInConsoleSheet[data-mode="team_kiosk"] #weighScanRow input{width:100%;min-width:0}
          body.kiosk-locked #weighInConsoleSheet[data-mode="team_kiosk"] > .scale-readout{
            grid-column:2;grid-row:2 / 4;min-height:0!important;margin:0;padding:20px;
            min-width:0;display:flex!important;flex-direction:column;justify-content:center;
          }
          body.kiosk-locked #weighInConsoleSheet[data-mode="team_kiosk"] .scale-readout input{
            font-size:clamp(72px,12vw,170px)!important;width:100%!important;min-width:0!important;
            padding:0!important;letter-spacing:-.04em;line-height:1.1;
          }
          body.kiosk-locked #weighInConsoleSheet[data-mode="team_kiosk"] .identity-photo,
          body.kiosk-locked #weighInConsoleSheet[data-mode="team_kiosk"] .identity-photo-placeholder{max-height:140px;max-width:140px}
        }`;
      document.head.append(css);
      const badge = document.createElement('small');
      badge.id = 'wmReaderStatus';badge.setAttribute('role','status');
      sheet.querySelector('.kiosk-title')?.append(badge);
      let intent = null, bypass = false;
      const state = () => window.wrestlingManagerNativeNFCStatus || {};
      const key = () => JSON.stringify([
        typeof session === 'undefined' ? null : session?.user?.id,
        typeof activeTeam === 'undefined' ? null : activeTeam?.id,
        typeof activeSeason === 'undefined' ? null : activeSeason?.id,
        typeof activeWeighInSession === 'undefined' ? null : activeWeighInSession?.id,
        document.body.classList.contains('kiosk-locked')
      ]);
      const busy = () => (typeof pendingNfcRequest !== 'undefined' && !!pendingNfcRequest) ||
        (typeof selectedWeighInEntry !== 'undefined' && !!selectedWeighInEntry);
      function clearIntent(){if(intent)clearTimeout(intent.timer);intent=null;}
      function valid(){return intent && intent.key === key() && !document.hidden && !sheet.classList.contains('hidden') && !busy() && !intent.button.disabled;}
      function refresh(command='status'){try{bridge.postMessage({command});}catch{clearIntent();}}
      function update(){
        const s = state();
        const battery = s.externalConnected && Number.isInteger(s.readerBatteryPercent) && s.readerBatteryPercent >= 0 && s.readerBatteryPercent <= 100 ? s.readerBatteryPercent : null;
        const lowBattery = battery !== null && battery <= 20;
        const batteryText = battery === null ? ' · Battery unavailable' : ' · 🔋 ' + battery + '%' + (lowBattery ? ' — Low battery' : '');
        const label = s.externalConnected ? (s.readerName || 'NFC reader') + ' connected' + batteryText :
          s.builtInAvailable ? 'iPhone NFC ready' :
          ['Connecting','Preparing reader','Looking for reader'].includes(s.externalState) ? 'NFC reader reconnecting…' : 'NFC reader disconnected';
        if(badge.textContent !== label)badge.textContent=label;
        badge.dataset.ready=String(!!s.available);
        badge.dataset.batteryLow=String(lowBattery);
        badge.setAttribute('aria-label', label.replace('🔋', 'Reader battery'));
        const phone='Hold your card or wristband at the top of the iPhone.';
        const reader='Hold your card or wristband on the connected NFC reader.';
        const unavailable = /^(NFC is unavailable on this device|Use Capture \/ Scan Card, or an attached card reader)/.test(help.textContent);
        let text=help.textContent;
        if(s.externalConnected && text===phone)text=reader;
        else if(!s.externalConnected && text===reader)text=s.builtInAvailable?phone:'Reader disconnected. Tap NFC to reconnect, or use Capture / Scan Card.';
        if(unavailable)text=s.available?'Reader ready. Tap NFC to scan your card.':s.externalConfigured?'Tap NFC to reconnect the reader, or use Capture / Scan Card.':'Connect the NFC reader in Scale & Card Reader Setup, or use Capture / Scan Card.';
        if(text!==help.textContent)help.textContent=text;
        if(intent && !valid())clearIntent();
      }
      window.addEventListener('wmNFCReaderStatus',()=>{
        update();
        if(!valid())return;
        if(state().available){
          const button=intent.button;clearIntent();
          // Run the normal guarded handler once, after the native status callback.
          bypass=true;try{button.click();}finally{bypass=false;}update();
        }else if(!state().externalConfigured){clearIntent();help.textContent='Connect the NFC reader in Scale & Card Reader Setup, or use Capture / Scan Card.';update();}
      });
      document.addEventListener('click',event=>{
        if(bypass)return;
        const button=event.target.closest?.('button');
        if(!button)return;
        if(!['kioskScanNfc','scanAthleteNfcBtn'].includes(button.id)){clearIntent();return;}
        // Preserve the existing Stop NFC search action and all pending writes.
        if(busy())return;
        event.preventDefault();event.stopImmediatePropagation();clearIntent();
        intent={button,key:key(),timer:setTimeout(()=>{const stillValid=valid();clearIntent();
          if(stillValid)
            help.textContent='Reader is not ready. Unlock and open Scale & Card Reader Setup, or use Capture / Scan Card.';
        },10000)};
        refresh('prepare');
      },true);
      document.addEventListener('visibilitychange',()=>{clearIntent();if(!document.hidden)refresh();});
      document.addEventListener('focusin',event=>{if(event.target.matches?.('input,textarea,select'))clearIntent();});
      new MutationObserver(update).observe(help,{childList:true,characterData:true,subtree:true});
      new MutationObserver(()=>{update();refresh();}).observe(document.body,{attributes:true,attributeFilter:['class']});
      new MutationObserver(update).observe(sheet,{attributes:true,attributeFilter:['class']});
      update();refresh();
    })();
    """#
    private let builtIn = WrestlingManagerBuiltInNfcBridge()
    private weak var webView: WKWebView?
    private var external: WrestlingManagerBluetoothNFC?
    private var externalRequestID: String?
    private var selectedWriter: String?
    private var replacementReply: ((Bool) -> Void)?
    private var backgroundObserver: NSObjectProtocol?
    private var statusObservation: AnyCancellable?
    private var lastStatusJSON: String?

    func configure(_ client: WrestlingManagerBluetoothNFC) {
        external = client
        statusObservation?.cancel()
        // Each WebView owns its subscription. Detaching an old WebView cannot
        // remove the new WebView's observer. Published values change after willSet.
        statusObservation = client.$state.combineLatest(client.$lastMessage, client.$readerName).combineLatest(client.$readerNicknames, client.$batteryPercent).sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.sendStatus(force: false) }
        }
    }
    func attach(to webView: WKWebView) {
        self.webView = webView; lastStatusJSON = nil; builtIn.attach(to: webView)
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }
    func detach() {
        cancel(); builtIn.detach()
        statusObservation?.cancel(); statusObservation = nil; lastStatusJSON = nil
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        backgroundObserver = nil; webView = nil
    }
    private var builtInAvailable: Bool {
        #if canImport(CoreNFC) && !targetEnvironment(macCatalyst)
        let usage = Bundle.main.object(forInfoDictionaryKey: "NFCReaderUsageDescription") as? String ?? ""
        return !usage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && UIDevice.current.userInterfaceIdiom == .phone && NFCTagReaderSession.readingAvailable
        #else
        return false
        #endif
    }
    func sendStatus(force: Bool = true) {
        let connected = external?.available == true
        let writer = selectedWriter ?? (connected ? "bluetooth" : "builtin")
        var packet: [String: Any] = ["event": "status", "timedRead": true, "available": connected || builtInAvailable,
              "externalConnected": connected, "externalConfigured": external?.hasRememberedReader == true,
              "externalState": external?.state.rawValue ?? "Disconnected", "builtInAvailable": builtInAvailable,
              "canWrite": writer == "bluetooth" ? connected : builtInAvailable,
              "writerSource": writer, "readerIdentifier": connected ? external?.savedReaderIdentifier?.uuidString ?? "" : "",
              "readerName": external?.displayName ?? "",
              "readerMessage": external?.lastMessage ?? "", "nativeNFCRevision": 20,
              "source": connected ? "bluetooth" : builtInAvailable ? "builtin" : "none"]
        // Explicit null clears old telemetry after disconnection or a failed read.
        packet["readerBatteryPercent"] = NSNull()
        if connected, let percent = external?.batteryPercent { packet["readerBatteryPercent"] = percent }
        guard let data = try? JSONSerialization.data(withJSONObject: packet, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        if !force, json == lastStatusJSON { return }
        if send(packet) { lastStatusJSON = json }
    }
    func cancel() {
        replacementReply = nil
        if let id = externalRequestID {
            externalRequestID = nil
            external?.cancelRead()
            send(["requestId": id, "ok": false, "cancelled": true,
                  "message": "Programming cancelled. If writing had started, program the card again before using it."])
        }
        builtIn.cancel()
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.webView === webView, message.frameInfo.isMainFrame, WrestlingManagerAppOrigin.contains(message.frameInfo.request.url),
              WrestlingManagerAppOrigin.contains(webView?.url),
              let body = message.body as? [String: Any], let command = body["command"] as? String else { return }
        if command == "status" { sendStatus(); return }
        if command == "selectWriter" {
            guard externalRequestID == nil, let writer = body["writer"] as? String, ["bluetooth", "builtin"].contains(writer) else { return }
            selectedWriter = writer; sendStatus(); return
        }
        if command == "prepare" {
            if let external, !external.available, external.hasRememberedReader { external.reconnect() }
            sendStatus(); return
        }
        if command == "cancel", let id = body["requestId"] as? String, id == externalRequestID { cancel(); return }
        if command == "confirmWrite" {
            guard let id = body["requestId"] as? String, id == externalRequestID, let reply = replacementReply else { return }
            replacementReply = nil; reply(body["approved"] as? Bool == true); return
        }
        guard ["read", "write"].contains(command) else {
            builtIn.userContentController(userContentController, didReceive: message); return
        }
        guard let id = body["requestId"] as? String, UUID(uuidString: id) != nil else { return }
        guard externalRequestID == nil else {
            send(["requestId": id, "ok": false, "message": "Finish or cancel the current card scan first."]); return
        }
        if command == "write" {
            guard let token = body["token"] as? String, WrestlingManagerACRProtocol.validToken(token),
                  let writer = body["writer"] as? String, ["bluetooth", "builtin"].contains(writer),
                  let readerID = body["readerIdentifier"] as? String,
                  UIApplication.shared.applicationState == .active else {
                send(["requestId": id, "ok": false, "message": "Reopen Athlete Cards and choose the writer to use."]); return
            }
            guard writer == "bluetooth" ? external?.available == true && external?.savedReaderIdentifier?.uuidString == readerID : builtInAvailable else {
                send(["requestId": id, "ok": false, "message": "The selected writer is not ready. Connect it and try again."]); return
            }
            selectedWriter = writer; externalRequestID = id
            authorizeWrite(id: id, token: token, readerID: readerID) { [weak self] allowed in
                guard let self, self.externalRequestID == id else { return }
                guard allowed else { self.cancel(); return }
                if writer == "builtin" {
                    self.externalRequestID = nil
                    self.builtIn.userContentController(userContentController, didReceive: message)
                    return
                }
                self.builtIn.cancel()
                guard let external = self.external, external.available else { self.cancel(); return }
                external.write(token: token, authorize: { [weak self] reply in
                    guard let self else { reply(false); return }
                    self.authorizeWrite(id: id, token: token, readerID: readerID, completion: reply)
                }, confirmReplacement: { [weak self] reply in
                    guard let self, self.externalRequestID == id else { reply(false); return }
                    self.replacementReply = reply
                    if !self.send(["event": "replaceRequired", "requestId": id]) { self.cancel() }
                }, completion: { [weak self] result in
                    guard let self, self.externalRequestID == id else { return }
                    self.externalRequestID = nil; self.replacementReply = nil
                    switch result {
                    case .success:
                        self.send(["requestId": id, "ok": true, "message": "Athlete card programmed and verified."])
                    case .failure(let error):
                        self.send(["requestId": id, "ok": false, "message": error.message,
                                   "cancelled": error.cancelled, "timedOut": error.timedOut])
                    }
                })
            }
            return
        }
        if command == "read", let external, external.available {
            guard UIApplication.shared.applicationState == .active else {
                send(["requestId": id, "ok": false, "cancelled": true]); return
            }
            builtIn.cancel()
            externalRequestID = id
            let requestedTimeout = body["timeoutSeconds"] as? Double ?? 30
            let timeout = requestedTimeout.isFinite ? min(30, max(1, requestedTimeout)) : 30
            external.read(timeout: timeout) { [weak self] result in
                guard let self, self.externalRequestID == id else { return }
                self.externalRequestID = nil
                switch result {
                case .success(let token):
                    guard WrestlingManagerACRProtocol.validToken(token) else { return }
                    self.send(["requestId": id, "ok": true, "token": token, "message": "Athlete card read."])
                case .failure(let error):
                    self.send(["requestId": id, "ok": false, "message": error.message,
                               "cancelled": error.cancelled, "timedOut": error.timedOut])
                }
            }
            return
        }
        if command == "read", !builtInAvailable {
            send(["requestId": id, "ok": false, "message": "Open Scale & Card Reader Setup and connect the ACS NFC reader, then try again."]); return
        }
        builtIn.userContentController(userContentController, didReceive: message)
    }
    private func authorizeWrite(id: String, token: String, readerID: String, completion: @escaping (Bool) -> Void) {
        guard externalRequestID == id, UIApplication.shared.applicationState == .active,
              let webView, WrestlingManagerAppOrigin.contains(webView.url),
              let data = try? JSONSerialization.data(withJSONObject: [id, token, readerID]),
              let arguments = String(data: data, encoding: .utf8) else { completion(false); return }
        webView.evaluateJavaScript("window.wmNFCWriterIsCurrent?.(...\(arguments)) === true") { [weak self] value, error in
            let allowed = error == nil && (value as? Bool) == true
            Task { @MainActor [weak self] in
                guard let self else { completion(false); return }
                completion(allowed && self.externalRequestID == id && UIApplication.shared.applicationState == .active && WrestlingManagerAppOrigin.contains(self.webView?.url))
            }
        }
    }
    @discardableResult
    private func send(_ result: [String: Any]) -> Bool {
        guard let webView, WrestlingManagerAppOrigin.contains(webView.url),
              let data = try? JSONSerialization.data(withJSONObject: result), let json = String(data: data, encoding: .utf8) else { return false }
        let isStatus = result["event"] as? String == "status"
        let prefix = isStatus
            ? "window.wrestlingManagerNativeNFCStatus = \(json); window.wrestlingManagerExternalNFCConnected = \(external?.available == true ? "true" : "false"); " : ""
        let suffix = isStatus ? "window.dispatchEvent(new Event('wmNFCReaderStatus'));" : ""
        webView.evaluateJavaScript(prefix + "window.wrestlingManagerNfcResult && window.wrestlingManagerNfcResult(\(json)); " + suffix, completionHandler: nil)
        return true
    }
}

@MainActor
struct WrestlingManagerNFCSetupSection: View {
    @ObservedObject var client: WrestlingManagerBluetoothNFC
    let onRename: () -> Void
    var body: some View {
        Section("Bluetooth NFC reader") {
            HStack(spacing: 12) {
                Image(systemName: "wave.3.right").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(client.displayName ?? "NFC Reader").font(.headline)
                    Text(client.state.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if client.available {
                    WrestlingManagerNFCBatteryIndicator(percent: client.batteryPercent)
                } else if client.state == .connecting || client.state == .discovering || client.state == .scanning {
                    ProgressView().accessibilityLabel(client.state.rawValue)
                }
            }
            Toggle("Auto-connect", isOn: $client.autoConnect)
                .accessibilityLabel("Auto-connect NFC reader")
            if client.available {
                Label(client.cardPresent ? "Card detected" : "Ready for a card", systemImage: "creditcard")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if client.state == .connecting || client.state == .discovering {
                Button("Cancel Connection") { client.cancelConnection() }
            } else {
                Button(client.state == .scanning ? "Stop Search" : "Find NFC Reader") {
                    if client.state == .scanning { client.stopSearch() } else { client.scan() }
                }
                if client.hasRememberedReader && client.state != .scanning {
                    Button("Reconnect Saved Reader") { client.reconnect() }
                }
                ForEach(client.devices) { device in
                    Button { client.connect(device) } label: {
                        HStack {
                            Text(client.displayName(for: device)).foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            if device.id == client.savedReaderIdentifier { Text("Saved").font(.caption).foregroundStyle(.secondary) }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let message = client.lastMessage { Text(message).font(.footnote).foregroundStyle(.secondary) }
            if client.available, let percent = client.batteryPercent, percent <= 20 {
                Text("Low battery. Charge your reader.").font(.footnote).foregroundStyle(.red)
            }
            if client.hasRememberedReader {
                DisclosureGroup("Reader settings") {
                    Button("Rename Reader", action: onRename)
                    if client.available { Button("Disconnect", role: .destructive) { client.disconnect() } }
                    Button("Forget Reader", role: .destructive) { client.forget() }
                }
            }
        }
    }
}

@MainActor
private struct WrestlingManagerNFCBatteryIndicator: View {
    let percent: Int?
    private var symbol: String {
        guard let percent else { return "battery.0percent" }
        if percent <= 10 { return "battery.0percent" }
        if percent <= 25 { return "battery.25percent" }
        if percent <= 50 { return "battery.50percent" }
        if percent <= 75 { return "battery.75percent" }
        return "battery.100percent"
    }
    private var tint: Color {
        guard let percent else { return .secondary }
        return percent <= 20 ? .red : .green
    }
    var body: some View {
        Label(percent.map { "\($0)%" } ?? "—", systemImage: symbol)
            .font(.subheadline.monospacedDigit()).foregroundStyle(tint).fixedSize()
            .accessibilityLabel(percent.map { "Reader battery \($0) percent" } ?? "Reader battery unavailable")
    }
}

// Editing owns its draft and has no subscription to live Bluetooth updates.
// Only Cancel or a successful Save closes this sheet.
@MainActor
struct WrestlingManagerNFCRenameView: View {
    private let save: (String) throws -> Void
    private let close: () -> Void
    @State private var name: String
    @State private var errorMessage: String?

    init(initialName: String, save: @escaping (String) throws -> Void, close: @escaping () -> Void) {
        _name = State(initialValue: initialName)
        self.save = save
        self.close = close
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Reader name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                } footer: {
                    Text("For example: Lyman NFC Scanner. This name is saved in Wrestling Manager on this device; the reader's broadcast Bluetooth name stays the same.")
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("Rename NFC Reader")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try save(name); close() }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}
