module Pages.Goldfish.Learn.Flashcards exposing (Model, Msg, page)

import Dict
import Effect exposing (Effect)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as Decode
import Learn.Engine as Engine exposing (Session, PackFilter)
import NotebookEntry exposing (NotebookEntry)
import Schema exposing (Block(..))
import Page exposing (Page)
import Ports
import Route exposing (Route)
import Route.Path
import Shared
import View exposing (View)
import Time
import Task
import Random
import Random.List

type alias Model =
    { session : Maybe Session
    , currentCardState : CardState
    , isLoading : Bool
    , filterType : PackFilter
    , langFilter : String
    }

type CardState = ShowingQuestion | ShowingAnswer

type Msg
    = GotNotebookData Decode.Value
    | GotSeedAndInit (List NotebookEntry) Time.Posix
    | GotTimeAndQuality Int Int
    | RevealAnswer
    | RateCard Int
    | QuitEarly
    | SessionAdvanced Session

saveAndAdvance : Int -> Int -> Session -> Cmd Msg
saveAndAdvance now quality sess =
    case sess.current of
        Nothing -> Cmd.none
        Just card ->
            let
                -- 1. Calculate the new state
                newSess = Engine.processAnswer now quality sess
                -- 2. Calculate the stats to save
                graded = Engine.evaluateCard now quality card
            in
            -- 3. Trigger the mutation port and a custom "Advanced" message
            Cmd.batch
                [ Ports.mutateNotebook (NotebookEntry.encodeMutation (NotebookEntry.UpdateStats graded))
                , Task.perform (\_ -> SessionAdvanced newSess) (Task.succeed ())
                ]

page : Shared.Model -> Route () -> Page Model Msg
page _ route =
    Page.new
        { init = \_ ->
            let
                rawFilterStr = Dict.get "filter" route.query |> Maybe.withDefault "all"
                fType = Engine.parseFilter rawFilterStr
                lFilter = Dict.get "lang" route.query |> Maybe.withDefault "all"
            in
            ( { session = Nothing
              , currentCardState = ShowingQuestion
              , isLoading = True
              , filterType = fType
              , langFilter = lFilter
              }
            , Effect.sendCmd (Ports.requestNotebook ())
            )
        , update = update
        , subscriptions = \_ -> Ports.receiveNotebook GotNotebookData
        , view = \model -> view model
        }

update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        GotNotebookData jsonValue ->
            if model.session /= Nothing then
                ( model, Effect.none )
            else
                let
                    -- 1. Decode your JSON
                    rawListResult = Decode.decodeValue (Decode.list Decode.value) jsonValue
                    validEntries = case rawListResult of
                        Ok rawValues -> List.filterMap (\rawItem -> Result.toMaybe (Decode.decodeValue NotebookEntry.decoder rawItem)) rawValues
                        Err _ -> []

                    -- 2. Apply your basic filters (Language/Type)
                    langFiltered = if model.langFilter == "all" then validEntries else List.filter (\e -> e.language == model.langFilter) validEntries
                in
                -- 3. Ask for the time, and pass our filtered list along for the ride!
                ( model, Effect.sendCmd (Task.perform (\t -> GotSeedAndInit langFiltered t) Time.now) )

        GotSeedAndInit finalQueue time ->
            let
                now = Time.posixToMillis time
                seed = Random.initialSeed now
                newSession = Engine.initSession now seed finalQueue model.filterType
            in
            ( { model | session = Just newSession, isLoading = False }, Effect.none )

        RateCard quality ->
            ( model, Effect.sendCmd (Task.perform (\t -> GotTimeAndQuality (Time.posixToMillis t) quality) Time.now) )

        GotTimeAndQuality now quality ->
            case model.session of
                Nothing ->
                    ( model, Effect.none )

                Just sess ->
                    let
                        -- 1. Get the next state IMMEDIATELY
                        newSess = Engine.processAnswer now quality sess

                        -- 2. Construct the save command
                        saveCmd = case sess.current of
                            Just card ->
                                NotebookEntry.UpdateStats (Engine.evaluateCard now quality card)
                                    |> NotebookEntry.encodeMutation
                                    |> Ports.mutateNotebook
                            Nothing -> Cmd.none
                    in
                    -- 3. If the list is empty, redirect. Otherwise, update the session.
                    if newSess.current == Nothing then
                        ( { model | session = Nothing }
                        , Effect.batch [ Effect.sendCmd saveCmd, Effect.pushRoute { path = Route.Path.Goldfish_Learn, query = Dict.empty, hash = Nothing } ]
                        )
                    else
                        ( { model | session = Just newSess, currentCardState = ShowingQuestion }
                        , Effect.sendCmd saveCmd
                        )

        SessionAdvanced newSess ->
            ( { model | session = Just newSess, currentCardState = ShowingQuestion }, Effect.none )

        RevealAnswer -> ( { model | currentCardState = ShowingAnswer }, Effect.none )
        QuitEarly -> ( model, Effect.pushRoute { path = Route.Path.Goldfish_Learn, query = Dict.empty, hash = Nothing } )

