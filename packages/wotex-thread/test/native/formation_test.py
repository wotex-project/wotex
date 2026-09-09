"""WTH-S04/WTH-V05 explicit formation on the real pinned OpenThread host."""
import json
import sys
import unittest

from dataset_test import Ownership, fields, encoded


class Formation(Ownership):
    def test_WTH_S04_V05_creation_authority_and_existing_dataset_reject_without_erasure(self):
        host = self.host()
        self.open(host, self.config())
        denied = host.call('form_network', dict(dataset=encoded(fields())))
        self.assertEqual(denied['error']['code'], 'creation_not_allowed')
        self.assertEqual(denied['error']['state']['role'], 'disabled')
        self.assertEqual(host.call('get_dataset', dict(kind='active'))['error']['code'], 'dataset_not_found')
        self.assertIsNone(host.call('close')['result'])
        host.finish(0)

    def test_WTH_S04_V05_success_requires_observed_leader_and_preserves_credentials(self):
        host = self.host()
        config = self.config(allow_network_creation=True)
        self.open(host, config)
        host.counter += 1
        request = f'formation-{host.counter}'
        host.process.stdin.write(json.dumps(dict(version=1, id=request, operation='form_network',
                                 parameters=dict(dataset=encoded(fields())), timeout_ms=60000)).encode()+b'\n')
        result = host.receive(timeout=61)
        self.assertEqual(result['id'], request)
        self.assertTrue(result['ok'], result)
        self.assertEqual(result['result']['role'], 'leader')
        self.assertTrue(result['result']['ipv6_enabled'] and result['result']['thread_enabled'])
        self.assertEqual(host.call('get_dataset', dict(kind='active'))['result'], encoded(fields()))
        self.assertTrue(host.call('set_enabled', dict(ipv6=False, thread=False))['ok'])
        repeated = host.call('form_network', dict(dataset=encoded(fields())))
        self.assertEqual(repeated['error']['code'], 'dataset_exists')
        self.assertEqual(host.call('get_dataset', dict(kind='active'))['result'], encoded(fields()))
        self.assertIsNone(host.call('close')['result'])
        host.finish(0)

    def test_WTH_S04_V05_expired_formation_reports_state_and_keeps_installed_dataset(self):
        host = self.host()
        self.open(host, self.config(allow_network_creation=True))
        host.process.stdin.write(json.dumps(dict(version=1, id='short-formation', operation='form_network',
                                 parameters=dict(dataset=encoded(fields())), timeout_ms=1)).encode()+b'\n')
        result = host.receive(timeout=1)
        self.assertFalse(result['ok'])
        self.assertEqual(result['error']['code'], 'formation_timeout')
        self.assertTrue(result['error']['state']['thread_enabled'])
        self.assertEqual(host.call('get_dataset', dict(kind='active'))['result'], encoded(fields()))
        self.assertIsNone(host.call('close')['result'])
        host.finish(0)

    def test_WTH_C03_V05_close_cancels_pending_formation_without_waiting_for_role(self):
        host = self.host()
        self.open(host, self.config(allow_network_creation=True))
        host.submit('form_network', dict(dataset=encoded(fields())))
        close_id = host.submit('close')
        result = host.receive(timeout=1)
        self.assertEqual(result['id'], close_id)
        self.assertIsNone(result['result'])
        host.finish(0)


if __name__ == '__main__':
    suite = unittest.TestSuite(Formation(name) for name in Formation.__dict__ if name.startswith('test_'))
    sys.exit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
