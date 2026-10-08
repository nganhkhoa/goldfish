module Pages.Goldfish.Notebook exposing (Model, Msg, page)

import Html exposing (..)
import Html.Attributes exposing (class, disabled, value)
import Html.Events exposing (on)
import Html.Events exposing (onClick, stopPropagationOn)
import Json.Decode as Decode
import Json.Encode as Encode
import Random
import Random.Extra
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

import NotebookEntry exposing (NotebookEntry)

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
    Sub.batch
        [ Ports.receiveNotebook GotNotebookData
        , Ports.receiveWordsByLevelNotebook GotLevelData
        ]

-- 1. DOMAIN & STATE

type ViewState
    = NotebookList
    | InsideNotebook
    | LoadingLevel

type alias Model =
    { viewState : ViewState
    , entries : List NotebookEntry
    , notebookEntries : List NotebookEntry
    , levelEntries : List NotebookEntry
    , expandedCardAst : Maybe CardAST -- For the full card modal
    , conjugationRule : String
    , conjugatedText : Maybe String
    , lang : Maybe String
    }


-- 2. MESSAGES & INIT

type Msg
    = GotNotebookData Decode.Value
    | GotLevelData Decode.Value
    | OpenNotebook String
    | OpenLevel String Int
    | GoBack
    | FlipCard String
    | RemoveEntry String
    | MarkRemembered String
    | ExpandCard CardAST
    | CloseModal
    | SetConjugationRule String
    | ApplyConjugation
    | IgnoreModalClick
    | ShuffleWords
    | ScrollToTop
    | Shuffled (List Float)

init : () -> ( Model, Effect Msg )
init _ =
    ( { viewState = NotebookList
      , entries = []
      , notebookEntries = []
      , levelEntries = []
      , expandedCardAst = Nothing
      , conjugationRule = "want"
      , conjugatedText = Nothing
      , lang = Nothing
      }
    , Effect.sendCmd (Ports.requestNotebook ())
    )


shuffleEntries : List NotebookEntry -> Random.Generator (List Float)
shuffleEntries entries =
    Random.list (List.length entries) (Random.float 0 1)

sortByRandom : List Float -> List NotebookEntry -> List NotebookEntry
sortByRandom values entries =
    List.map Tuple.second
        (List.sortBy Tuple.first (List.map2 Tuple.pair values entries))


