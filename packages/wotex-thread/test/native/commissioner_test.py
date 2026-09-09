"""WTH-S05/WTH-V08 real commissioner petition, exact admissions and teardown."""
import json
import sys
import time
import unittest

from management_test import Management


def eui(number):
    return dict(type='eui64', value=f'{number:016X}')


def admission(identity, lifetime=60):
    return dict(identity=identity, pskd='WTEST123', lifetime=lifetime)


class Commissioner(Management):
    def test_WTH_S05_V08_real_petition_and_exact_eui_discerner_admissions(self):
        host = self.leader()
        self.assertEqual(host.call('commissioner_start').get('result'), dict(state='active'))
        self.assertEqual(host.call('commissioner_start')['error']['code'], 'busy')
        identities = [eui(42)] + [dict(type='discerner', length=length, value=str((1 << length)-1))
                                  for length in range(1, 65)]
        for identity in identities:
            self.assertEqual(host.call('add_joiner', admission(identity))['result'], dict(identity=identity, lifetime_s=60))
            self.assertIsNone(host.call('remove_joiner', dict(identity=identity))['result'])
            absent = host.call('remove_joiner', dict(identity=identity))
            self.assertEqual(absent['error']['code'], 'remote_error')
            self.assertEqual(absent['error']['status'], 23)  # OT_ERROR_NOT_FOUND
        self.assertEqual(host.call('commissioner_stop')['result'], dict(state='disabled'))
        self.assertEqual(host.call('commissioner_stop')['result'], dict(state='disabled'))
        self.assertEqual(host.call('add_joiner', admission(eui(42)))['error']['code'], 'invalid_state')
        self.assertIsNone(host.call('close')['result'])
        host.finish(0)

    def test_WTH_S05_V08_sdk_capacity_expiry_and_stop_clear_records(self):
        host = self.leader()
        self.assertEqual(host.call('commissioner_start').get('result'), dict(state='active'))
        accepted = []
        for number in range(1, 66):
            result = host.call('add_joiner', admission(eui(number), lifetime=1))
            if not result['ok']:
                self.assertEqual(result['error'], dict(code='remote_error', status=3))
                break
            accepted.append(number)
        self.assertTrue(accepted and len(accepted) <= 64)
        time.sleep(1.1)
        self.assertEqual(host.call('add_joiner', admission(eui(100)))['result'], dict(identity=eui(100), lifetime_s=60))
        self.assertEqual(host.call('commissioner_stop')['result'], dict(state='disabled'))
        self.assertEqual(host.call('commissioner_start').get('result'), dict(state='active'))
        self.assertEqual(host.call('remove_joiner', dict(identity=eui(100)))['error']['status'], 23)
        self.assertIsNone(host.call('close')['result'])
        host.finish(0)

    def test_WTH_S05_V08_invalid_admissions_and_disabled_petition_never_succeed(self):
        host = self.host()
        self.open(host, self.config())
        self.assertEqual(host.call('commissioner_start')['error']['code'], 'remote_error')
        for identity in [None, dict(type='any'), dict(type='eui64', value='ffffffffffffffff'),
                         dict(type='discerner', length=64, value='18446744073709551616'),
                         dict(type='discerner', length=1, value='2'),
                         dict(type='discerner', length=1, value='01'),
                         dict(type='discerner', length=1, value=1)]:
            self.assertEqual(host.call('add_joiner', admission(identity))['error']['code'], 'invalid_joiner_identity')
        for values in [dict(identity=eui(42), pskd='INVALID', lifetime=60),
                       admission(eui(42), 0), admission(eui(42), 3601)]:
            self.assertEqual(host.call('add_joiner', values)['error']['code'], 'invalid_joiner_admission')
        self.assertIsNone(host.call('close')['result'])
        host.finish(0)

    def test_WTH_S05_V08_stop_preempts_pending_petition_without_late_completion(self):
        host = self.leader()
        commands = [dict(version=1, id='petition', operation='commissioner_start', parameters={}, timeout_ms=5000),
                    dict(version=1, id='stop', operation='commissioner_stop', parameters={}, timeout_ms=1000)]
        host.process.stdin.write(b''.join(json.dumps(value).encode()+b'\n' for value in commands))
        cancelled = host.receive(timeout=1)
        self.assertEqual(cancelled['id'], 'petition')
        self.assertEqual(cancelled['error']['code'], 'cancelled')
        stopped = host.receive(timeout=1)
        self.assertEqual(stopped['id'], 'stop')
        self.assertEqual(stopped['result'], dict(state='disabled'))
        self.assertIsNone(host.call('close')['result'])
        host.finish(0)


if __name__ == '__main__':
    suite = unittest.TestSuite(Commissioner(name) for name in Commissioner.__dict__ if name.startswith('test_'))
    sys.exit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
