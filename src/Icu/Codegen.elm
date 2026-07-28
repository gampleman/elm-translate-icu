module Icu.Codegen exposing
    ( generate, Options
    , ArgType(..), inferArgTypes, fieldName
    )

{-| Generate a type-safe Elm module from a master-language set of ICU messages.

The generator is a pure function from `(key, ICU string)` pairs to Elm source
text, so it can run anywhere Elm runs (a Node build step, a test, an editor
plugin). It emits one function per key. Each function takes the
[`Bundle`](Icu-Bundle#Bundle) first (I18n-first argument order) followed by a
record of the message's typed arguments; keys with no arguments take only the
bundle.

    greeting : Bundle -> { name : String } -> String

Non-master locales are never baked in — they load as data at runtime through
[`Icu.Bundle`](Icu-Bundle), so adding a locale or a translation needs no
regeneration. Only changing the master language's keys or their argument shapes
requires re-running the generator.

@docs generate, Options
@docs ArgType, inferArgTypes, fieldName

-}

import Dict exposing (Dict)
import Icu.Ast as Ast exposing (Message, Part(..), PluralSelector(..))
import Icu.Parser as Parser


{-| Generator options.

  - `moduleName` — the fully-qualified name of the module to generate, e.g.
    `"Translations"` or `"App.I18n"`.

-}
type alias Options =
    { moduleName : String }


{-| The inferred type of a message argument, determining the record field type
and which [`Icu.Format`](Icu-Format) binder the generated code uses.
-}
type ArgType
    = TString
    | TInt
    | TFloat
    | TTime


{-| Generate the Elm module source for the given master-language pairs.

Returns `Err` with `(key, error)` pairs if any message fails to parse; otherwise
`Ok` with the module source as a `String`. Run the output through `elm-format`
for canonical layout.

-}
generate : Options -> List ( String, String ) -> Result (List ( String, String )) String
generate options pairs =
    let
        ( parsed, errors ) =
            List.foldr
                (\( key, raw ) ( oks, errs ) ->
                    case Parser.parse raw of
                        Ok message ->
                            ( ( key, message ) :: oks, errs )

                        Err deadEnds ->
                            ( oks, ( key, Parser.deadEndsToString deadEnds ) :: errs )
                )
                ( [], [] )
                pairs
    in
    if not (List.isEmpty errors) then
        Err errors

    else
        Ok (renderModule options pairs parsed)



-- ARGUMENT TYPE INFERENCE


{-| Infer the type of every argument referenced in a message. When an argument
is used in more than one way, the widest compatible type wins (`Float` over
`Int`); a `String`/number conflict resolves to `String`.
-}
inferArgTypes : Message -> Dict String ArgType
inferArgTypes message =
    collect message Dict.empty


collect : Message -> Dict String ArgType -> Dict String ArgType
collect message acc =
    List.foldl collectPart acc message


collectPart : Part -> Dict String ArgType -> Dict String ArgType
collectPart part acc =
    case part of
        Literal _ ->
            acc

        Pound ->
            acc

        Argument name ->
            record name TString acc

        Number name _ ->
            record name TFloat acc

        Date name _ ->
            record name TTime acc

        Time name _ ->
            record name TTime acc

        Select name cases other ->
            let
                withName =
                    record name TString acc

                withCases =
                    List.foldl (\( _, msg ) a -> collect msg a) withName cases
            in
            collect other withCases

        Plural { arg, forms, other } ->
            let
                withArg =
                    record arg TInt acc

                withForms =
                    List.foldl (\( _, msg ) a -> collect msg a) withArg forms
            in
            collect other withForms


record : String -> ArgType -> Dict String ArgType -> Dict String ArgType
record name newType acc =
    case Dict.get name acc of
        Nothing ->
            Dict.insert name newType acc

        Just existing ->
            Dict.insert name (mergeTypes existing newType) acc


mergeTypes : ArgType -> ArgType -> ArgType
mergeTypes a b =
    if a == b then
        a

    else
        case ( a, b ) of
            ( TInt, TFloat ) ->
                TFloat

            ( TFloat, TInt ) ->
                TFloat

            -- Any String/number or String/time mix is a malformed message;
            -- fall back to String so the field at least type-checks.
            _ ->
                TString



-- RENDERING


renderModule : Options -> List ( String, String ) -> List ( String, Message ) -> String
renderModule options rawPairs entries =
    let
        header =
            "module "
                ++ options.moduleName
                ++ " exposing ("
                ++ String.join ", " ("init" :: List.map (Tuple.first >> functionName) entries)
                ++ ")\n\n"
                ++ imports

        masterPairs =
            "masterMessages : List ( String, String )\n"
                ++ "masterMessages =\n    [ "
                ++ (rawPairs
                        |> List.map (\( key, raw ) -> "( " ++ elmString key ++ ", " ++ elmString raw ++ " )")
                        |> String.join "\n    , "
                   )
                ++ "\n    ]"

        functions =
            List.map (\( key, message ) -> renderFunction key message) entries
    in
    String.join "\n\n" (header :: initFunction options :: masterPairs :: functions)


imports : String
imports =
    String.join "\n"
        [ "import Icu.Bundle as Bundle exposing (Bundle)"
        , "import Icu.Format as Format"
        , "import Icu.Locale exposing (Locale)"
        , "import Intl exposing (Intl)"
        , "import Time"
        ]


{-| The generated `init` builds a Bundle from the baked-in master messages.
Runtime locales are loaded separately via `Bundle.withLocale`.
-}
initFunction : Options -> String
initFunction _ =
    String.join "\n"
        [ "init : Intl -> Locale -> Bundle"
        , "init intl locale ="
        , "    let"
        , "        ( messages, _ ) ="
        , "            Bundle.parseMessages masterMessages"
        , "    in"
        , "    Bundle.fromMessages intl locale messages"
        ]


renderFunction : String -> Message -> String
renderFunction key message =
    let
        name =
            functionName key

        types =
            inferArgTypes message

        sortedArgs =
            Dict.toList types
    in
    if List.isEmpty sortedArgs then
        String.join "\n"
            [ name ++ " : Bundle -> String"
            , name ++ " bundle ="
            , "    Bundle.translate bundle " ++ elmString key ++ " Format.args"
            ]

    else
        let
            recordType =
                "{ "
                    ++ (sortedArgs
                            |> List.map (\( argName, t ) -> fieldName argName ++ " : " ++ typeAnnotation t)
                            |> String.join ", "
                       )
                    ++ " }"

            binders =
                sortedArgs
                    |> List.map
                        (\( argName, t ) ->
                            "|> Format."
                                ++ binder t
                                ++ " "
                                ++ elmString argName
                                ++ " args_."
                                ++ fieldName argName
                        )
                    |> String.join "\n            "
        in
        String.join "\n"
            [ name ++ " : Bundle -> " ++ recordType ++ " -> String"
            , name ++ " bundle args_ ="
            , "    Bundle.translate bundle "
                ++ elmString key
                ++ "\n        (Format.args\n            "
                ++ binders
                ++ "\n        )"
            ]


typeAnnotation : ArgType -> String
typeAnnotation t =
    case t of
        TString ->
            "String"

        TInt ->
            "Int"

        TFloat ->
            "Float"

        TTime ->
            "Time.Posix"


binder : ArgType -> String
binder t =
    case t of
        TString ->
            "string"

        TInt ->
            "int"

        TFloat ->
            "float"

        TTime ->
            "time"



-- IDENTIFIER SANITIZATION


{-| Turn a translation key into a valid, lowerCamelCase Elm function name.
`user.profile.title` becomes `userProfileTitle`.
-}
functionName : String -> String
functionName key =
    case sanitizeSegments key of
        [] ->
            "t_"

        first :: rest ->
            (lowerFirst first :: List.map upperFirst rest)
                |> String.concat
                |> ensureLower
                |> avoidReservedWord


{-| Elm reserved words can't be used as function or field names; suffix with `_`
(the conventional escape) so keys like `"type"` or `"if"` generate valid code.
-}
avoidReservedWord : String -> String
avoidReservedWord name =
    if List.member name reservedWords then
        name ++ "_"

    else
        name


reservedWords : List String
reservedWords =
    [ "if", "then", "else", "case", "of", "let", "in", "type", "module"
    , "where", "import", "exposing", "as", "port", "infix", "alias"
    ]


{-| Turn a key into a valid record field name (same rules as function names).
-}
fieldName : String -> String
fieldName =
    functionName


sanitizeSegments : String -> List String
sanitizeSegments key =
    key
        |> String.toList
        |> List.map
            (\c ->
                if Char.isAlphaNum c then
                    c

                else
                    ' '
            )
        |> String.fromList
        |> String.words


lowerFirst : String -> String
lowerFirst s =
    String.left 1 s |> String.toLower |> (\h -> h ++ String.dropLeft 1 s)


upperFirst : String -> String
upperFirst s =
    String.left 1 s |> String.toUpper |> (\h -> h ++ String.dropLeft 1 s)


ensureLower : String -> String
ensureLower s =
    if String.left 1 s |> String.all Char.isDigit then
        "t" ++ s

    else
        lowerFirst s



-- STRING LITERALS


elmString : String -> String
elmString s =
    "\""
        ++ (s
                |> String.replace "\\" "\\\\"
                |> String.replace "\"" "\\\""
                |> String.replace "\n" "\\n"
           )
        ++ "\""
