# Supported syntax and compatibility

This is a Jinja-style engine over JSON contexts, not a full Jinja implementation.
The compatibility oracle is **Jinja 3.1.6 + MarkupSafe 3.0.3**. The checked-in
suite has **246** shared-behavior cases: 55 core, 127 filter/markup, and 64
composition cases. Native regressions separately test conservative differences,
loader safety, diagnostics, resource limits and repeated rendering.

| Area | Supported | Deliberate limits |
| --- | --- | --- |
| Sources | text/HTML, expressions, comments, trimming | no raw/line-statement syntax, configurable delimiters, lstrip_blocks or trim_blocks options |
| Values | JsonValue scalars/arrays/objects | no host objects, Python repr, arbitrary-precision numbers, date objects |
| Expressions | lookup, arithmetic, comparisons, boolean logic, filters/tests, macro calls | no list/dict literals, exponent literals/operators, ternary syntax, host calls or methods |
| Flow | if/elif/else, for/else, set | simple loop target only; no unpacking, loop controls, recursive/filtered loops, set capture or namespaces |
| Composition | extends/block/super, scoped blocks, include/import/from | root-relative string template names; no include name lists, self.block(), super.super(), required blocks or conditional extends |
| Macros | lexical closures, defaults, keywords, call blocks with parameters | no varargs, kwargs, catch-all arguments or host callbacks |
| Loading | explicit memory and trusted filesystem environments | no networking, search-path fallbacks, symlink jail or automatic file reload |
| Output safety | default HTML escaping, explicit safe, safe concatenation/join, tojson | contextual JavaScript/CSS/URL escaping is the application's responsibility |

Supported syntax:

- `{{ expression }}`, `{# comment #}`, `{% tag %}`; `-` inside either end of a
  delimiter trims adjacent whitespace. Ordinary whitespace is preserved.
- Single/double quoted strings (`\\`, `\'`, `\"`, `\n`, `\r`, `\t` escapes),
  decimal integer/float literals, `true/false/none` and `True/False/None`.
- Names, `object.attribute`, `object['key']`, integer array/string indices
  (including negatives), parentheses. String indexing and iteration use Unicode
  codepoints. Names use ASCII letters, digits and underscore.
- `not`, `and`, `or`, `== != < <= > >=`, chained comparisons, `in`/`not in`,
  `+ - * / // %`, unary `+ -`, and string concatenation `~`. Standard Jinja
  precedence: `not` binds below comparisons; `~` below addition. Boolean and
  comparison chains short circuit and boolean operators return an operand.
- Nested `if`/`elif`/`else`/`endif`, `for name in expression`/`else`/`endfor`,
  and `set name = expression`. Loops support arrays, strings and object keys
  in dictionary insertion order. No tuple unpacking or filtered/recursive loops.
- `loop.index`, `index0`, `revindex`, `revindex0`, `length`, `first`, `last`.
  Each loop iteration has local bindings; assignments do not leak to the next
  iteration or out of the loop. Nested loops restore the outer `loop` binding.
  `if` does not introduce a scope. `for`'s `else` runs in its own binding scope.

Missing names/keys/out-of-range indices are undefined: they print as empty,
are false, and propagate through further lookup. Undefined iterables are empty.
Two undefined values compare equal; null is a separate defined value, prints
`None`, and is false. Assigning undefined raises an error. `strict_undefined=True` additionally raises
on printing, truth tests, comparison, lookup through, and iteration of undefined.
`default` and `is defined/undefined` can handle it without consuming it. Numeric operations,
ordering, membership in a scalar, and lookup on a defined scalar raise errors.
Booleans are not numeric arithmetic operands. Objects compare without regard to key order, arrays
in order; null and booleans have distinct types. Collections print using JSON,
not Python repr. Unsupported syntax/tags/filters/tests and invalid call signatures are rejected
during compilation, including inactive branches.
Calls may invoke template macros, `caller`, and `super`; host functions and
methods are never invoked. Macro arity and callable binding are checked at render
time; filter/test signatures and malformed call syntax are checked at compile time.

Integer equality and integer ordering retain i64 precision. Arithmetic uses
binary64 intermediates; integer operands and integer results must stay within
±(2^53−1), otherwise rendering fails rather than silently rounding. Mixed
integer/float arithmetic and ordering follow binary64 precision. `/` produces a
float, `//` floors, and `%` follows the divisor's sign. Nonfinite results and
zero divisors raise errors. Exponent literals/operators and list/object literals
are not part of this foundation.

Filters and tests use Jinja-style calls, for example:

```jinja
{% set heading = title|default('Untitled')|trim %}
<h1>{{ heading }}</h1>
{% for user in users|selectattr('active')|sort(attribute='name') %}
  {{ user.name|upper }}
{% endfor %}
{{ users|map(attribute='name', default='?')|join(', ') }}
{{ missing is undefined }}
```

Positional and keyword arguments are supported; keywords follow positional
arguments. Names below are also the keyword names. Parameters after `=` show
defaults; required parameters have no default.

