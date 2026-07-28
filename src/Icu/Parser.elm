module Icu.Parser exposing (parse, deadEndsToString)

{-| Parse an [ICU MessageFormat](https://formatjs.github.io/docs/core-concepts/icu-syntax)
string into an [`Icu.Ast.Message`](Icu-Ast#Message).

@docs parse, deadEndsToString

-}

import Icu.Ast as Ast exposing (Message, Part(..), PluralSelector(..))
import Parser exposing ((|.), (|=), Parser, Step(..))


{-| Parse an ICU message string.

    parse "Hello, {name}!"
    --> Ok [ Literal "Hello, ", Argument "name", Literal "!" ]

-}
parse : String -> Result (List Parser.DeadEnd) Message
parse input =
    Parser.run (message topLevel |. Parser.end) input


{-| Render parser errors as a human-readable string.
-}
deadEndsToString : List Parser.DeadEnd -> String
deadEndsToString deadEnds =
    String.join "; " (List.map deadEndToString deadEnds)


deadEndToString : Parser.DeadEnd -> String
deadEndToString { row, col, problem } =
    "row " ++ String.fromInt row ++ " col " ++ String.fromInt col ++ ": " ++ problemToString problem


problemToString : Parser.Problem -> String
problemToString problem =
    case problem of
        Parser.Expecting s ->
            "expecting " ++ s

        Parser.ExpectingInt ->
            "expecting int"

        Parser.ExpectingHex ->
            "expecting hex"

        Parser.ExpectingOctal ->
            "expecting octal"

        Parser.ExpectingBinary ->
            "expecting binary"

        Parser.ExpectingFloat ->
            "expecting float"

        Parser.ExpectingNumber ->
            "expecting number"

        Parser.ExpectingVariable ->
            "expecting variable"

        Parser.ExpectingSymbol s ->
            "expecting symbol " ++ s

        Parser.ExpectingKeyword s ->
            "expecting keyword " ++ s

        Parser.ExpectingEnd ->
            "expecting end"

        Parser.UnexpectedChar ->
            "unexpected char"

        Parser.Problem s ->
            s

        Parser.BadRepeat ->
            "bad repeat"



-- CONTEXT
--
-- A message is parsed differently depending on where it appears. At the top
-- level, `#` is just a literal character and only `{` opens a placeholder. In
-- a plural branch, `#` is the pound placeholder. In any nested branch, a
-- closing `}` terminates the message.


type alias Context =
    { nested : Bool -- are we inside a `{ ... }` branch (so `}` ends the message)?
    , pound : Bool -- does `#` mean the pound placeholder here?
    }


topLevel : Context
topLevel =
    { nested = False, pound = False }


branchContext : Bool -> Context
branchContext poundActive =
    { nested = True, pound = poundActive }



-- MESSAGE


message : Context -> Parser Message
message ctx =
    Parser.loop [] (messageStep ctx)
        |> Parser.map (List.reverse >> mergeLiterals)


messageStep : Context -> List Part -> Parser (Step (List Part) (List Part))
messageStep ctx revParts =
    -- `partParser` fails without consuming on a closing `}` (when nested) and
    -- at end-of-input, so falling through to `Done` terminates the loop. The
    -- caller (`branch`) consumes the `}`.
    Parser.oneOf
        [ partParser ctx |> Parser.map (\p -> Loop (p :: revParts))
        , Parser.succeed (Done revParts)
        ]


partParser : Context -> Parser Part
partParser ctx =
    Parser.oneOf
        [ placeholder
        , if ctx.pound then
            Parser.map (always Pound) (Parser.symbol "#")

          else
            -- `#` outside a plural is ordinary text, handled by `literal`.
            Parser.problem "not a pound context"
        , literal ctx
        ]



-- LITERAL TEXT
--
-- ICU quoting: a single quote starts a quoted section in which `{`, `}` (and
-- `#` inside plurals) are literal. `''` is a literal apostrophe. An unmatched
-- opening quote quotes to the end of the message.


literal : Context -> Parser Part
literal ctx =
    Parser.oneOf
        [ quoted
        , Parser.getChompedString (Parser.chompIf (isPlainChar ctx))
            |> Parser.map Literal
        ]


isPlainChar : Context -> Char -> Bool
isPlainChar ctx c =
    case c of
        '{' ->
            False

        '}' ->
            not ctx.nested

        '\'' ->
            False

        '#' ->
            not ctx.pound

        _ ->
            True


{-| Parse a quoted section starting at `'`. `''` yields a literal apostrophe.
`'{foo}'` yields the literal text `{foo}`.
-}
quoted : Parser Part
quoted =
    Parser.symbol "'"
        |> Parser.andThen
            (\_ ->
                Parser.oneOf
                    [ Parser.map (always (Literal "'")) (Parser.symbol "'")
                    , Parser.getChompedString (Parser.chompWhile (\c -> c /= '\''))
                        |> Parser.andThen
                            (\chomped ->
                                Parser.oneOf
                                    [ Parser.symbol "'" |> Parser.map (always (Literal chomped))
                                    , Parser.end |> Parser.map (always (Literal chomped))
                                    ]
                            )
                    ]
            )



-- PLACEHOLDER: { ... }


placeholder : Parser Part
placeholder =
    Parser.succeed identity
        |. Parser.symbol "{"
        |. spaces
        |= (argName
                |> Parser.andThen placeholderBody
           )
        |. spaces
        |. Parser.symbol "}"


placeholderBody : String -> Parser Part
placeholderBody name =
    Parser.oneOf
        [ Parser.succeed identity
            |. Parser.backtrackable spaces
            |. Parser.symbol ","
            |. spaces
            |= typedBody name
        , Parser.succeed (Argument name)
        ]


typedBody : String -> Parser Part
typedBody name =
    keyword
        |> Parser.andThen
            (\kind ->
                case kind of
                    "number" ->
                        Parser.map (Number name) optionalStyle

                    "date" ->
                        Parser.map (Date name) optionalStyle

                    "time" ->
                        Parser.map (Time name) optionalStyle

                    "select" ->
                        Parser.succeed identity
                            |. caseSeparator
                            |= selectBody name

                    "plural" ->
                        Parser.succeed identity
                            |. caseSeparator
                            |= pluralBody name False

                    "selectordinal" ->
                        Parser.succeed identity
                            |. caseSeparator
                            |= pluralBody name True

                    other ->
                        Parser.problem ("Unknown placeholder type: " ++ other)
            )


{-| An optional `, style` suffix on number/date/time. The style runs until the
closing `}` of the placeholder. Skeletons (`::currency/USD`) are captured
verbatim as the style string.
-}
optionalStyle : Parser (Maybe String)
optionalStyle =
    Parser.oneOf
        [ Parser.succeed (String.trim >> emptyToNothing)
            |. Parser.backtrackable spaces
            |. Parser.symbol ","
            |. spaces
            |= Parser.getChompedString (Parser.chompWhile (\c -> c /= '}'))
        , Parser.succeed Nothing
        ]


{-| The comma separating the `select` / `plural` keyword from its cases.
-}
caseSeparator : Parser ()
caseSeparator =
    Parser.succeed ()
        |. spaces
        |. Parser.symbol ","
        |. spaces


emptyToNothing : String -> Maybe String
emptyToNothing s =
    if String.isEmpty s then
        Nothing

    else
        Just s



-- SELECT


selectBody : String -> Parser Part
selectBody name =
    Parser.loop [] selectStep
        |> Parser.andThen
            (\cases ->
                case extractOther cases of
                    Just ( other, rest ) ->
                        Parser.succeed (Select name (List.reverse rest) other)

                    Nothing ->
                        Parser.problem "select requires an 'other' branch"
            )


selectStep : List ( String, Message ) -> Parser (Step (List ( String, Message )) (List ( String, Message )))
selectStep acc =
    Parser.oneOf
        [ Parser.succeed (\k v -> Loop (( k, v ) :: acc))
            |. Parser.backtrackable spaces
            |= selectorKey
            |. spaces
            |= branch False
        , Parser.succeed (Done acc) |. spaces
        ]



-- PLURAL / SELECTORDINAL


pluralBody : String -> Bool -> Parser Part
pluralBody name ordinal =
    Parser.succeed (\offset cases -> ( offset, cases ))
        |= pluralOffset
        |= Parser.loop [] (pluralStep name)
        |> Parser.andThen
            (\( offset, cases ) ->
                case extractOtherPlural cases of
                    Just ( other, rest ) ->
                        Parser.succeed <|
                            Plural
                                { arg = name
                                , ordinal = ordinal
                                , offset = offset
                                , forms = List.reverse rest
                                , other = other
                                }

                    Nothing ->
                        Parser.problem "plural requires an 'other' branch"
            )


pluralOffset : Parser Int
pluralOffset =
    Parser.oneOf
        [ Parser.succeed identity
            |. Parser.backtrackable spaces
            |. Parser.symbol "offset:"
            |. spaces
            |= Parser.int
        , Parser.succeed 0
        ]


pluralStep :
    String
    -> List ( PluralSelector, Message )
    -> Parser (Step (List ( PluralSelector, Message )) (List ( PluralSelector, Message )))
pluralStep name acc =
    Parser.oneOf
        [ Parser.succeed (\k v -> Loop (( k, v ) :: acc))
            |. Parser.backtrackable spaces
            |= pluralSelector
            |. spaces
            |= branch True
        , Parser.succeed (Done acc) |. spaces
        ]


pluralSelector : Parser PluralSelector
pluralSelector =
    Parser.oneOf
        [ Parser.succeed Exact
            |. Parser.symbol "="
            |= Parser.int
        , Parser.map Keyword selectorKey
        ]


{-| A `{ ... }` branch body. `poundActive` says whether `#` is meaningful
inside it (true for plural branches).
-}
branch : Bool -> Parser Message
branch poundActive =
    Parser.succeed identity
        |. Parser.symbol "{"
        |= message (branchContext poundActive)
        |. Parser.symbol "}"



-- SHARED LEXING


argName : Parser String
argName =
    Parser.getChompedString (Parser.chompWhile isNameChar)
        |> Parser.andThen
            (\s ->
                if String.isEmpty s then
                    Parser.problem "expected an argument name"

                else
                    Parser.succeed s
            )


isNameChar : Char -> Bool
isNameChar c =
    Char.isAlphaNum c || c == '_' || c == '.' || c == '-'


{-| A select/plural keyword like `other`, `one`, `few`.
-}
selectorKey : Parser String
selectorKey =
    Parser.getChompedString (Parser.chompWhile (\c -> Char.isAlphaNum c || c == '_'))
        |> Parser.andThen
            (\s ->
                if String.isEmpty s then
                    Parser.problem "expected a selector keyword"

                else
                    Parser.succeed s
            )


keyword : Parser String
keyword =
    Parser.getChompedString (Parser.chompWhile Char.isAlpha)
        |> Parser.andThen
            (\s ->
                if String.isEmpty s then
                    Parser.problem "expected a placeholder type"

                else
                    Parser.succeed s
            )


{-| Whitespace, including newlines.
-}
spaces : Parser ()
spaces =
    Parser.chompWhile (\c -> c == ' ' || c == '\t' || c == '\n' || c == '\u{000D}')



-- POST-PROCESSING


extractOther : List ( String, Message ) -> Maybe ( Message, List ( String, Message ) )
extractOther cases =
    case List.filter (\( k, _ ) -> k == "other") cases of
        ( _, other ) :: _ ->
            Just ( other, List.filter (\( k, _ ) -> k /= "other") cases )

        [] ->
            Nothing


extractOtherPlural :
    List ( PluralSelector, Message )
    -> Maybe ( Message, List ( PluralSelector, Message ) )
extractOtherPlural cases =
    case List.filter (\( k, _ ) -> k == Keyword "other") cases of
        ( _, other ) :: _ ->
            Just ( other, List.filter (\( k, _ ) -> k /= Keyword "other") cases )

        [] ->
            Nothing


{-| Merge adjacent `Literal` parts produced by the quoting rules into one.
-}
mergeLiterals : List Part -> List Part
mergeLiterals parts =
    List.foldr
        (\part acc ->
            case ( part, acc ) of
                ( Literal a, (Literal b) :: rest ) ->
                    Literal (a ++ b) :: rest

                _ ->
                    part :: acc
        )
        []
        parts
