module Pages.Goldfish.Learn.Typing exposing (Model, Msg, page)

import Dict
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, on)
import Json.Decode as Decode
import Random
import Task
import Time
import Page exposing (Page)
import Route exposing (Route)
import Shared
import Effect exposing (Effect)
import Ports
import View exposing (View)
import Route exposing (Route)
import Route.Path

import Schema
import Learn.Engine as Engine exposing (Session, PackFilter(..))
import NotebookEntry exposing (NotebookEntry)


-- MODEL

type CardState
    = ShowingQuestion
    | ShowingAnswer

type alias Model =
    { session : Maybe Session
    , currentCardState : CardState
    , isLoading : Bool
    , filterType : PackFilter
    , langFilter : String
    , typedInput : String
    , lastScore : Maybe Int
    , feedback : Maybe String
    }

parseFilter : String -> PackFilter
parseFilter str =
    case str of
        "due" -> Due
        "new" -> New
        _     -> All


-- INIT

page : Shared.Model -> Route () -> Page Model Msg
page _ route =
    Page.new
        { init = \_ ->
            let
                fType = parseFilter (Dict.get "filter" route.query |> Maybe.withDefault "all")
                lFilter = Dict.get "lang" route.query |> Maybe.withDefault "all"
            in
            ( { session = Nothing
              , currentCardState = ShowingQuestion
              , isLoading = True
              , filterType = fType
              , langFilter = lFilter
              , typedInput = ""
              , lastScore = Nothing
              , feedback = Nothing
              }
            , Effect.sendCmd (Ports.requestNotebook ())
            )
        , update = update
        , view = view
        , subscriptions = \_ -> Ports.receiveNotebook GotNotebookData
        }


-- UPDATE

type Msg
    = GotNotebookData Decode.Value
    | GotSeedAndInit (List NotebookEntry) Time.Posix
    | InputChanged String
    | SubmitTyping
    | RateCard Int
    | GotTimeAndQuality Int Int
    | QuitEarly
    | SkipCard


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        GotNotebookData jsonValue ->
            if model.session /= Nothing then
                ( model, Effect.none )
            else
                let
                    rawListResult = Decode.decodeValue (Decode.list Decode.value) jsonValue
                    validEntries = case rawListResult of
                        Ok rawValues -> List.filterMap (\rawItem -> Result.toMaybe (Decode.decodeValue NotebookEntry.decoder rawItem)) rawValues
                        Err _ -> []

                    langFiltered =
                        if model.langFilter == "all"
                        then validEntries
                        else List.filter (\e -> e.language == model.langFilter) validEntries
                in
                ( model, Effect.sendCmd (Task.perform (\t -> GotSeedAndInit langFiltered t) Time.now) )

        GotSeedAndInit baseQueue time ->
            let
                now = Time.posixToMillis time
                seed = Random.initialSeed now

                finalQueue = case model.filterType of
                    Due -> List.filter (\e -> e.nextReview == 0 || e.nextReview <= now) baseQueue
                    New -> List.filter (\e -> e.nextReview == 0) baseQueue
                    All -> baseQueue

                newSession = Engine.initSession now seed finalQueue model.filterType
            in
            ( { model | session = Just newSession, isLoading = False }, Effect.none )

        InputChanged newText ->
            ( { model | typedInput = newText, feedback = Nothing }, Effect.none )

        SubmitTyping ->
            case model.session |> Maybe.andThen .current of
                Just currentEntry ->
                    let
                        targetWord = getTargetWord currentEntry
                        score = evaluateTyping model.typedInput targetWord
                    in
                    if score >= 3 then
                        -- Good or Perfect: Show them the answer and Next button
                        ( { model
                          | currentCardState = ShowingAnswer
                          , lastScore = Just score
                          , feedback = Nothing
                          }
                        , Effect.none
                        )
                    else
                        -- Wrong: Let them try again
                        ( { model
                          | feedback = Just "Incorrect. Try again!"
                          -- Optional: You can clear `typedInput = ""` here if you want to force them to retype from scratch
                          }
                        , Effect.none
                        )
                Nothing ->
                    ( model, Effect.none )

        SkipCard ->
            ( { model
              | currentCardState = ShowingAnswer
              , lastScore = Just 1
              , feedback = Nothing
              }
            , Effect.none
            )

        RateCard quality ->
            ( model, Effect.sendCmd (Task.perform (\t -> GotTimeAndQuality (Time.posixToMillis t) quality) Time.now) )

        GotTimeAndQuality now quality ->
            case model.session of
                Just sess ->
                    case sess.current of
                        Just entry ->
                            let
                                -- 2. Advance the session state (returns Session)
                                updatedSess = Engine.processAnswer now quality sess

                                -- 3. Calculate the DB math for this specific card (returns NotebookEntry)
                                updatedEntry = Engine.evaluateCard now quality entry

                                -- 4. Wrap it in your ADT and encode
                                encodedCmd =
                                    Ports.mutateNotebook
                                        (NotebookEntry.encodeMutation (NotebookEntry.UpdateStats updatedEntry))
                            in
                            ( { model
                              | session = Just updatedSess
                              , currentCardState = ShowingQuestion
                              , typedInput = "" -- Clears input if playing the typing game
                              , lastScore = Nothing
                              }
                            , Effect.sendCmd encodedCmd
                            )
                        Nothing ->
                            ( model, Effect.none )
                Nothing ->
                    ( model, Effect.none )

        QuitEarly -> ( model, Effect.pushRoute { path = Route.Path.Goldfish_Learn, query = Dict.empty, hash = Nothing } )


