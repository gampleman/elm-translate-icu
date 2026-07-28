module Internal.Skeleton exposing
    ( numberOptions
    , dateOptions
    )

{-| Map ICU number/date format styles and skeletons onto the options objects
consumed by the browser `Intl.NumberFormat` / `Intl.DateTimeFormat`
constructors (as passed through by `anmolitor/intl-proxy`).

This module is pure — it takes the style/skeleton string from a parsed message
and returns `List ( String, Json.Encode.Value )` — so the mapping is fully
unit-testable without a live `Intl`.

@docs numberOptions
@docs dateOptions

-}

import Json.Encode as Encode


{-| Turn a `number` placeholder style into `Intl.NumberFormat` options.

Accepts both the legacy keyword styles (`integer`, `percent`, `currency`) and
modern ICU number skeletons, with or without the leading `::`
(`::currency/USD compact-short .00`).

Later tokens override earlier ones for the same option key.

-}
numberOptions : String -> List ( String, Encode.Value )
numberOptions raw =
    let
        trimmed =
            String.trim raw
    in
    if String.startsWith "::" trimmed then
        skeletonOptions (String.dropLeft 2 trimmed)

    else
        case trimmed of
            "integer" ->
                [ ( "maximumFractionDigits", Encode.int 0 ) ]

            "percent" ->
                [ ( "style", Encode.string "percent" ) ]

            "currency" ->
                -- ICU's bare `currency` uses the locale's default currency, but
                -- Intl.NumberFormat requires an explicit code. Without one it
                -- would throw, so emit no options and format as a plain number;
                -- use a `::currency/XXX` skeleton to pick a currency.
                []

            "" ->
                []

            _ ->
                -- Treat any other value as a skeleton written without `::`.
                skeletonOptions trimmed


skeletonOptions : String -> List ( String, Encode.Value )
skeletonOptions skeleton =
    skeleton
        |> String.words
        |> List.concatMap tokenOptions
        |> lastWins


{-| Map a single skeleton token to zero or more option pairs.
-}
tokenOptions : String -> List ( String, Encode.Value )
tokenOptions token =
    case String.split "/" token of
        [] ->
            []

        stem :: options ->
            stemOptions stem options


stemOptions : String -> List String -> List ( String, Encode.Value )
stemOptions stem options =
    case stem of
        "percent" ->
            [ ( "style", Encode.string "percent" ) ]

        "currency" ->
            case options of
                code :: _ ->
                    [ ( "style", Encode.string "currency" )
                    , ( "currency", Encode.string code )
                    ]

                [] ->
                    []

        "unit" ->
            case options of
                unit :: _ ->
                    [ ( "style", Encode.string "unit" )
                    , ( "unit", Encode.string (stripUnitCategory unit) )
                    ]

                [] ->
                    []

        "compact-short" ->
            [ ( "notation", Encode.string "compact" )
            , ( "compactDisplay", Encode.string "short" )
            ]

        "compact-long" ->
            [ ( "notation", Encode.string "compact" )
            , ( "compactDisplay", Encode.string "long" )
            ]

        "scientific" ->
            [ ( "notation", Encode.string "scientific" ) ]

        "engineering" ->
            [ ( "notation", Encode.string "engineering" ) ]

        "notation-simple" ->
            [ ( "notation", Encode.string "standard" ) ]

        "group-off" ->
            [ ( "useGrouping", Encode.bool False ) ]

        "group-auto" ->
            [ ( "useGrouping", Encode.string "auto" ) ]

        "group-min2" ->
            [ ( "useGrouping", Encode.string "min2" ) ]

        "group-on-aligned" ->
            [ ( "useGrouping", Encode.bool True ) ]

        "group-thousands" ->
            [ ( "useGrouping", Encode.string "always" ) ]

        "sign-auto" ->
            [ ( "signDisplay", Encode.string "auto" ) ]

        "sign-always" ->
            [ ( "signDisplay", Encode.string "always" ) ]

        "sign-never" ->
            [ ( "signDisplay", Encode.string "never" ) ]

        "sign-except-zero" ->
            [ ( "signDisplay", Encode.string "exceptZero" ) ]

        "sign-accounting" ->
            [ ( "currencySign", Encode.string "accounting" ) ]

        "sign-accounting-always" ->
            [ ( "currencySign", Encode.string "accounting" )
            , ( "signDisplay", Encode.string "always" )
            ]

        "precision-integer" ->
            [ ( "maximumFractionDigits", Encode.int 0 ) ]

        "integer-width" ->
            case options of
                pattern :: _ ->
                    [ ( "minimumIntegerDigits", Encode.int (max 1 (countChar '0' pattern)) ) ]

                [] ->
                    []

        _ ->
            fractionOrSignificant stem


