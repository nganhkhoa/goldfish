module Layouts.Main exposing (Model, Msg, Props, layout)

import Effect exposing (Effect, installDatabase)
import Html exposing (..)
import Html.Attributes exposing (class, classList, disabled, href)
import Html.Events exposing (..)
import Layout exposing (Layout)
import Route exposing (Route)
import View exposing (View)

import Ports
import Route
import Route.Path
import Shared
import Shared.Model
import Shared.Msg

type alias Props =
    {}

layout : Props -> Shared.Model -> Route () -> Layout () Model Msg contentMsg
layout props shared route =
    Layout.new
        { init = init
        , update = update
        , view = view shared
        , subscriptions = subscriptions
        }


-- MODEL

type alias Model =
    { isMobileMenuOpen : Bool
    , databaseReady : Bool
    }

init : () -> ( Model, Effect Msg )
init _ =
    ( { isMobileMenuOpen = False
      , databaseReady = False
      }
    , Effect.none
    )


-- UPDATE

type Msg
    = ToggleMenu
    | CloseMenu
    | SignInClicked
    | SignOutClicked
    | SyncClicked
    | ExportDatabaseClicked
    | ReceivedDatabaseStatus Bool
    | GotoSettings

update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        ToggleMenu ->
            ( { model | isMobileMenuOpen = not model.isMobileMenuOpen }
            , Effect.none
            )

        CloseMenu ->
            ( { model | isMobileMenuOpen = False }
            , Effect.none
            )

        SignInClicked ->
            ( model
            , Effect.sendCmd (Ports.requestSignIn ())
            )

        SignOutClicked ->
            ( model
            , Effect.sendCmd (Ports.requestSignOut ())
            )

        SyncClicked ->
            ( model
            , Effect.sendCmd (Ports.requestSync ())
            )

        ExportDatabaseClicked ->
            ( model
            , Effect.sendCmd (Ports.requestExportDatabase ())
            )

        GotoSettings ->
            ( model , Effect.none)

        ReceivedDatabaseStatus s ->
            ( { model | databaseReady = s }
            , Effect.none
            )

subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Ports.dbStatusReceived ReceivedDatabaseStatus
        ]


-- VIEW

view : Shared.Model -> { toContentMsg : Msg -> contentMsg, content : View contentMsg, model : Model } -> View contentMsg
view shared { toContentMsg, model, content } =
    { title = content.title
    , body =
        [ div [ class "app-layout" ]
            [ Html.map toContentMsg (viewHeader shared model)
            , main_
                [ class "page-content"
                , Html.Attributes.map toContentMsg (onClick CloseMenu)
                ]
                ((if model.databaseReady then
                    []
                  else
                    [ Html.map toContentMsg notifySetupRequirement ]
                 )
                    ++ content.body
                )
            ]
        ]
    }

notifySetupRequirement : Html Msg
notifySetupRequirement =
    div [] [ text "Setup required, please go to Settings page" ]

viewHeader : Shared.Model -> Model -> Html Msg
viewHeader shared model =
    header [ class "site-header" ]
        [ div [ class "header-brand" ]
            [ h1 [] [ text "Goldfish Dictionary" ] ]

        , div [ class "header-divider" ] []

        , button [ class "hamburger-btn", onClick ToggleMenu ]
            [ text (if model.isMobileMenuOpen then "✕" else "☰") ]

        , nav [ classList [ ( "header-nav", True ), ( "is-open", model.isMobileMenuOpen ) ] ]
            [ div [ class "nav-left" ]
                [ a [ Route.Path.href Route.Path.Goldfish
                    , class "nav-link"
                    , onClick ToggleMenu
                    ] [ text "Search" ]
                , a [ Route.Path.href Route.Path.Goldfish_Notebook
                    , class "nav-link"
                    , onClick ToggleMenu
                    ] [ text "Notebook" ]
                , a [ Route.Path.href Route.Path.Goldfish_Learn
                    , class "nav-link"
                    , onClick ToggleMenu
                    ] [ text "Learn" ]
                , a [ Route.Path.href Route.Path.Goldfish_Reader
                    , class "nav-link"
                    , onClick ToggleMenu
                    ] [ text "Reader" ]
                , a [ Route.Path.href Route.Path.Goldfish_Settings
                    , class "nav-link"
                    , onClick ToggleMenu
                    ] [ text "Settings" ]
                ]
            , div [ class "nav-right" ]
                [ a [ Route.Path.href Route.Path.Goldfish_Import, class "nav-link", onClick ToggleMenu ] [ text "Import DB" ]
                , button [ class "nav-link export-db-link", onClick ExportDatabaseClicked ] [ text "Export DB" ]
                , div [ class "header-actions" ] [ viewAuthSection shared ]
                ]
            ]
        ]

viewAuthSection : Shared.Model -> Html Msg
viewAuthSection shared =
    if shared.isAuthenticated then
        div [ class "auth-group-logged-in" ]
            [ case shared.syncMessage of
                Just msg -> span [ class "sync-status-text" ] [ text msg ]
                Nothing -> text ""

            , button
                [ class "sync-btn"
                , onClick SyncClicked
                , disabled shared.isSyncing
                ]
                [ text (if shared.isSyncing then "Syncing..." else "Sync DB") ]

            , button [ class "user-icon-btn", onClick SignOutClicked ] [ text "👤" ]
            ]
    else
        div [ class "auth-group-logged-out" ]
            [ button [ class "google-signin-btn", onClick SignInClicked ]
                [ text "Sign in with Google" ]
            ]
