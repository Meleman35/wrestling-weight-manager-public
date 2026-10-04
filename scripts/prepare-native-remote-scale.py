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
    repo = Path(__file__).resolve().parents[1]
    # Exact original vendor/client snapshot from the supplied source ZIP. Never
    # overwrite a differently edited client, including a prior remote install.
    expected = 'bbcb20277d29fe6dd0f5407610002d6d60a2daeaed8d3beedcfc0218d413ce36'
    if hashlib.sha256(scale.read_bytes()).hexdigest() != expected:
        raise RuntimeError('Scale source differs from the reviewed original upload. No files were changed. Use a fresh source copy.')
    scale_sources = repo / 'native-device-check/AmericanScaleKit/Sources/AmericanScaleKit'
    read_cycle = scale.with_name('AmericanScaleReadCycle.swift')
    if read_cycle.exists():
        raise RuntimeError('Scale read cycle already exists. No files were changed.')
    names = ['WrestlingManagerRemoteCapture.swift', 'WrestlingManagerRemotePhoto.swift',
             'WrestlingManagerRemoteCaptureHost.swift', 'WrestlingManagerRemoteReadiness.swift', 'WrestlingManagerRemoteOutbox.swift',
             'WrestlingManagerRemoteDelivery.swift', 'WrestlingManagerRemoteDeliveryStore.swift',
             'WrestlingManagerRemoteRetention.swift', 'WrestlingManagerRemoteHTTP.swift', 'WrestlingManagerRemoteReportingSession.swift', 'WrestlingManagerRemoteDeviceCheck.swift']
    changes = {scale: (scale_sources / 'AmericanScaleClient.swift').read_bytes(),
               read_cycle: (scale_sources / 'AmericanScaleReadCycle.swift').read_bytes()}
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
    print('Prepared remote capture components, optional BLE packet hook and bounded direct-read support.')
    print('Scale backup:', backup)
    print('Original scale SHA256:', hashlib.sha256(originals[scale]).hexdigest())
    print('Host activation, authorization and upload integration still required before device use.')


if __name__ == '__main__':
    main()