| Filters | Parameters |
| --- | --- |
| `escape`, `e`, `safe`, `string` | none |
| `default`, `d` | `default_value=''`, `boolean=False` |
| `upper`, `lower`, `title` | none |
| `trim` | `chars=None` |
| `replace` | `old`, `new`, `count=-1` |
| `length`, `count`, `first`, `last`, `reverse`, `list` | none |
| `join` | `d=''`, `attribute=None` |
| `sort` | `reverse=False`, `case_sensitive=False`, `attribute=None` |
| `dictsort` | `case_sensitive=False`, `by='key'`, `reverse=False` |
| `int` | `default=0`, `base=10` |
| `float` | `default=0.0` |
| `abs` | none |
| `round` | `precision=0`, `method='common'` |
| `select`, `reject` | `test` (omitted means truthiness), `argument` (optional) |
| `selectattr`, `rejectattr` | `attribute`, `test` (optional), `argument` (optional) |
| `map` | `filter`, `argument` OR `attribute`, `default` |
| `tojson` | none |

`is` and `is not` support `defined`, `undefined`, `none`, `string`, `number`,
`sequence`, `mapping`, `even`, `odd`, `boolean`, `integer`, `float`, `true`,
`false`, `iterable`, `escaped`, `lower`, `upper`, `callable`; `equalto`/`eq`, `ne`, `lt`,
`le`, `gt`, `ge`, `in`, `divisibleby` take one argument. Following Jinja, boolean
values satisfy `number`, objects and strings satisfy `sequence`, and default
undefined satisfies `sequence`/`iterable`. Strict undefined is not a sequence;
iterating it raises. Arithmetic still requires actual numeric operands.

Markup safety is tracked separately from text. `safe` is an explicit trust
assertion; only use it on HTML you trust. `escape` escapes untrusted text and
marks it trusted; applying it again does not double-escape. Assignment,
`default`, `string`, direct string indexing, and collection filtering/reordering
retain trust. Mixing trusted markup with untrusted text in `+` or `~` escapes
untrusted fragments; autoescaped `join` does the same for items and delimiters.
Trust survives `map('safe')`, `first`/`last`, `list`, `sort`, selection and loops.
Text transformations (`upper/lower/title/trim/replace/reverse`) deliberately
clear trust: transformed content must pass through output escaping. This is a
conservative difference from MarkupSafe methods that retain markup trust.

`{% autoescape false %}...{% endautoescape %}` changes the rendering policy for
that block; blocks can nest and restore the previous policy. Like Jinja,
autoescape blocks introduce a binding scope. The render API's `autoescape`
argument sets the initial policy. The environment selects the initial escaping and undefined policies. Each loaded
template starts with that environment policy; included templates do not inherit
a surrounding `autoescape` block. Macro bodies retain their declaration-time
escaping policy, and their returned markup is trusted according to the call-site
policy. These cases are covered by composition fixtures.

`tojson` sorts object keys, uses JSON spaces and ASCII Unicode escapes (including
surrogate pairs), escapes `< > & '` as Unicode escapes, and returns trusted JSON
for HTML script bodies. It is not safe inside double-quoted HTML attributes;
use an appropriate HTML context. `safe` never serializes objects as HTML.

Compatibility boundaries for this slice:

- Filter/test names are an explicit catalog. Unlisted Jinja built-ins, custom
  filter callbacks, function calls and host object attribute access are absent.
- Filters bind above arithmetic; tests bind like filters. Parenthesize an entire
  arithmetic expression before applying a test, e.g. `(x + 1) is even`.
- Collection filters are eager, bounded arrays rather than Python generators.
  Filters returning arrays print JSON; use `join`, loops or indexing for portable
  output. Missing mapped attributes retain undefined status for subsequent tests,
  selection and `default`. Nested host collections remain JSON values.
- `map` delegates one optional argument to a named filter, or accepts a dotted
  `attribute`/integer index with an optional default. Recursive `map('map')`,
  multiple forwarded arguments and attribute-plus-filter modes are rejected.
- `sort` supports one dotted attribute or integer index; multi-attribute sorting
  is not provided. Sorting is stable, with ASCII case folding by default.
  `dictsort` returns key/value pairs as two-element arrays.
- Case folding/title/whitespace behavior follows Zap's ASCII string methods;
  indexing, length, reverse and JSON escaping handle Unicode codepoints. No
  locale-dependent or full Unicode casing is claimed.
- Numeric conversion accepts finite decimal values, including exponent strings;
  `int` also supports bases 2/8/10/16. Invalid/out-of-range conversions return the
  supplied default; undefined raises. Python underscore numeric syntax and
  nonfinite values are not supported. Numeric defaults can be any template value.
- `round` supports precision −15…15 and `common` (ties to even), `ceil`, `floor`.
  Decimal precision uses binary64 scaling, so some decimal half cases can differ
  from Python's correctly rounded decimal conversion (e.g. `2.675` at precision 2).
