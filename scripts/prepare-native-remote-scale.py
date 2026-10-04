#!/usr/bin/env python3
"""Install dormant native remote-capture components and a real BLE packet hook.
Run against a COPY of the uploaded app/source package. No Xcode signing changes.
"""
import argparse
import hashlib
from pathlib import Path
import shutil
import datetime


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app-source', required=True, type=Path)
    parser.add_argument('--scale-client', required=True, type=Path)
    args = parser.parse_args()
    app = args.app_source.resolve()
    scale = args.scale_client.resolve()
    if not (app / 'ContentView.swift').is_file() or not scale.is_file():
        raise RuntimeError('Provide the app source folder and AmericanScaleClient.swift.')
    source = scale.read_text()
    property_anchor = '    public var displayUnit: AmericanScaleDisplayUnit = .pounds\n'
    packet_anchor = '            let messages = self.parser.append(data)\n            self.apply(messages)\n'
    if 'onRemoteWeightPacket' in source:
        raise RuntimeError('Remote hook already exists; review the prior installation before applying again.')
    if source.count(property_anchor) != 1 or source.count(packet_anchor) != 1:
        raise RuntimeError('Scale source differs from the reviewed upload. No files were changed.')
    source = source.replace(property_anchor, property_anchor + '''
    /// Real BLE packet evidence; optional and dormant until an authorized host connects it.
    public var onRemoteWeightPacket: (@MainActor (Double, Date) -> Void)?
''')
    source = source.replace(packet_anchor, '''            let messages = self.parser.append(data)
            let observedAt = Date()
            // Reject callbacks from a stale peripheral or incomplete connection.
            if self.connectionState == .ready, self.connectedPeripheral === peripheral {
                for message in messages {
                    if case .weight(let pounds) = message {
                        self.onRemoteWeightPacket?(pounds, observedAt)
                    }
                }
            }
            self.apply(messages)
''')
    repo = Path(__file__).resolve().parents[1]
    names = ['WrestlingManagerRemoteCapture.swift', 'WrestlingManagerRemotePhoto.swift',
             'WrestlingManagerRemoteCaptureHost.swift', 'WrestlingManagerRemoteOutbox.swift']
    changes = {scale: source.encode()}
    for name in names:
        target = app / name
        if target.exists():
            raise RuntimeError(f'{name} already exists. No files were changed.')
        changes[target] = (repo / 'native-candidate' / name).read_bytes()
    backup = app.parent / ('remote-capture-backup-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    backup.mkdir()
    shutil.copy2(scale, backup / 'AmericanScaleClient.swift')
    originals = {path: path.read_bytes() if path.exists() else None for path in changes}
    try:
        for path, data in changes.items():
            path.write_bytes(data)
    except Exception:
        for path, data in originals.items():
            if data is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(data)
        raise
    print('Prepared remote capture components and optional real BLE packet hook.')
    print('Scale backup:', backup)
    print('Original scale SHA256:', hashlib.sha256(originals[scale]).hexdigest())
    print('Host activation, authorization and upload integration still required before device use.')


if __name__ == '__main__':
    main()
