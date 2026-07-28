module LocaleTest exposing (suite)

import Expect
import Icu.Locale as Locale exposing (Locale)
import Test exposing (Test, describe, test)


parse : String -> Locale
parse s =
    case Locale.fromString s of
        Just loc ->
            loc

        Nothing ->
            Debug.todo ("test setup: could not parse " ++ s)


locales : List String -> List Locale
locales =
    List.filterMap Locale.fromString


suite : Test
suite =
    describe "Icu.Locale"
        [ describe "fromString / toString (canonicalization)"
            [ test "bare language lowercased"
                (\() -> Expect.equal "en" (Locale.toString (parse "EN")))
            , test "language-region"
                (\() -> Expect.equal "en-US" (Locale.toString (parse "en-us")))
            , test "language-script-region"
                (\() -> Expect.equal "zh-Hant-TW" (Locale.toString (parse "ZH_hant_tw")))
            , test "underscore separator"
                (\() -> Expect.equal "sr-Latn-RS" (Locale.toString (parse "sr_latn_rs")))
            , test "numeric region"
                (\() -> Expect.equal "es-419" (Locale.toString (parse "es-419")))
            , test "variant"
                (\() -> Expect.equal "de-DE-1996" (Locale.toString (parse "de-DE-1996")))
            , test "empty string is rejected"
                (\() -> Expect.equal Nothing (Locale.fromString ""))
            , test "single-letter primary subtag is rejected"
                (\() -> Expect.equal Nothing (Locale.fromString "x"))
            , test "extension subtags are dropped"
                (\() -> Expect.equal "en-US" (Locale.toString (parse "en-US-u-ca-gregory")))
            ]
        , describe "accessors"
            [ test "components of zh-Hant-TW"
                (\() ->
                    let
                        l =
                            parse "zh-Hant-TW"
                    in
                    Expect.equal
                        ( "zh", ( Just "Hant", Just "TW" ) )
                        ( Locale.language l, ( Locale.script l, Locale.region l ) )
                )
            ]
        , describe "fallbacks"
            [ test "script + region truncation chain"
                (\() ->
                    Expect.equal [ "zh-Hant-TW", "zh-Hant", "zh" ]
                        (Locale.fallbacks (parse "zh-Hant-TW") |> List.map Locale.toString)
                )
            , test "region-only chain"
                (\() ->
                    Expect.equal [ "en-US", "en" ]
                        (Locale.fallbacks (parse "en-US") |> List.map Locale.toString)
                )
            , test "bare language chain is a singleton"
                (\() ->
                    Expect.equal [ "fr" ]
                        (Locale.fallbacks (parse "fr") |> List.map Locale.toString)
                )
            ]
        , describe "bestMatch"
            [ test "generalizes region to language"
                (\() ->
                    Locale.fromString "en-US"
                        |> Maybe.andThen (Locale.bestMatch (locales [ "en", "en-GB", "fr" ]))
                        |> Maybe.map Locale.toString
                        |> Expect.equal (Just "en")
                )
            , test "prefers exact match over generalization"
                (\() ->
                    Locale.fromString "en-GB"
                        |> Maybe.andThen (Locale.bestMatch (locales [ "en", "en-GB", "fr" ]))
                        |> Maybe.map Locale.toString
                        |> Expect.equal (Just "en-GB")
                )
            , test "returns Nothing when nothing matches"
                (\() ->
                    Locale.fromString "de"
                        |> Maybe.andThen (Locale.bestMatch (locales [ "en", "fr" ]))
                        |> Expect.equal Nothing
                )
            ]
        , describe "negotiate"
            [ test "falls through to a lower-priority requested locale"
                (\() ->
                    Locale.negotiate
                        (locales [ "en", "fr-CA", "fr" ])
                        (locales [ "de", "fr-FR", "en" ])
                        |> Maybe.map Locale.toString
                        |> Expect.equal (Just "fr")
                )
            , test "honors priority order"
                (\() ->
                    Locale.negotiate
                        (locales [ "en", "fr" ])
                        (locales [ "fr", "en" ])
                        |> Maybe.map Locale.toString
                        |> Expect.equal (Just "fr")
                )
            ]
        ]
