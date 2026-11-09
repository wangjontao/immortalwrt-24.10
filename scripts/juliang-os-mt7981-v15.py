#!/usr/bin/env python3
import argparse
import re
import shutil
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FILOGIC = ROOT / "target/linux/mediatek/image/filogic.mk"
SINGLE_TARGET_PREFIX = "CONFIG_TARGET_mediatek_filogic_DEVICE_"
MULTI_TARGET_PREFIX = "CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_"


def load_devices():
    text = FILOGIC.read_text(encoding="utf-8")
    devices = []
    for match in re.finditer(
        r"(?ms)^define Device/([^\r\n]+)\r?\n(.*?)^endef", text
    ):
        device = match.group(1).strip()
        body = match.group(2)
        dts_match = re.search(
            r"^\s*DEVICE_DTS\s*:=\s*([^\r\n]+)", body, re.MULTILINE
        )
        if not dts_match:
            continue
        dts = dts_match.group(1).strip()
        if not dts.startswith("mt7981"):
            continue
        model_match = re.search(
            r"^\s*DEVICE_MODEL\s*:=\s*([^\r\n]+)", body, re.MULTILINE
        )
        vendor_match = re.search(
            r"^\s*DEVICE_VENDOR\s*:=\s*([^\r\n]+)", body, re.MULTILINE
        )
        model = model_match.group(1).strip() if model_match else device
        vendor = vendor_match.group(1).strip() if vendor_match else "Unknown"
        devices.append(
            {
                "device": device,
                "dts": dts,
                "label": f"{vendor} {model}".strip(),
            }
        )

    names = [entry["device"] for entry in devices]
    if len(names) != len(set(names)):
        raise ValueError("Duplicate MT7981 device in filogic.mk")
    if not devices:
        raise ValueError("No MT7981 devices found in filogic.mk")
    return sorted(devices, key=lambda entry: entry["device"])


def replace_setting(lines, key, value):
    replacement = (
        f"{key}={value}"
        if value in ("y", "m", "n")
        else f'{key}="{value}"'
    )
    kept = []
    replaced = False
    for line in lines:
        if line.startswith(f"{key}="):
            if not replaced:
                kept.append(replacement)
                replaced = True
            continue
        kept.append(line)
    if not replaced:
        kept.append(replacement)
    return kept


def configure(config_path):
    devices = load_devices()
    lines = config_path.read_text(encoding="utf-8").splitlines()
    if (
        "CONFIG_TARGET_mediatek=y" not in lines
        or "CONFIG_TARGET_mediatek_filogic=y" not in lines
    ):
        raise ValueError("MT7981 build requires the MediaTek Filogic target")

    def removable_target(line):
        return (
            line.startswith(SINGLE_TARGET_PREFIX)
            or line.startswith(MULTI_TARGET_PREFIX)
            or line.startswith("CONFIG_TARGET_ALL_PROFILES")
        )

    def removable_bootloader(line):
        if not line.startswith("CONFIG_PACKAGE_"):
            return False
        return any(
            marker in line
            for marker in (
                "u-boot-mt7981",
                "trusted-firmware-a-mt7981",
                "bl-mt7981",
            )
        )

    lines = [
        line
        for line in lines
        if not removable_target(line) and not removable_bootloader(line)
    ]
    lines = replace_setting(lines, "CONFIG_TARGET_MULTI_PROFILE", "y")
    lines = replace_setting(lines, "CONFIG_TARGET_PER_DEVICE_ROOTFS", "y")
    lines = replace_setting(lines, "CONFIG_TARGET_IMAGES_GZIP", "n")
    lines = replace_setting(lines, "CONFIG_IMAGEOPT", "y")
    lines = replace_setting(lines, "CONFIG_VERSIONOPT", "y")
    lines = replace_setting(lines, "CONFIG_VERSION_DIST", "JuLiang OS")
    lines = replace_setting(lines, "CONFIG_VERSION_MANUFACTURER", "JuLiang OS")
    lines = replace_setting(lines, "CONFIG_VERSION_PRODUCT", "JuLiang OS")
    lines = replace_setting(lines, "CONFIG_VERSION_NUMBER", "v1.5")
    lines = replace_setting(lines, "CONFIG_VERSION_HWREV", "MT7981")
    lines = replace_setting(lines, "CONFIG_VERSION_CODE", "MT7981-ALL-FINAL")
    lines.append("")
    lines.append("# CONFIG_TARGET_ALL_PROFILES is not set")
    lines.append("# JuLiang OS v1.5 MT7981 full target set")
    lines.extend(
        f"{MULTI_TARGET_PREFIX}{entry['device']}=y" for entry in devices
    )
    config_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Configured {len(devices)} MT7981 devices")


