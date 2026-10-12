import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class DeviceMatchTests(unittest.TestCase):
    def test_identifier_conflicts_and_missing_metadata(self):
        source = (ROOT / 'Sources/DeviceSave.swift').read_text()
        matcher = source.split('enum DeviceAppMatch {', 1)[1].split('\nstruct DeviceSaveView:', 1)[0]
        fixture = '''
assert(DeviceAppMatch.resolve(deviceID: nil, candidates: []) == nil)
assert(DeviceAppMatch.resolve(deviceID: nil, candidates: [417281773,417281773]) == 417281773)
assert(DeviceAppMatch.resolve(deviceID: nil, candidates: [492224193,6443619924]) == nil)
assert(DeviceAppMatch.resolve(deviceID: 417281773, candidates: []) == 417281773)
assert(DeviceAppMatch.resolve(deviceID: 417281773, candidates: [492224193]) == nil)
assert(DeviceAppMatch.resolve(deviceID: 417281773, candidates: [417281773]) == 417281773)
assert(DeviceAppMatch.resolve(deviceID: nil, candidates: [0,-1]) == nil)
'''
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / 'match.swift'
            path.write_text('enum DeviceAppMatch {' + matcher + fixture)
            subprocess.run(['swift', '-module-cache-path', str(ROOT / 'build/module-cache'), str(path)], check=True, capture_output=True)
