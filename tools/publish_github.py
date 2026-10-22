"""Create and verify an annotated version tag and GitHub release using Git and gh."""
import json
import subprocess

from publish_release import ROOT

REPOSITORY = 'jrmbbch/ck3-monarque-absolu'


def command(args, *, check=True):
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True, timeout=120)
    if check and result.returncode:
        raise RuntimeError(f'{args[0]} {args[1]} failed: {result.stderr.strip()}')
    return result


def remote_refs(tag):
    output = command(['git', 'ls-remote', 'origin', 'refs/heads/main',
                      f'refs/tags/{tag}', f'refs/tags/{tag}^{{}}']).stdout
    return dict((ref, sha) for sha, ref in (line.split() for line in output.splitlines()))


def read_release(tag):
    result = command(['gh', 'api', '--hostname', 'github.com',
                      f'repos/{REPOSITORY}/releases/tags/{tag}'], check=False)
    if result.returncode:
        if '(HTTP 404)' in result.stderr:
            return None
        raise RuntimeError(f'Cannot inspect GitHub release: {result.stderr.strip()}')
    return json.loads(result.stdout)


def validate_release(release, tag, notes):
    if (release.get('tag_name') != tag or release.get('draft')
            or release.get('prerelease') or release.get('body', '').strip() != notes.strip()):
        raise RuntimeError(f'Existing GitHub release {tag} differs from this release; refusing to overwrite it')


def validate_tag(refs, tag, commit):
    # A peeled ref exists for annotated tags; lightweight tags point directly at the commit.
    remote = refs.get(f'refs/tags/{tag}^{{}}', refs.get(f'refs/tags/{tag}'))
    if remote is not None and remote != commit:
        raise RuntimeError(f'Remote tag {tag} points to another commit; refusing to move it')
    return remote


def publish(info):
    tag = 'v' + info['version']
    if command(['git', 'status', '--porcelain', '--untracked-files=normal']).stdout.strip():
        raise RuntimeError('GitHub publication requires a clean working tree; commit and push the release changes first')
    origin = command(['git', 'remote', 'get-url', 'origin']).stdout.strip()
    if origin not in (f'https://github.com/{REPOSITORY}.git', f'https://github.com/{REPOSITORY}',
                      f'git@github.com:{REPOSITORY}.git'):
        raise RuntimeError('Unexpected origin repository; refusing to publish')
    commit = command(['git', 'rev-parse', 'HEAD']).stdout.strip()
    refs = remote_refs(tag)
    remote_tag = validate_tag(refs, tag, commit)
    if refs.get('refs/heads/main') != commit:
        raise RuntimeError('HEAD must match origin/main on GitHub; push the release commit before publishing')
    local = command(['git', 'rev-parse', '--verify', f'refs/tags/{tag}^{{commit}}'], check=False)
    if local.returncode == 0 and local.stdout.strip() != commit:
        raise RuntimeError(f'Local tag {tag} points to another commit; refusing to move it')
    existing = read_release(tag)
    if existing is not None:
        if remote_tag is None:
            raise RuntimeError('GitHub release exists without the expected remote tag')
        validate_release(existing, tag, info['notes'])
        print(f'GitHub: {tag} and its notes are already published; no changes made.')
        return
    if remote_tag is None:
        if local.returncode:
            command(['git', 'tag', '-a', tag, commit, '-m', f"Release {info['version']}"])
        command(['git', 'push', 'origin', f'refs/tags/{tag}:refs/tags/{tag}'])
    # Never ask gh to create an implicit tag from the default branch.
    if validate_tag(remote_refs(tag), tag, commit) is None:
        raise RuntimeError('The pushed tag is not visible on GitHub; check before retrying')
    notes_path = ROOT / 'docs/patch_notes' / f"{info['version']}.txt"
    command(['gh', 'release', 'create', tag, '--repo', REPOSITORY, '--verify-tag',
             '--title', tag, '--notes-file', str(notes_path)])
    created = read_release(tag)
    if created is None:
        raise RuntimeError('GitHub release creation returned without a visible release; check before retrying')
    validate_release(created, tag, info['notes'])
    print(f'GitHub: publication confirmed. https://github.com/{REPOSITORY}/releases/tag/{tag}')
