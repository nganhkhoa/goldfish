module Layouts.Main exposing (Model, Msg, Props, layout)

import Effect exposing (Effect, installDatabase)
import Html exposing (..)
import Html.Attributes exposing (class, classList, disabled, href) -- Added 'disabled'
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
    { isMobileMenuOpen : Bool }

init : () -> ( Model, Effect Msg )
init _ =
    ( { isMobileMenuOpen = False }
    , Effect.none
    )


-- UPDATE

type Msg
    = ToggleMenu
    | CloseMenu
    | SignInClicked    -- ADDED
    | SignOutClicked   -- ADDED
    | SyncClicked      -- ADDED
    | InstallClicked

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

        -- Delegate Auth/Sync actions to JavaScript via Ports
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

        InstallClicked ->
            ( model
            , installDatabase
            )

subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


-- VIEW

view : Shared.Model -> { toContentMsg : Msg -> contentMsg, content : View contentMsg, model : Model } -> View contentMsg
view shared { toContentMsg, model, content } =
    { title =
        if shared.dbStatus == Shared.Model.Ready then
            content.title
        else
            "Setup Required - Goldfish Dictionary"
    , body =
        [ div [ class "app-layout" ]
            [ Html.map toContentMsg (viewHeader shared model)
            , main_
                [ class "page-content"
                , Html.Attributes.map toContentMsg (onClick CloseMenu)
                ]
                -- THE GATEKEEPER: Check the database status before rendering the page
                (if shared.dbStatus == Shared.Model.Ready then
                    content.body
                 else
                    [ Html.map toContentMsg (viewSetupScreen shared.dbStatus) ]
                )
            ]
        ]
    }


-- THE NEW INSTALLATION UI
viewSetupScreen : Shared.Model.DbStatus -> Html Msg
viewSetupScreen status =
    case status of
        Shared.Model.Checking ->
            div [ class "setup-screen" ]
                [ text "Checking database..." ]

        Shared.Model.NeedsInstall ->
            div [ class "setup-screen" ]
                [ h2 [] [ text "Offline Dictionaries Required" ]
                , p [] [ text "Goldfish operates entirely offline after dictionaries are installed. Press the install button to get started." ]
                , button
                    [ class "install-btn", onClick InstallClicked ]
                    [ text "Download & Install (~5MB)" ]
                ]

        Shared.Model.Installing progressText ->
            div [ class "setup-screen" ]
                [ h2 [] [ text "Installing Database..." ]
                , p [ class "progress-text" ] [ text progressText ]
                , div [ class "spinner" ] [] -- You can style this in CSS later
                ]

        Shared.Model.Ready ->
            text "" -- This acts as a fallback; the 'if' statement above prevents this from ever rendering.

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
                [ a [ Route.Path.href Route.Path.Goldfish , class "nav-link" ] [ text "Search" ]
                , a [ Route.Path.href Route.Path.Goldfish_Notebook , class "nav-link" ] [ text "Notebook" ]
                ]
            , div [ class "nav-right" ]
                [ a [ href "#", class "nav-link" ] [ text "Settings" ]
                , a [ href "#", class "nav-link" ] [ text "Export DB" ]
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
