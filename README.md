# templates

Pure-Zap text and HTML templates. Implements
[zaplang-io/zap#313](https://github.com/zaplang-io/zap/issues/313).
Includes compiled rendering, filters, built-in tests, safe markup and undefined
policies. Loaders, inheritance and macros remain tracked in issue #3.

```zap
import templates

def main():
    dict[str, JsonValue] context = {"name": JsonValue.Str("<Ada>")}
    auto page = templates.compile("Hello {{ name }}!")
    assert templates.render_compiled(page, context) == "Hello &lt;Ada&gt;!"
    assert templates.render("{{ 2 + 3 }}", context) == "5"
```

Use a path dependency while developing:

```toml
[dependencies]
templates = { path = "../templates" }
```

Run `zap zenv create --no-venv` in the consuming project. The runtime has no
Python dependency. No published registry version is claimed yet.

`compile(source)` validates all branches and returns a reusable `Template`.
`render_compiled(template, context, autoescape=True, strict_undefined=False)`
renders it; `render(source, context, autoescape=True, strict_undefined=False)`
compiles and renders in one call.
`context` is a `dict[str, JsonValue]`. Rendering copies the binding dictionary;
assignments never modify the caller's bindings or context objects. Compiled nodes
are treated as immutable; rendering state is allocated per call. Do not manually
mutate the public compiler structures or construct invalid syntax nodes.

HTML escaping is **on by default**, including for `.txt` sources (there is no
filename loader yet). `& < > " '` become `&amp; &lt; &gt; &#34; &#39;`.
Pass `False` as the last argument for text output. `escape(text)` exposes the
same escaping. Static template text is trusted. HTML escaping is suitable for
HTML text and quoted attributes; it does not validate URLs or make values safe
inside JavaScript, CSS, unquoted attributes or executable template source.

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
Booleans are not numbers. Objects compare without regard to key order, arrays
in order; null and booleans have distinct types. Collections print using JSON,
not Python repr. Unsupported syntax/tags/filters/tests and invalid call signatures are rejected
during compilation, including inactive branches.
There are no function calls or host-code execution.

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
`false`, `iterable`, `escaped`, `lower`, `upper`; `equalto`/`eq`, `ne`, `lt`,
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
argument sets the initial policy. Environment/loader configuration follows in #3.

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

Errors carry `TemplateError at character N` (one-based source codepoint offset).
Structural errors point at the tag content or end of source; budget errors can
point at character 1. Limits: 1,048,576 source/output characters, 10,000 syntax
and expression nodes each, 64 parse/value-comparison nesting, 128 expression
evaluation nesting, 64 render nesting, 100,000 loop items and 100,000 evaluation
steps shared by nested loops and expressions. Contexts must be finite JSON trees.
These are defensive execution bounds, not a sandbox for untrusted template authors
or arbitrarily large host-supplied context objects.

Run `sh tools/run-tests.sh` with a codegen-enabled `zap` on PATH (or set `ZAP`).
`sh tools/run-tests.sh --check` performs frontend/IR checks.
`sh tools/check-package.sh` validates packaging and runs a separate consumer.
CI runs formatting, native assertions (including 127 Jinja differential fixtures)
and the package consumer using a pinned
published Zap image, on pull requests and main pushes only.

Expected outputs/errors are checked into `tests/fixtures/filters.json` and the
pure-Zap `tests/filters_fixtures_test.zap` runner. Regenerate with a temporary
Python environment using `tools/fixtures-requirements.txt`, then run
`python tools/generate-filter-fixtures.py` and `zap fmt tests`.
Jinja 3.1.6 and MarkupSafe 3.0.3 are generation-only dependencies; CI and package
consumers do not install or execute them. Differential fixtures assert the shared
supported behavior; `markup_test.zap` covers deliberate conservative differences.
Upstream references: [Jinja filters](https://github.com/pallets/jinja/blob/3.1.6/src/jinja2/filters.py)
and [tests](https://github.com/pallets/jinja/blob/3.1.6/src/jinja2/tests.py).

Agent-sized M build sequence:

1. [Parser, expressions, renderer](https://github.com/zaplang-io/templates/issues/1).
2. [Filters, tests, safe markup](https://github.com/zaplang-io/templates/issues/2).
3. [Loaders and template composition](https://github.com/zaplang-io/templates/issues/3).
4. [Compatibility, hardening, release](https://github.com/zaplang-io/templates/issues/4).

Each issue includes implementation and meaningful acceptance tests. PRs remain
unmerged until individually reviewed and explicitly approved by the user.
