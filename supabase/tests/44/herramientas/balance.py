import sys, re
def check(path):
    t = open(path, encoding='utf-8').read()
    i, n, depth, line, stack = 0, len(t), 0, 1, []
    dollars = []
    while i < n:
        c = t[i]
        if c == '\n': line += 1
        if t.startswith('--', i):
            j = t.find('\n', i); i = n if j < 0 else j; continue
        if c == "'":
            j = i + 1
            while True:
                k = t.find("'", j)
                if k < 0: return f'{path}: comilla sin cerrar en línea {line}'
                if t.startswith("''", k): j = k + 2; continue
                break
            line += t.count('\n', i, k); i = k + 1; continue
        m = re.match(r'\$([A-Za-z0-9_]*)\$', t[i:])
        if m and not (i > 0 and (t[i-1].isalnum() or t[i-1] == '_')):
            tag = m.group(0)
            if dollars and dollars[-1] == tag: dollars.pop()
            else: dollars.append(tag)
            i += len(tag); continue
        if c == '(': stack.append(line)
        elif c == ')':
            if not stack: return f'{path}: ")" de más en línea {line}'
            stack.pop()
        i += 1
    if stack: return f'{path}: "(" sin cerrar, abierto en línea {stack[-1]}'
    if dollars: return f'{path}: dólar sin cerrar {dollars}'
    return f'{path}: ok'
for p in sys.argv[1:]: print(check(p))
