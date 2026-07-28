module FormatTest exposing (suite)

import Dict
import Expect
import Icu.Parser as Parser
import Icu.Value as Value exposing (Value)
import Internal.Format as Format
import Test exposing (Test, describe, test)
import Time


{-| A deterministic fake backend so plural/number/date logic can be tested
without a live `Intl`.

  - number formatting: percent multiplies by 100 and appends `%`, otherwise the
    raw display string.
  - date formatting: renders the style name and epoch millis, so we can assert
    the style was threaded through.
  - plural category: the English cardinal rule (`one` for 1, else `other`), and
    a simple ordinal rule so `selectordinal` can be exercised.

-}
fakeBackend : Format.Backend
fakeBackend =
    { formatNumber =
        \style value ->
            case ( style, value ) of
                ( Just "percent", Value.Float f ) ->
                    String.fromFloat (f * 100) ++ "%"

                _ ->
                    Value.toDisplayString value
    , formatDate =
        \style value ->
            let
                label =
                    Maybe.withDefault "default" style
            in
            label ++ ":" ++ Value.toDisplayString value
    , selectPluralCategory =
        \ordinal n ->
            if ordinal then
                if n == 1 then
                    "one"

                else if n == 2 then
                    "two"

                else if n == 3 then
                    "few"

                else
                    "other"

            else if n == 1 then
                "one"

            else
                "other"
    }


fmt : List ( String, Value ) -> String -> String -> (() -> Expect.Expectation)
fmt argList input expected =
    \() ->
        case Parser.parse input of
            Ok message ->
                Expect.equal expected
                    (Format.format fakeBackend (Dict.fromList argList) message)

            Err err ->
                Expect.fail ("parse failed: " ++ Parser.deadEndsToString err)


suite : Test
suite =
    describe "Internal.Format"
        [ describe "literals and interpolation"
            [ test "plain literal" (fmt [] "hello" "hello")
            , test "string argument"
                (fmt [ ( "name", Value.Str "Alice" ) ] "Hi {name}!" "Hi Alice!")
            , test "missing argument shows placeholder"
                (fmt [] "Hi {name}!" "Hi {name}!")
            , test "int argument via display string"
                (fmt [ ( "n", Value.Int 42 ) ] "n={n}" "n=42")
            ]
        , describe "number / date / time"
            [ test "percent style"
                (fmt [ ( "r", Value.Float 0.25 ) ] "{r, number, percent}" "25%")
            , test "date threads style"
                (fmt [ ( "d", Value.Time (millis 1000) ) ] "{d, date, long}" "long:1000")
            , test "time threads style"
                (fmt [ ( "t", Value.Time (millis 5) ) ] "{t, time, short}" "short:5")
            ]
        , describe "select"
            [ test "matches a case"
                (fmt [ ( "g", Value.Str "female" ) ]
                    "{g, select, male {he} female {she} other {they}}"
                    "she"
                )
            , test "falls back to other"
                (fmt [ ( "g", Value.Str "nonbinary" ) ]
                    "{g, select, male {he} female {she} other {they}}"
                    "they"
                )
            , test "missing arg falls back to other"
                (fmt []
                    "{g, select, male {he} other {they}}"
                    "they"
                )
            ]
        , describe "plural"
            [ test "keyword one with pound"
                (fmt [ ( "c", Value.Int 1 ) ]
                    "{c, plural, one {# item} other {# items}}"
                    "1 item"
                )
            , test "keyword other with pound"
                (fmt [ ( "c", Value.Int 5 ) ]
                    "{c, plural, one {# item} other {# items}}"
                    "5 items"
                )
            , test "exact match beats keyword"
                (fmt [ ( "c", Value.Int 0 ) ]
                    "{c, plural, =0 {none} one {# item} other {# items}}"
                    "none"
                )
            , test "offset adjusts pound and category"
                (fmt [ ( "c", Value.Int 2 ) ]
                    "{c, plural, offset:1 one {# other person} other {# other people}}"
                    "1 other person"
                )
            , test "exact selector matches raw value, not offset value"
                (fmt [ ( "c", Value.Int 1 ) ]
                    "{c, plural, offset:1 =1 {you} other {# more}}"
                    "you"
                )
            , test "non-numeric arg falls back to other without pound"
                (fmt [ ( "c", Value.Str "lots" ) ]
                    "{c, plural, one {# item} other {some items}}"
                    "some items"
                )
            ]
        , describe "selectordinal"
            [ test "ordinal one"
                (fmt [ ( "n", Value.Int 1 ) ]
                    "{n, selectordinal, one {#st} two {#nd} few {#rd} other {#th}}"
                    "1st"
                )
            , test "ordinal few"
                (fmt [ ( "n", Value.Int 3 ) ]
                    "{n, selectordinal, one {#st} two {#nd} few {#rd} other {#th}}"
                    "3rd"
                )
            , test "ordinal other"
                (fmt [ ( "n", Value.Int 11 ) ]
                    "{n, selectordinal, one {#st} two {#nd} few {#rd} other {#th}}"
                    "11th"
                )
            ]
        , describe "nesting"
            [ test "select inside plural, with outer pound"
                (fmt [ ( "c", Value.Int 5 ), ( "g", Value.Str "male" ) ]
                    "{c, plural, one {a thing} other {# {g, select, male {his} other {their}} things}}"
                    "5 his things"
                )
            ]
        ]


millis : Int -> Time.Posix
millis =
    Time.millisToPosix
