#!/usr/bin/env python3
"""Pinned Jinja differential fixtures for the supported composition subset."""
import importlib.metadata
import json
from pathlib import Path
from jinja2 import Environment, DictLoader, StrictUndefined, Undefined
assert importlib.metadata.version('Jinja2') == '3.1.6'
assert importlib.metadata.version('MarkupSafe') == '3.0.3'
ROOT=Path(__file__).resolve().parents[1]
cases=[]
def case(name, files, root='main', context=None, strict=False, escaping=True, error=False):
    env=Environment(loader=DictLoader(files), autoescape=escaping, undefined=StrictUndefined if strict else Undefined)
    try:
        expected=env.get_template(root).render(context or {})
    except Exception as e:
        if not error: raise
        expected=None
        kind=type(e).__name__
    else:
        if error: raise AssertionError(name+' did not fail')
        kind=None
    cases.append(dict(name=name, files=files, root=root, context=context or {}, strict=strict, escaping=escaping, expected=expected, error=kind))
case('basic inheritance', {'base':'<h1>{% block title %}Base{% endblock %}</h1>{% block body %}body{% endblock %}','main':"{% extends 'base' %}{% block title %}Child{% endblock %}"})
case('named closing block', {'main':'{% block x %}X{% endblock x %}'})
case('three level super', {'base':'[{% block x %}A{% endblock %}]','middle':"{% extends 'base' %}{% block x %}B{{super()}}{% endblock %}",'main':"{% extends 'middle' %}{% block x %}C{{super()}}/{{super()}}{% endblock %}"})
case('super escaping', {'base':'{% block x %}<b>{{html}}</b>{% endblock %}','main':"{% extends 'base' %}{% block x %}<i>{{super()}}</i>{% endblock %}"},context={'html':'<script>'})
case('nested blocks', {'base':'{% block outer %}A{% block inner %}I{% endblock %}Z{% endblock %}','main':"{% extends 'base' %}{% block inner %}X{% endblock %}"})
case('nested override super', {'base':'{% block outer %}A{% block inner %}I{% endblock %}Z{% endblock %}','main':"{% extends 'base' %}{% block outer %}B{{super()}}Y{% endblock %}{% block inner %}X{% endblock %}"})
case('dynamic parent setup', {'base':'{% block x %}A{% endblock %}','main':"{% set parent = 'base' %}{% extends parent %}{% block x %}{{value}}{% endblock %}"},context={'value':'<b>'})
case('include context', {'main':"{% set x = 'local' %}{% include 'part' %}",'part':'{{x}}/{{html}}'},context={'html':'<b>'})
case('include without context', {'main':"{% set x = 2 %}{% include 'part' without context %}",'part':"{{x|default('missing')}}"})
case('include explicit context', {'main':"{% include part with context %}",'part':'{{value}}'},context={'part':'part','value':3})
case('nested includes', {'main':"M{% include 'a' %}",'a':"A{% include 'b' %}",'b':'B{{x}}'},context={'x':1})
case('include isolation', {'main':"{% set x = 1 %}{% include 'part' %}{{x}}",'part':'{% set x = 2 %}{{x}}'})
case('include inherited', {'main':"{% include 'child' %}",'base':'<{% block x %}A{% endblock %}>','child':"{% extends 'base' %}{% block x %}B{{super()}}{% endblock %}"})
case('include blocks isolated', {'main':"{% extends 'base' %}{% block x %}M{% include 'part' %}{{super()}}{% endblock %}",'base':'{% block x %}A{% endblock %}','part':'{% block x %}P{% endblock %}'})
case('ignore missing', {'main':"A{% include 'absent' ignore missing %}B"})
case('ignore missing with context', {'main':"A{% include 'absent' ignore missing with context %}B"})
case('ignore syntax error', {'main':"{% include 'bad' ignore missing %}",'bad':'{% if %}'},error=True)
case('missing include', {'main':"{% include 'absent' %}"},error=True)
case('macro literal', {'main':'{% macro hello() %}<b>Hello</b>{% endmacro %}{{hello()}}'})
case('macro positional keyword', {'main':"{% macro f(a,b='B') %}{{a}}/{{b}}{% endmacro %}{{f('A')}};{{f(b='Y',a='X')}}"})
case('macro context closure', {'main':"{% set x='A' %}{% macro f() %}{{x}}{% endmacro %}{% set x='B' %}{{f()}}"})
case('macro default context', {'main':"{% set x='A' %}{% macro f(a=x) %}{{a}}{% endmacro %}{% set x='B' %}{{f()}}"})
case('macro dependent default', {'main':"{% macro f(a,b=a) %}{{a}}/{{b}}{% endmacro %}{{f('A')}}"})
case('macro scopes', {'main':"{% set x=1 %}{% macro f() %}{% set x=2 %}{{x}}{% endmacro %}{{f()}}{{x}}"})
case('macro escaping', {'main':'{% macro f(x) %}<b>{{x}}</b>{% endmacro %}{{f(html)}}'},context={'html':'<i>&'})
case('macro safe argument', {'main':'{% macro f(x) %}<b>{{x}}</b>{% endmacro %}{{f(html|safe)}}'},context={'html':'<i>&'})
case('macro text mode', {'main':'{% macro f(x) %}<b>{{x}}</b>{% endmacro %}{{f(html)}}'},context={'html':'<i>'},escaping=False)
case('macro called in autoescape block', {'main':'{% macro f(x) %}<b>{{x}}</b>{% endmacro %}{% autoescape false %}{{f(html)}}{% endautoescape %}'},context={'html':'<i>'})
case('macro undefined parameter', {'main':"{% macro f(x) %}[{{x}}]{% endmacro %}{{f()}}"})
case('macro strict parameter', {'main':"{% macro f(x) %}[{{x}}]{% endmacro %}{{f()}}"},strict=True,error=True)
case('macro alias', {'main':"{% macro f() %}X{% endmacro %}{% set alias=f %}{{alias()}}"})
case('macro recursion finite', {'main':"{% macro f(n) %}{{n}}{% if n > 0 %}{{f(n-1)}}{% endif %}{% endmacro %}{{f(3)}}"})
case('macro callable type', {'main':'{% macro f() %}x{% endmacro %}{{f is callable}}/{{f is none}}/{% if f %}yes{% endif %}'})
case('two macros', {'main':'{% macro a(x) %}[{{x}}]{% endmacro %}{% macro b(x) %}{{a(x)}}{% endmacro %}{{b(html)}}'},context={'html':'<b>'})
case('import default isolation', {'main':"{% import 'lib' as lib %}{{lib.show()}}",'lib':"{% macro show() %}{{secret|default('isolated')}}{% endmacro %}"},context={'secret':'visible'})
case('import with context', {'main':"{% import 'lib' as lib with context %}{{lib.show()}}",'lib':"{% macro show() %}{{secret}}{% endmacro %}"},context={'secret':'<b>'})
case('from alias', {'main':"{% from 'lib' import show as f, other %}{{f()}}/{{other()}}",'lib':'{% macro show() %}A{% endmacro %}{% macro other() %}B{% endmacro %}'})
case('from with context', {'main':"{% from 'lib' import show with context %}{{show()}}",'lib':'{% macro show() %}{{secret}}{% endmacro %}'},context={'secret':'<b>'})
case('import exported assignment', {'main':"{% import 'lib' as lib %}{{lib.x}}/{{lib.f()}}",'lib':"{% set x='<b>'|safe %}{% macro f() %}{{x}}{% endmacro %}"})
case('import top level output hidden', {'main':"A{% import 'lib' as lib %}{{lib.f()}}B",'lib':'HIDDEN{% macro f() %}F{% endmacro %}'})
case('import nested', {'main':"{% import 'a' as a %}{{a.f()}}",'a':"{% import 'b' as b %}{% macro f() %}A{{b.f()}}{% endmacro %}",'b':'{% macro f() %}B{% endmacro %}'})
case('import name bracket', {'main':"{% import 'lib' as lib %}{{lib['f']()}}",'lib':'{% macro f() %}F{% endmacro %}'})
case('empty namespace lookup', {'main':"{% import 'lib' as lib %}{{lib.missing|default('none')}}",'lib':''})
case('empty namespace truth', {'main':"{% import 'lib' as lib %}{% if lib %}yes{% endif %}",'lib':''})
case('private import', {'main':"{% from 'lib' import _hidden %}",'lib':'{% macro _hidden() %}X{% endmacro %}'},error=True)
case('caller block', {'main':'{% macro wrapper() %}<b>{{caller()}}</b>{% endmacro %}{% call wrapper() %}{{html}}{% endcall %}'},context={'html':'<i>'})
case('caller arguments', {'main':"{% macro wrapper() %}[{{caller('Ada')}}]{% endmacro %}{% call(name) wrapper() %}Hello {{name}}{% endcall %}"})
case('caller outer lexical context', {'main':"{% set x='outer' %}{% macro wrapper() %}{% set x='inner' %}{{caller()}}{% endmacro %}{% call wrapper() %}{{x}}{% endcall %}"})
case('caller imported', {'main':"{% import 'lib' as lib %}{% call lib.wrap() %}{{html}}{% endcall %}",'lib':'{% macro wrap() %}<b>{{caller()}}</b>{% endmacro %}'},context={'html':'<i>'})
case('caller nested', {'main':'{% macro wrap() %}[{{caller()}}]{% endmacro %}{% call wrap() %}A{% call wrap() %}B{% endcall %}C{% endcall %}'})
case('macro unknown keyword', {'main':'{% macro f(x) %}{{x}}{% endmacro %}{{f(unknown=1)}}'},error=True)
case('macro excess positional', {'main':'{% macro f(x) %}{{x}}{% endmacro %}{{f(1,2)}}'},error=True)
case('macro duplicate argument', {'main':'{% macro f(x) %}{{x}}{% endmacro %}{{f(1,x=2)}}'},error=True)
case('bad macro parameter order', {'main':'{% macro f(x=1,y) %}{{x}}{% endmacro %}'},error=True)
case('duplicate block', {'main':'{% block x %}A{% endblock %}{% block x %}B{% endblock %}'},error=True)
case('mismatched endblock', {'main':'{% block x %}A{% endblock y %}'},error=True)
case('missing super', {'main':'{% block x %}{{super()}}{% endblock %}'},error=True)

