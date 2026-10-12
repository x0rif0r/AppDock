import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class InstallationPolicyTests(unittest.TestCase):
    def test_reinstall_never_downgrades_and_is_opt_in(self):
        source = (ROOT / 'Sources/Library.swift').read_text()
        policy = source.split('enum InstallationPolicy {', 1)[1].split('\nstruct DownloadRequest:', 1)[0]
        fixture = '''
assert(InstallationPolicy.shouldSkip(current: "1.3", requested: "1.3", reinstallSameVersion: false))
assert(!InstallationPolicy.shouldSkip(current: "1.3", requested: "1.3", reinstallSameVersion: true))
assert(InstallationPolicy.shouldSkip(current: "1.10", requested: "1.3", reinstallSameVersion: true))
assert(!InstallationPolicy.shouldSkip(current: "1.3", requested: "1.10", reinstallSameVersion: false))
'''
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / 'policy.swift'
            path.write_text('import Foundation\nenum InstallationPolicy {' + policy + fixture)
            subprocess.run(['swift', '-module-cache-path', str(ROOT / 'build/module-cache'), str(path)], check=True, capture_output=True)
