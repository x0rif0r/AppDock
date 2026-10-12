"""Tests local authentication transport with a fixture CLI; no Apple login."""
import json, pathlib, subprocess, tempfile, time, unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class AuthTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.root = pathlib.Path(self.temp.name)
        self.helper = self.root/'appdock-auth'
        subprocess.run(['clang','-O2','-Wall','-Wextra',str(ROOT/'Helpers/auth.c'),'-o',str(self.helper)],check=True)
        self.cli = self.root/'fixture-ipatool'
        self.cli.write_text('''#!/usr/bin/env python3
import json,pathlib,sys,time
root=pathlib.Path(__file__).parent
(root/'argv.json').write_text(json.dumps(sys.argv))
print('enter Apple ID (email address or phone number): ',end='',flush=True)
email=input()
print('enter password: ',end='',flush=True)
password=input()
if password=='fail':
 print('private-error: '+email+' '+password,flush=True);sys.exit(1)
print('enter 2FA code: ',end='',flush=True)
code=input()
print('private-values: '+email+' '+password+' '+code,flush=True)
print(json.dumps({'success':code=='123456'},separators=(',',':')),flush=True)
''');self.cli.chmod(0o700)
    def tearDown(self):self.temp.cleanup()
    def test_2fa_and_credentials_never_in_argv_or_public_events(self):
        task=subprocess.Popen([str(self.helper),str(self.cli)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
        task.stdin.write('fixture@example.invalid\nfixture-password\n');task.stdin.flush()
        output=[]
        while True:
            line=task.stdout.readline();self.assertTrue(line);output.append(line)
            if json.loads(line)['status']=='awaiting2fa':break
        task.stdin.write('123456\n');task.stdin.flush()
        while True:
            line=task.stdout.readline()
            if not line:break
            output.append(line)
        self.assertEqual(task.wait(timeout=5),0)
        self.assertEqual(json.loads(output[-1])['status'],'done')
        raw=''.join(output)+(self.root/'argv.json').read_text()
        for secret in ['fixture@example.invalid','fixture-password','123456']:self.assertNotIn(secret,raw)
        task.stdin.close();task.stdout.close()
    def test_rejected_credentials_are_redacted(self):
        r=subprocess.run([str(self.helper),str(self.cli)],input='fixture@example.invalid\nfail\n',capture_output=True,text=True,timeout=10)
        self.assertNotEqual(r.returncode,0)
        self.assertIn('failed',r.stdout)
        self.assertNotIn('fixture@example.invalid',r.stdout+r.stderr)
        self.assertNotIn('private-error',r.stdout+r.stderr)
    def test_cancel_waiting_for_2fa(self):
        task=subprocess.Popen([str(self.helper),str(self.cli)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
        task.stdin.write('fixture@example.invalid\nfixture-password\n');task.stdin.flush()
        while json.loads(task.stdout.readline())['status']!='awaiting2fa':pass
        task.terminate();self.assertNotEqual(task.wait(timeout=5),0)
        task.stdin.close();task.stdout.close()

if __name__=='__main__':unittest.main()
