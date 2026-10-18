"""Fail if a mobile ZIP/APK/IPA contains private .env values or unexpected config.

Values are compared in memory and never printed. Requires the original local
.env to compare historical provider values; use the same audit with rotated keys
present in the release build environment. Public Firebase IDs/Mapbox pk are not
secrets. This is an artifact check, not a full secret detector.
"""
import argparse
import hashlib
import json
import os
import zipfile
from pathlib import Path
from prepare_mobile_public_config import ROOT, local_values

parser = argparse.ArgumentParser()
parser.add_argument('artifact', type=Path)
parser.add_argument('--output', type=Path)
args = parser.parse_args()
values = {**local_values(), **{k: v for k, v in os.environ.items() if k.endswith(('_API_KEY', '_API_TOKEN'))}}
private = {k: v for k, v in values.items() if k not in {'MAPBOX_ACCESS_TOKEN', 'OPENWEATHER_TILES_ENABLED'} and len(v) >= 12}
if not private:
    raise SystemExit('No private comparison values available; audit cannot establish absence.')
issues = set()
assets = []
with zipfile.ZipFile(args.artifact) as archive:
    for name in archive.namelist():
        if name.endswith('/'):
            continue
        payload = archive.read(name)
        if name.rsplit('/', 1)[-1] == '.env':
            issues.add('private-env-asset')
        if name.endswith('/.env.public'):
            assets.append(name)
            for line in payload.decode('utf-8').splitlines():
                key, sep, value = line.partition('=')
                if not sep or key.startswith('#'):
                    continue
                if key not in {'MAPBOX_ACCESS_TOKEN', 'OPENWEATHER_TILES_ENABLED'}:
                    issues.add('unexpected-public-config-key')
                if key == 'MAPBOX_ACCESS_TOKEN' and value and not value.startswith('pk.'):
                    issues.add('nonpublic-mapbox-token')
        for key, value in private.items():
            if value.encode() in payload or value.encode('utf-16-le') in payload:
                issues.add('embedded-private-credential:' + key)
result = {'artifact': str(args.artifact), 'privateComparisons': len(private),
          'artifactSha256': hashlib.sha256(args.artifact.read_bytes()).hexdigest(),
          'publicAssets': assets, 'issues': sorted(issues), 'passed': not issues and len(assets) == 1}
if args.output:
    args.output.write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result, indent=2))
raise SystemExit(0 if result['passed'] else 1)
