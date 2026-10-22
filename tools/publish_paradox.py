"""Paradox Mods LFv1 adapter, matched to Paradox Launcher 2026.13.

Private, undocumented API: verify this adapter after launcher changes.
Only updates the existing mod. Secrets stay in memory and are never logged.
"""
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

from publish_release import PARADOX_ID, ROOT

API = 'https://api.paradox-interactive.com'
STORAGE = Path.home() / 'Library/Application Support/Paradox Interactive/launcher-v2/session.js'


def request(method, path, *, auth=None, data=None, binary=False):
    url = API + path
    headers = {'Accept': 'application/json', 'User-Agent': 'MonarqueAbsoluPublisher/1'}
    if auth:
        headers['Authorization'] = json.dumps(auth, separators=(',', ':'))
    if binary:
        headers['Content-Type'] = 'application/octet-stream'
    elif data is not None:
        headers['Content-Type'] = 'application/json'
        data = json.dumps(data).encode()
    req = urllib.request.Request(url, headers=headers, data=data, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            body = response.read()
            result = json.loads(body) if body else {}
    except urllib.error.HTTPError as error:
        # Server bodies and request headers can contain credentials: do not print them.
        raise RuntimeError(f'Paradox {method} {path.split("?")[0]} returned HTTP {error.code}') from None
    except urllib.error.URLError:
        raise RuntimeError('Paradox network request failed; publication status may be unknown') from None
    if isinstance(result, dict) and result.get('result') not in (None, 'OK', 'ok', True):
        raise RuntimeError('Paradox returned a non-success result; inspect the item before retrying')
    return result


def launcher_key():
    """Read the installed launcher's storage format; do not embed its key in the repo."""
    root = Path.home() / 'Library/Application Support/Paradox Interactive'
    archives = sorted(root.glob('launcher-v2.*/Paradox Launcher.app/Contents/Resources/app.asar'),
                      key=lambda p: [int(x) for x in re.findall(r'\d+', p.parts[-5])], reverse=True)
    for path in archives:
        with path.open('rb') as stream:
            header = struct.unpack('<4I', stream.read(16))
            files = json.loads(stream.read(header[3]))
            try:
                entry = files['files']['dist']['files']['main']['files']['index.mjs']
            except KeyError:
                continue
            stream.seek(8 + header[1] + int(entry['offset']))
            source = stream.read(entry['size']).decode()
        match = re.search(r'\w+="session\.js",\w+="([A-Fa-f0-9]{64})"', source)
        if match and 'aes-256-cbc' in source:
            return match[1]
    raise RuntimeError('Unsupported launcher storage format. Supply PDX_SESSION_TOKEN instead.')


def crypt_session(data, key, iv, decrypt=False):
    args = ['openssl', 'enc', '-aes-256-cbc', '-K', key, '-iv', iv.hex()]
    if decrypt:
        args.append('-d')
    result = subprocess.run(args, input=data, capture_output=True)
    if result.returncode:
        raise RuntimeError('Unable to read the launcher session; sign in through the launcher again')
    return result.stdout


def authenticate():
    explicit = os.environ.get('PDX_SESSION_TOKEN')
    if explicit:
        return {'session': {'token': explicit}}
    if not STORAGE.is_file():
        raise RuntimeError('No saved Paradox session. Sign in with Remember me in the launcher.')
    key = launcher_key()
    encrypted = bytes.fromhex(STORAGE.read_text().strip())
    saved = json.loads(crypt_session(encrypted[16:], key, encrypted[:16], decrypt=True))
    renewal = saved.get('refresh_token')
    if not renewal:
        raise RuntimeError('No saved Paradox renewal token; sign in with Remember me in the launcher.')
    result = request('PUT', '/accounts/sessions/launcher-v2', auth={'renewal': {'token': renewal}})
    session = result.get('session', {})
    if not session.get('token'):
        raise RuntimeError('Paradox session renewal failed')
    # Preserve Remember me if the server rotates its renewal token. Never store plaintext.
    if session.get('refresh_token') and session['refresh_token'] != renewal:
        saved['refresh_token'] = session['refresh_token']
        iv = os.urandom(16)
        STORAGE.write_text((iv + crypt_session(json.dumps(saved).encode(), key, iv)).hex())
    return {'session': {'token': session['token']}}


def metadata(auth=None):
    return request('GET', f'/mods?modId={PARADOX_ID}', auth=auth)['modDetail']


def notes_published(detail, notes):
    return any(entry.get('details', '').strip() == notes.strip()
               and str(entry.get('modVersion')) == str(detail.get('latestVersion'))
               for entry in detail.get('changelog', []))


def publish(content, info, timeout):
    auth = authenticate()
    before = metadata(auth)
    # The search index may temporarily omit an owned item after an update.
    # Check the authenticated permission on the actual destination instead.
    if before.get('actions', {}).get('canPublish') is not True:
        raise RuntimeError('The signed-in Paradox account cannot publish mod 161949; refusing to upload')
    if before.get('updating'):
        raise RuntimeError('Paradox is already processing an update; refusing a concurrent publication')
    if before.get('displayName') != info['name'] or before.get('game') != 'ck3':
        raise RuntimeError('Unexpected Paradox mod identity; refusing to upload')
    # Keep the exact remote mod name; the API uses it rather than its numerical ID for content uploads.
    if notes_published(before, info['notes']):
        print('Paradox: this version and its notes are already published; no upload performed.')
        return
    remote_name = before['name']
    filename = f"monarqueabsolu{info['version'].replace('.', '')}.zip"
    archive = content.parent / filename
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as package:
        for path in sorted(content.rglob('*')):
            if path.is_file():
                package.write(path, path.relative_to(content).as_posix())
    payload = {
        'modId': str(PARADOX_ID), 'modName': remote_name, 'gameName': 'ck3',
        'contentFileName': filename, 'os': 'Any', 'arch': 'Any',
        'longDescription': (ROOT / 'docs/paradox_mods_description.txt').read_text(),
        'shortDescription': (ROOT / 'docs/paradox_mods_short_description.txt').read_text().strip(),
        'displayName': info['name'], 'tags': info['tags'],
        'recommendedGameVersion': info['required'], 'changelogEntry': info['notes'],
    }
    # Existing thumbnail is preserved, as in the launcher's update path.
    quote = urllib.parse.quote
    print('Paradox: uploading the mod archive.', flush=True)
    request('PUT', f'/mods/content/ck3/{quote(remote_name, safe="")}/content/{filename}',
            auth=auth, data=archive.read_bytes(), binary=True)
    result = request('POST', '/mods/publishUpdate', auth=auth, data=payload)
    if result.get('modId') is not None and str(result['modId']) != str(PARADOX_ID):
        raise RuntimeError('Unexpected Paradox publication response; check the item before retrying')
    print('Paradox: update accepted; waiting for processing.', flush=True)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        after = metadata(auth)
        if (not after.get('updating') and after.get('state') == 'published'
                and after.get('latestUpdate') != before.get('latestUpdate')
                and notes_published(after, info['notes'])):
            print(f'Paradox: publication confirmed. https://mods.paradoxplaza.com/mods/{PARADOX_ID}/Any')
            return
        time.sleep(5)
    raise RuntimeError('Paradox processing timed out; check the item before retrying')
