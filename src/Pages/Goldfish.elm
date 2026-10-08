module Pages.Goldfish exposing (Model, Msg, page)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput)

import Ports
import Json.Decode as Decode
import Json.Encode as Encode

import Shared
import Effect exposing (Effect)
import Route exposing (Route)
import Page exposing (Page)
import View exposing (View)

import Set exposing (Set)

import Components.Card
import Components.Card exposing (..)
import NotebookEntry exposing (..)
import Schema exposing (CardAST, decodeToAST)

import Database.Consts exposing (..)

import Layouts

itemsPerPage : Int
itemsPerPage = 3

type alias Model =
    { query : String
    , activeLanguage : Language
    , results : List CardAST
    , currentPage : Int
    , savedWordIds : Set ( String, String )
    , englishSearch : Bool
    , hasSearched : Bool
    }

type Msg
    = SetLanguage Language
    | UpdateQuery String
    | SaveResult CardAST
    | GotResults Decode.Value
    | GotNotebookData Decode.Value
    | DoSearch
    | SetPage Int
    | ToggleEnglishSearch

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


init : () -> ( Model, Effect Msg )
init _ =
    ( { query = ""
      , activeLanguage = Korean
      , results = []
      , currentPage = 1
      , savedWordIds = Set.empty
      , englishSearch = False
      , hasSearched = False
      }
    , Effect.sendCmd (Ports.requestNotebook ()) -- Request notebook on load
    )

syncResultsWithNotebook : Set ( String, String ) -> List CardAST -> List CardAST
syncResultsWithNotebook notebookSet currentResults =
    List.map
        (\card ->
            -- Look up the exact tuple pair!
            { card | isSaved = Set.member ( card.language, card.id ) notebookSet }
        )
        currentResults


update : Msg -> Model -> (Model, Effect Msg)
update msg model =
    case msg of
        SetLanguage lang ->
            ({ model | activeLanguage = lang, results = [] }, Effect.none)

        UpdateQuery newQuery ->
            ({ model | query = newQuery }, Effect.none)

        DoSearch ->
            let lang = short_language_string model.activeLanguage
            in
            let
                payload =
                    Encode.object
                        [ ( "query", Encode.string model.query )
                        , ( "lang", Encode.string lang )
                        , ( "includeEnglish", Encode.bool model.englishSearch )
                        ]
            in
            ( { model | hasSearched = True }
            , Effect.sendCmd (Ports.requestSearch payload)
            )

        GotResults jsonValue ->
            case Decode.decodeValue (Decode.list (decodeToAST (long_language_string model.activeLanguage))) jsonValue of
                Ok validASTs ->
                    let syncedResults = syncResultsWithNotebook model.savedWordIds validASTs
                    in
                    ( { model | results = syncedResults, currentPage = 1 }
                    , Effect.none
                    )

                Err error ->
                    -- let
                    --     errorMessage =
                    --         Decode.errorToString error
                    --     _ =
                    --         Debug.log "🚨 DECODER FAILED" errorMessage
                    -- in
                    ( { model | results = [], currentPage = 1 }
                    , Effect.none
                    )

        ToggleEnglishSearch ->
            ( { model | englishSearch = not model.englishSearch }, Effect.none )

        SetPage newPage ->
            ( { model | currentPage = newPage }
            , Effect.none
            )

        SaveResult targetAst ->
            let
                -- 1. Optimistic UI Update
                updatedResults =
                    List.map
                        (\card ->
                            if card.id == targetAst.id then
                                { card | isSaved = not card.isSaved }
                            else
                                card
                        )
                        model.results

                -- 2. Construct Type-Safe Payload
                dbEffect =
                    if targetAst.isSaved then
                        -- REMOVING
                        RemoveByWordId
                            { lang = targetAst.language
                            , wordId = targetAst.id
                            }
                            |> encodeMutation
                            |> Ports.mutateNotebook
                            |> Effect.sendCmd
                    else
                        -- ADDING
                        Add
                            { lang = targetAst.language
                            , wordId = targetAst.id
                            , refId = ""
                            }
                            |> encodeMutation
                            |> Ports.mutateNotebook
                            |> Effect.sendCmd
            in
            ( { model | results = updatedResults }
            , dbEffect
            )

        GotNotebookData jsonValue ->
            let
                notebookKeyDecoder : Decode.Decoder ( String, String )
                notebookKeyDecoder =
                    Decode.map2 Tuple.pair
                        (Decode.field "lang" Decode.string)
                        (Decode.field "dict_data" (Decode.field "id" Decode.string))

                newSavedKeysList =
                    Decode.decodeValue (Decode.list notebookKeyDecoder) jsonValue
                        |> Result.withDefault []

                newSavedSet =
                    Set.fromList newSavedKeysList
            in
            ( { model
              | savedWordIds = newSavedSet
              , results = syncResultsWithNotebook newSavedSet model.results
              }
            , Effect.none
            )

subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Ports.receiveSearchResults GotResults
        , Ports.receiveNotebook GotNotebookData
        ]


view : Model -> View Msg
view model =
    let
        totalResults =
            List.length model.results

        totalPages =
            if totalResults == 0 then
                1
            else
                ceiling (toFloat totalResults / toFloat itemsPerPage)

        paginatedResults =
            model.results
                |> List.drop ((model.currentPage - 1) * itemsPerPage)
                |> List.take itemsPerPage
    in
    { title = "Search Dictionary"
    , body =
        [ div [ class "search-layout" ]
            [ aside [ class "search-left-tab" ]
                [ h3 [] [ text "Navigation / Filters" ]
                ]

            , section [ class "search-center-tab" ]
                [ div [ class "language-switch-group" ]
                    [ viewLanguageButton Chinese model.activeLanguage
                    , viewLanguageButton Korean model.activeLanguage
                    , viewLanguageButton Japanese model.activeLanguage
                    ]

                , div [ class "search-input-group" ]
                    [ label [ class "english-search-toggle" ]
                        [ input [ type_ "checkbox", checked model.englishSearch, onClick ToggleEnglishSearch ] []
                        , text " EN"
                        ]
                    , input
                        [ placeholder "Enter vocabulary..."
                        , value model.query
                        , onInput UpdateQuery
                        ] []
                    , button [ onClick DoSearch ] [ text "Search" ]
                    ]

                , div [ class "search-results" ]
                    (if List.isEmpty model.results then
                        if model.hasSearched then
                            [ div [ class "empty-state" ] [ text "No results found. Try a different spelling or enable English search." ] ]
                        else
                            [ div [ class "empty-state" ] [ text "Enter a word to search." ] ]
                     else
                        List.map viewCard paginatedResults
                        ++ [ viewPagination model.currentPage totalPages ]
                    )
                ]

            , aside [ class "search-right-tab" ]
                [ h3 [] [ text "Trending / Suggestions" ]
                ]
            ]
        ]
    }


viewLanguageButton : Language -> Language -> Html Msg
viewLanguageButton lang activeLang =
    button
        [ class "lang-btn", (if lang == activeLang then class "active" else class "" )
        , onClick (SetLanguage lang)
        ]
        [ text (long_language_string lang) ]

viewPagination : Int -> Int -> Html Msg
viewPagination currentPage totalPages =
    if totalPages <= 1 then
        text ""
    else
        div [ class "pagination-container" ]
            [ button
                [ class "pagination-btn"
                , onClick (SetPage (currentPage - 1))
                , disabled (currentPage <= 1)
                ]
                [ text "Previous" ]

            , span [ class "pagination-info" ]
                [ text ("Page " ++ String.fromInt currentPage ++ " of " ++ String.fromInt totalPages) ]

            , button
                [ class "pagination-btn"
                , onClick (SetPage (currentPage + 1))
                , disabled (currentPage >= totalPages)
                ]
                [ text "Next" ]
            ]

-- COMPONENT: CARD

viewCard : CardAST -> Html Msg
viewCard ast =
    Components.Card.view SaveResult ast
