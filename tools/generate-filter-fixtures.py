#!/usr/bin/env python3
"""Generate checked-in differential assertions; never needed by the Zap runtime."""
import importlib.metadata
import json
from pathlib import Path
import jinja2

assert jinja2.__version__ == "3.1.6"
assert importlib.metadata.version("MarkupSafe") == "3.0.3"
ROOT = Path(__file__).resolve().parents[1]
cases = []
def case(name, source, context=None, *, strict=False, autoescape=True, error=False):
    env = jinja2.Environment(autoescape=autoescape, undefined=jinja2.StrictUndefined if strict else jinja2.Undefined)
    try:
        expected = env.from_string(source).render(context or {})
    except Exception as exc:
        if not error:
            raise
        expected = None
        error_type = type(exc).__name__
    else:
        if error:
            raise AssertionError(f"{name} did not fail in Jinja")
        error_type = None
    cases.append(dict(name=name, source=source, context=context or {}, strict=strict, autoescape=autoescape, expected=expected, error=error_type))

for name in ['escape', 'e', 'safe', 'upper', 'lower', 'title', 'trim', 'length', 'count', 'string']:
    case(name, '{{ value|' + name + ' }}', {'value': ' <b>hello & bye</b> '})
case('unicode length', '{{value|length}}/{{value|reverse}}', {'value':'é😀終'})
case('title words', '{{value|title}}', {'value':'hello-world (NEW) [TEST]'})
case('trim characters', "{{value|trim('xy')}}", {'value':'xyHello yx'})
case('replace', "{{value|replace('ab','<',2)}}", {'value':'ababab'})
case('replace empty', "{{value|replace('', '-', 2)}}", {'value':'abc'})
case('replace zero', "{{value|replace('a', 'b', 0)}}", {'value':'aaa'})
case('default absent', "{{missing|default('<fallback>')}}")
case('default null', "{{value|default('fallback')}}", {'value':None})
case('default boolean', "{{value|d('fallback', true)}}", {'value':0})
case('default keyword', "{{missing|default(boolean=true, default_value='yes')}}")
case('first last', '{{values|first}}/{{values|last}}', {'values':['<a>','<z>']})
case('empty first', "{{values|first|default('empty')}}", {'values':[]})
case('string list', "{{value|list|join(',')}}", {'value':'é😀終'})
case('mapping list', "{{value|list|join(',')}}", {'value':{'b':1,'a':2}})
case('join', "{{values|join('<>')}}", {'values':['<b>','&']})
case('join attr', "{{values|join(', ', attribute='name')}}", {'values':[{'name':'A'},{'name':'<B>'}]})
case('sort', "{{values|sort|join(',')}}", {'values':['b','A','a','C']})
case('sort reverse sensitive', "{{values|sort(reverse=true, case_sensitive=true)|join(',')}}", {'values':['b','A','a','C']})
case('sort attribute', "{{values|sort(attribute='age')|map(attribute='name')|join(',')}}", {'values':[{'name':'B','age':2},{'name':'A','age':1}]})
case('reverse list', "{{values|reverse|join(',')}}", {'values':[1,2,3]})
case('dictsort keys', "{% for pair in value|dictsort %}{{pair[0]}}={{pair[1]}};{% endfor %}", {'value':{'b':2,'A':3,'a':1}})
case('dictsort values', "{% for pair in value|dictsort(by='value', reverse=true) %}{{pair[0]}};{% endfor %}", {'value':{'b':2,'a':3,'c':1}})
for value in ['42','-42','+42',' 3.9 ','invalid',None,True,3.9]:
    case(f'int {value!r}', '{{value|int}}', {'value':value})
for value in ['3.5','-3.5',' +2.25 ','invalid',None,True,4]:
    case(f'float {value!r}', '{{value|float}}', {'value':value})
case('int base', "{{value|int(base=16)}}", {'value':'0xff'})
case('int fallback', '{{value|int(default=7)}}', {'value':'broken'})
case('float fallback', '{{value|float(7)}}', {'value':'broken'})
case('abs', '{{value|abs}}', {'value':-12})
for value in [-3.5,-2.5,2.5,3.5,2.25,2.75]:
    case(f'round {value}', '{{value|round}}', {'value':value})
case('round precision', "{{value|round(1)}}/{{value|round(1,'ceil')}}/{{value|round(1,'floor')}}", {'value':2.25})
case('select', "{{values|select('odd')|join(',')}}", {'values':[0,1,2,3,4]})
case('reject', "{{values|reject('even')|join(',')}}", {'values':[0,1,2,3,4]})
case('select truth', "{{values|select|join(',')}}", {'values':[0,1,False,2,'']})
case('select compare', "{{values|select('ge',2)|join(',')}}", {'values':[1,2,3]})
case('selectattr', "{{values|selectattr('active')|map(attribute='name')|join(',')}}", {'values':[{'name':'A','active':True},{'name':'B','active':False}]})
case('rejectattr', "{{values|rejectattr('active','equalto',true)|map(attribute='name')|join(',')}}", {'values':[{'name':'A','active':True},{'name':'B','active':False}]})
case('map filter', "{{values|map('upper')|join(',')}}", {'values':['abc','<b>']})
case('map argument', "{{values|map('default','none')|join(',')}}", {'values':['abc','def']})
case('map nested attribute', "{{values|map(attribute='user.name', default='?')|join(',')}}", {'values':[{'user':{'name':'Ada'}},{'user':{}},{}]})
case('map index', "{{values|map(attribute='0')|join(',')}}", {'values':[[1,2],[3,4]]})
for test in ['defined','undefined','none','string','number','sequence','mapping','boolean','integer','float','true','false','iterable','escaped']:
    case('test '+test, '{{missing is '+test+'}}/{{value is '+test+'}}/{{value is not '+test+'}}', {'value':True})
