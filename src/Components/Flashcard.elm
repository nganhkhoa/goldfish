module Components.Flashcard exposing (Config, view)

import Html exposing (..)
import Html.Attributes exposing (class, title)
import Html.Events exposing (onClick, stopPropagationOn)
import Json.Decode as Decode

-- Assuming your AST and Blocks are defined in Schema
import Schema exposing (Block(..), CardAST)


-- 1. COMPONENT CONFIGURATION

type alias Config msg =
    { ast : CardAST
    , flipState : Int
    , memoryLevel : Int
    , onFlip : msg
    , onExpand : msg
    , onRemember : msg
    , onRemove : msg
    }


-- 2. HELPER: STOP EVENT BUBBLING
-- Prevents clicking an action button from also triggering the card flip

onClickStop : msg -> Attribute msg
onClickStop msg =
    stopPropagationOn "click" (Decode.succeed ( msg, True ))


-- 3. MAIN VIEW

view : Config msg -> Html msg
view config =
    div
    [ class (if config.memoryLevel == 2 then "flashcard is-remembered" else "flashcard") ]
        [ -- Expand Button (Top Right)
          button
            [ class "expand-btn"
            , onClickStop config.onExpand
            , title "Expand Full Card"
            ]
            [ text "⤢" ]

        , -- Clickable Body (The Flip Area)
          div
            [ class "flashcard-body"
            , onClick config.onFlip
            ]
            (renderFace config.ast.language config.flipState config.ast.layout)

        , -- Action Buttons (Bottom Right)
          div [ class "flashcard-actions" ]
            [ button
                -- Add a special "remembered" class if level is 2
                [ class (if config.memoryLevel == 2 then "action-chk remembered" else "action-chk")
                , onClickStop config.onRemember
                , title "Mark as Remembered"
                ]
                [ text "✔" ]
            , button [ class "action-tag", onClickStop config.onExpand ] [ text "🏷" ] -- Placeholder for tags
            , button [ class "action-del", onClickStop config.onRemove ] [ text "🗑" ]
            ]
        ]


-- 4. RENDERING LOGIC (The Content Extractor)

renderFace : String -> Int -> List Block -> List (Html msg)
renderFace language flipState layout =
    let
        blocksToRender =
            case flipState of
                0 -> -- FRONT: Word
                    List.filter isMainTitle layout

                1 -> -- MIDDLE: Pronunciation / Hanja / Kana
                    let subs = List.filter isSubTitle layout
                    in if List.isEmpty subs then [ Meaning "(No sub-title/reading available)" ] else subs

                _ -> -- BACK: Meaning
                    List.filter isMeaningOrDict layout
    in
    List.map renderBlock blocksToRender


-- 5. BLOCK HELPERS

isMainTitle : Block -> Bool
isMainTitle block =
    case block of
        MainTitle _ -> True
        _ -> False

isSubTitle : Block -> Bool
isSubTitle block =
    case block of
        SubTitle _ -> True
        _ -> False

isMeaningOrDict : Block -> Bool
isMeaningOrDict block =
    case block of
        Meaning _ -> True
        DictionaryEntry _ -> True
        _ -> False

renderBlock : Block -> Html msg
renderBlock block =
    case block of
        MainTitle txt -> h2 [ class "fc-main" ] [ text txt ]
        SubTitle txt -> h3 [ class "fc-sub" ] [ text txt ]
        Meaning txt -> p [ class "fc-mean" ] [ text txt ]
        DictionaryEntry e -> p [ class "fc-mean" ] [ text (e.pos ++ ": " ++ e.def) ]
        _ -> text ""
