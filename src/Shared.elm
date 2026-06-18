module Shared exposing
    ( Flags, decoder
    , Model, Msg
    , init, update, subscriptions
    )

{-|

@docs Flags, decoder
@docs Model, Msg
@docs init, update, subscriptions

-}

import Effect exposing (Effect)
import Json.Decode
import Route exposing (Route)
import Route.Path
import Shared.Model exposing (..)
import Shared.Msg exposing (..)

import Ports


-- FLAGS


type alias Flags =
    {}


decoder : Json.Decode.Decoder Flags
decoder =
    Json.Decode.succeed {}



-- INIT


type alias Model =
    Shared.Model.Model


init : Result Json.Decode.Error Flags -> Route () -> ( Model, Effect Msg )
init flagsResult route =
    ( { isAuthenticated = False
      , isSyncing = False
      , syncMessage = Nothing
      , dbStatus = Checking
      }
    , Effect.none
    )



-- UPDATE


type alias Msg =
    Shared.Msg.Msg


update : Route () -> Msg -> Model -> ( Model, Effect Msg )
update route msg model =
    case msg of
        DbStatusChanged isReady ->
            if isReady then
                ( { model | dbStatus = Ready }, Effect.none )
            else
                ( { model | dbStatus = NeedsInstall }, Effect.none )

        StartInstallClicked ->
            ( { model | dbStatus = Installing "Preparing..." }
            , Effect.sendCmd (Ports.startDbInstall ())
            )

        InstallProgressMsg progressStr ->
            ( { model | dbStatus = Installing progressStr }, Effect.none )

        AuthStatusChanged status ->
            ( { model | isAuthenticated = status }
            , Effect.none
            )

        SyncStatusReceived message ->
            ( { model
              | isSyncing = False
              , syncMessage = Just message
              }
            , Effect.none
            )



-- SUBSCRIPTIONS


subscriptions : Route () -> Model -> Sub Msg
subscriptions route model =
    Sub.batch
        [ Ports.authStatusChanged AuthStatusChanged
        , Ports.syncStatus SyncStatusReceived
        , Ports.dbStatusReceived DbStatusChanged
        , Ports.installProgress InstallProgressMsg
        ]