for test,value in [('even',4),('odd',-3),('lower','hello'),('upper','HI')]:
    case('test '+test, '{{value is '+test+'}}', {'value':value})
case('test arguments', '{{value is divisibleby(3)}}/{{value is equalto(6)}}', {'value':6})
case('test precedence', '{{not value is odd}}/{{(value + 1) is even}}', {'value':3})
case('filter precedence', '{{-value|abs}}/{{2 + value|abs}}', {'value':-3})
case('safe escaping idempotent', '{{value|safe|escape}}', {'value':'<b>&amp;</b>'})
case('untrusted escape idempotent', '{{value|escape|escape}}', {'value':'<b>&</b>'})
case('safe assignment', '{% set x = value|safe %}{{x}}', {'value':'<b>&</b>'})
case('safe concat left', "{{(a|safe) ~ b}}", {'a':'<b>','b':'<i>&'})
case('safe concat right', "{{a ~ (b|safe)}}", {'a':'<b>&','b':'<i>'})
case('safe addition', "{{(a|safe) + b}}", {'a':'<b>','b':'<i>&'})
case('escaped concat', "{{(a|e) ~ b}}", {'a':'<b>','b':'<i>'})
case('safe map join', "{{values|map('safe')|join('<>')}}", {'values':['<b>','<i>']})
case('safe separator join', "{{values|join('<>'|safe)}}", {'values':['<b>','<i>']})
case('map safe first', "{{values|map('safe')|first}}", {'values':['<b>','<i>']})
case('safe list reverse sort', "{{values|map('safe')|list|reverse|sort|join(',')}}", {'values':['<b>','<a>']})
case('safe loop', "{% for x in values|map('safe') %}{{x}}{% endfor %}", {'values':['<b>','<i>']})
case('safe string', '{{value|safe|string}}', {'value':'<b>'})
case('disabled escape', "{{value}}/{{value|escape}}", {'value':'<b>'}, autoescape=False)
case('autoescape nested', '{% autoescape false %}{{value}}{% autoescape true %}{{value}}{% endautoescape %}{{value}}{% endautoescape %}{{value}}', {'value':'<b>'})
case('autoescape scope', '{% set x = 1 %}{% autoescape false %}{% set x = 2 %}{{x}}{% endautoescape %}{{x}}')
case('strict default', "{{missing|default('ok')}}", strict=True)
case('strict tests', '{{missing is defined}}/{{missing is undefined}}/{{missing is none}}', strict=True)
for source in ['{{missing}}','{% if missing %}yes{% endif %}','{{missing == none}}','{{missing|length}}','{% for x in missing %}x{% endfor %}']:
    case('strict error '+source, source, strict=True,error=True)
case('tojson', '{{value|tojson}}', {'value':{'z':'</script> & \'','a':[1,True,None]}})
case('tojson unicode', '{{value|tojson}}', {'value':{'é':'😀終\u2028'}})
case('undefined map test', "{{values|map(attribute='missing')|first is undefined}}", {'values':[{}]})
for name,source in [
    ('unknown filter','{{value|unknown}}'),('unknown test','{{value is unknown}}'),
    ('replace arity',"{{value|replace('a')}}"),('unknown keyword','{{value|sort(typo=true)}}'),
    ('duplicate keyword','{{value|join("a",d="b")}}'),('bad type','{{value|join(12)}}'),
    ('round method',"{{value|round(0,'broken')}}"),('round precision','{{value|round(1.5)}}'),
    ('test arity','{{value is defined(1)}}'),('dictsort type','{{value|dictsort}}'),
    ('sort mixed','{{value|sort|join}}'),('map arguments','{{value|map|list}}'),
]:
    context={'value':[1,'a']} if name=='sort mixed' else {'value':2}
    case(name, source, context,error=True)

(ROOT/'tests/fixtures/filters.json').write_text(json.dumps({'jinja':'3.1.6','markupsafe':'3.0.3','cases':cases},indent=2,ensure_ascii=False)+'\n')
header='''# Generated by tools/generate-filter-fixtures.py using pinned Jinja/MarkupSafe.
import templates

def context(str text) -> dict[str, JsonValue]:
    match json.loads(text):
        case JsonValue.Object(fields):
            return fields
        case _:
            return {}

def check(str name, str source, str data, str expected, bool strict, bool escaping):
    auto actual = templates.render(source, context(data), escaping, strict)
    if actual != expected:
        raise name + ": expected [" + expected + "] got [" + actual + "]"

def bad(str name, str source, str data, bool strict, bool escaping):
    auto caught = False
    try:
        auto output = templates.render(source, context(data), escaping, strict)
    except Exception as e:
        assert "TemplateError at character " in str(e)
        caught = True
    if not caught:
        raise name + ": expected template error"

def main():
'''
q=lambda x:json.dumps(x, ensure_ascii=False)
lines=[header]
for c in cases:
    args=', '.join(map(q,[c['name'],c['source'],json.dumps(c['context'],ensure_ascii=False)]))
    flags=f"{c['strict']}, {c['autoescape']}"
    if c['error']:
        lines.append(f'    bad({args}, {flags})\n')
    else:
        lines.append(f'    check({args}, {q(c["expected"])}, {flags})\n')
lines.append(f'    print("Jinja differential fixtures: {len(cases)} PASS")\n')
(ROOT/'tests/filters_fixtures_test.zap').write_text(''.join(lines))
print(f'Generated {len(cases)} fixtures')
