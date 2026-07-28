module SkeletonTest exposing (suite)

import Expect
import Internal.Skeleton as Skeleton
import Json.Encode as Encode
import Test exposing (Test, describe, test)


{-| Render options to a stable, comparable string form.
-}
show : List ( String, Encode.Value ) -> String
show pairs =
    pairs
        |> List.map (\( k, v ) -> k ++ "=" ++ Encode.encode 0 v)
        |> String.join ","


num : String -> String
num =
    Skeleton.numberOptions >> show


date : String -> String
date =
    Skeleton.dateOptions >> show


suite : Test
suite =
    describe "Internal.Skeleton"
        [ describe "legacy number styles"
            [ test "integer" (\() -> Expect.equal "maximumFractionDigits=0" (num "integer"))
            , test "percent" (\() -> Expect.equal "style=\"percent\"" (num "percent"))
            , test "empty is no options" (\() -> Expect.equal "" (num ""))
            , test "bare currency emits nothing (needs a code)" (\() -> Expect.equal "" (num "currency"))
            ]
        , describe "skeleton stems"
            [ test "currency with code"
                (\() -> Expect.equal "style=\"currency\",currency=\"USD\"" (num "::currency/USD"))
            , test "skeleton without leading ::"
                (\() -> Expect.equal "style=\"currency\",currency=\"EUR\"" (num "currency/EUR"))
            , test "percent stem"
                (\() -> Expect.equal "style=\"percent\"" (num "::percent"))
            , test "compact-short"
                (\() -> Expect.equal "notation=\"compact\",compactDisplay=\"short\"" (num "::compact-short"))
            , test "scientific"
                (\() -> Expect.equal "notation=\"scientific\"" (num "::scientific"))
            , test "group-off"
                (\() -> Expect.equal "useGrouping=false" (num "::group-off"))
            , test "sign-always"
                (\() -> Expect.equal "signDisplay=\"always\"" (num "::sign-always"))
            , test "unit strips category"
                (\() -> Expect.equal "style=\"unit\",unit=\"meter\"" (num "::unit/length-meter"))
            ]
        , describe "precision"
            [ test "fraction .00 fixes 2 digits"
                (\() -> Expect.equal "minimumFractionDigits=2,maximumFractionDigits=2" (num "::.00"))
            , test "fraction .0# is min 1 max 2"
                (\() -> Expect.equal "minimumFractionDigits=1,maximumFractionDigits=2" (num "::.0#"))
            , test "fraction .00* is unbounded max"
                (\() -> Expect.equal "minimumFractionDigits=2" (num "::.00*"))
            , test "precision-integer"
                (\() -> Expect.equal "maximumFractionDigits=0" (num "::precision-integer"))
            , test "significant digits @@@"
                (\() -> Expect.equal "minimumSignificantDigits=3,maximumSignificantDigits=3" (num "::@@@"))
            , test "significant digits @@#"
                (\() -> Expect.equal "minimumSignificantDigits=2,maximumSignificantDigits=3" (num "::@@#"))
            ]
        , describe "multi-token skeletons"
            [ test "currency + compact + precision"
                (\() ->
                    Expect.equal
                        "style=\"currency\",currency=\"USD\",notation=\"compact\",compactDisplay=\"short\",minimumFractionDigits=2,maximumFractionDigits=2"
                        (num "::currency/USD compact-short .00")
                )
            , test "later token wins for a shared key"
                (\() -> Expect.equal "notation=\"scientific\",compactDisplay=\"short\"" (num "::compact-short scientific"))
            ]
        , describe "legacy date styles"
            [ test "short" (\() -> Expect.equal "dateStyle=\"short\"" (date "short"))
            , test "full" (\() -> Expect.equal "dateStyle=\"full\"" (date "full"))
            , test "empty yields nothing" (\() -> Expect.equal "" (date ""))
            ]
        , describe "date field skeletons"
            [ test "yMMMd"
                (\() ->
                    Expect.equal
                        "year=\"numeric\",month=\"short\",day=\"numeric\""
                        (date "yMMMd")
                )
            , test "leading :: is stripped"
                (\() ->
                    Expect.equal
                        "year=\"numeric\",month=\"short\",day=\"numeric\""
                        (date "::yMMMd")
                )
            , test "month width by run length"
                (\() -> Expect.equal "month=\"numeric\"" (date "M"))
            , test "MM is 2-digit"
                (\() -> Expect.equal "month=\"2-digit\"" (date "MM"))
            , test "MMMM is long"
                (\() -> Expect.equal "month=\"long\"" (date "MMMM"))
            , test "MMMMM is narrow"
                (\() -> Expect.equal "month=\"narrow\"" (date "MMMMM"))
            , test "yy is 2-digit year"
                (\() -> Expect.equal "year=\"2-digit\"" (date "yy"))
            , test "Hms 24-hour time"
                (\() ->
                    Expect.equal
                        "hour=\"numeric\",hourCycle=\"h23\",minute=\"numeric\",second=\"numeric\""
                        (date "Hms")
                )
            , test "hh 12-hour"
                (\() -> Expect.equal "hour=\"2-digit\",hourCycle=\"h12\"" (date "hh"))
            , test "EEEE long weekday"
                (\() -> Expect.equal "weekday=\"long\"" (date "EEEE"))
            , test "E short weekday"
                (\() -> Expect.equal "weekday=\"short\"" (date "E"))
            , test "z timezone name"
                (\() -> Expect.equal "timeZoneName=\"short\"" (date "z"))
            , test "unknown symbols contribute nothing"
                (\() -> Expect.equal "day=\"numeric\"" (date "Qd"))
            , test "full datetime skeleton"
                (\() ->
                    Expect.equal
                        "year=\"numeric\",month=\"long\",day=\"numeric\",hour=\"numeric\",hourCycle=\"h23\",minute=\"2-digit\""
                        (date "yMMMMdHmm")
                )
            ]
        ]
