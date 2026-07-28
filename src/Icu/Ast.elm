module Icu.Ast exposing
    ( Message, Part(..)
    , PluralForm, PluralSelector(..)
    , argumentNames
    )

{-| The abstract syntax tree for an ICU MessageFormat message.

A parsed message is a list of [`Part`](#Part)s. This module is the shared
representation that a parser produces and that a formatter or code generator
consumes — it deliberately mirrors the structure of the
[ICU syntax](https://formatjs.github.io/docs/core-concepts/icu-syntax).

@docs Message, Part
@docs PluralForm, PluralSelector
@docs argumentNames

-}


{-| A message is an ordered sequence of parts. Rendering the message means
rendering each part in turn and concatenating the results.
-}
type alias Message =
    List Part


{-| A single piece of a message.

  - `Literal` — raw text, e.g. `Hello`. ICU quoting (`''`, `'{'`) is resolved
    by the parser, so a `Literal` holds the already-unescaped text.
  - `Argument` — a bare placeholder `{name}`.
  - `Number` / `Date` / `Time` — a typed placeholder such as `{n, number}` or
    `{d, date, long}`, with an optional style/skeleton string.
  - `Select` — `{g, select, ...}`, a plain keyword switch with a mandatory
    `other` branch.
  - `Plural` — `{n, plural, ...}` or `{n, selectordinal, ...}`. `ordinal`
    distinguishes the two; `offset` carries `offset:N`.
  - `Pound` — the `#` placeholder inside a plural branch, replaced by the
    (offset-adjusted) argument value.

-}
type Part
    = Literal String
    | Argument String
    | Number String (Maybe String)
    | Date String (Maybe String)
    | Time String (Maybe String)
    | Select String (List ( String, Message )) Message
    | Plural
        { arg : String
        , ordinal : Bool
        , offset : Int
        , forms : List PluralForm
        , other : Message
        }
    | Pound


{-| One branch of a `plural` / `selectordinal` block, e.g. `one {...}` or
`=0 {...}`.
-}
type alias PluralForm =
    ( PluralSelector, Message )


{-| Selects which plural branch applies: either an exact literal match
(`=0`, `=1`, ...) or a CLDR plural keyword (`zero`, `one`, `two`, `few`,
`many`). The `other` branch is stored separately on [`Part.Plural`](#Part).
-}
type PluralSelector
    = Exact Int
    | Keyword String


{-| Collect every argument name referenced anywhere in a message, including
those nested inside `select` and `plural` branches. Order of first appearance
is preserved and duplicates are removed.
-}
argumentNames : Message -> List String
argumentNames message =
    -- `collectNames` prepends, so the raw list is in reverse appearance order.
    -- Reverse it, then dedup keeping the first occurrence.
    collectNames message []
        |> List.reverse
        |> List.foldl
            (\name acc ->
                if List.member name acc then
                    acc

                else
                    name :: acc
            )
            []
        |> List.reverse


collectNames : Message -> List String -> List String
collectNames message acc =
    List.foldl collectNamesPart acc message


collectNamesPart : Part -> List String -> List String
collectNamesPart part acc =
    case part of
        Literal _ ->
            acc

        Pound ->
            acc

        Argument name ->
            name :: acc

        Number name _ ->
            name :: acc

        Date name _ ->
            name :: acc

        Time name _ ->
            name :: acc

        Select name cases other ->
            let
                withCases =
                    List.foldl (\( _, msg ) a -> collectNames msg a) (name :: acc) cases
            in
            collectNames other withCases

        Plural { arg, forms, other } ->
            let
                withForms =
                    List.foldl (\( _, msg ) a -> collectNames msg a) (arg :: acc) forms
            in
            collectNames other withForms
