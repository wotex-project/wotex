#!/usr/bin/env python3
"""Independent exact JSON field projection vectors; no production imports."""
import argparse
import json
from decimal import Decimal
from pathlib import Path

class Integer(str):
    pass

def typed(value):
    if value is None: return {"type": "null"}
    if isinstance(value, bool): return {"type": "boolean", "value": value}
    if isinstance(value, Integer):
        n = int(value)
        return {"type": "sint" if n <= 2**63-1 else "uint", "value": str(n)}
    if isinstance(value, Decimal):
        t = value.as_tuple()
        digits = ''.join(map(str, t.digits)).lstrip('0')
        coefficient = digits.rstrip('0')
        c = int(coefficient or '0') * (-1 if t.sign else 1)
        exponent = t.exponent + len(digits)-len(coefficient) if c else 0
        return {"type": "decimal", "coefficient": str(c), "exponent": exponent}
    if isinstance(value, str): return {"type": "text", "value": value}
    if isinstance(value, list): return {"type": "list", "items": [typed(v) for v in value]}
    return {"type": "object", "entries": [{"key": k, "value": typed(value[k])} for k in sorted(value, key=lambda k: k.encode())]}

def corpus():
    samples = [(raw, []) for raw in ['null','true','false','""','"12"','0','-9223372036854775808','18446744073709551615','9007199254740993.1','-0.0e9','[]','{}']]
    samples += [('{"x":[0,false,null,1.2300e2]}', ['x', str(i)]) for i in range(4)]
    samples += [(' {"a/b":{"~1":{"01":42}},"x":99} ', ['a/b','~1','01']), ('{"é":"😀","é":"different"}', ['é']), ('{"a":{"b":[]}}', ['a']), ('[1,{"v":-0.00012}]', ['1','v'])]
    rows=[]
    for i,(raw,path) in enumerate(samples):
        native=json.loads(raw,parse_int=Integer,parse_float=Decimal)
        for key in path: native = native[int(key)] if isinstance(native,list) else native[key]
        rows.append({"id":f"valid-{i:02}","payload":raw,"selector":{"topic":"samples/value","path":path},"topic":"samples/value","qos":i%3,"retain":bool(i%2),"expected":typed(native)})
    failures=[('null',['a'],'profile_value_missing'),('{"a":null}',['missing'],'profile_value_missing'),('[0]',['01'],'profile_value_missing'),('[0]',['-'],'profile_value_missing'),('[0]',['1'],'profile_value_missing'),('{"a":1,"a":2}',[],'json_invalid_input'),('{"a":1,"unselected":1e32768}',['a'],'json_unsupported_value'),('{"a":1,"unselected":[1,]}',['a'],'json_invalid_input'),('1e32768',[],'json_unsupported_value'),('1'+'0'*128,[],'json_output_limit')]
    for raw,path,error in failures:
        rows.append({"id":f"refusal-{len(rows):02}","payload":raw,"selector":{"topic":"samples/value","path":path},"topic":"samples/value","qos":0,"retain":False,"error":error})
    rows.append({"id":"ignore","payload":"private-canary invalid JSON","selector":{"topic":"samples/value","path":[]},"topic":"other/value","qos":1,"retain":True,"ignore":True})
    return {"format":"wotex-mqtt.json-projection-v1","cases":rows}

if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    path=Path(__file__).with_name('json_projection_vectors.json')
    text=json.dumps(corpus(),ensure_ascii=True,indent=2)+'\n'
    if args.check:
        assert path.read_text()==text,'frozen corpus drift'
        print(f'{len(corpus()["cases"])} independent JSON projection vectors verified')
    else: path.write_text(text)
