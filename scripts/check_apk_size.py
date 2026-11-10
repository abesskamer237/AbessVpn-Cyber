#!/usr/bin/env python3
"""Verify release packaging before publishing and record actual APK sizes."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

LIMITS = {'arm64-v8a': 25_000_000, 'armeabi-v7a': 23_000_000, 'x86_64': 30_000_000, 'universal': 75_000_000}
CRITICAL = {'libgojni.so', 'libflutter.so', 'libapp.so', 'libtun2socks.so'}


def inspect_apk(file):
    with zipfile.ZipFile(file) as apk:
        entries = apk.infolist()
        names = {entry.filename for entry in entries}
        assert not any(Path(name).name in {'geoip.dat', 'geosite.dat'} for name in names), 'Unused geographic databases are still packaged'
        libraries = [entry for entry in entries if entry.filename.startswith('lib/') and entry.filename.endswith('.so')]
        assert libraries, 'Native libraries missing'
        abis = sorted({entry.filename.split('/')[1] for entry in libraries})
        for abi in abis:
            actual = {Path(entry.filename).name for entry in libraries if entry.filename.startswith(f'lib/{abi}/')}
            assert CRITICAL <= actual, f'Incomplete native VPN/Flutter engine for {abi}'
        assert all(entry.compress_type == zipfile.ZIP_DEFLATED for entry in libraries), 'Native libraries must be compressed inside the APK'
        for entry in entries:
            if entry.filename.endswith('MaterialIcons-Regular.otf'):
                assert entry.file_size < 300_000, 'Material icon font was not reduced'
            assert not entry.filename.endswith('CupertinoIcons.ttf'), 'Unused Cupertino icon font included'
        kind = abis[0] if len(abis) == 1 else 'universal'
        assert kind in LIMITS, f'Unknown ABI: {kind}'
        size = file.stat().st_size
        assert size <= LIMITS[kind], f'{file.name} exceeds {LIMITS[kind] / 1e6:.0f} MB release budget ({size / 1e6:.2f} MB)'
        return {'file': file.name, 'abis': abis, 'bytes': size, 'megabytes': round(size / 1e6, 2),
                'native_uncompressed_bytes': sum(entry.file_size for entry in libraries),
                'native_compressed_bytes': sum(entry.compress_size for entry in libraries),
                'sha256': hashlib.sha256(file.read_bytes()).hexdigest(),
                'vpn_engine_sha256': {entry.filename: hashlib.sha256(apk.read(entry)).hexdigest()
                                      for entry in libraries if Path(entry.filename).name in {'libgojni.so', 'libtun2socks.so'}}}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('apks', nargs='+', type=Path)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--markdown', required=True, type=Path)
    args = parser.parse_args()
    # Asset exclusion is safe only while the app's generated configurations do
    # not reference GeoIP/GeoSite files. A future routing feature must revisit it.
    for source in Path('lib').rglob('*.dart'):
        assert not re.search(r'\b(?:geoip|geosite):|\bext:(?:geoip|geosite)', source.read_text()), f'{source}: geographic routing requires the excluded databases'
    reports = [inspect_apk(file) for file in args.apks]
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(reports, indent=2) + '\n')
    rows = ['# Taille réelle des APK', '', 'Prenez la variante ARM64 ou ARM32 adaptée au téléphone pour le téléchargement le plus petit. La variante universelle contient plusieurs architectures.', '', '| Fichier | Architecture | Taille du téléchargement |', '|---|---|---:|']
    for report in reports:
        rows.append(f"| {report['file']} | {', '.join(report['abis'])} | {report['megabytes']:.2f} Mo |")
        print(f"{report['file']}: {report['megabytes']:.2f} MB — packaging and size checks passed")
    rows += ['', 'Choisissez ARM64 pour un téléphone arm64-v8a, ARM32 pour armeabi-v7a. Le fichier universel est plus gros car il contient plusieurs architectures.', '',
             'Android 7.0 ou supérieur. Les moteurs natifs restent inclus et sont décompressés à l’installation : la taille installée est supérieure à celle du téléchargement.', '']
    args.markdown.parent.mkdir(parents=True, exist_ok=True)
    args.markdown.write_text('\n'.join(rows))


if __name__ == '__main__':
    main()