-- VIEW

view : Model -> View Msg
view model =
    { title = "Typing Game"
    , body =
        [ div [ class "notebook-container" ]
            [ button [ class "back-btn", onClick QuitEarly ] [ text "← End Session" ]
            , if model.isLoading then
                div [] [ text "Loading..." ]
              else
                viewFlashcardArea model
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
                    -- Use the helper to render the meaning
                    [ p [ class "typing-prompt-label" ] [ text "Meaning:" ]
                    , h2 [ class "typing-prompt-text" ] [ text (getMeaning card) ]
                    ]

                , hr [ class "flashcard-divider" ] []

                , div [ class "flashcard-action" ]
                      [ if model.currentCardState == ShowingAnswer then
                        let
                            score = Maybe.withDefault 1 model.lastScore
                            feedbackClass = if score >= 3 then "correct" else "incorrect"
                        in
                        div [ class ("typing-results " ++ feedbackClass) ]
                            -- Added strong tags for visual hierarchy
                            [ p [] [ text "Correct Answer: ", strong [] [ text (getTargetWord card) ] ]
                            , p [] [ text "You Typed: ", strong [] [ text (if String.isEmpty model.typedInput then "(Skipped)" else model.typedInput) ] ]
                            , h3 [] [ text ("Score: " ++ String.fromInt score) ]
                            , button [ class "btn-next", onClick (RateCard score), autofocus True ] [ text "Next Card" ]
                            ]
                      else
                        div [ class "typing-interaction" ]
                            [ div [ class "typing-input-container" ]
                                [ input
                                    [ type_ "text"
                                    , value model.typedInput
                                    , onInput InputChanged
                                    , onEnter SubmitTyping -- Enter key works!
                                    , placeholder "Type the word..."
                                    , autofocus True
                                    ] []
                                , button [ onClick SubmitTyping ] [ text "Submit" ]
                                , button [ class "btn-skip", onClick SkipCard ] [ text "Skip" ]
                                ]
                            -- Show the "Try Again" feedback if it exists
                            , case model.feedback of
                                Just msgText ->
                                    div [ class "typing-feedback-error" ] [ text msgText ]
                                Nothing ->
                                    text ""
                            ]
                    ]
                ]

-- HELPERS

onEnter : Msg -> Html.Attribute Msg
onEnter msg =
    let
        isEnter code =
            if code == 13 then Decode.succeed msg else Decode.fail "not ENTER"
    in
    on "keydown" (Decode.andThen isEnter Html.Events.keyCode)


evaluateTyping : String -> String -> Int
evaluateTyping userInput targetAnswer =
    let
        user = String.trim (String.toLower userInput)
        target = String.trim (String.toLower targetAnswer)

        matchingChars =
            List.map2 (\u t -> if u == t then 1 else 0) (String.toList user) (String.toList target)
                |> List.sum

        lengthDiff = abs (String.length user - String.length target)
    in
    if user == target then
        4
    else if lengthDiff <= 1 && matchingChars >= (String.length target - 1) then
        3
    else if String.startsWith user target && String.length user > (String.length target // 2) then
        2
    else
        1

getTargetWord : NotebookEntry -> String
getTargetWord entry =
    entry.ast.layout
        |> List.filterMap (\block ->
            case block of
                Schema.MainTitle title -> Just title
                _ -> Nothing
        )
        |> List.head
        |> Maybe.withDefault "UNKNOWN"

getMeaning : NotebookEntry -> String
getMeaning entry =
    entry.ast.layout
        |> List.filterMap (\block ->
            case block of
                Schema.Meaning meaning -> Just meaning
                _ -> Nothing
        )
        |> String.join " / " -- In case there are multiple meaning blocks
