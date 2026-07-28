# elm-translate-icu

Type-safe internationalization for Elm using the [ICU MessageFormat](https://formatjs.github.io/docs/core-concepts/icu-syntax)
syntax — the same message format used by [FormatJS](https://formatjs.github.io/)
and `intl-messageformat` across the JavaScript ecosystem.

Write your translations as ICU messages, and a code generator turns them into
strongly-typed Elm functions. Plurals, gender selection, and locale-correct
number/date formatting are handled for you via the browser's `Intl` API.

```elm
-- from: "greeting": "Hello, {name}!"
Translations.greeting bundle { name = "Alice" }
--> "Hello, Alice!"

-- from: "inbox": "{count, plural, =0 {No messages} one {# message} other {# messages}}"
Translations.inbox bundle { count = 3 }
--> "3 messages"
```

## Why

- **Type-safe.** Each message becomes a function whose arguments are checked by
  the compiler. Reference a missing variable or pass the wrong type and your
  build fails — not your production app.
- **Standard format.** ICU MessageFormat is widely supported by translation
  tooling and TMS platforms. Your `.json` files are portable.
- **Correct plurals and formatting.** Plural category selection and
  number/date/currency formatting are delegated to the browser `Intl` API, so
  they follow CLDR rules for every locale.
- **Add languages without redeploying.** Only your reference language drives
  code generation. Additional locales load as plain JSON data at runtime, so
  translators can ship new languages and fixes without a recompile.

## How it works

```
reference.json ──▶  generate  ──▶  Translations.elm   (typed functions)
                                        │
   other locales' JSON  ─────▶  loaded at runtime  ─────▶  formatted strings
```

You maintain one **reference language** file (usually English). The generator
reads it and emits a `Translations` module with one function per key. Other
languages are loaded from JSON at runtime and matched to the user's locale;
any key a translation is missing falls back to the reference language.

## Install

```sh
elm install gampleman/elm-translate-icu
```

The library needs the browser `Intl` API, which you pass in from JavaScript as a
flag when your app starts:

```js
// index.js
Elm.Main.init({ flags: { intl: window.Intl } });
```

## Getting started

**1. Write your reference translations** as ICU messages in a JSON file:

```json
{
  "greeting": "Hello, {name}!",
  "inbox": "{count, plural, =0 {No messages} one {# message} other {# messages}}",
  "lastSeen": "Last seen {when, date, long}",
  "price": "Total: {amount, number, ::currency/USD}"
}
```

**2. Generate the typed module** with the [CLI](#cli):

```sh
npx elm-translate-icu en.json --module Translations --output src/Translations.elm
```

This produces functions whose argument records are inferred from each message:

```elm
greeting  : Bundle -> { name : String } -> String
inbox     : Bundle -> { count : Int } -> String
lastSeen  : Bundle -> { when : Time.Posix } -> String
price     : Bundle -> { amount : Float } -> String
```

**3. Initialize a bundle** and call the functions:

```elm
import Icu.Bundle exposing (Bundle)
import Icu.Locale as Locale
import Intl exposing (Intl)
import Translations

type alias Model =
    { bundle : Bundle }

init : Intl -> Model
init intl =
    let
        locale =
            Locale.fromString "en-US" |> Maybe.withDefault Locale.default
    in
    { bundle = Translations.init intl locale }

view : Model -> Html msg
view model =
    text (Translations.greeting model.bundle { name = "Alice" })
```

**4. Load another language at runtime** and switch to it — no recompile needed:

```elm
import Icu.Bundle as Bundle
import Icu.Locale as Locale

-- `frenchJson` is the contents of fr.json fetched at runtime
switchToFrench : String -> Bundle -> Bundle
switchToFrench frenchJson bundle =
    case ( Locale.fromString "fr", Bundle.decodeMessages frenchJson ) of
        ( Just locale, Ok ( messages, _ ) ) ->
            Bundle.withLocale locale messages bundle

        _ ->
            bundle
```

Keys absent from `fr.json` automatically fall back to the reference language.

### Choosing a locale for the user

`Icu.Locale` implements BCP 47 matching, so you can pick the best available
translation from a browser's language preferences:

```elm
Locale.negotiate
    (List.filterMap Locale.fromString [ "en", "fr", "de" ])   -- what you ship
    (List.filterMap Locale.fromString [ "fr-CA", "fr", "en" ]) -- what the user wants
    |> Maybe.map Locale.toString
--> Just "fr"
```

## Supported ICU syntax

The full ICU MessageFormat grammar is supported:

| Feature | Example |
|---|---|
| Simple arguments | `Hello, {name}!` |
| Numbers | `{n, number}`, `{n, number, ::currency/USD}` |
| Dates & times | `{d, date, long}`, `{t, time, ::Hms}` |
| Select (e.g. gender) | `{gender, select, male {he} female {she} other {they}}` |
| Plurals | `{count, plural, one {# item} other {# items}}` |
| Ordinals | `{n, selectordinal, one {#st} two {#nd} few {#rd} other {#th}}` |
| Plural offset & exact matches | `{n, plural, offset:1 =0 {none} one {#} other {# more}}` |
| Nested messages | `{c, plural, other {{g, select, ...} things}}` |
| Quoting | `'{'` → literal `{`, `''` → literal `'` |

### Number formats

`number` placeholders accept ICU number skeletons as well as the `integer` and
`percent` keywords:

| Skeleton | Effect |
|---|---|
| `::currency/USD` | currency, USD |
| `::.00` | exactly 2 fraction digits |
| `::.0#` | 1–2 fraction digits |
| `::@@@` | 3 significant digits |
| `::compact-short` | compact notation (e.g. `1.2K`) |
| `::scientific` / `::engineering` | scientific / engineering notation |
| `::percent` | percent |
| `::unit/length-meter` | unit formatting |
| `::group-off` | disable digit grouping |
| `::sign-always` / `::sign-except-zero` | sign display |

Tokens combine and later tokens win: `::currency/USD compact-short .00`.

### Date & time formats

`date` / `time` placeholders accept the styles `short`, `medium`, `long`, and
`full`, as well as field-level ICU skeletons where each field's length sets its
width:

| Skeleton | Renders |
|---|---|
| `yMMMd` | year (numeric), month (short), day (numeric) |
| `yyMM` | 2-digit year and month |
| `MMMM` | full month name (`M`→numeric, `MM`→2-digit, `MMM`→short, `MMMMM`→narrow) |
| `EEEE` | full weekday name |
| `Hms` | 24-hour time with minutes and seconds |
| `hh` | 2-digit 12-hour hour |

Field symbols: `y` `M` `L` `d` `E` `e` `c` `G` `h` `H` `K` `k` `m` `s` `a` `z`
`v` `V`. Unknown symbols are ignored; a leading `::` is optional.

## CLI

```sh
elm-translate-icu <reference.json> --module <ModuleName> [--output <file>]
```

Nested JSON objects are flattened with dots (`{ "inbox": { "count": ... } }`
becomes the key `inbox.count`). See [`cli/README.md`](cli/README.md) for all
options and exit codes.

The generator is also available as the pure Elm function
`Icu.Codegen.generate : Options -> List (String, String) -> Result _ String`,
so it can be driven directly from your own Elm build tooling.

## Parsing ICU directly

If you only need the parser — for tooling, validation, or your own formatter —
`Icu.Parser` and `Icu.Ast` are usable on their own:

```elm
Icu.Parser.parse "Hello, {name}!"
--> Ok [ Literal "Hello, ", Argument "name", Literal "!" ]
```

## Development

```sh
elm-test                          # run the test suite
elm-format --yes src/ tests/      # format
```

## License

BSD-3-Clause. See [LICENSE](LICENSE).
