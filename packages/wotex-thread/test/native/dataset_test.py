"""WTH-S01/WTH-V02 real pinned-SDK validity and explicit Dataset export."""
import base64
import json
from pathlib import Path
import subprocess
import sys
import unittest

SEED = Path(sys.argv.pop(3))
from owner_test import Ownership


def fields():
    return [(0, bytes.fromhex('00000f')), (1, bytes.fromhex('1234')),
            (2, bytes.fromhex('0102030405060708')), (3, b'wotex-sdk'),
            (4, b'0123456789abcdef'), (5, b'fedcba9876543210'),
            (7, bytes.fromhex('fd01020304050607')), (12, bytes.fromhex('02a0f7f8')),
            (14, bytes.fromhex('0000000000010000')), (53, bytes.fromhex('0004001fffe0')),
            (250, b'unknown')]


def encoded(values):
    raw = b''.join(bytes((tag, len(value))) + value for tag, value in values)
    return dict(type='bytes', base64=base64.b64encode(raw).decode())


def pending():
    return fields() + [(51, bytes.fromhex('0000000000010000')), (52, bytes.fromhex('000493e0'))]


class DatasetTests(Ownership):
    def test_WTH_S01_V02_validity_is_not_presence_or_network_mutation(self):
        host = self.host()
        config = self.config()
        state = self.open(host, config)
        settings = Path(config['storage_path']) / 'settings.data'
        before = settings.read_bytes()
        for kind, values in [('active', fields()), ('pending', pending())]:
            self.assertIsNone(host.call('validate_dataset', dict(kind=kind, dataset=encoded(values)))['result'])
        mutations = [(4, None), (0, b'\0\0\x01'), (1, b'\xff\xff'), (2, b'\0'*8),
                     (7, b'\0'*8), (53, bytes.fromhex('000400000000')),
                     (3, b'\xff'), (5, b'too-short')]
        for tag, replacement in mutations:
            values = [(key, replacement if key == tag else value) for key, value in fields()
                      if key != tag or replacement is not None]
            result = host.call('validate_dataset', dict(kind='active', dataset=encoded(values)))
            self.assertEqual(result['error'], dict(code='invalid_dataset'))
        for kind, values in [('pending', fields()), ('active', pending()), ('active', fields() + [(250, b'dup')])]:
            self.assertEqual(host.call('validate_dataset', dict(kind=kind, dataset=encoded(values)))['error'],
                             dict(code='invalid_dataset'))
        self.assertEqual(settings.read_bytes(), before)
        self.assertEqual(host.call('inspect')['result'], state)
        for kind in ['active', 'pending']:
            self.assertEqual(host.call('get_dataset', dict(kind=kind))['error'], dict(code='dataset_not_found'))
        self.assertIsNone(host.call('close')['result'])
        host.finish(0)

    def test_WTH_C07_V02_binary_envelopes_are_exact_and_bounded(self):
        host = self.host()
        self.open(host, self.config())
        for value in [dict(type='bytes', base64='AB=='), dict(type='bytes', base64='A'*341),
                      dict(type='bytes', base64=base64.b64encode(b'x'*255).decode()),
                      dict(type='bytes', base64='A A==')]:
            self.assertEqual(host.call('validate_dataset', dict(kind='active', dataset=value))['error'],
                             dict(code='invalid_dataset'))
        for parameters in [dict(kind='unknown', dataset=encoded(fields())),
                           dict(kind='active', dataset=dict(type='text', base64='')),
                           dict(kind='active', dataset=encoded(fields()), extra=True)]:
            self.assertEqual(host.call('validate_dataset', parameters)['error'], dict(code='invalid_request'))
        self.assertIsNone(host.call('close')['result'])
        host.finish(0)

    def test_WTH_S01_V02_exports_real_sdk_storage_with_unknown_tlvs(self):
        config = self.config()
        seed = subprocess.run([str(SEED)], input=json.dumps(dict(config=config, active=encoded(fields()),
                              pending=encoded(pending()))).encode()+b'\n', stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=5)
        self.assertEqual((seed.returncode, seed.stdout, seed.stderr), (0, b'', b''))
        config['storage_mode'] = 'open_existing'
        host = self.host()
        opened = host.call('open', config)
        self.assertTrue(opened['ok'])
        self.assertEqual(opened['result'], dict(role='disabled', network_name='wotex-sdk', rloc16=None,
                                              ipv6_enabled=False, thread_enabled=False, generation=1))
        self.assertEqual(host.call('get_dataset', dict(kind='active'))['result'], encoded(fields()))
        result = host.call('get_dataset', dict(kind='pending'))['result']
        # The real SDK updates elapsed Delay Timer on read; all other TLVs are preserved.
        raw = base64.b64decode(result['base64'])
        self.assertIn(bytes((250, 7))+b'unknown', raw)
        self.assertIn(bytes((5, 16))+b'fedcba9876543210', raw)
        self.assertIsNone(host.call('validate_dataset', dict(kind='pending', dataset=result))['result'])
        self.assertIsNone(host.call('close')['result'])
        host.finish(0)


if __name__ == '__main__':
    # Run only this package's cases; inherited ownership methods are exercised by owner_test.py.
    suite = unittest.TestSuite(DatasetTests(name) for name in DatasetTests.__dict__ if name.startswith('test_'))
    sys.exit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
