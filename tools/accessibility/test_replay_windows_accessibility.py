import json
import pathlib
import unittest
from unittest.mock import patch

from replay_windows_accessibility import read_sessions, replay_text, session_error


class AccessibilityLogReplayTest(unittest.TestCase):
    def read(self, text):
        with patch.object(pathlib.Path, "read_text", return_value=text):
            return read_sessions(pathlib.Path("debug.log"))

    def test_persisted_log_escaping_preserves_session_ids(self):
        record = {"session": 'launch\\with"quotes', "batch": 1, "nodes": [{"id": 0, "children": []}]}
        payload = json.dumps(record).replace("\\", "\\\\")
        sessions = self.read(f"[2026-10-30T12:00:00Z][DEBUG] Windows accessibility update {payload}\n")
        self.assertEqual(sessions[record["session"]], [record])

    def test_sessions_are_kept_separate_and_require_batch_one(self):
        records = [
            {"session": "old", "batch": 1, "nodes": [{"id": 0, "children": []}]},
            {"session": "new", "batch": 2, "nodes": [{"id": 0, "children": []}]},
        ]
        sessions = self.read("\n".join("Windows accessibility update " + json.dumps(record) for record in records))
        self.assertIsNone(session_error(sessions["old"]))
        self.assertEqual(session_error(sessions["new"]), "expected batch 1, found 2")

    def test_missing_descendant_trace_preserves_the_absent_update(self):
        updates = [
            {"batch": 1, "nodes": [
                {"id": 0, "children": [1, 2]}, {"id": 1, "children": [3]},
                {"id": 3, "children": [31]}, {"id": 31, "children": []}, {"id": 2, "children": []},
            ]},
            {"batch": 2, "nodes": [
                {"id": 1, "children": []}, {"id": 2, "children": [3]}, {"id": 3, "children": [31]},
            ]},
        ]
        fixture = pathlib.Path(__file__).resolve().parents[2] / "test/fixtures/accessibility/missing_descendant.txt"
        self.assertEqual(replay_text(updates), fixture.read_text(encoding="ascii"))

    def test_empty_action_only_batches_are_preserved(self):
        self.assertEqual(replay_text([{"batch": 1, "nodes": []}]), "R\nB 0\n")

    def test_invalid_children_and_batch_gaps_are_rejected(self):
        invalid = {"session": "s", "batch": 1, "nodes": [{"id": 0, "children": [True]}]}
        with self.assertRaisesRegex(ValueError, "Invalid child IDs"):
            self.read("Windows accessibility update " + json.dumps(invalid))
        self.assertEqual(session_error([{"batch": 1}, {"batch": 3}]), "expected batch 2, found 3")


if __name__ == "__main__":
    unittest.main()
