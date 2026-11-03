# Migrating a Jinja-style application

The source language is a documented Jinja subset. Start with the
[support matrix](SUPPORT.md); do not assume an arbitrary existing Python template
will render identically.

## Pass JSON data explicitly

Replace Python objects, methods and implicit globals with JSON-compatible
fields prepared by the application:

```zap
import templates

def main():
    dict[str, str] pages = {"profile": "<h1>{{ user.name }}</h1>"}
    auto env = templates.environment(pages, True, True)
    dict[str, JsonValue] context = {"user": json.loads("{\"name\":\"Ada <script>\"}")}
    assert templates.render_named(env, "profile", context) == "<h1>Ada &lt;script&gt;</h1>"
```

Precompute URLs, dates, complex business logic and custom filter transformations
in Zap. The template cannot call host methods or Python functions. Prepare
arrays/objects in the context rather than constructing them with template literals.
Use loops with one target; dictionary iteration yields keys, and `dictsort`
yields two-element arrays accessed as `pair[0]` and `pair[1]`.

## Select a loader and undefined policy

`environment(sources, True, True)` uses an explicit in-memory source namespace,
HTML escaping, and strict undefined. For trusted application files, use
`filesystem_environment("pages", True, True)`. All loaded names are root-relative;
`include 'partials/header.html'` has the same meaning in every directory.

Default undefined prints as empty and iterates as empty. Strict undefined catches
missing data when consumed. `{{ optional|default('fallback') }}` and
`{% if optional is defined %}` work with strict policy. A missing intermediate
object (`missing.name`) still raises under strict policy.

Use `env.globals` for JSON values common to every request; request context wins.
Use `set_source`/`invalidate` after template changes. There is no automatic file
mtime reload or implicit environment-wide request-context cache.

## Preserve explicit module boundaries

```jinja
{% extends 'layout.html' %}
{% import 'components.html' as ui %}
{% block body %}
  {% call ui.card(title) %}
    {% for user in users %}{% include 'row.html' %}{% endfor %}
  {% endcall %}
{% endblock %}
```

Imports do not see request data unless you add `with context`; includes do by
default. Avoid importing request-specific data into reusable component libraries.
Pass macro arguments explicitly. A macro can read later assignments in its
lexical scope; its defaults are evaluated when called. Varargs, kwargs and custom
callbacks are absent. Only declared non-private root bindings are exported.

Blocks do not see local loop bindings unless the base declares `block name scoped`.
Use `super()` for the next override. Put child output inside blocks; conditional
inheritance and arbitrary top-level child control flow are unsupported.

## Keep HTML trust narrow

Normal interpolation escapes. `safe` declares content already trusted; it does not
sanitize HTML. Safe concatenation/join escapes untrusted fragments. Case, trim,
replace and reverse transformations deliberately clear trust, unlike some
MarkupSafe operations; output can therefore gain an additional escape layer.
Prefer composing markup with templates/macros over transforming trusted HTML.

Each loaded template starts with the environment's escaping policy, even when
included inside `autoescape false`. Macro bodies keep their declaration-time
policy. `tojson` is for HTML script bodies, not double-quoted HTML attributes.
URL validation and JavaScript/CSS context handling belong in the application.

## Account for representation and numeric differences

Collections print as JSON, not Python repr or generator object names. Render
collections through loops, `join`, indexing or `tojson`. Booleans do not coerce
into arithmetic numbers, though `is number` follows Jinja's boolean classification.
Integer arithmetic is limited to exact binary64 intermediates; integer comparison
retains i64 precision. Case folding and title/strip behavior are ASCII-oriented;
length, indexing, reverse and JSON escapes use Unicode codepoints.

Use integer minor units or application-side decimal handling for decimal-sensitive
values. `round` uses binary64 scaling and can differ from Python at decimal half
cases. Verify a port using the checked-in fixture approach for the application's
actual templates and inputs.
