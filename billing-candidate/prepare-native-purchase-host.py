#!/usr/bin/env python3
"""Patch the reviewed native host copy; fail closed on a different source."""
import hashlib
from pathlib import Path
import sys

EXPECTED = '186b6d4b03ed0d59940ea9ec21cc90178f530ff5feb6497a5a975283614cbd52'

def prepare(source):
    if hashlib.sha256(source).hexdigest() != EXPECTED:
        raise ValueError('Native source differs from reviewed October 1 source; review before patching.')
    text = source.decode('utf-8')
    edits = [
        ('        context.coordinator.webView = webView\n', '        context.coordinator.webView = webView\n        context.coordinator.purchaseHost = WrestlingManagerPurchaseHost(webView: webView)\n'),
        ('        coordinator.deletionBridge.detach()\n', '        coordinator.deletionBridge.detach()\n        coordinator.purchaseHost?.detach()\n        coordinator.purchaseHost = nil\n'),
        ('        weak var webView: WKWebView?\n', '        weak var webView: WKWebView?\n        var purchaseHost: WrestlingManagerPurchaseHost?\n'),
        ('            deletionBridge.pageChanged()\n', '            purchaseHost?.stop()\n            deletionBridge.pageChanged()\n'),
        ('                videoPilotBridge.reset()\n', '                purchaseHost?.stop()\n                videoPilotBridge.reset()\n'),
        ('                if locked { videoPilotBridge.reset() }', '                if locked { purchaseHost?.stop(); videoPilotBridge.reset() }'),
        ('        @objc private func appEnteredBackground() {\n', '        @objc private func appEnteredBackground() {\n            purchaseHost?.stop()\n'),
    ]
    for old, new in edits:
        expected = 2 if old == '            deletionBridge.pageChanged()\n' else 1
        if text.count(old) != expected:
            raise ValueError('Unexpected native host structure: ' + old.strip())
        text = text.replace(old, new)
    return text

if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: prepare-native-purchase-host.py SOURCE OUTPUT')
    Path(sys.argv[2]).write_text(prepare(Path(sys.argv[1]).read_bytes()))