def verify_config(config_path):
    devices = load_devices()
    expected = {entry["device"] for entry in devices}
    selected = set()
    settings = {}
    for line in config_path.read_text(encoding="utf-8").splitlines():
        if line.startswith(MULTI_TARGET_PREFIX) and line.endswith("=y"):
            selected.add(line[len(MULTI_TARGET_PREFIX) : -2])
        if line.startswith("CONFIG_") and "=" in line:
            key, _, value = line.partition("=")
            settings[key] = value.strip('"')

    missing = sorted(expected - selected)
    unexpected = sorted(selected - expected)
    if missing or unexpected:
        raise ValueError(
            f"MT7981 target mismatch: missing={missing or 'none'}, "
            f"unexpected={unexpected or 'none'}"
        )
    expected_settings = {
        "CONFIG_TARGET_MULTI_PROFILE": "y",
        "CONFIG_TARGET_PER_DEVICE_ROOTFS": "y",
        "CONFIG_TARGET_IMAGES_GZIP": "n",
        "CONFIG_IMAGEOPT": "y",
        "CONFIG_VERSIONOPT": "y",
        "CONFIG_VERSION_NUMBER": "v1.5",
        "CONFIG_VERSION_HWREV": "MT7981",
        "CONFIG_VERSION_CODE": "MT7981-ALL-FINAL",
    }
    for key, value in expected_settings.items():
        if settings.get(key) != value:
            raise ValueError(f"{key} must be {value}")
    if settings.get("CONFIG_TARGET_ALL_PROFILES") == "y":
        raise ValueError("CONFIG_TARGET_ALL_PROFILES must be disabled")
    print(f"Verified {len(expected)} MT7981 targets in {config_path}")


def collect(source, destination):
    devices = load_devices()
    destination.mkdir(parents=True, exist_ok=True)
    inventory = []
    copied = set()
    for entry in devices:
        device = entry["device"]
        patterns = (
            f"*-{device}-squashfs-sysupgrade.bin",
            f"*-{device}-squashfs-factory.bin",
            f"*-{device}-sysupgrade.itb",
        )
        images = []
        for pattern in patterns:
            images.extend(sorted(source.glob(pattern)))
        if not images:
            raise FileNotFoundError(f"No image found for {device}")
        for image in images:
            if image not in copied:
                shutil.copy2(image, destination / image.name)
                copied.add(image)
        for manifest in source.glob(f"*{device}*.manifest"):
            shutil.copy2(manifest, destination / manifest.name)
        inventory.append(
            f"{device}\t{entry['label']}\t"
            + ",".join(image.name for image in images)
        )

    for name in (
        "profiles.json",
        "config.buildinfo",
        "feeds.buildinfo",
        "version.buildinfo",
    ):
        path = source / name
        if path.is_file():
            shutil.copy2(path, destination / name)
    (destination / "INVENTORY.txt").write_text(
        "device\tlabel\timages\n" + "\n".join(inventory) + "\n",
        encoding="utf-8",
    )
    print(f"Collected images for {len(devices)} MT7981 devices")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "command", choices=("list", "configure", "verify-config", "collect")
    )
    parser.add_argument("path", type=Path, nargs="?")
    parser.add_argument("destination", type=Path, nargs="?")
    args = parser.parse_args()

    try:
        if args.command == "list":
            for entry in load_devices():
                print(f"{entry['device']}\t{entry['label']}")
        elif args.command == "configure":
            configure(args.path)
        elif args.command == "verify-config":
            verify_config(args.path)
        else:
            if args.path is None or args.destination is None:
                parser.error("collect requires source and destination")
            collect(args.path, args.destination)
    except (FileNotFoundError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
