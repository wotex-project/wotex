"""WTH-S04/WTH-V06 actual SDK management callbacks, never synthetic acceptance."""
import json
import sys
import unittest

from dataset_test import Ownership, fields, encoded, pending


def timestamp(values, number):
    return [(tag, (number << 16).to_bytes(8, 'big') if tag == 14 else value) for tag, value in values]


class Management(Ownership):
    def leader(self):
        host = self.host()
        self.open(host, self.config(allow_network_creation=True))
        host.process.stdin.write(json.dumps(dict(version=1, id='formation', operation='form_network',
                                 parameters=dict(dataset=encoded(fields())), timeout_ms=30000)).encode()+b'\n')
        result = host.receive(timeout=31)
        self.assertTrue(result['ok'], result)
        self.assertEqual(result['result']['role'], 'leader')
        return host

    def test_WTH_S04_V06_active_callback_acceptance_then_stale_rejection(self):
        host = self.leader()
        changed = timestamp(fields(), 2)
        result = host.call('management_active_set', dict(dataset=encoded(changed)))
        self.assertEqual(result.get('result'), dict(accepted=True, effective='not_verified'), result)
        self.assertEqual(host.call('get_dataset', dict(kind='active'))['result'], encoded(changed))
        rejected = host.call('management_active_set', dict(dataset=encoded(fields())))
        self.assertFalse(rejected['ok'])
        self.assertEqual(rejected['error']['code'], 'remote_error')
        self.assertEqual(rejected['error']['status'], 37)  # OT_ERROR_REJECTED
        self.assertIsNone(host.call('close')['result'])
        host.finish(0)

    def test_WTH_S04_V06_pending_callback_is_separate_from_activation(self):
        host = self.leader()
        result = host.call('management_pending_set', dict(dataset=encoded(timestamp(pending(), 2))))
        self.assertEqual(result.get('result'), dict(accepted=True, effective='not_verified'), result)
        self.assertEqual(host.call('get_dataset', dict(kind='active'))['result'], encoded(fields()))
        self.assertTrue(host.call('get_dataset', dict(kind='pending'))['ok'])
        self.assertIsNone(host.call('close')['result'])
        host.finish(0)

    def test_WTH_S04_V06_busy_and_close_preserve_callback_storage(self):
        host = self.leader()
        # One input batch submits a short exchange, checks exclusion, then closes
        # while the SDK still owns the callback. No network result is fabricated.
        commands = [dict(version=1, id='update', operation='management_active_set',
                         parameters=dict(dataset=encoded(timestamp(fields(), 2))), timeout_ms=1),
                    dict(version=1, id='overlap', operation='management_pending_set',
                         parameters=dict(dataset=encoded(timestamp(pending(), 3))), timeout_ms=5000),
                    dict(version=1, id='shutdown', operation='close', parameters={}, timeout_ms=1000)]
        host.process.stdin.write(b''.join(json.dumps(value).encode()+b'\n' for value in commands))
        overlap = host.receive(timeout=1)
        self.assertEqual(overlap['id'], 'overlap')
        self.assertEqual(overlap['error']['code'], 'busy')
        closed = host.receive(timeout=1)
        self.assertEqual(closed['id'], 'shutdown')
        self.assertIsNone(closed['result'])
        host.finish(0)

    def test_WTH_S04_V06_invalid_and_disabled_updates_never_report_acceptance(self):
        host = self.host()
        self.open(host, self.config())
        for operation in ['management_active_set', 'management_pending_set']:
            invalid = host.call(operation, dict(dataset=encoded([])))
            self.assertEqual(invalid['error']['code'], 'invalid_dataset')
        disabled = host.call('management_active_set', dict(dataset=encoded(fields())))
        self.assertFalse(disabled['ok'])
        self.assertEqual(disabled['error']['code'], 'remote_error')
        self.assertEqual(host.call('get_dataset', dict(kind='active'))['error']['code'], 'dataset_not_found')
        self.assertIsNone(host.call('close')['result'])
        host.finish(0)


if __name__ == '__main__':
    suite = unittest.TestSuite(Management(name) for name in Management.__dict__ if name.startswith('test_'))
    sys.exit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
