#!/usr/bin/env python3
"""Independent JSON-to-C02 vectors; no Runtime/BEAM imports or encoders."""
import argparse, hashlib, json
from decimal import Decimal
from pathlib import Path

class Refusal(Exception):
    pass

class Integer(str):
    pass

def objects(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise Refusal('invalid_input')
        result[key] = value
    return result

def node(value):
    if value is None: return {'type': 'null'}
    if isinstance(value, bool): return {'type': 'boolean', 'value': value}
    if isinstance(value, Integer):
        n = int(value)
        if not -(2**63) <= n <= 2**64-1: raise Refusal('unsupported_value')
        return {'type': 'sint' if n <= 2**63-1 else 'uint', 'value': str(n)}
    if isinstance(value, Decimal):
        t = value.as_tuple()
        digits = ''.join(map(str, t.digits)).lstrip('0')
        if not digits: c, e = 0, 0
        else:
            stripped = digits.rstrip('0')
            c = int(stripped) * (-1 if t.sign else 1)
            e = t.exponent + len(digits)-len(stripped)
        if not -(2**63) <= c <= 2**63-1 or not -32768 <= e <= 32767:
            raise Refusal('unsupported_value')
        return {'type':'decimal','coefficient':str(c),'exponent':e}
    if isinstance(value, str): return {'type':'text','value':value}
    if isinstance(value, list): return {'type':'list','items':[node(v) for v in value]}
    if isinstance(value, dict):
        if any(not 1 <= len(k.encode('utf-8')) <= 128 for k in value): raise Refusal('unsupported_value')
        return {'type':'object','entries':[{'key':k,'value':node(value[k])} for k in sorted(value,key=lambda k:k.encode('utf-8'))]}
    raise AssertionError(type(value))

def vectors():
    valid = [
      'null','true','false','""','"42"','"\\u0000é😀"','[]','{}',
      '0','-0','1','-1','-9223372036854775808','9223372036854775807',
      '9223372036854775808','18446744073709551615','9007199254740993',
      '0.0','-0.0e999999','1.2300e2','1000.000','1e-32768','1e32767',
      '10e-32769','9007199254740993.1','-9223372036854775808.0',
      '{"z":[true,null,0.1],"a":{"b":"text"}}',
      '{"😀":1,"é":2,"a":3,"\\uE000":4}',
      ' \t\r\n {"a":1} \t\r\n',
    ]
    cases=[]
    for i, raw in enumerate(valid):
        value=node(json.loads(raw,parse_int=Integer,parse_float=Decimal,object_pairs_hook=objects))
        canonical=json.dumps(value,sort_keys=True,ensure_ascii=False,separators=(',',':'))
        cases.append({'id':f'valid-{i:02}','input':raw,'expected':value,'canonical':canonical,'sha256':hashlib.sha256(canonical.encode()).hexdigest()})
    for code, raws in {
      'invalid_input':['',' ','{','[1,]','{"a":1,}','{"a":1,"a":2}','{"a":1,"\\u0061":2}','01','+1','NaN','Infinity','1 2','/* x */ 1','"\\uD800"','"\\uDC00"','\ufeff1','truex'],
      'unsupported_value':['-9223372036854775809','18446744073709551616','1e32768','1e-32769','9223372036854775808.1','{"":1}','{"'+'x'*129+'":0}'],
      'output_limit':['1'+('0'*128),'"'+'x'*4097+'"','['*9+']'*9,'['+','.join('0' for _ in range(257))+']']
    }.items():
        for raw in raws: cases.append({'id':f'invalid-{len(cases):02}','input':raw,'error':code})
    return {'format':'wotex-runtime.codec-json-v1','cases':cases}

def main():
    p=argparse.ArgumentParser(); p.add_argument('--check',action='store_true'); args=p.parse_args()
    path=Path(__file__).with_name('codec_json_vectors.json')
    text=json.dumps(vectors(),ensure_ascii=True,indent=2)+'\n'
    if args.check:
        assert path.read_text()==text,'frozen corpus drift'
        print(f'{len(vectors()["cases"])} independent JSON/C02 vectors verified')
    else: path.write_text(text)
if __name__=='__main__': main()
