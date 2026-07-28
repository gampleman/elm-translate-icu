module Icu.Value exposing
    ( Value(..)
    , toDisplayString
    )

{-| A runtime argument value substituted into a message.

@docs Value
@docs toDisplayString

-}

import Time


{-| The value bound to a placeholder when formatting a message.

  - `Str` — for `{name}` and `select` arguments.
  - `Int` / `Float` — for `number`, `plural`, and `selectordinal` arguments.
  - `Time` — for `date` and `time` arguments.

-}
type Value
    = Str String
    | Int Int
    | Float Float
    | Time Time.Posix


{-| A best-effort plain-string rendering, used when a value is substituted for a
bare `{name}` placeholder (no type/format). Numbers are rendered without locale
formatting; use a `number` placeholder for that. Times render as their epoch
milliseconds, which is rarely what you want — prefer a `date`/`time`
placeholder.
-}
toDisplayString : Value -> String
toDisplayString value =
    case value of
        Str s ->
            s

        Int i ->
            String.fromInt i

        Float f ->
            String.fromFloat f

        Time posix ->
            String.fromInt (Time.posixToMillis posix)
