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
import Schema exposing (CardAST, decodeToAST)

import Layouts

itemsPerPage : Int
itemsPerPage = 3

type alias Model =
    { query : String
    , activeLanguage : String
    , results : List CardAST
    , currentPage : Int
    , savedWordIds : Set ( String, String )
    }

type Msg
    = SetLanguage String
    | UpdateQuery String
    | SaveResult CardAST
    | GotResults Decode.Value
    | GotNotebookData Decode.Value
    | DoSearch
    | SetPage Int

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
      , activeLanguage = "Korean"
      , results = []
      , currentPage = 1
      , savedWordIds = Set.empty
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


-- NEW: Type-Safe JS Mutations
type NotebookMutation
    = AddWord { lang : String, wordId : String, refId : Maybe String }
    | RemoveWordByWordId { lang : String, wordId : String }
    | RemoveWordById { notebookId : String }
    | UpdateLevel { notebookId : String, newLevel : Int }

encodeMutation : NotebookMutation -> Encode.Value
encodeMutation mutation =
    case mutation of
        AddWord data ->
            Encode.object
                [ ( "action", Encode.string "ADD" )
                , ( "lang", Encode.string data.lang )
                , ( "wordId", Encode.string data.wordId )
                , ( "refId"
                  , case data.refId of
                        Just id -> Encode.string id
                        Nothing -> Encode.null
                  )
                ]

        RemoveWordByWordId data ->
            Encode.object
                [ ( "action", Encode.string "REMOVE_BY_WORD_ID" )
                , ( "lang", Encode.string data.lang )
                , ( "wordId", Encode.string data.wordId )
                ]

        RemoveWordById data ->
            Encode.object
                [ ( "action", Encode.string "REMOVE" )
                , ( "notebookIdString", Encode.string data.notebookId )
                ]

        UpdateLevel data ->
            Encode.object
                [ ( "action", Encode.string "UPDATE_LEVEL" )
                , ( "notebookIdString", Encode.string data.notebookId )
                , ( "newLevel", Encode.int data.newLevel )
                ]


update : Msg -> Model -> (Model, Effect Msg)
update msg model =
    case msg of
        SetLanguage lang ->
            ({ model | activeLanguage = lang, results = [] }, Effect.none)

        UpdateQuery newQuery ->
            ({ model | query = newQuery }, Effect.none)

        DoSearch ->
            let lang =
                    case model.activeLanguage of
                        "Chinese" -> "cn"
                        "Korean" -> "ko"
                        "Japanese" -> "jp"
                        _ -> ""
            in
            let
                payload =
                    Encode.object
                        [ ( "query", Encode.string model.query )
                        , ( "lang", Encode.string lang )
                        ]
            in
            ( model
            , Effect.sendCmd (Ports.requestSearch payload)
            )

        GotResults jsonValue ->
            case Decode.decodeValue (Decode.list (decodeToAST model.activeLanguage)) jsonValue of
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
                        RemoveWordByWordId
                            { lang = targetAst.language
                            , wordId = targetAst.id
                            }
                            |> encodeMutation
                            |> Ports.mutateNotebook
                            |> Effect.sendCmd
                    else
                        -- ADDING
                        AddWord
                            { lang = targetAst.language
                            , wordId = targetAst.id
                            , refId = Nothing
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
                    [ viewLanguageButton "Chinese" model.activeLanguage
                    , viewLanguageButton "Korean" model.activeLanguage
                    , viewLanguageButton "Japanese" model.activeLanguage
                    ]

                , div [ class "search-input-group" ]
                    [ input
                        [ placeholder "Enter vocabulary..."
                        , value model.query
                        , onInput UpdateQuery
                        ] []
                    , button [ onClick DoSearch ] [ text "Search" ]
                    ]

                , div [ class "search-results" ]
                    (if List.isEmpty model.results then
                        [ div [ class "empty-state" ] [ text "No results. Try searching for a word." ] ]
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


viewLanguageButton : String -> String -> Html Msg
viewLanguageButton lang activeLang =
    button
        [ class "lang-btn", (if lang == activeLang then class "active" else class "" )
        , onClick (SetLanguage lang)
        ]
        [ text lang ]

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
