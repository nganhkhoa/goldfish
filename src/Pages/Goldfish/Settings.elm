module Pages.Goldfish.Settings exposing (Model, Msg, page)

import Html exposing (..)
import Html.Attributes exposing (class, disabled)
import Html.Events exposing (onClick)
import Json.Decode as Decode
import Json.Encode as Encode

import Route exposing (Route)
import Page exposing (Page)
import View exposing (View)

import Effect exposing (Effect)
import Ports
import Shared
import Shared.Model
import Layouts


type Tab
    = Installation DatabaseStatus

type DatabaseStatus
    = Ready
    | Checking
    | NeedsInstall
    | Installing String


type alias Model =
    { tab : Tab
    }

-- settings should propagate to the shared state
-- or it should collect from the setting key in local storage
type Msg
    = None
    | InitiateInstall
    | ReceivedDatabaseStatus Bool
    | InstallProgressReceived String

page : Shared.Model -> Route () -> Page Model Msg
page shared route =
    Page.new
        { init = \_ -> initFromShared shared
        , update = update
        , subscriptions = subscriptions
        , view = view
        }
    |> Page.withLayout toLayout

init : () -> ( Model, Effect Msg )
init _ =
    ( { tab = Installation Checking }
    , Effect.none
    )

initFromShared : Shared.Model -> ( Model, Effect Msg )
initFromShared shared =
    ( { tab =
            Installation
                (case shared.dbStatus of
                    Shared.Model.Ready -> Ready
                    Shared.Model.NeedsInstall -> NeedsInstall
                    Shared.Model.Installing progress -> Installing progress
                    Shared.Model.Checking -> Checking
                )
      }
    , Effect.sendCmd (Ports.requestDbStatus ())
    )


toLayout : Model -> Layouts.Layout Msg
toLayout model =
    Layouts.Main
        { }

subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Ports.dbStatusReceived ReceivedDatabaseStatus
        , Ports.installProgress InstallProgressReceived
        ]

update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        InitiateInstall ->
            ( { model | tab = Installation (Installing "Preparing...") }
            , Effect.sendCmd (Ports.startDbInstall ())
            )
        InstallProgressReceived progress ->
            ( { model | tab = Installation (Installing progress) }
            , Effect.none
            )
        ReceivedDatabaseStatus True ->
            ( { model | tab = Installation Ready }
            , Effect.none
            )
        ReceivedDatabaseStatus False ->
            ( { model | tab = Installation NeedsInstall }
            , Effect.none
            )

        _ -> (model, Effect.none)

view : Model -> View Msg
view model =
    { title = "Settings"
    , body =
        [ div
            [ class "settings" ]
            [ renderByTab model.tab ]
        ]
    }

renderByTab : Tab -> Html Msg
renderByTab tab =
    case tab of
        Installation dbstatus ->
            div []
                [ section [ class "setup-screen" ]
                    (case dbstatus of
                        Checking ->
                            [ text "Checking database..." ]

                        NeedsInstall ->
                            [ h2 [] [ text "Offline Dictionaries Required" ]
                            , p [] [ text "Goldfish operates entirely offline after dictionaries are installed. Press the install button to get started." ]
                            , button
                                [ class "install-btn", onClick InitiateInstall ]
                                [ text "Download & Install (~10MB)" ]
                            ]

                        Installing progressText ->
                            [ h2 [] [ text "Installing Database..." ]
                            , p [ class "progress-text" ] [ text progressText ]
                            , div [ class "spinner" ] []
                            ]

                        Ready ->
                            [ h2 [] [ text "Offline Dictionary Ready" ]
                            ]
                    )
                ]