case('include own escaping policy', {'main':"{% autoescape false %}{% include 'part' %}{% endautoescape %}",'part':'{{html}}'},context={'html':'<b>'})
case('macro defined in false block', {'main':'{% autoescape false %}{% macro f() %}<b>{{html}}</b>{% endmacro %}{{f()}}{% endautoescape %}'},context={'html':'<i>'})
case('import globals not exported', {'main':"{% import 'lib' as lib with context %}{{lib.secret|default('hidden')}}",'lib':'{% macro f() %}F{% endmacro %}'},context={'secret':'private'})
case('from globals not exported', {'main':"{% from 'lib' import secret with context %}{{secret}}",'lib':''},context={'secret':'private'}, strict=True,error=True)
q=lambda s: json.dumps(s,ensure_ascii=False)
header='''# Generated by tools/generate-composition-fixtures.py.
import templates

def sources(str text) -> dict[str, str]:
    dict[str, str] result = {}
    match json.loads(text):
        case JsonValue.Object(fields):
            for key in fields:
                match fields[key]:
                    case JsonValue.Str(s):
                        result[key] = s
                    case _:
                        raise "invalid fixture source"
        case _:
            raise "invalid fixture sources"
    return result

def context(str text) -> dict[str, JsonValue]:
    match json.loads(text):
        case JsonValue.Object(fields):
            return fields
        case _:
            return {}

def check(str name, str files, str root, str data, str expected, bool strict, bool escaping):
    auto env = templates.environment(sources(files), escaping, strict)
    auto actual = templates.render_named(env, root, context(data))
    if actual != expected:
        raise name + ": expected [" + expected + "] got [" + actual + "]"

def bad(str name, str files, str root, str data, bool strict, bool escaping):
    auto env = templates.environment(sources(files), escaping, strict)
    auto caught = False
    try:
        auto output = templates.render_named(env, root, context(data))
    except Exception as e:
        assert "TemplateError" in str(e)
        caught = True
    if not caught:
        raise name + ": expected template error"

def main():
'''
lines=[header]
for c in cases:
    args=', '.join(map(q,[c['name'],json.dumps(c['files'],ensure_ascii=False),c['root'],json.dumps(c['context'],ensure_ascii=False)]))
    if c['error']: lines.append(f"    bad({args}, {c['strict']}, {c['escaping']})\n")
    else: lines.append(f"    check({args}, {q(c['expected'])}, {c['strict']}, {c['escaping']})\n")
lines.append(f'    print("Jinja composition fixtures: {len(cases)} PASS")\n')
(ROOT/'tests/composition_fixtures_test.zap').write_text(''.join(lines))
(ROOT/'tests/fixtures/composition.json').write_text(json.dumps(dict(jinja='3.1.6',markupsafe='3.0.3',cases=cases),indent=2,ensure_ascii=False)+'\n')
print(f'Generated {len(cases)} composition fixtures')
