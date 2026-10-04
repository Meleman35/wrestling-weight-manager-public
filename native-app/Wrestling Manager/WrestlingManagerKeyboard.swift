// Generated from build/keyboard-navigation.js and build/keyboard-webview.swift.
import UIKit
import WebKit

enum WrestlingManagerKeyboard {
    static let script = #"""
/* Wrestling Manager: keyboard navigation for static and dynamically opened forms. */
(() => {
  'use strict';
  if (window.WMKeyboardNavigation?.version >= 213) return;
  // Publish immediately, even at document start, so an older website/native
  // injection cannot install a second Return handler over this one.
  window.WMKeyboardNavigation = {version:213,moveFocus};
  const controls = 'input,select,textarea,button,a[href],summary,[tabindex],[contenteditable="true"]';
  const panels = 'dialog[open],.ows-modal,[role="dialog"],.sheet,#wmOfficialSheets,#authView,#appLockOverlay';
  const handledEnter = new Set(['appLockPin','editWeightClassAdd','teammateWeightPin','weightPinConfirm','weighScanToken']);
  const textTypes = new Set(['text','email','password','search','tel','url','number']);
  function visible(el) {
    if (!(el instanceof HTMLElement) || el.matches(':disabled,[disabled],[type="hidden"]') || el.closest('[hidden],.hidden,[inert],[aria-hidden="true"]')) return false;
    if (!el.getClientRects().length || ['hidden','collapse'].includes(getComputedStyle(el).visibility)) return false;
    for (let d=el.closest('details');d;d=d.parentElement?.closest('details')) {
      if (!d.open && !d.querySelector(':scope > summary')?.contains(el)) return false;
    }
    return true;
  }
  function scope(el) { return el.closest(panels) || document.body; }
  function fields(el) {
    const container=el.form || el.closest('[data-keyboard-group]') || scope(el);
    const candidates=el.form ? Array.from(el.form.elements) : [...container.querySelectorAll('input,select,textarea')];
    return candidates.filter(n=>visible(n) && !n.readOnly && (n.matches('textarea,select') || (n instanceof HTMLInputElement && (textTypes.has(n.type)||['date','time','datetime-local'].includes(n.type)))));
  }
  function submitter(form) {
    return Array.from(form.elements).find(n=>visible(n) && ((n instanceof HTMLButtonElement && n.type==='submit') || (n instanceof HTMLInputElement && ['submit','image'].includes(n.type))));
  }
  function nextField(el) { const list=fields(el);return list[list.indexOf(el)+1]; }
  function focus(el) { el.focus();el.scrollIntoView({block:'nearest',inline:'nearest'}); }
  function moveFocus(direction=1, native=false) {
    const el=document.activeElement;
    if (!document.body || !(el instanceof HTMLElement) || el.closest('[data-keyboard-native]')) return false;
    const step=direction<0?-1:1;
    // A native Tab command may arrive before the first field has been clicked.
    // Start within the visible dialog, lock screen or sign-in panel in that case.
    const container=el===document.body || !visible(el)
      ? [...document.querySelectorAll(panels)].filter(visible).at(-1)||document.body
      : scope(el);
    const list=[...container.querySelectorAll(controls)]
      .filter(n=>visible(n)&&n.tabIndex>=0)
      .sort((a,b)=>(a.tabIndex||Infinity)-(b.tabIndex||Infinity));
    if (!list.length) return false;
    const current=el.closest(controls),index=list.indexOf(current);
    let target;
    if (index<0) target=step<0?list.at(-1):list[0];
    else target=list[index+step];
    if (!target && (native || container.matches('dialog[open],.ows-modal,[role="dialog"],.sheet,#wmOfficialSheets,#appLockOverlay'))) target=step<0?list.at(-1):list[0];
    if (!target) return false;
    focus(target);
    return document.activeElement===target;
  }
  // Run Tab in capture phase so a form's bubbling listener cannot swallow it.
  // In WKWebView, the native key command calls moveFocus directly because UIKit
  // can consume Tab without producing any DOM keyboard event.
  document.addEventListener('keydown',event=>{
    if (event.key!=='Tab' || event.defaultPrevented || event.isComposing || event.keyCode===229 || event.altKey || event.ctrlKey || event.metaKey) return;
    const el=event.target;
    if (!(el instanceof HTMLElement) || !visible(el) || el.closest('[data-keyboard-native]')) return;
    // Browser date/time controls retain native segment navigation. The native
    // app command advances to the next whole control; arrow keys edit segments.
    if (el.matches('input[type="date"],input[type="time"],input[type="datetime-local"]')) return;
    if (moveFocus(event.shiftKey?-1:1)) {
      event.preventDefault();
      event.stopImmediatePropagation();
    }
  },true);
  function enter(el) {
    if (!el.reportValidity()) return;
    const next=nextField(el);
    if (next) { focus(next);return; }
    const button=el.form && submitter(el.form);
    if (button) { el.form.requestSubmit(button);return; }
    // No form action: close the soft keyboard, keeping edits saved by the field handler.
    el.blur();
  }
  document.addEventListener('keydown',event=>{
    if (event.defaultPrevented || event.isComposing || event.keyCode===229 || event.altKey || event.ctrlKey || event.metaKey) return;
    const el=event.target;
    if (!(el instanceof HTMLElement) || !visible(el) || el.closest('[data-keyboard-native]')) return;
    if (event.key!=='Enter' || !(el instanceof HTMLInputElement) || !textTypes.has(el.type) || el.readOnly || handledEnter.has(el.id)) return;
    event.preventDefault();
    if (!event.repeat && !event.shiftKey) enter(el);
  });
  // Some iOS keyboards express Return as beforeinput instead of a keydown.
  document.addEventListener('beforeinput',event=>{
    const el=event.target;
    if (event.defaultPrevented || event.isComposing || !['insertLineBreak','insertParagraph'].includes(event.inputType) || !(el instanceof HTMLInputElement) || !textTypes.has(el.type) || el.readOnly || handledEnter.has(el.id) || !visible(el)) return;
    event.preventDefault();enter(el);
  });
  function hints() {
    for (const el of document.querySelectorAll('input')) {
      if (!visible(el) || !textTypes.has(el.type) || el.readOnly || handledEnter.has(el.id)) continue;
      const hint=nextField(el)?'next':el.form&&submitter(el.form)?(el.type==='search'?'search':'go'):'done';
      if (el.getAttribute('enterkeyhint')!==hint) el.setAttribute('enterkeyhint',hint);
    }
  }
  let pending=false;
  function refresh() { if (pending) return;pending=true;queueMicrotask(()=>{pending=false;hints();}); }
  document.addEventListener('focusin',refresh);
  function ready() {
    new MutationObserver(records=>{
      if (records.some(r=>[...r.addedNodes,...r.removedNodes].some(n=>n instanceof HTMLElement && (n.matches('input,select,textarea,button') || n.querySelector('input,select,textarea,button'))))) refresh();
    }).observe(document.body,{childList:true,subtree:true});
    hints();
  }
  if (document.body) ready();
  else document.addEventListener('DOMContentLoaded',ready,{once:true});
})();

"""#
}

// App-owned Tab commands for iOS, iPadOS and Mac Catalyst.
// UIKit can handle focus navigation before WKWebView sends DOM keydown events.
@MainActor
final class WrestlingManagerKeyboardWebView: WKWebView {
    private lazy var tabCommands: [UIKeyCommand] = {
        let forward = UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(moveFormFocus(_:)))
        let backward = UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(moveFormFocus(_:)))
        for command in [forward, backward] {
            command.wantsPriorityOverSystemBehavior = true
        }
        return [forward, backward]
    }()

    override var keyCommands: [UIKeyCommand]? {
        let inherited = (super.keyCommands ?? []).filter { command in
            !(command.input == "\t" && (command.modifierFlags.isEmpty || command.modifierFlags == .shift))
        }
        return tabCommands + inherited
    }

    @objc private func moveFormFocus(_ command: UIKeyCommand) {
        let direction = command.modifierFlags.contains(.shift) ? -1 : 1
        // Only move focus. This does not synthesize Return, click or submission.
        // The same helper is installed at document start in both app web views.
        evaluateJavaScript("window.WMKeyboardNavigation?.moveFocus?.(\(direction), true);", completionHandler: nil)
    }
}
