# elm-translate-icu (CLI)

Generate a type-safe Elm module from your master-language ICU translations.

The generator itself is the pure Elm function `Icu.Codegen.generate`; this
package is a thin Node wrapper that reads a JSON file, runs the generator in a
headless Elm worker, and writes the output.

## Usage

```sh
elm-translate-icu <master.json> --module <ModuleName> [--output <file>]
```

`<master.json>` is a JSON object mapping keys to ICU message strings. Nested
objects are flattened with dots:

```json
{
  "greeting": "Hello, {name}!",
  "inbox": {
    "count": "{count, plural, one {# message} other {# messages}}"
  },
  "price": "Total: {amount, number, ::currency/USD .00}"
}
```

```sh
# write to Translations.elm (path derived from the module name)
elm-translate-icu en.json --module Translations

# custom output path
elm-translate-icu en.json --module App.I18n -o src/App/I18n.elm

# print to stdout (e.g. to pipe through elm-format)
elm-translate-icu en.json --module Translations --stdout | elm-format --stdin
```

Only the **master** language is passed to the generator — it defines the keys
and their argument types. Other locales are loaded as data at runtime via
`Icu.Bundle`, so adding a locale or a translation never requires regenerating.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | success |
| `1` | usage error (bad args, unreadable/invalid JSON) |
| `2` | one or more messages failed to parse as ICU (errors printed per key) |

## Building from source

```sh
npm run build   # elm make src/Worker.elm --optimize --output=worker.js
```