{-| Fraction precision (`.00`, `.##`, `.0#`, `.00*`) and significant-digit
precision (`@@@`, `@##`, `@@+`) tokens.
-}
fractionOrSignificant : String -> List ( String, Encode.Value )
fractionOrSignificant stem =
    if String.startsWith "." stem then
        let
            body =
                String.dropLeft 1 stem

            unbounded =
                String.contains "*" body || String.contains "+" body

            zeros =
                countChar '0' body

            hashes =
                countChar '#' body

            base =
                [ ( "minimumFractionDigits", Encode.int zeros ) ]
        in
        if unbounded then
            base

        else
            base ++ [ ( "maximumFractionDigits", Encode.int (zeros + hashes) ) ]

    else if String.startsWith "@" stem then
        let
            unbounded =
                String.contains "*" stem || String.contains "+" stem

            ats =
                countChar '@' stem

            hashes =
                countChar '#' stem

            base =
                [ ( "minimumSignificantDigits", Encode.int ats ) ]
        in
        if unbounded then
            base

        else
            base ++ [ ( "maximumSignificantDigits", Encode.int (ats + hashes) ) ]

    else
        []



-- DATE / TIME


{-| Turn a `date` / `time` placeholder style into `Intl.DateTimeFormat` options.

Two forms are supported:

  - The legacy ICU styles `short`, `medium`, `long`, and `full`, applied to
    `dateStyle` (both `date` and `time` placeholders share this vocabulary and
    `intl-proxy` accepts `dateStyle`).
  - Field-level ICU date skeletons such as `yMMMd`, `Hms`, or `EEEEMMMMd`
    (optionally written with a leading `::`). Each run of a field symbol maps
    onto the corresponding `Intl.DateTimeFormat` option, with the run length
    selecting the representation (`M` numeric, `MM` 2-digit, `MMM` short,
    `MMMM` long, `MMMMM` narrow).

Unknown/empty input yields no options (locale default).

-}
dateOptions : String -> List ( String, Encode.Value )
dateOptions raw =
    case String.trim raw of
        "" ->
            []

        "short" ->
            [ ( "dateStyle", Encode.string "short" ) ]

        "medium" ->
            [ ( "dateStyle", Encode.string "medium" ) ]

        "long" ->
            [ ( "dateStyle", Encode.string "long" ) ]

        "full" ->
            [ ( "dateStyle", Encode.string "full" ) ]

        trimmed ->
            trimmed
                |> stripSkeletonPrefix
                |> runs
                |> List.concatMap dateFieldOptions
                |> lastWins


stripSkeletonPrefix : String -> String
stripSkeletonPrefix s =
    if String.startsWith "::" s then
        String.dropLeft 2 s

    else
        s


