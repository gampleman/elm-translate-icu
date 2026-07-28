module Icu.Locale exposing
    ( Locale
    , default
    , fromString, toString
    , language, script, region, variants
    , fallbacks, bestMatch, negotiate
    )

{-| Parse and resolve [BCP 47](https://www.rfc-editor.org/info/bcp47) language
tags.

This module lets you match a requested locale (or a prioritized list of
requested locales, as in an HTTP `Accept-Language` header) against the set of
locales you actually have translations for — without hard-coding which locales
exist. New translations can be added as data at runtime and resolution keeps
working.

@docs Locale
@docs default
@docs fromString, toString
@docs language, script, region, variants
@docs fallbacks, bestMatch, negotiate

-}


{-| A parsed, canonicalized BCP 47 language tag.

Canonical case is applied on parse: language lowercase (`en`), script in title
case (`Latn`), region uppercase (`US`), variants lowercase. Extension and
private-use subtags (`-u-…`, `-x-…`) are not retained — they don't affect
translation lookup.

-}
type Locale
    = Locale
        { language : String
        , script : Maybe String
        , region : Maybe String
        , variants : List String
        }


{-| The `en` locale — a sensible total default when no locale has been
negotiated yet, so callers can hold a concrete `Locale` (and thus a concrete
`Bundle`) without threading a `Maybe` everywhere.

    toString default
    --> "en"

-}
default : Locale
default =
    Locale
        { language = "en"
        , script = Nothing
        , region = Nothing
        , variants = []
        }


{-| Parse a BCP 47 tag such as `"en"`, `"en-US"`, `"zh-Hant-TW"`, or
`"sr-Latn-RS"`. Both `-` and `_` are accepted as separators. Returns `Nothing`
if there is no valid primary language subtag.

    fromString "en-US" |> Maybe.map toString
    --> Just "en-US"

    fromString "ZH_hant_tw" |> Maybe.map toString
    --> Just "zh-Hant-TW"

-}
fromString : String -> Maybe Locale
fromString raw =
    case
        raw
            |> String.replace "_" "-"
            |> String.split "-"
            |> List.filter (not << String.isEmpty)
    of
        [] ->
            Nothing

        lang :: rest ->
            if isLanguage lang then
                Just <|
                    parseRest
                        { language = String.toLower lang
                        , script = Nothing
                        , region = Nothing
                        , variants = []
                        }
                        rest

            else
                Nothing


parseRest :
    { language : String, script : Maybe String, region : Maybe String, variants : List String }
    -> List String
    -> Locale
parseRest acc subtags =
    case subtags of
        [] ->
            Locale acc

        s :: more ->
            if acc.script == Nothing && acc.region == Nothing && List.isEmpty acc.variants && isScript s then
                parseRest { acc | script = Just (titleCase s) } more

            else if acc.region == Nothing && List.isEmpty acc.variants && isRegion s then
                parseRest { acc | region = Just (String.toUpper s) } more

            else if isVariant s then
                parseRest { acc | variants = acc.variants ++ [ String.toLower s ] } more

            else
                -- Extension / private-use / unrecognized subtag: stop here.
                Locale acc


{-| Render a `Locale` back to its canonical string form.
-}
toString : Locale -> String
toString (Locale l) =
    [ [ l.language ]
    , maybeToList l.script
    , maybeToList l.region
    , l.variants
    ]
        |> List.concat
        |> String.join "-"


{-| The primary language subtag, e.g. `"en"`.
-}
language : Locale -> String
language (Locale l) =
    l.language


{-| The script subtag, if present, e.g. `Just "Hant"`.
-}
script : Locale -> Maybe String
script (Locale l) =
    l.script


{-| The region subtag, if present, e.g. `Just "US"`.
-}
region : Locale -> Maybe String
region (Locale l) =
    l.region


{-| The variant subtags, if any.
-}
variants : Locale -> List String
variants (Locale l) =
    l.variants


{-| The fallback chain for a locale, most specific first, following RFC 4647
"lookup" truncation: trailing subtags are dropped one group at a time down to
the bare language.

    fromString "zh-Hant-TW"
        |> Maybe.map (fallbacks >> List.map toString)
    --> Just [ "zh-Hant-TW", "zh-Hant", "zh" ]

-}
fallbacks : Locale -> List Locale
fallbacks (Locale l) =
    [ Locale l
    , Locale { l | variants = [] }
    , Locale { l | variants = [], region = Nothing }
    , Locale { l | variants = [], region = Nothing, script = Nothing }
    ]
        |> dedupConsecutive


{-| Find the best available locale for a single requested locale, using the
[`fallbacks`](#fallbacks) chain. The requested locale is progressively
generalized until one of the `available` locales matches exactly (in canonical
form); returns `Nothing` if nothing matches.

    resolve want =
        [ "en", "en-GB", "fr" ]
            |> List.filterMap fromString
            |> (\avail -> fromString want |> Maybe.andThen (bestMatch avail))
            |> Maybe.map toString

    resolve "en-US" --> Just "en"
    resolve "en-GB" --> Just "en-GB"
    resolve "de"    --> Nothing

-}
bestMatch : List Locale -> Locale -> Maybe Locale
bestMatch available requested =
    let
        availStrings =
            List.map (\loc -> ( toString loc, loc )) available
    in
    fallbacks requested
        |> List.map toString
        |> firstJust (\tag -> lookupAssoc tag availStrings)


{-| Negotiate against a prioritized list of requested locales (highest priority
first, as in an `Accept-Language` header). Returns the [`bestMatch`](#bestMatch)
for the first requested locale that resolves.

    let
        avail =
            List.filterMap fromString [ "en", "fr-CA", "fr" ]
        wanted =
            List.filterMap fromString [ "de", "fr-FR", "en" ]
    in
    negotiate avail wanted |> Maybe.map toString
    --> Just "fr"

-}
negotiate : List Locale -> List Locale -> Maybe Locale
negotiate available requestedInPriorityOrder =
    firstJust (bestMatch available) requestedInPriorityOrder



-- SUBTAG CLASSIFICATION


isLanguage : String -> Bool
isLanguage s =
    let
        n =
            String.length s
    in
    n >= 2 && n <= 8 && String.all Char.isAlpha s


isScript : String -> Bool
isScript s =
    String.length s == 4 && String.all Char.isAlpha s


isRegion : String -> Bool
isRegion s =
    (String.length s == 2 && String.all Char.isAlpha s)
        || (String.length s == 3 && String.all Char.isDigit s)


isVariant : String -> Bool
isVariant s =
    let
        n =
            String.length s
    in
    (n >= 5 && n <= 8 && String.all Char.isAlphaNum s)
        || (n == 4 && (String.left 1 s |> String.all Char.isDigit) && String.all Char.isAlphaNum s)



-- HELPERS


titleCase : String -> String
titleCase s =
    String.left 1 s |> String.toUpper |> (\head -> head ++ (String.dropLeft 1 s |> String.toLower))


maybeToList : Maybe a -> List a
maybeToList m =
    case m of
        Just a ->
            [ a ]

        Nothing ->
            []


dedupConsecutive : List Locale -> List Locale
dedupConsecutive locales =
    List.foldr
        (\loc acc ->
            case acc of
                head :: _ ->
                    if toString head == toString loc then
                        acc

                    else
                        loc :: acc

                [] ->
                    [ loc ]
        )
        []
        locales


firstJust : (a -> Maybe b) -> List a -> Maybe b
firstJust f list =
    case list of
        [] ->
            Nothing

        x :: xs ->
            case f x of
                Just b ->
                    Just b

                Nothing ->
                    firstJust f xs


lookupAssoc : String -> List ( String, a ) -> Maybe a
lookupAssoc key pairs =
    case pairs of
        [] ->
            Nothing

        ( k, v ) :: rest ->
            if k == key then
                Just v

            else
                lookupAssoc key rest
