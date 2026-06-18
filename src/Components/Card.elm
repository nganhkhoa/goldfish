module Components.Card exposing (view)

import Html exposing (..)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick)

import Schema exposing (Block(..), CardAST)

view : (CardAST -> msg) -> CardAST -> Html msg
view onSave ast =
    div [ class "flexible-card" ]
        [ -- Header (Save Button)
          div [ class "card-header" ]
            [ button
                [ class "save-btn", onClick (onSave ast) ]
                [ text (if ast.isSaved then "♥ Saved" else "♡ Save") ]
            ]
        , -- Body (Iterate through the AST and render each block)
          div [ class "card-body" ]
            (List.map viewBlock ast.layout)
        ]


-- 3. THE BLOCK RENDERER

viewBlock : Block -> Html msg
viewBlock block =
    case block of
        MainTitle txt ->
            h2 [ class "block-main-title" ] [ text txt ]

        SubTitle txt ->
            span [ class "block-sub-title" ] [ text txt ]

        InlineTags tags ->
            div [ class "block-tags-row" ]
                (List.map (\t -> span [ class "pill-tag" ] [ text t ]) tags)

        Meaning txt ->
            p [ class "block-meaning" ] [ text txt ]

        ActionRow actions ->
            div [ class "block-action-row" ]
                (List.map (\act -> button [ class "action-btn" ] [ text act ]) actions)

        DictionaryEntry entry ->
            div [ class "block-dict-entry" ]
                [ span [ class "dict-pos" ] [ text entry.pos ]
                , span [ class "dict-def" ] [ text entry.def ]
                ]
