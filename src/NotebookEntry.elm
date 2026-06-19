module NotebookEntry exposing (NotebookEntry, NotebookMutation(..), decoder, encodeMutation)

import Json.Decode as Decode
import Json.Encode as Encode

import Schema exposing (CardAST, Block(..), decodeToAST)

type alias NotebookEntry =
    { notebookId : Int
    , memoryLevel : Int
    , language : String
    , ast : CardAST
    , flipState : Int
    -- The new SM-2 continuous variables:
    , interval : Float       -- The current gap between reviews (in days)
    , easeFactor : Float     -- The multiplier (default is 2.5)
    , nextReview : Int       -- Unix timestamp in milliseconds for the next due date
    }

type NotebookMutation
    = Add { lang : String, wordId : String, refId : String }
    | Remove { notebookId : Int }
    | RemoveByWordId { lang : String, wordId : String }
    | UpdateLevel { notebookId : Int, newLevel : Int }
    | UpdateStats NotebookEntry


-- 3. THE DECODER (Bridging DB to AST)

decoder : Decode.Decoder NotebookEntry
decoder =
    Decode.field "lang" Decode.string
        |> Decode.andThen
            (\lang ->
                -- We use map8 because NotebookEntry now has exactly 8 fields
                Decode.map8 NotebookEntry
                    (Decode.field "notebook_id" Decode.int)
                    (Decode.field "memory_level" Decode.int)
                    (Decode.succeed lang)
                    (Decode.field "dict_data" (decodeToAST lang))
                    (Decode.succeed 0) -- flipState always starts at 0

                    -- Schema Migration: Attempt to read SM-2 fields, fallback if missing
                    (Decode.maybe (Decode.field "interval" Decode.float)
                        |> Decode.map (Maybe.withDefault 0.0)
                    )
                    (Decode.maybe (Decode.field "easeFactor" Decode.float)
                        |> Decode.map (Maybe.withDefault 2.5)
                    )
                    (Decode.maybe (Decode.field "nextReview" Decode.int)
                        |> Decode.map (Maybe.withDefault 0)
                    )
            )

encodeMutation : NotebookMutation -> Encode.Value
encodeMutation mutation =
    case mutation of
        Add data ->
            Encode.object
                [ ( "action", Encode.string "ADD" )
                , ( "lang", Encode.string data.lang )
                , ( "wordId", Encode.string data.wordId )
                , ( "refId", Encode.string data.refId )
                ]

        Remove data ->
            Encode.object
                [ ( "action", Encode.string "REMOVE" )
                -- JS expects notebookIdString, so we cast the Int to a String
                , ( "notebookIdString", Encode.string (String.fromInt data.notebookId) )
                ]

        RemoveByWordId data ->
            Encode.object
                [ ( "action", Encode.string "REMOVE_BY_WORD_ID" )
                , ( "lang", Encode.string data.lang )
                , ( "wordId", Encode.string data.wordId )
                ]

        UpdateLevel data ->
            Encode.object
                [ ( "action", Encode.string "UPDATE_LEVEL" )
                , ( "notebookIdString", Encode.string (String.fromInt data.notebookId) )
                , ( "newLevel", Encode.int data.newLevel )
                ]

        UpdateStats entry ->
            Encode.object
                [ ( "action", Encode.string "UPDATE_STATS" )
                , ( "notebookIdString", Encode.string (String.fromInt entry.notebookId) )
                , ( "newLevel", Encode.int entry.memoryLevel )
                , ( "interval", Encode.float entry.interval )
                , ( "easeFactor", Encode.float entry.easeFactor )
                , ( "nextReview", Encode.int entry.nextReview )
                ]
