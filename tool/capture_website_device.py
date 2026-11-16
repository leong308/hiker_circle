"""Capture original Android media for the website without credentials or audio.

Examples:
  python tool/capture_website_device.py shot trail-detail.png
  python tool/capture_website_device.py record trail-discovery.mp4 --seconds 12

Media is stored in the tracked showcase source directory. Each capture appends
its device/build provenance to capture-log.json. Review every capture before
wiring it into the catalog. Pass --demo for the isolated production-widget demo.
"""

import argparse
import json
from pathlib import Path
import subprocess
from datetime import datetime, timezone, timedelta

from normalize_capture_videos import normalize_video

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "web" / "internal-showcase" / "media"


def adb(*args, binary=False):
    return subprocess.check_output(["adb", *args], text=not binary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=["shot", "record"])
    parser.add_argument("filename")
    parser.add_argument("--seconds", type=int, default=12)
    parser.add_argument("--demo", action="store_true")
    parser.add_argument("--note", default="")
    parser.add_argument("--register-only", action="store_true", help="Log an existing, reviewed capture without replacing it")
    parser.add_argument("--output", type=Path, default=DEST)
    args = parser.parse_args()
    if Path(args.filename).name != args.filename:
        parser.error("Use a filename without directory components")
    if not 3 <= args.seconds <= 60:
        parser.error("Recordings must last 3–60 seconds")
    args.output.mkdir(parents=True, exist_ok=True)
    target = args.output / args.filename
    normalization = None
    if args.register_only:
        if not target.is_file() or target.stat().st_size == 0:
            parser.error("The existing capture must be present and nonempty")
    elif args.kind == "shot":
        if target.suffix.lower() != ".png":
            parser.error("Screenshots use PNG")
        target.write_bytes(adb("exec-out", "screencap", "-p", binary=True))
    else:
        if target.suffix.lower() != ".mp4":
            parser.error("Recordings use MP4")
        remote = "/sdcard/hikercircle-website-capture.mp4"
        subprocess.run(["adb", "shell", "rm", "-f", remote], check=True)
        print(f"Recording {args.filename} for {args.seconds}s; navigate on the device now.", flush=True)
        subprocess.run(["adb", "shell", "screenrecord", "--bit-rate", "4000000",
                        "--time-limit", str(args.seconds), remote], check=True)
        subprocess.run(["adb", "pull", remote, str(target)], check=True)
        subprocess.run(["adb", "shell", "rm", "-f", remote], check=True)
        # Android may omit a stationary tail. Preserve the untouched original,
        # hold only its actual final frame when >0.4s short, and enable fast-start.
        normalization = normalize_video(target, args.seconds)
        # The web provenance log uses a workspace-relative archive location.
        normalization["original"] = Path(normalization["original"]).relative_to(ROOT).as_posix()
    package = "com.leongziqi.hikercircle" + (".showcase" if args.demo else "")
    details = adb("shell", "dumpsys", "package", package)
    version = next((line.strip() for line in details.splitlines() if "versionName=" in line), "unknown")
    record = {
        "file": args.filename,
        "kind": "image" if args.kind == "shot" else "video",
        "capturedAt": datetime.now(timezone(timedelta(hours=8))).isoformat(),
        "device": adb("shell", "getprop", "ro.product.model").strip(),
        "package": package,
        "version": version,
        "data": "isolated production-widget demo; fictional data" if args.demo else "connected app session",
        "note": args.note,
    }
    if normalization is not None:
        record["requestedSeconds"] = args.seconds
        record["videoNormalization"] = normalization
    log_path = args.output / "capture-log.json"
    log = json.loads(log_path.read_text(encoding="utf-8")) if log_path.exists() else []
    log = [entry for entry in log if entry["file"] != args.filename]
    log.append(record)
    log_path.write_text(json.dumps(log, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"saved": str(target), "bytes": target.stat().st_size}))


if __name__ == "__main__":
    main()
