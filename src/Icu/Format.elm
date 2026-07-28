module Icu.Format exposing
    ( format, formatWith
    , Args, args, string, int, float, time
    )

{-| Format a parsed ICU [`Message`](Icu-Ast#Message) into a `String`, using the
browser [`Intl`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl)
API (via [`anmolitor/intl-proxy`](https://package.elm-lang.org/packages/anmolitor/intl-proxy/latest/))
for locale-correct plural selection and number/date formatting.

You obtain the `Intl` value once at startup by decoding a flag with
[`Intl.decode`](https://package.elm-lang.org/packages/anmolitor/intl-proxy/latest/Intl#decode),
passing `window.Intl` in through JavaScript.

@docs format, formatWith
@docs Args, args, string, int, float, time

-}

import Dict exposing (Dict)
import Icu.Ast exposing (Message)
import Icu.Locale as Locale exposing (Locale)
import Icu.Value exposing (Value(..))
import Internal.Format as Internal
import Internal.Skeleton as Skeleton
import Intl exposing (Intl, PluralType(..))
import Time


{-| A collection of named argument values to substitute into a message. Build
one with [`args`](#args) and the value helpers.
-}
type Args
    = Args (Dict String Value)


{-| An empty argument set to pipe values into.

    Icu.Format.args
        |> Icu.Format.string "name" "Alice"
        |> Icu.Format.int "count" 3

-}
args : Args
args =
    Args Dict.empty


{-| Bind a string argument (for `{name}` and `select`).
-}
string : String -> String -> Args -> Args
string name value (Args dict) =
    Args (Dict.insert name (Str value) dict)


{-| Bind an integer argument (for `number`, `plural`, `selectordinal`).
-}
int : String -> Int -> Args -> Args
int name value (Args dict) =
    Args (Dict.insert name (Int value) dict)


{-| Bind a floating-point argument (for `number` and `plural`).
-}
float : String -> Float -> Args -> Args
float name value (Args dict) =
    Args (Dict.insert name (Float value) dict)


{-| Bind a time argument (for `date` and `time`).
-}
time : String -> Time.Posix -> Args -> Args
time name value (Args dict) =
    Args (Dict.insert name (Time value) dict)


{-| Format a message for a locale with the given arguments.

    Icu.Format.format intl
        locale
        (Icu.Format.args |> Icu.Format.string "name" "Alice")
        message

-}
format : Intl -> Locale -> Args -> Message -> String
format intl locale (Args dict) message =
    Internal.format (backend intl locale) dict message


{-| Like [`format`](#format), but takes the argument dictionary directly. Useful
for generated code that already has a `Dict String Value`.
-}
formatWith : Intl -> Locale -> Dict String Value -> Message -> String
formatWith intl locale dict message =
    Internal.format (backend intl locale) dict message


backend : Intl -> Locale -> Internal.Backend
backend intl locale =
    let
        lang =
            Locale.toString locale
    in
    { formatNumber = \style value -> formatNumber intl lang style value
    , formatDate = \style value -> formatDate intl lang style value
    , selectPluralCategory =
        \ordinal n ->
            Intl.determinePluralRuleFloat intl
                { language = lang
                , type_ =
                    if ordinal then
                        Ordinal

                    else
                        Cardinal
                , number = n
                }
                |> Intl.pluralRuleToString
    }


formatNumber : Intl -> String -> Maybe String -> Value -> String
formatNumber intl lang style value =
    let
        numArgs =
            Skeleton.numberOptions (Maybe.withDefault "" style)
    in
    case value of
        Int i ->
            Intl.formatInt intl { language = lang, args = numArgs, number = i }

        Float f ->
            Intl.formatFloat intl { language = lang, args = numArgs, number = f }

        _ ->
            Icu.Value.toDisplayString value


formatDate : Intl -> String -> Maybe String -> Value -> String
formatDate intl lang style value =
    case value of
        Time posix ->
            Intl.formatDateTime intl
                { time = posix
                , args = Skeleton.dateOptions (Maybe.withDefault "" style)
                , language = lang
                }

        _ ->
            Icu.Value.toDisplayString value