decodeEntries : Decode.Value -> List NotebookEntry
decodeEntries jsonValue =
    case Decode.decodeValue (Decode.list Decode.value) jsonValue of
        Ok rawValues ->
            List.filterMap
                (\rawItem ->
                    case Decode.decodeValue NotebookEntry.decoder rawItem of
                        Ok entry -> Just entry
                        Err _ -> Nothing
                )
                rawValues

        Err _ ->
            []

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
                                    case Decode.decodeValue NotebookEntry.decoder rawItem of
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
            ( { model | entries = validEntries, notebookEntries = validEntries }, Effect.none )

        ScrollToTop ->
            ( model, Effect.sendCmd (Ports.scrollToTop ()) )

        ShuffleWords ->
            ( model, Effect.sendCmd (Random.generate Shuffled (shuffleEntries model.entries)) )

        Shuffled order ->
            ( { model | entries = sortByRandom order model.entries }
            , Effect.none
            )

        GotLevelData jsonValue ->
            let
                decoded = decodeEntries jsonValue
            in
            ( { model | viewState = InsideNotebook, entries = decoded, levelEntries = decoded }
            , Effect.none
            )

        OpenNotebook lang ->
            -- Always reload the real notebook before showing the all-saved view.
            -- The current entries may be a level-filtered result set.
            ( { model | viewState = InsideNotebook, entries = [], lang = Just lang }
            , Effect.sendCmd (Ports.requestNotebook ())
            )

        GoBack ->
            -- A level view uses the same `entries` field as the notebook view.
            -- Clear it immediately and reload the actual notebook so level
            -- words cannot leak into the notebook list after navigating back.
            ( { model | viewState = NotebookList, entries = [], expandedCardAst = Nothing }
            , Effect.sendCmd (Ports.requestNotebook ())
            )

        FlipCard nbId ->
            let
                updatedEntries =
                    List.map
                        (\entry ->
                            if entry.cardKey == nbId then
                                let
                                    -- Scan the AST layout to see if a valid SubTitle block exists
                                    hasSubTitle =
                                        List.any
                                            (\block ->
                                                case block of
                                                    SubTitle text ->
                                                        not (String.isEmpty (String.trim text))

                                                    _ ->
                                                        False
                                            )
                                            entry.ast.layout

                                    -- Route the states based on the AST check
                                    nextState =
                                        case entry.flipState of
                                            0 ->
                                                -- If on Main Title: go to SubTitle if it exists, else skip to Meaning
                                                if hasSubTitle then 1 else 2

                                            1 ->
                                                -- If on SubTitle: always go to Meaning next
                                                2

                                            _ ->
                                                -- If on Meaning (2) or fallback: loop back to Main Title
                                                0
                                in
                                { entry | flipState = nextState }
                            else
                                entry
                        )
                        model.entries
            in
            ( { model | entries = updatedEntries }, Effect.none )

        RemoveEntry cardKey ->
            case List.filter (\entry -> entry.cardKey == cardKey) model.entries |> List.head of
                Just entry ->
                    let
                        deleteCmd =
                            NotebookEntry.Remove { notebookId = entry.notebookId }
                                |> NotebookEntry.encodeMutation
                                |> Ports.mutateNotebook
                    in
                    ( model, Effect.sendCmd deleteCmd )

                Nothing ->
                    ( model, Effect.none )

        MarkRemembered nbId ->
            let
                -- Card interactions use the stable dictionary key, not a
                -- generated notebook/index value.
                maybeEntry =
                    List.head (List.filter (\e -> e.cardKey == nbId) model.entries)

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
                            if entry.cardKey == nbId then
                                { entry | memoryLevel = newLevel }
                            else
                                entry
                        )
                        model.entries

                -- 3. DB Mutation Payload
                payload =
                    case maybeEntry of
                        Just entry ->
                            Encode.object
                                [ ( "action", Encode.string "UPDATE_LEVEL" )
                                , ( "notebookIdString", Encode.string (String.fromInt entry.notebookId) )
                                , ( "newLevel", Encode.int newLevel )
                                ]

                        Nothing ->
                            Encode.object []
            in
            ( { model | entries = updatedEntries }
            , Effect.sendCmd (Ports.mutateNotebook payload)
            )

        OpenLevel lang level ->
            let
                payload =
                    Encode.object
                        [ ( "lang", Encode.string lang )
                        , ( "level", Encode.int level )
                        ]
            in
            ( { model | viewState = InsideNotebook, entries = [], lang = Just lang }
            , Effect.sendCmd (Ports.requestWordsByLevelNotebook payload)
            )

        ExpandCard ast ->
            ( { model | expandedCardAst = Just ast }, Effect.none )

        CloseModal ->
            ( { model | expandedCardAst = Nothing }, Effect.none )

        SetConjugationRule rule ->
            ( { model | conjugationRule = rule }, Effect.none )

        IgnoreModalClick ->
            ( model, Effect.none )

        ApplyConjugation ->
            ( { model
                | conjugatedText =
                    model.expandedCardAst
                        |> Maybe.andThen (\ast -> mainTitle ast |> Maybe.andThen (applyDemoRule model.conjugationRule))
              }
            , Effect.none
            )


-- 5. VIEW RENDERING

view : Model -> View Msg
view model =
    { title = "Your Notebooks"
    , body =
        [ div [ class "notebook-container" ]
            [ case model.viewState of
                LoadingLevel ->
                    div [ class "loading-state" ] [ text "Loading words..." ]

                NotebookList ->
                    viewNotebookList model.notebookEntries

                InsideNotebook ->
                    viewNotebookGrid model.lang model.entries

            , floatingToolbar model.viewState
            , viewModal model model.expandedCardAst
            ]
        ]
    }


