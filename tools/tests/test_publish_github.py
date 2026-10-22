"""Offline publication tests: reject conflicting state and resume partial releases."""
import contextlib
import io
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import publish_github as github
import publish_release as release


class GitHubTests(unittest.TestCase):
    def setUp(self):
        self.info = {'version': '1.2.3', 'notes': '1.2.3\nRelease notes'}
        self.commit = 'a' * 40
        self.refs = {'refs/heads/main': self.commit}
        self.existing = {'tag_name': 'v1.2.3', 'body': self.info['notes'],
                         'draft': False, 'prerelease': False}
        self.commands = []
        self.dirty = False
        self.local = False

    def command(self, args, **kwargs):
        self.commands.append(args)
        value, code = '', 0
        if args[:3] == ['git', 'status', '--porcelain']:
            value = ' M descriptor.mod' if self.dirty else ''
        elif args[:3] == ['git', 'remote', 'get-url']:
            value = f'https://github.com/{github.REPOSITORY}.git'
        elif args == ['git', 'rev-parse', 'HEAD']:
            value = self.commit
        elif args[:3] == ['git', 'rev-parse', '--verify']:
            value, code = (self.commit, 0) if self.local else ('', 128)
        return subprocess.CompletedProcess(args, code, stdout=value, stderr='')

    def execute(self, refs, releases):
        with patch.object(github, 'command', side_effect=self.command), \
                patch.object(github, 'remote_refs', side_effect=refs), \
                patch.object(github, 'read_release', side_effect=releases), \
                contextlib.redirect_stdout(io.StringIO()):
            github.publish(self.info)

    def test_new_tag_is_annotated_and_release_uses_notes_file(self):
        tagged = dict(self.refs, **{'refs/tags/v1.2.3^{}': self.commit})
        self.execute([self.refs, tagged], [None, self.existing])
        self.assertIn(['git', 'tag', '-a', 'v1.2.3', self.commit, '-m', 'Release 1.2.3'], self.commands)
        self.assertIn(['git', 'push', 'origin', 'refs/tags/v1.2.3:refs/tags/v1.2.3'], self.commands)
        creation = next(cmd for cmd in self.commands if cmd[:3] == ['gh', 'release', 'create'])
        self.assertIn('--verify-tag', creation)
        self.assertEqual(creation[-2:], ['--notes-file', str(release.ROOT / 'docs/patch_notes/1.2.3.txt')])

    def test_matching_release_does_not_mutate_anything(self):
        tagged = dict(self.refs, **{'refs/tags/v1.2.3': self.commit})
        self.execute([tagged], [self.existing])
        self.assertFalse(any(cmd[:2] in (['git', 'tag'], ['git', 'push'], ['gh', 'release']) for cmd in self.commands))

    def test_existing_tag_resumes_release_creation_without_push(self):
        tagged = dict(self.refs, **{'refs/tags/v1.2.3^{}': self.commit})
        self.execute([tagged, tagged], [None, self.existing])
        self.assertFalse(any(cmd[:2] == ['git', 'push'] for cmd in self.commands))
        self.assertTrue(any(cmd[:3] == ['gh', 'release', 'create'] for cmd in self.commands))

    def test_conflicting_tag_is_never_moved(self):
        tagged = dict(self.refs, **{'refs/tags/v1.2.3^{}': 'b' * 40})
        with self.assertRaisesRegex(RuntimeError, 'refusing to move'):
            self.execute([tagged], [])
        self.assertFalse(any(cmd[:2] == ['git', 'push'] for cmd in self.commands))

    def test_dirty_worktree_stops_before_network(self):
        self.dirty = True
        with self.assertRaisesRegex(RuntimeError, 'clean working tree'):
            self.execute([], [])

    def test_unpushed_commit_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'push the release commit'):
            self.execute([{'refs/heads/main': 'b' * 40}], [])

    def test_existing_notes_are_never_overwritten(self):
        tagged = dict(self.refs, **{'refs/tags/v1.2.3': self.commit})
        with self.assertRaisesRegex(RuntimeError, 'refusing to overwrite'):
            self.execute([tagged], [dict(self.existing, body='different notes')])

    def test_authentication_error_is_not_treated_as_missing_release(self):
        response = subprocess.CompletedProcess([], 1, stdout='', stderr='HTTP 401 unauthorized')
        with patch.object(github, 'command', return_value=response):
            with self.assertRaisesRegex(RuntimeError, 'Cannot inspect'):
                github.read_release('v1.2.3')

    def test_github_failure_prevents_steam_and_paradox_calls(self):
        with patch.object(release, 'stage_release'), \
                patch.object(release, 'SteamPublisher') as steam, \
                patch.object(github, 'publish', side_effect=RuntimeError('GitHub failed')), \
                patch('publish_paradox.publish') as paradox, \
                patch.object(sys, 'argv', ['publish_release.py', 'all', '--publish']), \
                contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, 'GitHub failed'):
                release.main()
            steam.assert_not_called()
            paradox.assert_not_called()

if __name__ == '__main__':
    unittest.main()
