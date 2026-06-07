import os
import re

querier_file = r'd:\projects\supanotes\backend\internal\db\sqlcgen\querier.go'
with open(querier_file, 'r', encoding='utf-8') as f:
    querier_code = f.read()

interface_match = re.search(r'type Querier interface \{(.*?)\}', querier_code, re.DOTALL)
methods = interface_match.group(1).strip().split('\n')

method_sigs = []
for m in methods:
    m = m.strip()
    if not m: continue
    name = m.split('(')[0].strip()
    method_sigs.append((name, m))

for target_file in [r'd:\projects\supanotes\backend\internal\auth\service_test.go', r'd:\projects\supanotes\backend\internal\auth\handler_test.go']:
    if not os.path.exists(target_file):
        continue
    
    with open(target_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    if 'type mockQuerier struct' not in content:
        continue
    
    append_str = ""
    for name, sig in method_sigs:
        if f'func (m *mockQuerier) {name}(' not in content:
            ret_part = sig[sig.rfind(')')+1:].strip()
            if ret_part.startswith('('):
                ret_part = ret_part[1:-1]
            rets = []
            for rt in ret_part.split(','):
                rt = rt.strip()
                if ' ' in rt:
                    rt = rt.split(' ')[-1] # get type if named
                if rt == 'error': rets.append('nil')
                elif rt.startswith('[]'): rets.append('nil')
                elif rt == 'bool': rets.append('false')
                elif rt == 'int' or rt == 'int32': rets.append('0')
                elif rt == 'string': rets.append('""')
                else: 
                    typename = rt.split('.')[-1]
                    rets.append('sqlcgen.' + typename + '{}')
            
            impl = f"func (m *mockQuerier) {sig} {{ return {', '.join(rets)} }}"
            append_str += impl + "\n"
    
    if append_str:
        with open(target_file, 'a', encoding='utf-8') as f:
            f.write("\n" + append_str)
        print(f"Added methods to {target_file}")
