module Pages.Goldfish.Import exposing (Model, Msg, page)

import Html exposing (..)
import Html.Attributes exposing (class, type_)
import Html.Events exposing (onClick)
import Page exposing (Page)
import Route exposing (Route)
import Shared
import View exposing (View)
import Effect exposing (Effect)
import Layouts
import Ports


type alias Model = { status : String }

type Msg = StartImport | ImportStatus String

page : Shared.Model -> Route () -> Page Model Msg
page shared route =
    Page.new
        { init = \_ -> ( { status = "Choose a Goldfish notebook JSON export." }, Effect.none )
        , update = update
        , subscriptions = \_ -> Ports.importStatus ImportStatus
        , view = view
        }
    |> Page.withLayout (\_ -> Layouts.Main {})

update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        StartImport ->
            ( { model | status = "Importing..." }, Effect.sendCmd (Ports.importDatabaseFile ()) )
        ImportStatus status ->
            ( { model | status = status }, Effect.none )

view : Model -> View Msg
view model =
    { title = "Import | Goldfish"
    , body =
        [ div [ class "import-page" ]
            [ h1 [ class "page-title" ] [ text "Import notebook" ]
            , p [] [ text "Import a version 1 or version 2 Goldfish notebook export. Existing entries are preserved." ]
            , button [ class "reading-primary-button", type_ "button", onClick StartImport ] [ text "Choose JSON file" ]
            , p [ class "import-status" ] [ text model.status ]
            ]
        ]
    }
