module Icu.Bundle exposing
    ( Bundle, Messages
    , fromMessages, decodeMessages, parseMessages
    , withLocale, currentLocale
    , translate
    )

{-| A runtime store of translations for the generated code to target.

A `Bundle` holds the `Intl` handle, the active `Locale`, the active locale's
messages, and a set of fallback messages (the master language). Keys missing
from the active locale fall back to the master, so a locale can ship partial
translations. New locales are loaded as data at runtime — adding one requires no
recompile.

@docs Bundle, Messages
@docs fromMessages, decodeMessages, parseMessages
@docs withLocale, currentLocale
@docs translate

-}

import Dict exposing (Dict)
import Icu.Ast exposing (Message)
import Icu.Format as Format
import Icu.Locale as Locale exposing (Locale)
import Icu.Parser as Parser
import Intl exposing (Intl)
import Json.Decode as Decode


{-| A map from translation key to its parsed message.
-}
type alias Messages =
    Dict String Message


{-| An opaque runtime translation store.
-}
type Bundle
    = Bundle
        { intl : Intl
        , locale : Locale
        , active : Messages
        , fallback : Messages
        }


{-| Build a bundle from already-parsed messages. The messages passed here serve
as both the active locale and the fallback (they are the master language).
Generated code calls this in its `init`.
-}
fromMessages : Intl -> Locale -> Messages -> Bundle
fromMessages intl locale messages =
    Bundle
        { intl = intl
        , locale = locale
        , active = messages
        , fallback = messages
        }


{-| Parse a JSON object of `{ "key": "ICU string", ... }` into [`Messages`](#Messages).

Returns the list of `(key, parseError)` pairs for any values that are not valid
ICU, alongside the messages that did parse. This is total: a malformed entry is
reported but does not abort the whole load.

-}
decodeMessages : String -> Result Decode.Error ( Messages, List ( String, String ) )
decodeMessages json =
    Decode.decodeString (Decode.keyValuePairs Decode.string) json
        |> Result.map (List.reverse >> parseMessages)


{-| Parse an association list of `(key, ICU string)` into messages, collecting
any per-key parse errors. Exposed for callers that already have the pairs (e.g.
generated code baking in the master language).
-}
parseMessages : List ( String, String ) -> ( Messages, List ( String, String ) )
parseMessages pairs =
    List.foldl
        (\( key, raw ) ( ok, errs ) ->
            case Parser.parse raw of
                Ok message ->
                    ( Dict.insert key message ok, errs )

                Err deadEnds ->
                    ( ok, ( key, Parser.deadEndsToString deadEnds ) :: errs )
        )
        ( Dict.empty, [] )
        pairs
        |> Tuple.mapSecond List.reverse


{-| Switch the active locale, replacing the active messages. The fallback
(master) messages are preserved, so keys missing from the new locale still
resolve.
-}
withLocale : Locale -> Messages -> Bundle -> Bundle
withLocale locale messages (Bundle b) =
    Bundle { b | locale = locale, active = messages }


{-| The bundle's currently active locale.
-}
currentLocale : Bundle -> Locale
currentLocale (Bundle b) =
    b.locale


{-| Format the message for `key` with the given arguments, formatting for the
active locale. If the key is absent from the active locale it falls back to the
master language; if it is absent there too, the key itself is returned so the
gap is visible.
-}
translate : Bundle -> String -> Format.Args -> String
translate (Bundle b) key args =
    case lookup key b of
        Just message ->
            Format.format b.intl b.locale args message

        Nothing ->
            key


lookup : String -> { a | active : Messages, fallback : Messages } -> Maybe Message
lookup key b =
    case Dict.get key b.active of
        Just message ->
            Just message

        Nothing ->
            Dict.get key b.fallback
