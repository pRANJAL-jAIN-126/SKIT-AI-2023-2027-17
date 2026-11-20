"""
Tests for generate_report.py (Form-3 weekly progress report generator).

Each test builds a throwaway git repository in a temp directory, so no network access, GitHub token or the
project's own history is needed. Run from the project root:

    python -m unittest discover -s tests/python -v
"""
import datetime
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

os.environ.setdefault("MPLBACKEND", "Agg")  # headless, like the GitHub Actions runner

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, ROOT)
import generate_report  # noqa: E402


def _git(repo, *args, env=None):
    full_env = dict(os.environ)
    full_env.update(env or {})
    subprocess.check_call(["git", *args], cwd=repo, env=full_env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _commit(repo, author, days_ago, filename, lines, message):
    when = (datetime.datetime.now() - datetime.timedelta(days=days_ago)).strftime("%Y-%m-%dT12:00:00")
    with open(os.path.join(repo, filename), "a", encoding="utf-8") as f:
        f.write("".join(f"line {i}\n" for i in range(lines)))
    _git(repo, "add", filename)
    _git(
        repo,
        "-c", f"user.name={author}",
        "-c", f"user.email={author.replace(' ', '.').replace('[', '').replace(']', '')}@example.test",
        "commit", "-q", "-m", message,
        env={"GIT_AUTHOR_DATE": when, "GIT_COMMITTER_DATE": when},
    )


class GenerateReportTest(unittest.TestCase):
    def setUp(self):
        self.repo = tempfile.mkdtemp(prefix="form3-")
        _git(self.repo, "init", "-q", "-b", "main")
        self.old_cwd = os.getcwd()
        os.chdir(self.repo)

    def tearDown(self):
        os.chdir(self.old_cwd)
        shutil.rmtree(self.repo, ignore_errors=True)

    def _pdfs(self):
        return [f for f in os.listdir(self.repo) if f.endswith(".pdf")]

    # ---------------------------------------------------------------- git metrics

    def test_weekly_window_counts_recent_human_commits_only(self):
        # chronological order, like real history (git log --since stops walking at older commits)
        _commit(self.repo, "Ritvik", 20, "c.js", 3, "old work outside the window")
        _commit(self.repo, "Nitin", 2, "a.cls", 5, "fix: overdue check")
        _commit(self.repo, "Nitin", 1, "a.cls", 10, "feat: booking hold")
        _commit(self.repo, "Pranjal", 0, "b.cls", 7, "feat: OCR parser")
        _commit(self.repo, "github-actions[bot]", 0, "r.txt", 1, "docs: archive Form-3 weekly progress report")

        students, timeline, logs, scope = generate_report.get_git_metrics("weekly")

        self.assertEqual(set(students), {"Nitin", "Pranjal"})
        self.assertEqual(students["Nitin"]["commits"], 2)
        self.assertEqual(students["Nitin"]["added"], 15)
        self.assertEqual(students["Pranjal"]["added"], 7)
        self.assertEqual(len(students["Nitin"]["active_days"]), 2)
        self.assertIn("Last 7 Days", scope)
        self.assertEqual(len(logs["Nitin"]), 2)
        self.assertEqual(sum(sum(v.values()) for v in timeline.values()), 3)

    def test_final_interval_includes_all_history(self):
        _commit(self.repo, "Ritvik", 40, "c.js", 3, "car fleet search")
        _commit(self.repo, "Nitin", 1, "a.cls", 2, "booking")
        students, _, _, scope = generate_report.get_git_metrics("final")
        self.assertEqual(set(students), {"Ritvik", "Nitin"})
        self.assertIn("All Commits", scope)

    def test_monthly_interval_uses_30_day_window(self):
        _commit(self.repo, "Ritvik", 45, "c.js", 3, "outside month")
        _commit(self.repo, "Ritvik", 25, "c.js", 3, "inside month")
        students, timeline, _, scope = generate_report.get_git_metrics("monthly")
        self.assertEqual(students["Ritvik"]["commits"], 1)
        self.assertIn("Last 30 Days", scope)
        self.assertTrue(all("-W" in key for key in timeline))

    def test_empty_reporting_period_returns_no_students(self):
        _commit(self.repo, "Nitin", 30, "a.cls", 2, "old")
        students, timeline, logs, _ = generate_report.get_git_metrics("weekly")
        self.assertEqual(dict(students), {})
        self.assertEqual(dict(logs), {})

    def test_student_names_containing_bot_are_not_dropped(self):
        _commit(self.repo, "Ankit Talbot", 0, "a.cls", 4, "feat: inspection form")
        _commit(self.repo, "dependabot[bot]", 0, "p.json", 1, "chore: bump")
        students, _, _, _ = generate_report.get_git_metrics("weekly")
        self.assertEqual(set(students), {"Ankit Talbot"})

    def test_is_bot_author(self):
        for bot in ("github-actions[bot]", "dependabot[bot]", "GitHub-Actions", "renovate"):
            self.assertTrue(generate_report.is_bot_author(bot), bot)
        for human in ("Nitin", "Ankit Talbot", "Botha", "Pranjal Jain", "", None):
            self.assertFalse(generate_report.is_bot_author(human), human)

    def test_binary_numstat_lines_are_ignored(self):
        with open(os.path.join(self.repo, "logo.png"), "wb") as f:
            f.write(bytes(range(256)))
        _git(self.repo, "add", "logo.png")
        _git(self.repo, "-c", "user.name=Ritvik", "-c", "user.email=r@example.test", "commit", "-q", "-m", "add image")
        students, _, _, _ = generate_report.get_git_metrics("weekly")
        self.assertEqual(students["Ritvik"]["commits"], 1)
        self.assertEqual(students["Ritvik"]["added"], 0)

    def test_outside_git_repository_returns_none(self):
        not_repo = tempfile.mkdtemp(prefix="not-a-repo-")
        try:
            os.chdir(not_repo)
            students, timeline, logs, _ = generate_report.get_git_metrics("weekly")
            self.assertIsNone(students)
            generate_report.generate_pdf("weekly")  # must not raise
            self.assertEqual([f for f in os.listdir(not_repo) if f.endswith(".pdf")], [])
        finally:
            os.chdir(self.repo)
            shutil.rmtree(not_repo, ignore_errors=True)

    # ---------------------------------------------------------------- PDF output

    def test_weekly_pdf_is_generated_with_expected_name(self):
        _commit(self.repo, "Nitin", 0, "a.cls", 3, "fix: <script>alert(1)</script> & escape check")
        generate_report.generate_pdf("weekly")
        pdfs = self._pdfs()
        repo_name = os.path.basename(self.repo)
        today = datetime.date.today().strftime("%Y-%m-%d")
        self.assertEqual(pdfs, [f"{repo_name}_Weekly_Progress_Report_Form-3_{today}.pdf"])
        with open(os.path.join(self.repo, pdfs[0]), "rb") as f:
            self.assertTrue(f.read(5).startswith(b"%PDF-"))
        self.assertGreater(os.path.getsize(os.path.join(self.repo, pdfs[0])), 5000)

    def test_pdf_is_generated_for_an_empty_week(self):
        _commit(self.repo, "Nitin", 30, "a.cls", 3, "old")
        generate_report.generate_pdf("weekly")
        self.assertEqual(len(self._pdfs()), 1)

    def test_final_and_monthly_pdf_names(self):
        _commit(self.repo, "Nitin", 0, "a.cls", 3, "x")
        generate_report.generate_pdf("final")
        generate_report.generate_pdf("monthly")
        names = sorted(self._pdfs())
        self.assertEqual(len(names), 2)
        self.assertTrue(any("_Final_Report_" in n for n in names))
        self.assertTrue(any("_Monthly_Progress_Report_Form-3_" in n for n in names))

    def test_many_students_chart_does_not_fail(self):
        for i in range(7):  # more authors than the 5-colour palette
            _commit(self.repo, f"Student {i}", 0, f"f{i}.txt", i + 1, f"work {i}")
        generate_report.generate_pdf("weekly")
        self.assertEqual(len(self._pdfs()), 1)


class WorkflowConfigTest(unittest.TestCase):
    """Static checks of .github/workflows/auto_weekly_report.yml (it cannot be run locally)."""

    @classmethod
    def setUpClass(cls):
        with open(os.path.join(ROOT, ".github", "workflows", "auto_weekly_report.yml"), encoding="utf-8") as f:
            cls.text = f.read()

    def test_yaml_parses_when_pyyaml_available(self):
        try:
            import yaml
        except ImportError:
            self.skipTest("PyYAML not installed")
        doc = yaml.safe_load(self.text)
        triggers = doc.get(True) or doc.get("on")  # PyYAML reads the bare key `on` as boolean True
        self.assertIn("schedule", triggers)
        self.assertIn("workflow_dispatch", triggers)
        steps = doc["jobs"]["generate-and-commit"]["steps"]
        self.assertEqual(steps[0]["with"]["fetch-depth"], 0, "full history is needed for git log")

    def test_schedule_and_commands(self):
        self.assertIn("cron: '29 18 * * 4'", self.text, "Thursday 23:59 IST")
        self.assertIn("pip install reportlab matplotlib", self.text)
        self.assertIn("python generate_report.py weekly", self.text)
        self.assertIn("[skip ci]", self.text, "bot commit does not retrigger CI")
        self.assertIn("git diff --staged --quiet", self.text, "no empty commit when nothing changed")
        self.assertIn("contents: write", self.text)


if __name__ == "__main__":
    unittest.main()
