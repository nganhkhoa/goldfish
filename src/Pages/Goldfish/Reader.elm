module Pages.Goldfish.Reader exposing (Model, Msg, page)

import Html exposing (..)
import Html.Attributes exposing (class, classList, cols, disabled, rows, selected, value)
import Html.Events exposing (on, onClick, onInput)
import Json.Decode as Decode
import Page exposing (Page)
import Route exposing (Route)
import Shared
import View exposing (View)
import Effect exposing (Effect)
import Layouts
import Database.Consts exposing (Language(..), long_language_string)
import Components.Card as Card
import Schema exposing (Block(..), CardAST)


type alias Model =
    { language : Language
    , sourceText : String
    , sentences : List (List String)
    , sentenceIndex : Int
    , selectedWord : Maybe String
    , conjugationRule : String
    , conjugatedWord : Maybe String
    }


type Msg
    = SetLanguage Language
    | SetSourceText String
    | StartReading
    | PreviousSentence
    | NextSentence
    | SelectWord String
    | SaveWord CardAST
    | SetConjugationRule String
    | ApplyConjugation


page : Shared.Model -> Route () -> Page Model Msg
page shared route =
    Page.new
        { init = \_ -> ( initModel, Effect.none )
        , update = update
        , subscriptions = \_ -> Sub.none
        , view = view
        }
    |> Page.withLayout (\_ -> Layouts.Main {})


initModel : Model
initModel =
    { language = Korean
    , sourceText = exampleText
    , sentences = splitSentences exampleText
    , sentenceIndex = 0
    , selectedWord = Nothing
    , conjugationRule = "want"
    , conjugatedWord = Nothing
    }


exampleText : String
exampleText =
    "오늘은 날씨가 좋습니다. 우리는 공원에서 산책을 합니다. 새로운 단어를 함께 공부해요."


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        SetLanguage language ->
            ( { model | language = language }, Effect.none )

        SetSourceText text ->
            ( { model | sourceText = text }, Effect.none )

        StartReading ->
            ( { model
                | sentences = splitSentences model.sourceText
                , sentenceIndex = 0
                , selectedWord = Nothing
              }
            , Effect.none
            )

        PreviousSentence ->
            ( { model | sentenceIndex = max 0 (model.sentenceIndex - 1), selectedWord = Nothing }, Effect.none )

        NextSentence ->
            ( { model | sentenceIndex = min (max 0 (List.length model.sentences - 1)) (model.sentenceIndex + 1), selectedWord = Nothing }, Effect.none )

        SelectWord word ->
            ( { model | selectedWord = Just word }, Effect.none )

        SaveWord ast ->
            ( model, Effect.none )

        SetConjugationRule rule ->
            ( { model | conjugationRule = rule }, Effect.none )

        ApplyConjugation ->
            ( { model | conjugatedWord = applyDemoRule model.conjugationRule (Maybe.withDefault "食べる" model.selectedWord) }
            , Effect.none
            )


splitSentences : String -> List (List String)
splitSentences text =
    text
        |> String.split "."
        |> List.concatMap (\sentence ->
            let clean = String.trim sentence
            in if String.isEmpty clean then [] else [ String.words clean ]
        )


currentSentence : Model -> List String
currentSentence model =
    model.sentences
        |> List.drop model.sentenceIndex
        |> List.head
        |> Maybe.withDefault []


view : Model -> View Msg
view model =
    { title = "Reading Utility | Goldfish"
    , body =
        [ div [ class "reading-page" ]
            [ h1 [ class "page-title" ] [ text "Reading Utility" ]
            , div [ class "reading-input-panel" ]
                [ p [] [ text "Paste a text, choose a language, and read it one sentence at a time." ]
                , div [ class "reading-language-buttons" ] (List.map (languageButton model.language) [ Chinese, Korean, Japanese ])
                , textarea [ class "reading-text-input", rows 6, cols 60, value model.sourceText, onInput SetSourceText ] []
                , button [ class "reading-primary-button", onClick StartReading ] [ text "Start reading" ]
                ]
            , div [ class "reading-workspace" ]
                [ div [ class "reading-sentence-panel" ]
                    [ div [ class "reading-counter" ] [ text (String.fromInt (model.sentenceIndex + 1) ++ " / " ++ String.fromInt (max 1 (List.length model.sentences))) ]
                    , h2 [] (List.map (\word -> span [ class "sentence-word" ] [ text (word ++ " ") ]) (currentSentence model))
                    , p [ class "translation-placeholder" ] [ text "English translation will appear here." ]
                    , div [ class "reading-navigation" ]
                        [ button [ onClick PreviousSentence, disabled (model.sentenceIndex == 0) ] [ text "← Previous" ]
                        , button [ onClick NextSentence, disabled (model.sentenceIndex >= List.length model.sentences - 1) ] [ text "Next →" ]
                        ]
                    ]
                , div [ class "reading-words-panel" ]
                    [ h3 [] [ text "Words in this sentence" ]
                    , div [ class "reading-word-cards" ] (List.map (wordCard model.selectedWord) (currentSentence model))
                    , conjugationPanel model
                    ]
                ]
            ]
        ]
    }


conjugationPanel : Model -> Html Msg
conjugationPanel model =
    case model.selectedWord of
        Nothing -> text ""
        Just word ->
            div [ class "conjugation-panel" ]
                [ h3 [] [ text ("Conjugation helper: " ++ word) ]
                , select [ on "change" (Decode.map SetConjugationRule (Decode.field "target" (Decode.field "value" Decode.string))) ]
                    [ option [ value "want" ] [ text "Want to do (たい)" ]
                    , option [ value "negative" ] [ text "Negative informal" ]
                    , option [ value "polite" ] [ text "Polite form" ]
                    ]
                , button [ class "reading-primary-button", onClick ApplyConjugation ] [ text "Add" ]
                , case model.conjugatedWord of
                    Just result -> p [ class "conjugation-result" ] [ text result ]
                    Nothing -> text ""
                ]


applyDemoRule : String -> String -> Maybe String
applyDemoRule rule word =
    case rule of
        "want" ->
            if String.endsWith "る" word then Just (String.dropRight 1 word ++ "たい") else Just (word ++ "たい")
        "negative" ->
            if String.endsWith "い" word then Just (String.dropRight 1 word ++ "くない") else Just (word ++ "ない")
        "polite" ->
            if String.endsWith "る" word then Just (String.dropRight 1 word ++ "ます") else Just (word ++ "ます")
        _ -> Just word


languageButton : Language -> Language -> Html Msg
languageButton active language =
    button [ classList [ ( "active", active == language ) ], onClick (SetLanguage language) ] [ text (long_language_string language) ]


wordCard : Maybe String -> String -> Html Msg
wordCard selectedWord word =
    let
        card =
            { id = word
            , language = "ko"
            , isSaved = False
            , layout = [ MainTitle word, Meaning "Meaning will appear here" ]
            }
    in
    div [ classList [ ( "reading-word-card", True ), ( "selected", selectedWord == Just word ) ], onClick (SelectWord word) ]
        [ Card.view SaveWord card
        , button [ class "conjugation-toggle", onClick (SelectWord word) ] [ text "Conjugate" ]
        ]
