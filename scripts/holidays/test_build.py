import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


spec = importlib.util.spec_from_file_location("holiday_build", Path(__file__).with_name("build.py"))
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


def source(root, year, days):
    (root / f"{year}.json").write_text(json.dumps({"year": year, "papers": [], "days": days}))


def day(stamp, off=True):
    return {"date": stamp, "name": "测试", "isOffDay": off}


class HolidayBuildTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.src = self.root / "source"
        self.old = self.root / "old"
        self.new = self.root / "new"
        self.src.mkdir()
        self.old.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def run_plan(self):
        return build.plan(self.src, self.old, self.new, "a" * 40, "2026-09-23T02:00:00Z")

    def test_noop_retains_exact_bytes_and_timestamps(self):
        source(self.src, 2007, [day("2006-12-31"), day("2007-01-01", False)])
        self.assertEqual(self.run_plan(), ["2007.json"])
        for file in self.new.glob("*.json"):
            (self.old / file.name).write_bytes(file.read_bytes())
        before = (self.old / "index.json").read_bytes()
        self.assertEqual(self.run_plan(), [])
        self.assertEqual((self.new / "index.json").read_bytes(), before)

    def test_cross_year_conflict_rejects_everything(self):
        source(self.src, 2007, [day("2008-01-01", True)])
        source(self.src, 2008, [day("2008-01-01", False)])
        with self.assertRaisesRegex(ValueError, "cross-year type conflict"):
            self.run_plan()
        self.assertFalse((self.new / "index.json").exists())

    def test_invalid_and_duplicate_dates(self):
        source(self.src, 2007, [day("2007-02-29")])
        with self.assertRaisesRegex(ValueError, "invalid date"):
            self.run_plan()
        source(self.src, 2007, [day("2007-01-01"), day("2007-01-01")])
        with self.assertRaisesRegex(ValueError, "duplicate date"):
            self.run_plan()

    def test_large_drop_in_off_days_blocks_publish(self):
        source(self.src, 2007, [day(f"2007-01-{n:02d}") for n in range(1, 6)])
        self.run_plan()
        for file in self.new.glob("*.json"):
            (self.old / file.name).write_bytes(file.read_bytes())
        source(self.src, 2007, [day("2007-01-01")])
        with self.assertRaisesRegex(ValueError, "manual review required"):
            self.run_plan()


if __name__ == "__main__":
    unittest.main()
