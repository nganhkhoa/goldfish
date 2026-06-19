module Pages.Goldfish.Learn exposing (Model, Msg, page)

import Dict
import Effect exposing (Effect)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput)
import Json.Decode as Decode
import NotebookEntry exposing (NotebookEntry)
import Page exposing (Page)
import Ports
import Route exposing (Route)
import Route.Path
import Shared
import View exposing (View)

import Layouts

type DeckFilter
    = DueOnly
    | Unlearned
    | AllCards

type Game
    = Flashcards
    | Typing

type alias Model =
    { entries : List NotebookEntry
    , selectedFilter : DeckFilter
    , selectedLanguage : Maybe String
    }

type Msg
    = GotNotebookData Decode.Value
    | SetFilter DeckFilter
    | SetLanguage String
    | Launch Game

page : Shared.Model -> Route () -> Page Model Msg
page shared route =
    Page.new
        { init = \_ ->
            ( { entries = []
              , selectedFilter = DueOnly
              , selectedLanguage = Nothing
              }
            -- 1. Ask JS for the database the moment the page loads
            , Effect.sendCmd (Ports.requestNotebook ())
            )
        , update = update
        -- 2. Listen for JS to send the database back
        , subscriptions = \_ -> Ports.receiveNotebook GotNotebookData
        , view = \model -> view model
        }
    |> Page.withLayout toLayout

toLayout : Model -> Layouts.Layout Msg
toLayout model =
    Layouts.Main
        { }

update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        GotNotebookData jsonValue ->
            let
                rawListResult =
                    Decode.decodeValue (Decode.list Decode.value) jsonValue

                validEntries =
                    case rawListResult of
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

                -- Auto-select the first available language if one isn't selected
                firstAvailableLang =
                    List.head validEntries |> Maybe.map .language
            in
            ( { model
                | entries = validEntries
                , selectedLanguage =
                    if model.selectedLanguage == Nothing then
                        firstAvailableLang
                    else
                        model.selectedLanguage
              }
            , Effect.none
            )

        SetFilter filter ->
            ( { model | selectedFilter = filter }, Effect.none )

        SetLanguage lang ->
            ( { model | selectedLanguage = Just lang }, Effect.none )

        Launch game ->
            let
                filterParam =
                    case model.selectedFilter of
                        DueOnly -> "due"
                        Unlearned -> "new"
                        AllCards -> "all"

                langParam =
                    Maybe.withDefault "all" model.selectedLanguage

                path = case game of
                    Flashcards -> Route.Path.Goldfish_Learn_Flashcards
                    Typing -> Route.Path.Goldfish_Learn_Typing
            in
            ( model
            -- 3. Pass the user's intent to the Flashcard page via URL parameters!
            , Effect.pushRoute
                { path = path
                , query = Dict.fromList
                    [ ( "filter", filterParam )
                    , ( "lang", langParam )
                    ]
                , hash = Nothing
                }
            )

view : Model -> View Msg
view model =
    { title = "Learn | Goldfish"
    , body =
        [ div [ class "notebook-container" ]
            [ h1 [ class "page-title" ] [ text "Training Hub" ]

            -- Language Selection
            , div [ class "setup-screen" ]
                [ h2 [] [ text "1. Select Language View" ]
                , viewLanguageSelector model
                ]

            -- Filter Selection
            , div [ class "setup-screen" ]
                [ h2 [] [ text "2. Choose your deck" ]
                , div [ class "block-action-row" ]
                    [ button
                        [ class "action-btn"
                        , classList [ ("active", model.selectedFilter == DueOnly) ]
                        , onClick (SetFilter DueOnly)
                        ] [ text "Due for Review" ]
                    , button
                        [ class "action-btn"
                        , classList [ ("active", model.selectedFilter == Unlearned) ]
                        , onClick (SetFilter Unlearned)
                        ] [ text "New Words" ]
                    , button
                        [ class "action-btn"
                        , classList [ ("active", model.selectedFilter == AllCards) ]
                        , onClick (SetFilter AllCards)
                        ] [ text "Cram Everything" ]
                    ]
                ]

            -- Game Selection
            , div [ class "setup-screen" ]
                [ h2 [] [ text "3. Select a Game" ]
                , div [ class "pack-grid" ]
                    [ div [ class "pack-card", onClick (Launch Flashcards) ]
                        [ h3 [] [ text "Classic Flashcards" ]
                        , p [ class "pack-count" ] [ text "Anki-style pure recall" ]
                        ]
                    , div [ class "pack-card", onClick (Launch Typing) ]
                        [ h3 [] [ text "Typing Practice" ]
                        , p [ class "pack-count" ] [ text "Strict recall & spelling" ]
                        ]
                    ]
                ]
            ]
        ]
    }

-- Extracts unique languages from the DB and renders a simple select dropdown
viewLanguageSelector : Model -> Html Msg
viewLanguageSelector model =
    let
        -- Get a list of unique languages currently in the database
        uniqueLanguages =
            List.foldl
                (\entry acc ->
                    if List.member entry.language acc then acc else entry.language :: acc
                )
                []
                model.entries
    in
    if List.isEmpty uniqueLanguages then
        p [ class "sync-status-text" ] [ text "No words found in database." ]
    else
        select
            [ class "search-input-group" -- Reusing your existing CSS for clean inputs
            , style "padding" "0.75rem 1rem"
            , style "width" "100%"
            , style "border-radius" "8px"
            , onInput SetLanguage
            ]
            (List.map
                (\lang ->
                    option
                        [ value lang
                        , selected (model.selectedLanguage == Just lang)
                        ]
                        [ text lang ]
                )
                uniqueLanguages
            )
