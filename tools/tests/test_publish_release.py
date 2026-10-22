"""Offline checks: packaging boundaries and remote publication confirmation."""
import contextlib
import ctypes as C
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import publish_release as release
from publish_paradox import notes_published


class PackagingTests(unittest.TestCase):
    def test_stage_only_game_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / 'mod'
            with contextlib.redirect_stdout(io.StringIO()):
                release.stage_release(target)
            self.assertEqual({p.name for p in target.iterdir()},
                             {'common', 'events', 'localization', 'descriptor.mod', 'thumbnail.png'})
            self.assertEqual((target / 'descriptor.mod').read_bytes(),
                             (release.ROOT / 'descriptor.mod').read_bytes())
            self.assertTrue((target / 'localization/french/monarque_absolu_l_french.yml').read_bytes().startswith(b'\xef\xbb\xbf'))

    def test_reject_symlinks_before_copying(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in ('common', 'events', 'localization'):
                (root / name).mkdir()
            (root / 'common/secret').symlink_to('/etc/passwd')
            with patch.object(release, 'ROOT', root), patch.object(release.subprocess, 'run'):
                with self.assertRaisesRegex(RuntimeError, 'Symlink'):
                    release.stage_release(root / 'output')
            self.assertFalse((root / 'output').exists())

    def test_release_notes_match_version(self):
        info = release.release_info()
        self.assertTrue(info['notes'].startswith(info['version'] + '\n'))
        self.assertEqual(release.STEAM_ID, 3813333986)


class ConfirmationTests(unittest.TestCase):
    def test_paradox_requires_notes_on_latest_version(self):
        detail = {'latestVersion': 6, 'changelog': [{'modVersion': 5, 'details': '1.0.5\nnotes'}]}
        self.assertFalse(notes_published(detail, '1.0.5\nnotes'))
        detail['changelog'].append({'modVersion': 6, 'details': '1.0.5\nnotes\n'})
        self.assertTrue(notes_published(detail, '1.0.5\nnotes'))

    def steam_with_result(self, result):
        publisher = release.SteamPublisher.__new__(release.SteamPublisher)
        publisher.ugc = 1
        publisher.pipe = 1
        publisher.start = lambda *_: 10
        publisher.submit = lambda *_: 20
        publisher.bind = lambda *_: lambda *args: True
        publisher.frame = lambda *_: None
        completed = release.CallCompleted(20, 3404, 8)
        pending = [True]
        def callback(pipe, message_ptr):
            if not pending:
                return False
            pending.pop()
            message = C.cast(message_ptr, C.POINTER(release.CallbackMessage)).contents
            message.callback, message.data, message.size = 703, C.addressof(completed), C.sizeof(completed)
            return True
        publisher.next_callback = callback
        publisher.free_callback = lambda *_: None
        def get_result(pipe, call, output, size, kind, failed):
            C.memmove(output, result.to_bytes(4, 'little') + b'\0' * 4, 8)
            return True
        publisher.result = get_result
        return publisher

    def test_steam_rejection_is_never_reported_as_success(self):
        publisher = self.steam_with_result(15)  # k_EResultAccessDenied
        with contextlib.redirect_stdout(io.StringIO()), self.assertRaisesRegex(RuntimeError, 'EResult=15'):
            publisher.publish(Path('/tmp/staged'), {'name': 'Mod', 'notes': 'notes'}, 1)

    def test_steam_accepts_reported_callback_size(self):
        publisher = self.steam_with_result(1)
        with contextlib.redirect_stdout(io.StringIO()) as output:
            publisher.publish(Path('/tmp/staged'), {'name': 'Mod', 'notes': 'notes'}, 1)
        self.assertIn('publication confirmed', output.getvalue())


if __name__ == '__main__':
    unittest.main()