view : Model -> View Msg
view model =
    { title = "Flashcards"
    , body =
        [ div [ class "notebook-container" ]
            [ button [ class "back-btn", onClick QuitEarly ] [ text "← End Session" ]
            , if model.isLoading
              then div [] [ text "Loading..." ]
              else viewFlashcardArea model
            ]
        ]
    }

viewFlashcardArea : Model -> Html Msg
viewFlashcardArea model =
    case Maybe.andThen .current model.session of
        Nothing ->
            div [ class "flashcard-empty" ] [ h2 [] [ text "Session Complete!" ] ]

        Just card ->
            div [ class "flashcard-wrapper" ]
                [ div [ class "flashcard-front" ]
                    (List.filterMap renderQuestionBlock card.ast.layout)

                , div [ class "flashcard-action" ]
                    [ if model.currentCardState == ShowingAnswer then
                        div [ class "flashcard-back" ]
                            (List.filterMap renderAnswerBlock card.ast.layout ++ [ viewGradingButtons ])
                      else
                        button [ class "btn-show-answer", onClick RevealAnswer ] [ text "Show Answer" ]
                    ]
                ]

renderQuestionBlock : Block -> Maybe (Html Msg)
renderQuestionBlock block =
    case block of
        MainTitle titleText -> Just (h1 [ class "block-main-title" ] [ text titleText ])
        SubTitle subText -> Just (p [ class "block-sub-title" ] [ text subText ])
        _ -> Nothing

renderAnswerBlock : Block -> Maybe (Html Msg)
renderAnswerBlock block =
    case block of
        Meaning meaningText -> Just (p [ class "block-meaning" ] [ text meaningText ])
        DictionaryEntry dict ->
            Just (div [ class "block-dict-entry" ]
                [ div [ class "dict-pos" ] [ text dict.pos ]
                , div [ class "dict-def" ] [ text dict.def ]
                ])
        InlineTags tags ->
            Just (div [ class "block-tags-row", style "margin-bottom" "1rem" ]
                (List.map (\t -> span [ class "pill-tag" ] [ text t ]) tags))
        _ -> Nothing

viewGradingButtons : Html Msg
viewGradingButtons =
    div [ style "display" "flex", style "gap" "0.5rem", style "width" "100%" ]
        [ button [ class "action-btn action-del", style "flex" "1", onClick (RateCard 0) ] [ text "Again" ]
        , button [ class "action-btn action-tag", style "flex" "1", onClick (RateCard 2) ] [ text "Hard" ]
        , button [ class "action-btn action-chk", style "flex" "1", onClick (RateCard 4) ] [ text "Good" ]
        , button [ class "action-btn action-chk", style "flex" "1", style "background-color" "#16a34a", style "color" "white", onClick (RateCard 5) ] [ text "Easy" ]
        ]

