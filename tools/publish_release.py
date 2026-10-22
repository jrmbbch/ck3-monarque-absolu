#!/usr/bin/env python3
"""Publish Monarque Absolu to GitHub, Steam Workshop and Paradox Mods with release notes.

No arguments publishes nothing. See --help and docs/publishing.md.
"""
import argparse
import ctypes as C
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
APP_ID = 1158310
STEAM_ID = 3813333986
PARADOX_ID = 161949
GAME = Path.home() / 'Library/Application Support/Steam/steamapps/common/Crusader Kings III'


def release_info():
    source = (ROOT / 'descriptor.mod').read_text(encoding='utf-8-sig')
    def field(name):
        match = re.search(rf'^{name}="([^"\n]+)"$', source, re.M)
        if not match:
            raise RuntimeError(f'Missing descriptor field: {name}')
        return match.group(1)
    version = field('version')
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise RuntimeError('Invalid release version')
    if int(field('remote_file_id')) != STEAM_ID:
        raise RuntimeError('Unexpected Steam item ID; refusing to publish')
    notes = (ROOT / 'docs/patch_notes' / f'{version}.txt').read_text().strip()
    if not notes.startswith(version + '\n'):
        raise RuntimeError('Release notes do not match descriptor version')
    return dict(version=version, name=field('name'), required=field('supported_version'),
                notes=notes, tags=re.findall(r'"([^"]+)"', re.search(r'tags=\{(.*?)\}', source, re.S)[1]))


def stage_release(destination):
    """Allowlist only game files; never upload the repository or authentication data."""
    subprocess.run([sys.executable, str(ROOT / 'tools/check_localization.py')], check=True)
    for name in ('common', 'events', 'localization'):
        if (ROOT / name).is_symlink() or any(p.is_symlink() for p in (ROOT / name).rglob('*')):
            raise RuntimeError(f'Symlink in release sources: {name}')
    for name in ('descriptor.mod', 'thumbnail.png'):
        if (ROOT / name).is_symlink():
            raise RuntimeError(f'Symlink in release sources: {name}')
    destination.mkdir()
    for name in ('common', 'events', 'localization'):
        shutil.copytree(ROOT / name, destination / name,
                        ignore=shutil.ignore_patterns('.DS_Store', '__pycache__'))
    for name in ('descriptor.mod', 'thumbnail.png'):
        shutil.copy2(ROOT / name, destination / name)
    for path in destination.rglob('*'):
        if path.is_symlink():
            raise RuntimeError(f'Symlink in release: {path.relative_to(destination)}')


class CallbackMessage(C.Structure):
    _fields_ = [('user', C.c_int), ('callback', C.c_int),
                ('data', C.c_void_p), ('size', C.c_int)]


class CallCompleted(C.Structure):
    _fields_ = [('handle', C.c_uint64), ('callback', C.c_int), ('size', C.c_uint32)]


