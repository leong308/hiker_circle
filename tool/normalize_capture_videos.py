"""Normalize reviewed device recordings, preserving every original first.

Android screenrecord may omit an unchanged final screen. A recording more than
0.4 seconds short is extended by holding its final actual frame. No transition,
interaction or hardware event is generated. Longer footage is never trimmed.

The default batch is the 15 reviewed website recordings from 16 November 2026.
Future device captures call normalize_video directly with their requested time.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone, timedelta
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "web" / "internal-showcase" / "media"
CAPTURE_ROOT = ROOT / "tmp" / "website-capture-20261116"
REQUESTED_SECONDS = {
    "enhanced-preview.mp4": 12,
    "route-preview.mp4": 25,
    "trail-forecast.mp4": 20,
    "achievements.mp4": 18,
    "hike-analysis.mp4": 20,
    "create-hike.mp4": 26,
    "physical-button-scan.mp4": 15,
    "active-tracking.mp4": 20,
    "team-tools.mp4": 18,
    "required-gear.mp4": 22,
    "duress-demo.mp4": 12,
    "community.mp4": 16,
    "physical-button.mp4": 25,
    "preparation-review.mp4": 20,
    "button-test-logs.mp4": 20,
}


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def probe(path):
    result = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_entries",
        "format=duration:stream=codec_type,codec_name,pix_fmt,r_frame_rate,width,height",
        "-of", "json", str(path),
    ], text=True))
    video = next(stream for stream in result["streams"] if stream["codec_type"] == "video")
    return {
        "durationSeconds": float(result["format"]["duration"]),
        "codec": video["codec_name"], "pixelFormat": video["pix_fmt"],
        "frameRate": video["r_frame_rate"],
        "width": video["width"], "height": video["height"],
        "audioStreams": sum(stream["codec_type"] == "audio" for stream in result["streams"]),
    }


def preserve_original(source, raw_directory):
    source = Path(source).resolve(strict=True)
    raw_directory = Path(raw_directory).resolve()
    raw_directory.mkdir(parents=True, exist_ok=True)
    digest = sha256(source)
    archive = raw_directory / source.name
    if archive.exists() and sha256(archive) != digest:
        archive = raw_directory / f"{source.stem}--{digest[:12]}{source.suffix}"
    if not archive.exists():
        shutil.copy2(source, archive)
    if sha256(archive) != digest:
        raise RuntimeError(f"Original archive checksum mismatch: {source.name}")
    return archive, digest


def normalize_video(source, requested_seconds, raw_directory=None):
    """Archive a capture and make a silent 24fps H.264 web copy atomically."""
    source = Path(source).resolve(strict=True)
    if source.suffix.lower() != ".mp4" or requested_seconds <= 0:
        raise ValueError("An MP4 and a positive requested duration are required")
    if raw_directory is None:
        date = datetime.now(timezone(timedelta(hours=8))).strftime("%Y%m%d")
        raw_directory = ROOT / "tmp" / f"website-capture-{date}" / "raw"
    before = probe(source)
    archive, original_hash = preserve_original(source, raw_directory)
    shortfall = float(requested_seconds) - before["durationSeconds"]
    held_seconds = shortfall if shortfall > 0.4 else 0.0
    filters = ["fps=24"]
    if held_seconds:
        filters.append(f"tpad=stop_mode=clone:stop_duration={held_seconds:.6f}")
    temporary = source.with_name(f".{source.stem}.normalizing-{uuid.uuid4().hex}.mp4")
    command = [
        "ffmpeg", "-v", "error", "-nostdin", "-y", "-i", str(archive),
        "-map", "0:v:0", "-vf", ",".join(filters), "-an",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", "24",
        "-crf", "20", "-preset", "veryfast", "-threads", "4",
        "-movflags", "+faststart",
    ]
    if held_seconds:
        command.extend(["-t", str(requested_seconds)])
    command.append(str(temporary))
    try:
        subprocess.run(command, check=True)
        after = probe(temporary)
        if (after["codec"] != "h264" or after["pixelFormat"] != "yuv420p"
                or after["frameRate"] != "24/1" or after["audioStreams"] != 0):
            raise RuntimeError(f"Unexpected normalized video format: {source.name}")
        if (after["width"], after["height"]) != (before["width"], before["height"]):
            raise RuntimeError(f"Capture dimensions changed: {source.name}")
        expected = float(requested_seconds) if held_seconds else before["durationSeconds"]
        if abs(after["durationSeconds"] - expected) > 0.1:
            raise RuntimeError(f"Unexpected normalized duration: {source.name}")
        # The source is preserved above; replace only this reviewed output file.
        temporary.replace(source)
    finally:
        if temporary.is_file():
            temporary.unlink()
    return {
        "file": source.name, "requestedSeconds": requested_seconds,
        "before": before, "after": after,
        "heldFinalFrameSeconds": round(held_seconds, 6),
        "original": str(archive), "originalSha256": original_hash,
        "outputSha256": sha256(source),
        "treatment": "Held the final actual frame" if held_seconds else "Preserved full footage; no tail added",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--media-directory", type=Path, default=MEDIA)
    parser.add_argument("--raw-directory", type=Path, default=CAPTURE_ROOT / "raw")
    parser.add_argument("--report", type=Path, default=CAPTURE_ROOT / "video-duration-report.json")
    parser.add_argument("--workers", type=int, choices=[1, 2, 3, 4], default=2)
    args = parser.parse_args()
    # This batch intentionally touches only the explicit reviewed filename list.
    missing = [name for name in REQUESTED_SECONDS if not (args.media_directory / name).is_file()]
    if missing:
        parser.error("Missing reviewed captures: " + ", ".join(missing))
    records, errors = {}, []
    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        jobs = {
            executor.submit(normalize_video, args.media_directory / name, seconds, args.raw_directory): name
            for name, seconds in REQUESTED_SECONDS.items()
        }
        for job in as_completed(jobs):
            name = jobs[job]
            try:
                record = job.result()
                records[name] = record
                print(json.dumps({
                    "file": name, "before": record["before"]["durationSeconds"],
                    "after": record["after"]["durationSeconds"],
                    "heldSeconds": record["heldFinalFrameSeconds"],
                }), flush=True)
            except Exception as error:
                errors.append({"file": name, "error": str(error)})
                print(json.dumps(errors[-1]), flush=True)
    report = {"videos": [records[name] for name in REQUESTED_SECONDS if name in records], "errors": errors}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"report": str(args.report.resolve()), "normalized": len(records), "errors": len(errors)}), flush=True)
    if errors:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
