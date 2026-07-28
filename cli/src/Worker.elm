port module Worker exposing (main)

{-| A thin worker that bridges the JS CLI to the pure `Icu.Codegen.generate`.

The JS side sends the master translations (as `(key, icuString)` pairs) plus the
target module name; this worker replies with either the generated Elm source or
the list of per-key parse errors.
-}

import Icu.Codegen as Codegen
import Json.Decode as Decode
import Json.Encode as Encode


type alias Input =
    { moduleName : String
    , pairs : List ( String, String )
    }


port generated : Encode.Value -> Cmd msg


decoder : Decode.Decoder Input
decoder =
    Decode.map2 Input
        (Decode.field "moduleName" Decode.string)
        (Decode.field "pairs" (Decode.keyValuePairs Decode.string))


run : Input -> Encode.Value
run input =
    case Codegen.generate { moduleName = input.moduleName } input.pairs of
        Ok source ->
            Encode.object
                [ ( "ok", Encode.bool True )
                , ( "source", Encode.string source )
                ]

        Err errors ->
            Encode.object
                [ ( "ok", Encode.bool False )
                , ( "errors"
                  , Encode.list
                        (\( key, message ) ->
                            Encode.object
                                [ ( "key", Encode.string key )
                                , ( "message", Encode.string message )
                                ]
                        )
                        errors
                  )
                ]


main : Program Decode.Value () ()
main =
    Platform.worker
        { init =
            \flags ->
                ( ()
                , case Decode.decodeValue decoder flags of
                    Ok input ->
                        generated (run input)

                    Err err ->
                        generated
                            (Encode.object
                                [ ( "ok", Encode.bool False )
                                , ( "errors"
                                  , Encode.list identity
                                        [ Encode.object
                                            [ ( "key", Encode.string "<input>" )
                                            , ( "message", Encode.string (Decode.errorToString err) )
                                            ]
                                        ]
                                  )
                                ]
                            )
                )
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }
