module CodegenTest exposing (suite)

import Dict
import Expect
import Icu.Codegen as Codegen exposing (ArgType(..))
import Icu.Parser as Parser
import Test exposing (Test, describe, test)


types : String -> Dict.Dict String ArgType
types raw =
    case Parser.parse raw of
        Ok message ->
            Codegen.inferArgTypes message

        Err _ ->
            Dict.empty


suite : Test
suite =
    describe "Icu.Codegen"
        [ describe "inferArgTypes"
            [ test "bare argument is String"
                (\() -> Expect.equal (Just TString) (Dict.get "name" (types "Hi {name}")))
            , test "number argument is Float"
                (\() -> Expect.equal (Just TFloat) (Dict.get "n" (types "{n, number}")))
            , test "plural argument is Int"
                (\() -> Expect.equal (Just TInt) (Dict.get "c" (types "{c, plural, other {#}}")))
            , test "date argument is Time"
                (\() -> Expect.equal (Just TTime) (Dict.get "d" (types "{d, date, long}")))
            , test "select argument is String"
                (\() -> Expect.equal (Just TString) (Dict.get "g" (types "{g, select, other {x}}")))
            , test "int widened to float when used both ways"
                (\() -> Expect.equal (Just TFloat) (Dict.get "x" (types "{x, plural, other {{x, number}}}")))
            , test "collects nested arguments"
                (\() ->
                    Expect.equal
                        [ ( "count", TInt ), ( "name", TString ) ]
                        (Dict.toList (types "{count, plural, other {{name} has # items}}"))
                )
            ]
        , describe "functionName / fieldName sanitization"
            [ test "dotted key becomes camelCase"
                (\() -> Expect.equal "userProfileTitle" (Codegen.fieldName "user.profile.title"))
            , test "leading digit is prefixed"
                (\() -> Expect.equal "t1st" (Codegen.fieldName "1st"))
            ]
        , describe "generate"
            [ test "reports parse errors keyed by name"
                (\() ->
                    case Codegen.generate { moduleName = "T" } [ ( "bad", "{n, plural, one {#}}" ) ] of
                        Err errs ->
                            Expect.equal [ "bad" ] (List.map Tuple.first errs)

                        Ok _ ->
                            Expect.fail "expected a parse error (plural without other)"
                )
            , test "emits module header and function names"
                (\() ->
                    case
                        Codegen.generate { moduleName = "Translations" }
                            [ ( "greeting", "Hello, {name}!" )
                            , ( "count.items", "{c, plural, one {# item} other {# items}}" )
                            ]
                    of
                        Ok src ->
                            Expect.all
                                [ \s -> Expect.equal True (String.contains "module Translations exposing" s)
                                , \s -> Expect.equal True (String.contains "greeting : Bundle -> { name : String } -> String" s)
                                , \s -> Expect.equal True (String.contains "countItems : Bundle -> { c : Int } -> String" s)
                                , \s -> Expect.equal True (String.contains "Format.string \"name\" args_.name" s)
                                , \s -> Expect.equal True (String.contains "masterMessages" s)
                                ]
                                src

                        Err _ ->
                            Expect.fail "expected successful generation"
                )
            , test "no-argument message takes only the bundle"
                (\() ->
                    case Codegen.generate { moduleName = "T" } [ ( "hello", "Hello!" ) ] of
                        Ok src ->
                            Expect.equal True (String.contains "hello : Bundle -> String" src)

                        Err _ ->
                            Expect.fail "expected successful generation"
                )
            ]
        ]