class SteamPublisher:
    """Flat Steamworks API provided by the installed game; no password handling."""
    def __init__(self, library):
        os.environ['SteamAppId'] = str(APP_ID)
        os.environ['SteamGameId'] = str(APP_ID)
        self.lib = C.CDLL(str(library))
        self.bind('SteamAPI_Init', C.c_bool, [])
        self.bind('SteamAPI_Shutdown', None, [])
        if not self.lib.SteamAPI_Init():
            raise RuntimeError('Steam initialization failed. Open Steam and sign in to the owner account.')
        try:
            self.ugc = self.bind('SteamAPI_SteamUGC_v016', C.c_void_p, [])()
            if not self.ugc:
                raise RuntimeError('Required Steamworks interface unavailable')
            self.start = self.bind('SteamAPI_ISteamUGC_StartItemUpdate', C.c_uint64,
                                   [C.c_void_p, C.c_uint32, C.c_uint64])
            self.submit = self.bind('SteamAPI_ISteamUGC_SubmitItemUpdate', C.c_uint64,
                                    [C.c_void_p, C.c_uint64, C.c_char_p])
            self.bind('SteamAPI_ManualDispatch_Init', None, [])()
            self.pipe = self.bind('SteamAPI_GetHSteamPipe', C.c_int, [])()
            self.frame = self.bind('SteamAPI_ManualDispatch_RunFrame', None, [C.c_int])
            self.next_callback = self.bind('SteamAPI_ManualDispatch_GetNextCallback', C.c_bool,
                                           [C.c_int, C.POINTER(CallbackMessage)])
            self.free_callback = self.bind('SteamAPI_ManualDispatch_FreeLastCallback', None, [C.c_int])
            self.result = self.bind('SteamAPI_ManualDispatch_GetAPICallResult', C.c_bool,
                                    [C.c_int, C.c_uint64, C.c_void_p, C.c_int, C.c_int, C.POINTER(C.c_bool)])
        except Exception:
            self.close()
            raise

    def bind(self, name, result, args):
        fn = getattr(self.lib, name)
        fn.restype, fn.argtypes = result, args
        return fn

    def close(self):
        self.lib.SteamAPI_Shutdown()

    def publish(self, content, info, timeout):
        handle = self.start(self.ugc, APP_ID, STEAM_ID)
        if handle in (0, 2**64 - 1):
            raise RuntimeError('Steam rejected the item update handle')
        settings = {
            'Title': info['name'],
            'Description': (ROOT / 'docs/workshop_description.bbcode').read_text(),
            'Content': str(content),
            'Preview': str(content / 'thumbnail.png'),
        }
        for suffix, value in settings.items():
            fn = self.bind('SteamAPI_ISteamUGC_SetItem' + suffix, C.c_bool,
                           [C.c_void_p, C.c_uint64, C.c_char_p])
            if not fn(self.ugc, handle, value.encode()):
                raise RuntimeError(f'Steam rejected {suffix}')
        # Tags/visibility are intentionally preserved for the existing item.
        call = self.submit(self.ugc, handle, info['notes'].encode())
        if not call:
            raise RuntimeError('Steam did not start the submission')
        print('Steam: update submitted; waiting for the server result.', flush=True)
        deadline = time.monotonic() + timeout
        message = CallbackMessage()
        while time.monotonic() < deadline:
            self.frame(self.pipe)
            while self.next_callback(self.pipe, C.byref(message)):
                ready = None
                try:
                    if message.callback == 703 and message.size == C.sizeof(CallCompleted):
                        completed = CallCompleted.from_buffer_copy(C.string_at(message.data, message.size))
                        if completed.handle == call:
                            ready = completed
                finally:
                    self.free_callback(self.pipe)
                if ready is None:
                    continue
                if ready.callback != 3404 or ready.size < 5:
                    raise RuntimeError('Unexpected Steam submission callback')
                # Use the size reported by this SDK, rather than assume a callback ABI version.
                output = C.create_string_buffer(ready.size)
                failed = C.c_bool()
                if not self.result(self.pipe, call, output, ready.size, 3404, C.byref(failed)) or failed.value:
                    raise RuntimeError('Steam callback failed; check the item before retrying')
                result = int.from_bytes(output.raw[:4], 'little', signed=True)
                if result != 1:
                    raise RuntimeError(f'Steam rejected publication (EResult={result})')
                if output.raw[4]:
                    raise RuntimeError('Uploaded, but Steam requires the owner to accept the Workshop agreement on the item page')
                print(f'Steam: publication confirmed. https://steamcommunity.com/sharedfiles/filedetails/?id={STEAM_ID}')
                return
            time.sleep(0.25)
        raise RuntimeError('Steam submission timed out; status unknown. Check the item before retrying.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('platform', choices=['github', 'steam', 'paradox', 'all'])
    parser.add_argument('--publish', action='store_true', help='Actually upload; otherwise stage and validate only')
    parser.add_argument('--steam-library', type=Path, default=GAME / 'binaries/ck3.app/Contents/Frameworks/libsteam_api.dylib')
    parser.add_argument('--timeout', type=int, default=300)
    args = parser.parse_args()
    info = release_info()
    print(f"Version {info['version']}; platforms: {args.platform}; upload: {args.publish}")
    with tempfile.TemporaryDirectory(prefix='mqa-publish-') as temporary:
        content = Path(temporary) / 'monarque_absolu'
        stage_release(content)
        print(f"Validated {sum(p.is_file() for p in content.rglob('*'))} game files; notes: {info['notes']}")
        if args.platform in ('github', 'all'):
            print(f"GitHub: tag v{info['version']} and release with matching notes; publication requires a clean, pushed commit.")
        if not args.publish:
            print('Dry run complete; no authentication or network requests performed.')
            return
        if args.platform in ('github', 'all'):
            from publish_github import publish as publish_github
            publish_github(info)
        if args.platform in ('steam', 'all'):
            publisher = SteamPublisher(args.steam_library)
            try:
                publisher.publish(content, info, args.timeout)
            finally:
                publisher.close()
        if args.platform in ('paradox', 'all'):
            from publish_paradox import publish
            publish(content, info, args.timeout)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        sys.exit(f'Publication stopped: {error}')
