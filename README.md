# templates

Pure-Zap text and HTML templates. Implements
[zaplang-io/zap#313](https://github.com/zaplang-io/zap/issues/313).
This first implementation covers the rendering foundation; filters, safe markup,
loaders, inheritance and macros are tracked separately and are not available yet.

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
`render_compiled(template, context, autoescape=True)` renders it;
`render(source, context, autoescape=True)` compiles and renders in one call.
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
`None`, and is false. Assigning undefined raises an error. Numeric operations,
ordering, membership in a scalar, and lookup on a defined scalar raise errors.
Booleans are not numbers. Objects compare without regard to key order, arrays
in order; null and booleans have distinct types. Collections print using JSON,
not Python repr. Unsupported syntax/tags/filters are rejected during compilation.
There are no function calls or host-code execution.

Integer equality and integer ordering retain i64 precision. Arithmetic uses
binary64 intermediates; integer operands and integer results must stay within
±(2^53−1), otherwise rendering fails rather than silently rounding. Mixed
integer/float arithmetic and ordering follow binary64 precision. `/` produces a
float, `//` floors, and `%` follows the divisor's sign. Nonfinite results and
zero divisors raise errors. Exponent literals/operators and list/object literals
are not part of this foundation.

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
CI runs formatting, native assertions and the package consumer using a pinned
published Zap image, on pull requests and main pushes only.

Agent-sized M build sequence:

1. [Parser, expressions, renderer](https://github.com/zaplang-io/templates/issues/1).
2. [Filters, tests, safe markup](https://github.com/zaplang-io/templates/issues/2).
3. [Loaders and template composition](https://github.com/zaplang-io/templates/issues/3).
4. [Compatibility, hardening, release](https://github.com/zaplang-io/templates/issues/4).

Each issue includes implementation and meaningful acceptance tests. PRs remain
unmerged until individually reviewed and explicitly approved by the user.
