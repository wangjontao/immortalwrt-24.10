#!/usr/bin/env python3
"""Find the manifest emitted by OpenWrt, including per-profile manifests."""
from pathlib import Path
import argparse


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("device", nargs="?")
    args = parser.parse_args()

    candidates = sorted(
        path
        for path in args.root.rglob("*.manifest")
        if path.is_file() and path.stat().st_size > 0
    )
    if not candidates:
        raise SystemExit("No non-empty firmware manifest found")

    device = args.device or ""
    exact = [path for path in candidates if path.name == f"{device}.manifest"]
    related = [path for path in candidates if device and device in path.name]
    selected = exact or related or candidates
    print(selected[0])


if __name__ == "__main__":
    main()
