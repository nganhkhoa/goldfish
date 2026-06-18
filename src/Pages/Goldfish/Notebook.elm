module Pages.Goldfish.Notebook exposing (Model, Msg, page)

import Html exposing (..)
import Html.Attributes exposing (class, disabled)
import Html.Events exposing (onClick)
import Json.Decode as Decode
import Json.Encode as Encode
import Ports
import Shared
import Effect exposing (Effect)
import Route exposing (Route)
import Page exposing (Page)
import View exposing (View)
import Layouts

-- Assume you have these exposed from your Schema/Components
import Schema exposing (CardAST, Block(..), decodeToAST)
import Components.Card as Card
import Components.Flashcard as Flashcard

page : Shared.Model -> Route () -> Page Model Msg
page shared route =
    Page.new
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }
    |> Page.withLayout toLayout

toLayout : Model -> Layouts.Layout Msg
toLayout model =
    Layouts.Main
        { }

subscriptions : Model -> Sub Msg
subscriptions model =
    Ports.receiveNotebook GotNotebookData

-- 1. DOMAIN & STATE

type ViewState
    = NotebookList
    | InsideNotebook String -- The language code (e.g., "ko")

type alias NotebookEntry =
    { notebookId : Int
    , memoryLevel : Int
    , language : String
    , ast : CardAST
    , flipState : Int -- 0 = Front, 1 = Middle, 2 = Back
    }

type alias Model =
    { viewState : ViewState
    , entries : List NotebookEntry
    , expandedCardAst : Maybe CardAST -- For the full card modal
    }


-- 2. MESSAGES & INIT

type Msg
    = GotNotebookData Decode.Value
    | OpenNotebook String
    | GoBack
    | FlipCard Int
    | RemoveEntry Int
    | MarkRemembered Int
    | ExpandCard CardAST
    | CloseModal

init : () -> ( Model, Effect Msg )
init _ =
    ( { viewState = NotebookList
      , entries = []
      , expandedCardAst = Nothing
      }
    , Effect.sendCmd (Ports.requestNotebook ())
    )


-- 3. THE DECODER (Bridging DB to AST)

notebookEntryDecoder : Decode.Decoder NotebookEntry
notebookEntryDecoder =
    Decode.field "lang" Decode.string
        |> Decode.andThen
            (\lang ->
                Decode.map4
                    (\nbId memLevel ast _ ->
                        { notebookId = nbId
                        , memoryLevel = memLevel
                        , language = lang
                        , ast = ast
                        , flipState = 0 -- Start on Front
                        }
                    )
                    (Decode.field "notebook_id" Decode.int)
                    (Decode.field "memory_level" Decode.int)
                    (Decode.field "dict_data" (decodeToAST lang))
                    (Decode.succeed ())
            )


-- 4. UPDATE PIPELINE

