# elm-translate-icu

An Elm library for the [ICU MessageFormat](https://formatjs.github.io/docs/core-concepts/icu-syntax)
syntax used by [FormatJS](https://formatjs.github.io/) and `intl-messageformat`.

At the time of writing, no Elm package parses or formats ICU MessageFormat.
The existing i18n packages (`ChristophP/elm-i18next`, `andreasewering/elm-placeholder`,
`lukewestby/elm-string-interpolate`, `ccapndave/elm-translator`) support only
simple `{var}` interpolation, and `andreasewering/travelm-agency` targets the
*Fluent* format — a deliberate ICU alternative, not ICU. This package fills
that gap.

The architecture is modeled on travelm-agency's clean two-stage design
(parser → shared AST → generator), but is an independent implementation.

## Status

| Component | State |
|---|---|
| `Icu.Ast` — the message AST | ✅ done |
| `Icu.Parser` — ICU string → AST | ✅ done, full syntax |
| `Icu.Locale` — BCP 47 parse + resolution | ✅ done |
| `Icu.Format` — Intl-backed runtime formatting | ✅ done |
| `Icu.Bundle` — runtime translation store | ✅ done |
| `Icu.Codegen` — master-language code generator | ✅ done |
| `Internal.Skeleton` — ICU number + date skeleton → Intl options | ✅ done |
| `cli/` — Node CLI wrapper (`elm-translate-icu`) | ✅ done |

109 tests green. The generated code is verified to compile against the runtime
library end-to-end.

## CLI

A Node wrapper drives the pure generator from the command line:

```sh
elm-translate-icu en.json --module Translations
```

See [`cli/README.md`](cli/README.md). The generator itself
(`Icu.Codegen.generate`) is a pure Elm function, so it can also be invoked from
any Elm build tooling directly.

## Number skeletons

`number` placeholders accept ICU number skeletons in addition to the legacy
`integer` / `percent` styles:

| Skeleton | Effect |
|---|---|
| `::currency/USD` | currency style, USD |
| `::.00` | exactly 2 fraction digits |
| `::.0#` | 1–2 fraction digits |
| `::@@@` | 3 significant digits |
| `::compact-short` | compact notation (e.g. `1.2K`) |
| `::scientific` / `::engineering` | scientific / engineering notation |
| `::percent` | percent style |
| `::unit/length-meter` | unit style |
| `::group-off` | disable digit grouping |
| `::sign-always` / `::sign-except-zero` | sign display |

Tokens combine (`::currency/USD compact-short .00`); later tokens override
earlier ones for the same option.

## Date skeletons

`date` / `time` placeholders accept both the legacy styles (`short`, `medium`,
`long`, `full`) and field-level ICU date skeletons, which map onto
`Intl.DateTimeFormat` options. The run length of each field symbol selects its
representation:

| Skeleton | Effect |
|---|---|
| `yMMMd` | `year: numeric, month: short, day: numeric` |
| `yyMM` | 2-digit year and month |
| `MMMM` | full month name (`M`→numeric, `MM`→2-digit, `MMM`→short, `MMMMM`→narrow) |
| `EEEE` | full weekday name (`E`→short, `EEEEE`→narrow) |
| `Hms` | 24-hour time with minutes and seconds |
| `hh` | 2-digit 12-hour hour |
| `z` | time-zone name |

Supported field symbols: `y`/`Y` (year), `M`/`L` (month), `d` (day), `E`/`e`/`c`
(weekday), `G` (era), `h`/`H`/`K`/`k` (hour), `m` (minute), `s` (second), `a`
(AM/PM), `z`/`v`/`V` (time zone). Unknown symbols are ignored. A leading `::` is
optional.

## Supported ICU syntax

The parser handles the full ICU MessageFormat grammar:

- Simple arguments — `{name}`
- Number / date / time with styles and skeletons — `{n, number, ::currency/USD}`, `{d, date, long}`
- `select` — `{gender, select, male {he} female {she} other {they}}`
- `plural` and `selectordinal`, including `offset:N`, exact matches (`=0`), and
  the `#` pound placeholder — `{count, plural, one {# item} other {# items}}`
- Nested messages inside branches
- ICU quoting — `'{'`, `''`, and quoted sections

```elm
import Icu.Parser

Icu.Parser.parse "Hello, {name}!"
--> Ok [ Literal "Hello, ", Argument "name", Literal "!" ]
```

## Design direction

Codegen is driven by a single **master (reference) language**: its keys and
message shapes generate a type-safe Elm API. Other locales' translations load
as runtime data, so **adding a locale or a translation does not require a
recompile** — only changes to the master language's set of keys/arguments do.
Locale selection is resolved at runtime (BCP 47 matching), and CLDR-dependent
formatting (plural category selection, number/date formatting) is delegated to
the browser `Intl` API via a proxy, following the `anmolitor/intl-proxy`
approach.

### Pipeline

```
master ICU JSON ──▶ Icu.Codegen.generate ──▶ Translations.elm (typed API)
                                                     │
runtime locale JSON ──▶ Icu.Bundle ◀─────────────────┘
                          │
                          ▼
                    Icu.Format (Intl-backed) ──▶ final String
```

`Icu.Codegen` is a **pure function** (`(key, ICU string) pairs → Elm source`),
so it runs anywhere Elm runs — a Node build step, a test, an editor plugin. It
emits one function per key, I18n argument first, with a typed record of the
message's arguments:

```elm
greeting  : Bundle -> { name : String } -> String
inboxCount : Bundle -> { count : Int, name : String } -> String
welcome   : Bundle -> String    -- no arguments
```

Argument types are inferred from usage: bare `{x}` and `select` → `String`,
`number` → `Float`, `plural`/`selectordinal` → `Int`, `date`/`time` →
`Time.Posix`.

## Development

```sh
elm make src/Icu/Parser.elm --output=/dev/null   # typecheck
elm-test                                          # run the suite
elm-format --yes src/ tests/                      # format
```