- `tojson` does not accept indentation/options; configured JSON serializers and
  Python-specific types are not supported. Output and execution budgets apply.
- Unknown dynamic filters/tests supplied to collection filters also raise on
  empty input, making misspellings deterministic rather than lazily ignored.


## Composition and binding scope

`extends` must be a single top-level tag. Child setup may contain whitespace,
assignments, macro declarations, imports and blocks; other top-level output or
control flow is rejected. Child declarations run before the parent is resolved.
Multi-level block overrides choose the most-derived implementation; `super()`
renders the next implementation and returns markup. Block names are unique within
one source. A block may be nested inside another block.

Blocks introduce local bindings and normally see the template's root bindings.
`{% block cell scoped %}` also exposes bindings at its invocation site, such as
loop variables; an override inherits the base block's scoped invocation context.
Assignments inside blocks/macros/includes do not change the caller's bindings.

`include` accepts `with context` (default), `without context`, and `ignore missing`
(before the context suffix). Includes use their own inheritance chain. Missing
suppression covers absent files only, not syntax errors, unsafe names or execution
errors. Names are relative to the loader root, including inside nested directories.

`import 'file' as module` and `from 'file' import name as alias, other` default to
**without context**. `with context` takes a binding snapshot at the import site.
Environment globals remain available to default-isolated imports/includes.
Only declared root-level variables/macros/imports are exported, not incoming
context or globals. Names starting with `_` are private. A missing `from` export
raises immediately, whereas Jinja can defer that failure until value use.
Imported namespaces allow direct dot/item lookup; namespace objects cannot be
printed or traversed by attribute-based collection filters.

Macros capture their lexical binding dictionary, so later assignments in that
scope are visible. Defaults are evaluated on invocation and can reference earlier
parameters. Missing required parameters become undefined; strict policy raises
when such a value is consumed. A macro's local assignments stay local. Calls can
only target template-created macros, `caller`, and `super`; JSON input cannot
forge executable references. Macro results retain the markup rules described
above. Direct macro aliases and imported macro calls are supported.

`{% call wrapper() %}...{% endcall %}` passes a lexical `caller` callback;
`{% call(item) wrapper() %}` gives that callback a parameter. Nested call blocks
and imported wrappers are supported. No Python runtime is involved.

## Diagnostics and bounded execution

Errors contain `TemplateError at character N`, using one-based source codepoints.
Loaded-template and macro failures include template/macro names and the include
or inheritance chain. Structural failures can point at tag content/end of source;
budget failures may point at character 1. Exception formatting is not a stable API.
Unterminated comments are rejected even though Jinja tolerates some end-of-file
comment forms. Literal escapes are limited to the list above.

| Resource | Bound |
| --- | --- |
| Source / emitted or captured string | 1,048,576 codepoints each |
| Filesystem source before read | 4,194,304 bytes |
| Syntax/expression nodes | 10,000 each; scanning rejects more than 10,000 segments |
| Parse / value-comparison nesting | 64 |
| Expression evaluation nesting | 128 |
| Render / macro/block depth | 64 shared internal levels; nested constructs consume levels |
| Template execution depth | 32 shared internal levels |
| Inheritance chain | 32 templates |
| Iteration / execution | 100,000 items; 100,000 steps shared by expressions, filters, comparisons and loops |
| Macro/call parameters | 16 |
| Macro references / exported values | 10,000 each per render |
| Compiled cache | 256 templates; the next insertion clears the cache |
| Loader name | 1,024 codepoints |

Captured macro strings have their own output counter; final insertion counts
against the final output counter. All captures share execution/depth budgets.
Sources and literal scanning use codepoint arrays. Replacement uses KMP matching;
sorting uses stable mergesort. These choices avoid known repeated-prefix and
Unicode slicing pathologies. Host-provided contexts must be finite JSON trees.
Bounds are defensive limits, not a security sandbox or a promise of fixed total
memory usage for arbitrarily large host data.

## Verification and fixture regeneration

`sh tools/run-tests.sh` executes native assertions; `--check` performs frontend/IR
checks. `sh tools/check-package.sh` packages the library and compiles/runs an
external consumer. `sh tools/check-example.sh` does the same for the HTTP example.
All run in pinned native CI without installing Jinja or MarkupSafe.

For generation-only verification, create a temporary Python venv, install
`tools/fixtures-requirements.txt`, then run:

```sh
FIXTURE_PYTHON=/path/to/venv/bin/python ZAP=/path/to/zap sh tools/check-fixtures.sh
```

This regenerates all six JSON/Zap artifacts in a temporary directory, formats the
Zap runners, and compares them byte-for-byte. `--write` updates checked-in files.
The three generators assert exact dependency versions. CI has a separate oracle
regeneration job; Python is never a dependency of library consumers.

References: [Jinja filters](https://github.com/pallets/jinja/blob/3.1.6/src/jinja2/filters.py),
[tests](https://github.com/pallets/jinja/blob/3.1.6/src/jinja2/tests.py), and
[template documentation](https://jinja.palletsprojects.com/en/stable/templates/).
