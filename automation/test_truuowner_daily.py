import unittest
from unittest.mock import patch
import truuowner_daily as m

class DailyMarketingTests(unittest.TestCase):
    def test_extracts_multiple_text_blocks(self):
        self.assertEqual(m.extract_text({"content": [
            {"type": "text", "text": "First"},
            {"type": "tool_use", "name": "not-text"},
            {"type": "text", "text": "Second"},
        ]}), "First\n\nSecond")

    def test_missing_text(self):
        self.assertEqual(m.extract_text({"content": []}), "")

    def test_prompt_contains_guardrails(self):
        prompt = m.make_prompt("2026-11-21")
        self.assertIn("do not invent", prompt.lower())
        self.assertIn("prior customers", prompt.lower())

    @patch.dict("os.environ", {}, clear=True)
    def test_missing_secret_fails_closed(self):
        with patch("sys.argv", ["truuowner_daily.py"]):
            with self.assertRaises(SystemExit) as cm:
                m.main()
        self.assertEqual(cm.exception.code, 2)

if __name__ == "__main__":
    unittest.main()