update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        GotNotebookData jsonValue ->
            let
                -- 1. Decode the array into a list of raw JSON values first
                rawListResult =
                    Decode.decodeValue (Decode.list Decode.value) jsonValue

                -- 2. Try to decode each item individually
                validEntries =
                    case rawListResult of
                        Ok rawValues ->
                            List.filterMap
                                (\rawItem ->
                                    case Decode.decodeValue notebookEntryDecoder rawItem of
                                        Ok entry ->
                                            Just entry

                                        Err error ->
                                            -- Log exactly which entry is broken so you can fix your DB!
                                            -- let
                                            --     _ = Debug.log "🚨 SKIPPED BROKEN ENTRY" (Decode.errorToString error)
                                            -- in
                                            Nothing
                                )
                                rawValues

                        Err mainError ->
                            -- let
                            --     _ = Debug.log "🚨 CRITICAL NOTEBOOK FAIL" (Decode.errorToString mainError)
                            -- in
                            []
            in
            ( { model | entries = validEntries }, Effect.none )

        OpenNotebook lang ->
            ( { model | viewState = InsideNotebook lang }, Effect.none )

        GoBack ->
            ( { model | viewState = NotebookList, expandedCardAst = Nothing }, Effect.none )

        FlipCard nbId ->
            let
                updatedEntries =
                    List.map
                        (\entry ->
                            if entry.notebookId == nbId then
                                -- Cycle through 0, 1, 2
                                { entry | flipState = modBy 3 (entry.flipState + 1) }
                            else
                                entry
                        )
                        model.entries
            in
            ( { model | entries = updatedEntries }, Effect.none )

        RemoveEntry nbId ->
            let
                -- 1. Optimistic UI: Instantly remove it from the grid
                updatedEntries =
                    List.filter (\entry -> entry.notebookId /= nbId) model.entries

                -- 2. Send the strict mutation type to JS
                payload =
                    Encode.object
                        [ ( "action", Encode.string "REMOVE" )
                        , ( "notebookIdString", Encode.string (String.fromInt nbId) )
                        ]
            in
            ( { model | entries = updatedEntries }
            , Effect.sendCmd (Ports.mutateNotebook payload)
            )

        MarkRemembered nbId ->
            let
                -- 1. Find the current entry to determine the new level
                maybeEntry =
                    List.head (List.filter (\e -> e.notebookId == nbId) model.entries)

                newLevel =
                    case maybeEntry of
                        Just entry ->
                            if entry.memoryLevel == 2 then 0 else 2
                        Nothing ->
                            0

                -- 2. Optimistic UI Update
                updatedEntries =
                    List.map
                        (\entry ->
                            if entry.notebookId == nbId then
                                { entry | memoryLevel = newLevel }
                            else
                                entry
                        )
                        model.entries

                -- 3. DB Mutation Payload
                payload =
                    Encode.object
                        [ ( "action", Encode.string "UPDATE_LEVEL" )
                        , ( "notebookIdString", Encode.string (String.fromInt nbId) )
                        , ( "newLevel", Encode.int newLevel )
                        ]
            in
            ( { model | entries = updatedEntries }
            , Effect.sendCmd (Ports.mutateNotebook payload)
            )

        ExpandCard ast ->
            ( { model | expandedCardAst = Just ast }, Effect.none )

        CloseModal ->
            ( { model | expandedCardAst = Nothing }, Effect.none )


-- 5. VIEW RENDERING

view : Model -> View Msg
view model =
    { title = "Your Notebooks"
    , body =
        [ div [ class "notebook-container" ]
            [ case model.viewState of
                NotebookList ->
                    viewNotebookList model.entries

                InsideNotebook lang ->
                    viewNotebookGrid lang model.entries

            , -- The Full Card Modal Overlay
              viewModal model.expandedCardAst
            ]
        ]
    }


-- VIEW: The Summary List (Image 1)
viewNotebookList : List NotebookEntry -> Html Msg
viewNotebookList entries =
    let
        countLang lang =
            List.length (List.filter (\e -> e.language == lang) entries)

        viewPack title lang count =
            div [ class "pack-card", onClick (OpenNotebook lang) ]
                [ h3 [] [ text title ]
                , span [ class "pack-count" ] [ text (String.fromInt count ++ " saved words") ]
                ]
    in
    div []
        [ h2 [ class "page-title" ] [ text "Your Notebooks" ]
        , div [ class "pack-grid" ]
            [ viewPack "All Saved Words" "" (List.length entries)
            , viewPack "Chinese Pack" "cn" (countLang "cn")
            , viewPack "Japanese Pack" "jp" (countLang "jp")
            , viewPack "Korean Pack" "ko" (countLang "ko")
            ]
        ]


-- VIEW: The Flashcard Grid (Images 2 & 3)
viewNotebookGrid : String -> List NotebookEntry -> Html Msg
viewNotebookGrid targetLang allEntries =
    let
        filteredEntries =
            if targetLang == "" then
                allEntries
            else
                List.filter (\e -> e.language == targetLang) allEntries
    in
    div []
        [ button [ class "back-btn", onClick GoBack ] [ text "← Back to Notebooks" ]
        , div [ class "flashcard-grid" ]
            -- Map the entries directly into the new component!
            (List.map
                (\entry ->
                    Flashcard.view
                        { ast = entry.ast
                        , flipState = entry.flipState
                        , memoryLevel = entry.memoryLevel
                        , onFlip = FlipCard entry.notebookId
                        , onExpand = ExpandCard entry.ast
                        , onRemember = MarkRemembered entry.notebookId
                        , onRemove = RemoveEntry entry.notebookId
                        }
                )
                filteredEntries
            )
        ]

-- VIEW: The Expand Modal
viewModal : Maybe CardAST -> Html Msg
viewModal maybeAst =
    case maybeAst of
        Just ast ->
            div [ class "modal-backdrop", onClick CloseModal ]
                [ div [ class "modal-content", onClick CloseModal ]
                    [ Card.view (\_ -> CloseModal) ast ]
                ]
        Nothing ->
            text ""
