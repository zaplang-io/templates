# templates

Pure-Zap text and HTML templates: compiled rendering, filters, safe markup,
inheritance, includes, imports and lexical macros. Implements
[zaplang-io/zap#313](https://github.com/zaplang-io/zap/issues/313).
Jinja-style syntax over JSON contexts; [supported syntax and limits](docs/SUPPORT.md)
are explicit. No Python runtime or web framework dependency.

```zap
import templates

def main():
    dict[str, JsonValue] context = {"name": JsonValue.Str("<Ada>")}
    auto page = templates.compile("Hello {{ name }}!")
    assert templates.render_compiled(page, context) == "Hello &lt;Ada&gt;!"

    dict[str, str] sources = {
        "base": "<main>{% block body %}{% endblock %}</main>",
        "page": "{% extends 'base' %}{% block body %}{{name|upper}}{% endblock %}",
    }
    auto env = templates.environment(sources, True, True)
    assert templates.render_named(env, "page", context) == "<main>&lt;ADA&gt;</main>"
```

Add a path dependency during development, then run `zap zenv create --no-venv`
in the consuming project:

```toml
[dependencies]
templates = { path = "../templates" }
```

No registry publication or release tag is claimed yet. The package manifest is
version `0.1.0`; see the [release checklist](docs/RELEASING.md) before publishing.

| API | Behavior |
| --- | --- |
| `compile(source, name='<string>')` | validate source and return reusable syntax |
| `render(source, context, autoescape=True, strict_undefined=False)` | compile and render a standalone source |
| `render_compiled(template, context, autoescape=True, strict_undefined=False)` | render standalone syntax with fresh state |
| `environment(sources, autoescape=True, strict_undefined=False)` | copy an explicit `dict[str,str]` source namespace |
| `filesystem_environment(root, autoescape=True, strict_undefined=False)` | load names under an explicitly selected trusted directory |
| `render_named(env, name, context)` | render a cached named template and its composition dependencies |
| `get_template(env, name)` | load/compile/cache named syntax |
| `set_source(env, name, source)` | add/replace an in-memory override and invalidate all compiled entries |
| `invalidate(env)` | clear all compiled entries, including dependency snapshots |
| `normalize_name(name)` | validate/canonicalize a relative loader name |
| `escape(text)` | escape HTML `& < > " '` characters |

Contexts are `dict[str, JsonValue]`. Host contexts are not mutated. Use
`render_named` for composition; standalone `render_compiled` has no loader.
`env.globals` supplies JSON bindings to every render, including isolated imports.
Request bindings override globals. Compiled syntax is treated as immutable.

Escaping is **on by default**, including `.txt` templates. Pass `False` for the
`autoescape` argument to generate plain text. `safe` explicitly trusts HTML;
`escape` escapes untrusted content without double-escaping trusted markup.
Use trusted template sources. HTML escaping does not validate URLs or make values
safe in CSS, JavaScript or unquoted attributes. `tojson` supports HTML script
bodies; see the [HTML trust rules](docs/SUPPORT.md).

Loader names are root-relative, never relative to the including file. They reject
absolute paths, `..`, backslashes, drive/scheme separators and control characters.
Filesystem loaders require a **trusted directory tree**: the pinned Zap API lacks
symlink/canonical-path inspection, so this is lexical traversal protection, not a
symlink jail. Do not allow untrusted users to create files/symlinks under the root.
Memory source overrides take precedence over files. Files are compiled snapshots;
changes require `invalidate(env)`. The cache holds at most 256 entries and clears
on the next insertion. Imports cache syntax only, never request data or closures.

Rendering state, closures, namespaces, budgets and block chains are per call.
Environment caches/globals/source maps are mutable and not thread-safe; use an
environment per worker or synchronize all access. Do not mutate public AST fields.

Run the standalone [HTML application](examples/html_app), which serves one
loopback HTTP request on an ephemeral port and exits:

```sh
sh tools/check-example.sh
```

It consumes the package through a path dependency and exercises multi-file
inheritance, `super()`, an imported macro, a call block, includes and escaping.
[Migration examples](docs/MIGRATING.md) explain adapting Python/Jinja applications.

Validation with a codegen-enabled Zap (`ZAP=/path/to/zap` overrides the executable):

```sh
zap fmt --check src tests examples
sh tools/run-tests.sh
sh tools/check-package.sh
sh tools/check-example.sh
```

The pinned CI toolchain runs on pull requests and main pushes only. The suite
contains **246 Jinja differential fixtures**, plus markup, filesystem/cache,
cycle, Unicode, resource-limit, recovery and repeated-render regressions.
Fixture generation uses pinned Jinja 3.1.6/MarkupSafe 3.0.3 in a separate workflow;
production rendering and native fixture execution remain pure Zap.

The four agent-sized M implementation slices are
[rendering](https://github.com/zaplang-io/templates/issues/1),
[filters/markup](https://github.com/zaplang-io/templates/issues/2),
[composition](https://github.com/zaplang-io/templates/issues/3), and
[conformance/release readiness](https://github.com/zaplang-io/templates/issues/4).
PRs require individual user review and explicit merge approval. The parent tracker
stays open until the final reviewed PR is merged.
