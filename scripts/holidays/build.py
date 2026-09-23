#!/usr/bin/env python3
"""Validate holiday-cn and prepare a minimal, all-or-nothing publication plan."""

import argparse
import hashlib
import json
import re
from datetime import date, datetime, timezone
from pathlib import Path


SOURCE = "NateScarlet/holiday-cn"
YEAR_FILE = re.compile(r"(20\d{2})\.json\Z")
DATE = re.compile(r"\d{4}-\d{2}-\d{2}\Z")


def fail(message):
    raise ValueError(message)


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def json_bytes(data):
    return (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def validate_source(path, year):
    data = read_json(path)
    if not isinstance(data, dict) or type(data.get("year")) is not int or data["year"] != year:
        fail(f"{path}: year does not match filename")
    if not isinstance(data.get("papers"), list) or not all(isinstance(x, str) for x in data["papers"]):
        fail(f"{path}: invalid papers")
    if not isinstance(data.get("days"), list):
        fail(f"{path}: invalid days")
    seen = set()
    days = []
    for row in data["days"]:
        if not isinstance(row, dict) or not isinstance(row.get("name"), str) or type(row.get("isOffDay")) is not bool:
            fail(f"{path}: invalid day entry: {row!r}")
        stamp = row.get("date")
        if not isinstance(stamp, str) or not DATE.fullmatch(stamp):
            fail(f"{path}: invalid date format: {stamp!r}")
        try:
            parsed = date.fromisoformat(stamp)
        except ValueError as exc:
            fail(f"{path}: invalid date {stamp}: {exc}")
        if not year - 1 <= parsed.year <= year + 1:
            fail(f"{path}: date out of range: {stamp}")
        if stamp in seen:
            fail(f"{path}: duplicate date: {stamp}")
        seen.add(stamp)
        days.append({"date": stamp, "name": row["name"], "type": "off" if row["isOffDay"] else "work"})
    return {"papers": data["papers"], "days": sorted(days, key=lambda x: x["date"])}


def plan(source_dir, previous_dir, output_dir, commit, now):
    years = {}
    cross_year = {}
    files = sorted(p for p in source_dir.iterdir() if YEAR_FILE.fullmatch(p.name) and int(p.stem) >= 2007)
    if not files or int(files[0].stem) != 2007:
        fail("source missing 2007.json")
    present = {int(p.stem) for p in files}
    if present != set(range(2007, max(present) + 1)):
        fail(f"source has missing years: {sorted(set(range(2007, max(present) + 1)) - present)}")
    for path in files:
        year = int(path.stem)
        value = validate_source(path, year)
        for day in value["days"]:
            prior = cross_year.get(day["date"])
            if prior and prior[1] != day["type"]:
                fail(f"cross-year type conflict on {day['date']}: {prior[0]}={prior[1]}, {year}={day['type']}")
            cross_year[day["date"]] = (year, day["type"])
        years[str(year)] = value

    old_index_path = previous_dir / "index.json"
    old_index = read_json(old_index_path) if old_index_path.exists() else None
    if old_index is not None and (old_index.get("schemaVersion") != 1 or old_index.get("source") != SOURCE or not isinstance(old_index.get("years"), dict)):
        fail("previous index has an unexpected format")
    old_years = old_index["years"] if old_index else {}
    vanished = set(old_years) - set(years)
    if vanished:
        fail(f"previously published years disappeared: {sorted(vanished)}")
    output_dir.mkdir(parents=True, exist_ok=True)
    changes = []
    entries = {}
    for year, value in years.items():
        filename = f"{year}.json"
        old_path = previous_dir / filename
        old_meta = old_years.get(year)
        old = read_json(old_path) if old_path.exists() else None
        if bool(old_meta) != bool(old):
            fail(f"previous index/file mismatch: {filename}")
        if old is not None:
            raw = old_path.read_bytes()
            if sha256(raw) != old_meta.get("sha256") or old_meta.get("url") != filename:
                fail(f"previous file hash/url mismatch: {filename}")
        same = old is not None and old.get("papers") == value["papers"] and old.get("days") == value["days"]
        if old is not None:
            old_off = sum(day.get("type") == "off" for day in old.get("days", []))
            new_off = sum(day["type"] == "off" for day in value["days"])
            if old_off - new_off > 3:
                fail(f"{year}: off days fell from {old_off} to {new_off}; manual review required")
        if same:
            raw = old_path.read_bytes()
            updated_at = old_meta["updatedAt"]
        else:
            raw = json_bytes({"schemaVersion": 1, "year": int(year),
                              "source": {"repo": SOURCE, "commit": commit, "fetchedAt": now},
                              **value})
            (output_dir / filename).write_bytes(raw)
            changes.append(filename)
            updated_at = now
        (output_dir / filename).write_bytes(raw)
        entries[year] = {"url": filename, "sha256": sha256(raw), "updatedAt": updated_at}
    if changes:
        (output_dir / "index.json").write_bytes(json_bytes({"schemaVersion": 1, "source": SOURCE,
                                                               "generatedAt": now, "years": entries}))
    elif old_index_path.exists():
        (output_dir / "index.json").write_bytes(old_index_path.read_bytes())
    (output_dir / "manifest.json").write_bytes(json_bytes({"changed": changes, "indexChanged": bool(changes)}))
    return changes


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--previous", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--commit", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.commit):
        fail("invalid source commit SHA")
    changed = plan(args.source, args.previous, args.output, args.commit,
                   datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"))
    print(f"Validated {len(list(args.source.glob('[0-9][0-9][0-9][0-9].json')))} source years; changed: {changed}")