{-| Map one field run (a symbol and its repeat count) to `Intl.DateTimeFormat`
options. Follows the LDML date field symbols used by ICU skeletons; unknown
symbols contribute nothing.
-}
dateFieldOptions : ( Char, Int ) -> List ( String, Encode.Value )
dateFieldOptions ( symbol, count ) =
    case symbol of
        'y' ->
            [ ( "year", numericOr2Digit count ) ]

        'Y' ->
            [ ( "year", numericOr2Digit count ) ]

        'M' ->
            [ ( "month", monthRepresentation count ) ]

        'L' ->
            [ ( "month", monthRepresentation count ) ]

        'd' ->
            [ ( "day", numericOr2Digit count ) ]

        'E' ->
            [ ( "weekday", weekdayRepresentation count ) ]

        'e' ->
            [ ( "weekday", weekdayRepresentation count ) ]

        'c' ->
            [ ( "weekday", weekdayRepresentation count ) ]

        'G' ->
            [ ( "era", nameWidth count ) ]

        'h' ->
            [ ( "hour", numericOr2Digit count ), ( "hourCycle", Encode.string "h12" ) ]

        'H' ->
            [ ( "hour", numericOr2Digit count ), ( "hourCycle", Encode.string "h23" ) ]

        'K' ->
            [ ( "hour", numericOr2Digit count ), ( "hourCycle", Encode.string "h11" ) ]

        'k' ->
            [ ( "hour", numericOr2Digit count ), ( "hourCycle", Encode.string "h24" ) ]

        'm' ->
            [ ( "minute", numericOr2Digit count ) ]

        's' ->
            [ ( "second", numericOr2Digit count ) ]

        'a' ->
            [ ( "hour12", Encode.bool True ) ]

        'z' ->
            [ ( "timeZoneName", timeZoneNameWidth count ) ]

        'v' ->
            [ ( "timeZoneName", timeZoneNameWidth count ) ]

        'V' ->
            [ ( "timeZoneName", timeZoneNameWidth count ) ]

        _ ->
            []


numericOr2Digit : Int -> Encode.Value
numericOr2Digit count =
    if count >= 2 then
        Encode.string "2-digit"

    else
        Encode.string "numeric"


monthRepresentation : Int -> Encode.Value
monthRepresentation count =
    Encode.string <|
        case count of
            1 ->
                "numeric"

            2 ->
                "2-digit"

            3 ->
                "short"

            4 ->
                "long"

            _ ->
                "narrow"


weekdayRepresentation : Int -> Encode.Value
weekdayRepresentation count =
    Encode.string <|
        if count >= 5 then
            "narrow"

        else if count == 4 then
            "long"

        else
            "short"


nameWidth : Int -> Encode.Value
nameWidth count =
    Encode.string <|
        if count >= 5 then
            "narrow"

        else if count == 4 then
            "long"

        else
            "short"


timeZoneNameWidth : Int -> Encode.Value
timeZoneNameWidth count =
    Encode.string <|
        if count >= 4 then
            "long"

        else
            "short"


{-| Group a string into runs of the same character, e.g. `"yMMMd"` becomes
`[ ( 'y', 1 ), ( 'M', 3 ), ( 'd', 1 ) ]`.
-}
runs : String -> List ( Char, Int )
runs s =
    String.toList s
        |> List.foldl
            (\c acc ->
                case acc of
                    ( prev, n ) :: rest ->
                        if prev == c then
                            ( prev, n + 1 ) :: rest

                        else
                            ( c, 1 ) :: acc

                    [] ->
                        [ ( c, 1 ) ]
            )
            []
        |> List.reverse



-- HELPERS


{-| Strip an ICU measure-unit category prefix so `length-meter` becomes `meter`,
matching the `Intl` unit identifier. Units without a category (e.g.
`kilometer-per-hour`, written in ICU as `speed-kilometer-per-hour`) keep their
tail.
-}
stripUnitCategory : String -> String
stripUnitCategory unit =
    case String.split "-" unit of
        _ :: rest ->
            if List.isEmpty rest then
                unit

            else
                String.join "-" rest

        [] ->
            unit


countChar : Char -> String -> Int
countChar c =
    String.foldl
        (\ch acc ->
            if ch == c then
                acc + 1

            else
                acc
        )
        0


{-| Deduplicate option pairs by key, keeping the last occurrence (skeleton
tokens are applied left-to-right, later overrides earlier), preserving the order
of first appearance otherwise.
-}
lastWins : List ( String, Encode.Value ) -> List ( String, Encode.Value )
lastWins pairs =
    let
        lastValueFor key =
            pairs
                |> List.filter (\( k, _ ) -> k == key)
                |> List.reverse
                |> List.head
                |> Maybe.map Tuple.second
    in
    List.foldl
        (\( key, _ ) ( seen, acc ) ->
            if List.member key seen then
                ( seen, acc )

            else
                case lastValueFor key of
                    Just v ->
                        ( key :: seen, ( key, v ) :: acc )

                    Nothing ->
                        ( seen, acc )
        )
        ( [], [] )
        pairs
        |> Tuple.second
        |> List.reverse
