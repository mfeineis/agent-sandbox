"""Firebreak Git boundary regression tests. Only Python's stdlib, no VM.

Developed for Python 3.14+. The tests also run on older 3.x interpreters
for environments where 3.14 has not yet been installed.
"""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

FB = Path(__file__).resolve().parents[1] / "firebreak"
FIXTURES = Path(__file__).resolve().parent / "fixtures"


class GitBoundaryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="firebreak-tests-")
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name) / "project"
        self.repo.mkdir()
        self.env = os.environ.copy()
        self.env["PATH"] = str(FIXTURES) + os.pathsep + self.env["PATH"]
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Test User")
        self.git("config", "user.email", "test@example.invalid")
        (self.repo / "tracked.txt").write_text("one\n")
        self.git("add", "tracked.txt")
        self.git("commit", "-qm", "first")
        (self.repo / "tracked.txt").write_text("two\n")
        self.git("commit", "-qam", "second")
        self.firebreak("config", "init")

    def cmd(self, *argv: str, cwd: Path | None = None, check=True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(a) for a in argv], cwd=cwd or self.repo, env=self.env,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=check,
        )

    def git(self, *args: str, cwd: Path | None = None) -> str:
        return self.cmd("git", *args, cwd=cwd).stdout.strip()

    def firebreak(self, *args: str) -> subprocess.CompletedProcess[str]:
        return self.cmd(str(FB), *args)

    def export(self, mode: str, depth: int = 5) -> Path:
        output = Path(self.tmp.name) / f"export-{mode}-{depth}"
        self.firebreak("demo", "__test-export", str(output), mode, str(depth))
        return output

    def test_snapshot_has_only_tracked_working_content(self) -> None:
        (self.repo / "tracked.txt").write_text("two\nthree\n")
        (self.repo / "private-untracked.env").write_text("TOKEN=DO_NOT_LEAK\n")
        exported = self.export("snapshot")
        files = self.git("ls-tree", "-r", "--name-only", "HEAD", cwd=exported / "repo")
        self.assertIn("tracked.txt", files)
        self.assertNotIn("private-untracked.env", files)
        self.assertEqual((exported / "repo" / "tracked.txt").read_text(), "two\nthree\n")
        # No host remotes or real .git directory appear in the working tree.
        self.assertFalse((exported / "repo" / "private-untracked.env").exists())
        self.assertTrue((exported / "import.bundle").is_file())
        self.assertEqual(len(self.git("rev-list", "--all", cwd=exported / "repo").splitlines()), 1)

    def test_full_history_keeps_original_commits(self) -> None:
        original = self.git("rev-parse", "HEAD")
        exported = self.export("full")
        self.assertEqual(self.git("rev-parse", "HEAD", cwd=exported / "repo"), original)
        self.assertEqual(len(self.git("rev-list", "--all", cwd=exported / "repo").splitlines()), 2)
        # Git bundle contains commits, not local .git/config (credential URLs).
        self.assertNotIn(b"git@example.org", (exported / "import.bundle").read_bytes())

    def test_shallow_history_recreates_only_recent_trees(self) -> None:
        (self.repo / "tracked.txt").write_text("three\n")
        self.git("commit", "-qam", "third")
        exported = self.export("shallow", depth=2)
        self.assertEqual(len(self.git("rev-list", "--all", cwd=exported / "repo").splitlines()), 2)
        self.assertEqual((exported / "repo" / "tracked.txt").read_text(), "three\n")

    def test_return_creates_review_branch_without_checkout(self) -> None:
        exported = self.export("snapshot")
        guestrepo = exported / "repo"
        guestbase = self.git("rev-parse", "HEAD", cwd=guestrepo)
        hostbase = self.git("rev-parse", "HEAD")
        (guestrepo / "tracked.txt").write_text("two\nAGENT_EDIT\n")
        (guestrepo / "agent-added.py").write_text("print('guest')\n")
        self.git("add", "-A", cwd=guestrepo)
        self.git("-c", "user.name=Agent", "-c", "user.email=agent@localhost", "commit", "-qm", "agent work", cwd=guestrepo)
        guesttip = self.git("rev-parse", "HEAD", cwd=guestrepo)
        self.git("update-ref", "refs/remotes/origin/main", guesttip, cwd=guestrepo)
        guestbundle = exported / "return.bundle"
        self.git("bundle", "create", str(guestbundle), "refs/remotes/origin/main", cwd=guestrepo)
        self.firebreak("demo", "__test-review", str(guestbundle), hostbase, guestbase)
        branch = f"firebreak/demo/{guesttip[:12]}"
        self.assertEqual(self.git("show", f"{branch}:tracked.txt"), "two\nAGENT_EDIT")
        self.assertEqual(self.git("show", f"{branch}:agent-added.py"), "print('guest')")
        self.assertEqual((self.repo / "tracked.txt").read_text(), "two\n")
        self.assertEqual(self.git("rev-parse", "HEAD"), hostbase)
        # Refuse to overwrite an existing reviewed result.
        conflict = self.cmd(str(FB), "demo", "__test-review", str(guestbundle), hostbase, guestbase, check=False)
        self.assertNotEqual(conflict.returncode, 0)

    def test_return_preserves_original_dirty_tracked_files(self) -> None:
        # Regression: a patch from guest baseline to guest tip is not enough,
        # because the initial guest snapshot may include host dirty edits.
        (self.repo / "tracked.txt").write_text("two\nhost-dirty\n")
        exported = self.export("snapshot")
        guestrepo = exported / "repo"
        guestbase = self.git("rev-parse", "HEAD", cwd=guestrepo)
        hostbase = self.git("rev-parse", "HEAD")
        (guestrepo / "agent.txt").write_text("made-by-agent\n")
        self.git("add", "-A", cwd=guestrepo)
        self.git("-c", "user.name=Agent", "-c", "user.email=agent@localhost", "commit", "-qm", "agent work", cwd=guestrepo)
        tip = self.git("rev-parse", "HEAD", cwd=guestrepo)
        self.git("update-ref", "refs/remotes/origin/main", tip, cwd=guestrepo)
        bundle = exported / "guest.bundle"
        self.git("bundle", "create", str(bundle), "refs/remotes/origin/main", cwd=guestrepo)
        self.firebreak("demo", "__test-review", str(bundle), hostbase, guestbase)
        branch = f"firebreak/demo/{tip[:12]}"
        self.assertEqual(self.git("show", f"{branch}:tracked.txt"), "two\nhost-dirty")
        self.assertEqual(self.git("show", f"{branch}:agent.txt"), "made-by-agent")
        self.assertEqual((self.repo / "tracked.txt").read_text(), "two\nhost-dirty\n")

    def test_conflicting_review_fails_closed(self) -> None:
        exported = self.export("snapshot")
        guestrepo = exported / "repo"
        guestbase = self.git("rev-parse", "HEAD", cwd=guestrepo)
        hostbase = self.git("rev-parse", "HEAD")
        # Simulate a guest revision against an imported initial tree.
        (guestrepo / "tracked.txt").write_text("two\nagent\n")
        self.git("-c", "user.name=Agent", "-c", "user.email=agent@localhost", "commit", "-qam", "agent", cwd=guestrepo)
        guesttip = self.git("rev-parse", "HEAD", cwd=guestrepo)
        self.git("update-ref", "refs/remotes/origin/main", guesttip, cwd=guestrepo)
        bundle = exported / "return.bundle"
        self.git("bundle", "create", str(bundle), "refs/remotes/origin/main", cwd=guestrepo)
        bogus_base = self.git("rev-parse", "HEAD~1")
        # A baseline not present in the guest history must be rejected.
        result = self.cmd(str(FB), "demo", "__test-review", str(bundle), hostbase, bogus_base, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.git("branch", "--list", f"firebreak/demo/{guesttip[:12]}"))


if __name__ == "__main__":
    unittest.main()
