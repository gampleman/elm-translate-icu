module Internal.Format exposing
    ( Backend
    , format
    )

{-| The pure, backend-agnostic message formatter.

This module contains no dependency on `Intl` or any effect, so it can be
exercised directly in tests with a fake [`Backend`](#Backend). `Icu.Format`
wraps it with a real backend built from `anmolitor/intl-proxy`.

@docs Backend
@docs format

-}

import Dict exposing (Dict)
import Icu.Ast as Ast exposing (Message, Part(..), PluralSelector(..))
import Icu.Value as Value exposing (Value)


{-| The locale-dependent operations the formatter delegates. A real backend
routes these to the browser `Intl` API; a test backend fakes them.

  - `formatNumber style value` — format a numeric value, honoring an optional
    ICU number style/skeleton.
  - `formatDate style value` — format a time value, honoring an optional
    date/time style.
  - `selectPluralCategory ordinal n` — return the CLDR plural category
    (`"zero"`, `"one"`, `"two"`, `"few"`, `"many"`, `"other"`) for `n`, using
    ordinal rules when `ordinal` is `True`.

-}
type alias Backend =
    { formatNumber : Maybe String -> Value -> String
    , formatDate : Maybe String -> Value -> String
    , selectPluralCategory : Bool -> Float -> String
    }


{-| Format a parsed message against a set of argument values. Missing or
type-mismatched arguments degrade gracefully: an absent argument renders as its
placeholder name in braces (e.g. `{name}`) so the gap is visible rather than
silent.
-}
format : Backend -> Dict String Value -> Message -> String
format backend args message =
    formatParts backend args Nothing message


{-| `poundValue` is the offset-adjusted number to render for a `#` placeholder,
set only while formatting inside a plural branch.
-}
formatParts : Backend -> Dict String Value -> Maybe Float -> Message -> String
formatParts backend args poundValue parts =
    parts
        |> List.map (formatPart backend args poundValue)
        |> String.concat


formatPart : Backend -> Dict String Value -> Maybe Float -> Part -> String
formatPart backend args poundValue part =
    case part of
        Literal text ->
            text

        Pound ->
            case poundValue of
                Just n ->
                    backend.formatNumber Nothing (numberToValue n)

                Nothing ->
                    "#"

        Argument name ->
            case Dict.get name args of
                Just value ->
                    Value.toDisplayString value

                Nothing ->
                    missing name

        Number name style ->
            withArg args name (backend.formatNumber style)

        Date name style ->
            withArg args name (backend.formatDate style)

        Time name style ->
            withArg args name (backend.formatDate style)

        Select name cases other ->
            let
                selector =
                    case Dict.get name args of
                        Just value ->
                            Value.toDisplayString value

                        Nothing ->
                            ""

                chosen =
                    lookupCase selector cases |> Maybe.withDefault other
            in
            formatParts backend args poundValue chosen

        Plural plural ->
            formatPlural backend args plural


formatPlural :
    Backend
    -> Dict String Value
    ->
        { arg : String
        , ordinal : Bool
        , offset : Int
        , forms : List Ast.PluralForm
        , other : Message
        }
    -> String
formatPlural backend args plural =
    case Dict.get plural.arg args |> Maybe.andThen toFloat of
        Nothing ->
            -- Non-numeric or missing argument: fall back to `other`, no pound.
            formatParts backend args Nothing plural.other

        Just n ->
            let
                adjusted =
                    n - toFloat_ plural.offset

                chosen =
                    -- Exact `=N` selectors match the raw value (before offset);
                    -- keyword selectors match the CLDR category of the adjusted
                    -- value.
                    case lookupExact n plural.forms of
                        Just message ->
                            message

                        Nothing ->
                            let
                                category =
                                    backend.selectPluralCategory plural.ordinal adjusted
                            in
                            lookupKeyword category plural.forms
                                |> Maybe.withDefault plural.other
            in
            formatParts backend args (Just adjusted) chosen



-- HELPERS


withArg : Dict String Value -> String -> (Value -> String) -> String
withArg args name render =
    case Dict.get name args of
        Just value ->
            render value

        Nothing ->
            missing name


missing : String -> String
missing name =
    "{" ++ name ++ "}"


lookupCase : String -> List ( String, Message ) -> Maybe Message
lookupCase key cases =
    case cases of
        [] ->
            Nothing

        ( k, v ) :: rest ->
            if k == key then
                Just v

            else
                lookupCase key rest


lookupExact : Float -> List Ast.PluralForm -> Maybe Message
lookupExact n forms =
    case forms of
        [] ->
            Nothing

        ( Exact e, message ) :: rest ->
            if toFloat_ e == n then
                Just message

            else
                lookupExact n rest

        _ :: rest ->
            lookupExact n rest


lookupKeyword : String -> List Ast.PluralForm -> Maybe Message
lookupKeyword category forms =
    case forms of
        [] ->
            Nothing

        ( Keyword k, message ) :: rest ->
            if k == category then
                Just message

            else
                lookupKeyword category rest

        _ :: rest ->
            lookupKeyword category rest


toFloat : Value -> Maybe Float
toFloat value =
    case value of
        Value.Int i ->
            Just (toFloat_ i)

        Value.Float f ->
            Just f

        _ ->
            Nothing


numberToValue : Float -> Value
numberToValue n =
    if toFloat_ (round n) == n then
        Value.Int (round n)

    else
        Value.Float n


toFloat_ : Int -> Float
toFloat_ =
    Basics.toFloat
