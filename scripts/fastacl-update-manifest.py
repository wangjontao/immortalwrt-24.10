#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path


IMAGE_SUFFIXES = ('.bin', '.itb', '.img.gz')


def find_image(artifacts: Path, device: str) -> Path | None:
    candidates = []
    patterns = [f'*{device}*sysupgrade*']
    if device == 'generic':
        patterns.append('*x86*generic*combined-efi.img.gz')
        patterns.append('*x86*generic*combined.img.gz')
    for pattern in patterns:
        for path in artifacts.rglob(pattern):
            lower = path.name.lower()
            if path.is_file() and lower.endswith(IMAGE_SUFFIXES):
                candidates.append(path)
    if not candidates:
        return None
    if device == 'generic':
        return sorted(
            candidates,
            key=lambda path: (
                0 if 'combined-efi.img.gz' in path.name.lower() else 1,
                len(path.name),
                path.name,
            ),
        )[0]
    return sorted(candidates, key=lambda p: (len(p.name), p.name))[0]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description='Generate and sign a FastACL update manifest.')
    parser.add_argument('--artifacts', required=True, type=Path)
    parser.add_argument('--models', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--version', required=True)
    parser.add_argument('--channel', required=True, choices=('stable', 'beta'))
    parser.add_argument('--base-url', default='https://up.juliangtk.top')
    parser.add_argument('--notes-url', default='')
    parser.add_argument('--source-runs', default='')
    parser.add_argument('--require-all', action='store_true')
    parser.add_argument('--usign', type=Path)
    parser.add_argument('--signing-key', type=Path)
    args = parser.parse_args()

    models = json.loads(args.models.read_text(encoding='utf-8'))
    if not isinstance(models, list) or not models:
        raise SystemExit('Model mapping must be a non-empty list.')

    entries = []
    seen_boards = set()
    missing = []
    for model in models:
        device = model['device']
        board = model['board']
        if board in seen_boards:
            raise SystemExit(f'Duplicate board mapping: {board}')
        seen_boards.add(board)
        image = find_image(args.artifacts, device)
        if image is None:
            missing.append(device)
            continue
        relative = f'releases/{args.version}/{image.name}'
        entries.append({
            'board': board,
            'label': model.get('label', device),
            'image': relative,
            'sha256': sha256(image),
            'size': image.stat().st_size,
            'keep_config': True,
            'upgrade_method': 'sysupgrade',
        })

    if not entries:
        raise SystemExit('No matching sysupgrade images were found.')
    if args.require_all and missing:
        raise SystemExit(f'Missing sysupgrade images: {", ".join(missing)}')

    manifest = {
        'schema': 1,
        'channel': args.channel,
        'version': args.version,
        'published_at': datetime.now(timezone.utc).isoformat(),
        'base_url': args.base_url.rstrip('/'),
        'notes_url': args.notes_url,
        'source_runs': [item for item in args.source_runs.split(',') if item],
        'models': sorted(entries, key=lambda item: item['board']),
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + '\n'
    fd, temporary = tempfile.mkstemp(prefix='manifest.', suffix='.json', dir=args.output.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as handle:
            handle.write(payload)
        os.replace(temporary, args.output)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)

    if bool(args.usign) != bool(args.signing_key):
        raise SystemExit('--usign and --signing-key must be supplied together.')
    if args.usign and args.signing_key:
        subprocess.run([
            str(args.usign),
            '-S',
            '-m', str(args.output),
            '-s', str(args.signing_key),
            '-x', f'{args.output}.sig',
        ], check=True)

    print(f'Generated {args.output} with {len(entries)} model entries.')


if __name__ == '__main__':
    main()
