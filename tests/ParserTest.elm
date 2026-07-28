module ParserTest exposing (suite)

import Expect
import Icu.Ast exposing (Message, Part(..), PluralSelector(..))
import Icu.Parser as Parser
import Test exposing (Test, describe, test)


ok : String -> Message -> (() -> Expect.Expectation)
ok input expected =
    \() ->
        case Parser.parse input of
            Ok parts ->
                Expect.equal expected parts

            Err e ->
                Expect.fail ("parse failed: " ++ Parser.deadEndsToString e)


err : String -> (() -> Expect.Expectation)
err input =
    \() ->
        case Parser.parse input of
            Ok parts ->
                Expect.fail ("expected failure but parsed: " ++ Debug.toString parts)

            Err _ ->
                Expect.pass


suite : Test
suite =
    describe "Icu.Parser"
        [ describe "literals & simple arguments"
            [ test "plain text" (ok "Hello world" [ Literal "Hello world" ])
            , test "empty string" (ok "" [])
            , test "single argument" (ok "{name}" [ Argument "name" ])
            , test "argument in text"
                (ok "Hello, {name}!"
                    [ Literal "Hello, ", Argument "name", Literal "!" ]
                )
            , test "whitespace inside braces" (ok "{ name }" [ Argument "name" ])
            , test "hash outside plural is literal" (ok "50# off" [ Literal "50# off" ])
            ]
        , describe "quoting"
            [ test "escaped braces" (ok "'{' not an arg" [ Literal "{ not an arg" ])
            , test "double apostrophe" (ok "it''s" [ Literal "it's" ])
            , test "quoted section"
                (ok "'{name}'" [ Literal "{name}" ])
            ]
        , describe "typed arguments"
            [ test "number" (ok "{n, number}" [ Number "n" Nothing ])
            , test "number with style"
                (ok "{n, number, percent}" [ Number "n" (Just "percent") ])
            , test "number with skeleton"
                (ok "{n, number, ::currency/USD}" [ Number "n" (Just "::currency/USD") ])
            , test "date" (ok "{d, date, long}" [ Date "d" (Just "long") ])
            , test "time" (ok "{t, time, short}" [ Time "t" (Just "short") ])
            ]
        , describe "select"
            [ test "basic select"
                (ok "{g, select, male {he} female {she} other {they}}"
                    [ Select "g"
                        [ ( "male", [ Literal "he" ] )
                        , ( "female", [ Literal "she" ] )
                        ]
                        [ Literal "they" ]
                    ]
                )
            , test "select requires other" (err "{g, select, male {he}}")
            ]
        , describe "plural"
            [ test "basic plural with pound"
                (ok "{count, plural, one {# item} other {# items}}"
                    [ Plural
                        { arg = "count"
                        , ordinal = False
                        , offset = 0
                        , forms = [ ( Keyword "one", [ Pound, Literal " item" ] ) ]
                        , other = [ Pound, Literal " items" ]
                        }
                    ]
                )
            , test "exact match and offset"
                (ok "{count, plural, offset:1 =0 {none} one {#} other {# more}}"
                    [ Plural
                        { arg = "count"
                        , ordinal = False
                        , offset = 1
                        , forms =
                            [ ( Exact 0, [ Literal "none" ] )
                            , ( Keyword "one", [ Pound ] )
                            ]
                        , other = [ Pound, Literal " more" ]
                        }
                    ]
                )
            , test "selectordinal"
                (ok "{n, selectordinal, one {#st} other {#th}}"
                    [ Plural
                        { arg = "n"
                        , ordinal = True
                        , offset = 0
                        , forms = [ ( Keyword "one", [ Pound, Literal "st" ] ) ]
                        , other = [ Pound, Literal "th" ]
                        }
                    ]
                )
            , test "plural requires other" (err "{n, plural, one {#}}")
            ]
        , describe "nesting"
            [ test "select inside plural"
                (ok "{count, plural, one {{g, select, male {his} other {their}} item} other {items}}"
                    [ Plural
                        { arg = "count"
                        , ordinal = False
                        , offset = 0
                        , forms =
                            [ ( Keyword "one"
                              , [ Select "g" [ ( "male", [ Literal "his" ] ) ] [ Literal "their" ]
                                , Literal " item"
                                ]
                              )
                            ]
                        , other = [ Literal "items" ]
                        }
                    ]
                )
            ]
        , describe "argumentNames"
            [ test "collects nested names deduped"
                (\() ->
                    case Parser.parse "{count, plural, one {{name} has # thing} other {{name} has # things — {when, date}}}" of
                        Ok parts ->
                            Expect.equal [ "count", "name", "when" ] (Icu.Ast.argumentNames parts)

                        Err e ->
                            Expect.fail (Parser.deadEndsToString e)
                )
            ]
        ]