floatingToolbar : ViewState -> Html Msg
floatingToolbar state =
    case state of
        NotebookList ->
            text ""

        _ ->
            div [ class "floating-toolbar" ]
                [ button [ class "toolbar-button", onClick ScrollToTop ] [ text "↑ Top" ]
                , button [ class "toolbar-button", onClick ShuffleWords ] [ text "🔀 Shuffle" ]
                ]


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

        viewLangGroup title lang prefix levels =
            div [ class "lang-group-card" ]
                [ h3 [] [ text title ]
                , div [ class "level-buttons" ]
                    (List.map
                        (\lvl ->
                            button
                                [ class "pack-card", onClick (OpenLevel lang lvl) ]
                                [ text (prefix ++ " " ++ String.fromInt lvl) ]
                        )
                        levels
                    )
                ]
    in
    div []
        [ h2 [ class "page-title" ] [ text "Your Notebooks" ]
        , div [ class "pack-grid" ]
            [ viewPack "All Saved Words" "" (List.length entries)
            , viewPack "Chinese Pack" "cn" (countLang "cn")
            , viewPack "Japanese Pack" "jp" (countLang "jp")
            , viewPack "Korean Pack" "ko" (countLang "ko")
            , viewLangGroup "Chinese" "cn" "HSK" [ 1, 2, 3, 4, 5, 6, 7 ]
            , viewLangGroup "Japanese" "jp" "JLPT N" [ 5, 4, 3, 2, 1 ]
            , viewLangGroup "Korean" "ko" "TOPIK" [ 1, 2 ]
            ]
        ]


-- VIEW: The Flashcard Grid (Images 2 & 3)
viewNotebookGrid : Maybe String -> List NotebookEntry -> Html Msg
viewNotebookGrid targetLang allEntries =
    let
        filteredEntries =
            case targetLang of
                Just lang -> List.filter (\e -> e.language == lang) allEntries
                _ -> allEntries
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
                        , onFlip = FlipCard entry.cardKey
                        , onExpand = ExpandCard entry.ast
                        , onRemember = MarkRemembered entry.cardKey
                        , onRemove = RemoveEntry entry.cardKey
                        }
                )
                filteredEntries
            )
        ]

-- VIEW: The Expand Modal
mainTitle : CardAST -> Maybe String
mainTitle ast =
    ast.layout
        |> List.filterMap (\block -> case block of
            MainTitle word -> Just word
            _ -> Nothing
        )
        |> List.head

applyDemoRule : String -> String -> Maybe String
applyDemoRule rule word =
    case rule of
        "want" -> Just (if String.endsWith "る" word then String.dropRight 1 word ++ "たい" else word ++ "たい")
        "negative" -> Just (if String.endsWith "い" word then String.dropRight 1 word ++ "くない" else word ++ "ない")
        "polite" -> Just (if String.endsWith "る" word then String.dropRight 1 word ++ "ます" else word ++ "ます")
        _ -> Just word

conjugationPanel : Model -> CardAST -> Html Msg
conjugationPanel model ast =
    div [ class "conjugation-panel" ]
        [ h3 [] [ text "Conjugation helper" ]
        , select [ on "change" (Decode.map SetConjugationRule (Decode.field "target" (Decode.field "value" Decode.string))) ]
            [ option [ value "want" ] [ text "Want to do (たい)" ]
            , option [ value "negative" ] [ text "Negative informal" ]
            , option [ value "polite" ] [ text "Polite form" ]
            ]
        , button [ class "reading-primary-button", onClick ApplyConjugation ] [ text "Add" ]
        , case model.conjugatedText of
            Just result -> p [ class "conjugation-result" ] [ text result ]
            Nothing -> text ""
        ]


viewModal : Model -> Maybe CardAST -> Html Msg
viewModal model maybeAst =
    case maybeAst of
        Just ast ->
            div [ class "modal-backdrop", onClick CloseModal ]
                [ div [ class "modal-content", stopPropagationOn "click" (Decode.succeed ( IgnoreModalClick, True )) ]
                    [ Card.view (\_ -> CloseModal) ast
                    , conjugationPanel model ast
                    ]
                ]
        Nothing ->
            text ""

