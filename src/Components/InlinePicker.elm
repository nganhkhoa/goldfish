module Components.InlinePicker exposing (PickerCharacter, PickerLayout(..), pickerIndexDecoder, view)

import Html exposing (Html, button, div, p, span, strong, text)
import Html.Attributes exposing (class, classList)
import Html.Events exposing (onClick)
import Json.Decode as Decode
import Components.InlinePickerFamilies exposing (familiesFor)


type PickerLayout = LeftRight | TopBottom | Surround | ThreePart | Overlay

type alias PickerCharacter = { hanzi : String, pinyin : String, gloss : String, layout : PickerLayout, parts : List String }
type alias Index = { characters : List PickerCharacter }
type alias Config msg = { open : Bool, layout : Maybe PickerLayout, family : Maybe String, part : Maybe String, characters : List PickerCharacter, chooseLayout : PickerLayout -> msg, chooseFamily : String -> msg, choosePart : String -> msg, restartAt : Int -> msg, pick : String -> msg, close : msg }

pickerIndexDecoder = Decode.map Index (Decode.field "characters" (Decode.list characterDecoder))
characterDecoder = Decode.map5 PickerCharacter (Decode.field "hanzi" Decode.string) (Decode.field "pinyin" Decode.string) (Decode.field "gloss" Decode.string) (Decode.field "layout" layoutDecoder) (Decode.field "parts" (Decode.list Decode.string))
layoutDecoder = Decode.string |> Decode.andThen (\s -> case fromKey s of
    Just x -> Decode.succeed x
    Nothing -> Decode.fail "layout")
fromKey s = case s of
    "leftRight" -> Just LeftRight
    "topBottom" -> Just TopBottom
    "surround" -> Just Surround
    "threePart" -> Just ThreePart
    "overlay" -> Just Overlay
    _ -> Nothing
layouts = [ LeftRight, TopBottom, Surround, ThreePart, Overlay ]
layoutName l = case l of
    LeftRight -> "Left + right"
    TopBottom -> "Top + bottom"
    Surround -> "Around"
    ThreePart -> "Three parts"
    Overlay -> "Overlay"
layoutGlyph l = case l of
    LeftRight -> "⿰"
    TopBottom -> "⿱"
    Surround -> "⿴"
    ThreePart -> "⿲"
    Overlay -> "⿻"
groups = [ ( "月", [ "月", "⺼" ] ), ( "水", [ "水", "氵" ] ), ( "手", [ "手", "扌" ] ), ( "心", [ "心", "忄" ] ), ( "言", [ "言", "讠" ] ), ( "人", [ "人", "亻" ] ), ( "金", [ "金", "钅" ] ), ( "辶", [ "辶", "⻌" ] ) ]
leader x = groups |> List.filter (\(_, xs) -> List.member x xs) |> List.head |> Maybe.map Tuple.first |> Maybe.withDefault x
layoutKey layout = case layout of
    LeftRight -> "leftRight"
    TopBottom -> "topBottom"
    Surround -> "surround"
    ThreePart -> "threePart"
    Overlay -> "overlay"
familyParts layout f = familiesFor (layoutKey layout) |> List.filter (\(name, _) -> name == f) |> List.head |> Maybe.map Tuple.second |> Maybe.withDefault []

view c =
    if not c.open then text "" else
    div [ class "inline-picker" ]
        [ div [ class "inline-picker-head" ] [ strong [] [ text "Character picker" ], button [ onClick c.close ] [ text "Close" ] ]
        , div [ class "picker-door-stack" ]
            [ door c 1 "1 Layout" (c.layout /= Nothing) (viewLayouts c)
            , door c 2 "2 Family" (c.family /= Nothing) (viewFamilies c)
            , door c 3 "3 Piece" (c.part /= Nothing) (viewParts c)
            ]
        , viewCandidates c
        ]
door c step label done content =
    div [ classList [ ( "picker-door", True ), ( "done", done ) ] ]
        [ button [ class "door-label", onClick (c.restartAt step) ] [ text label ]
        , div [ class "door-details" ] [ content ]
        ]
viewLayouts c = div [ class "inline-choice-row" ] (List.map (\l -> button [ classList [ ( "inline-choice", True ), ( "selected", c.layout == Just l ) ], onClick (c.chooseLayout l) ] [ text (layoutGlyph l ++ " " ++ layoutName l) ]) layouts)
viewFamilies c =
    case c.layout of
        Just layout ->
            div [ class "inline-family-row" ]
                (familiesFor (layoutKey layout)
                    |> List.map (\(name, xs) -> button [ classList [ ( "inline-family", True ), ( "selected", c.family == Just name ) ], onClick (c.chooseFamily name) ] [ strong [] [ text name ], span [] [ text (String.join " " xs) ] ])
                )
        Nothing -> p [] [ text "Choose a layout first." ]
viewParts c = case (c.layout, c.family) of
    (Just layout, Just f) -> div [ class "inline-choice-row" ] (List.map (\part -> button [ classList [ ( "inline-choice", True ), ( "selected", c.part == Just part ) ], onClick (c.choosePart part) ] [ text part ]) (familyParts layout f))
    (Just layout, _) -> div [ class "inline-choice-row" ] (c.characters |> List.filter (\x -> x.layout == layout) |> List.filterMap (\x -> List.head x.parts) |> List.map leader |> unique |> List.take 18 |> List.map (\part -> button [ class "inline-choice", onClick (c.choosePart part) ] [ text part ]))
    _ -> text ""
viewCandidates c = case (c.layout, c.part) of
    (Just layout, Just part) ->
        let matches = c.characters |> List.filter (\x -> x.layout == layout && (List.head x.parts |> Maybe.map leader) == Just part)
        in div [ class "inline-candidates" ] (List.map (\x -> button [ class "inline-candidate", onClick (c.pick x.hanzi) ] [ span [ class "inline-hanzi" ] [ text x.hanzi ], if String.isEmpty x.pinyin then text "" else span [ class "inline-pronunciation" ] [ text x.pinyin ] ]) matches)
    _ -> p [ class "inline-picker-hint" ] [ text "Choose one visible piece; candidates appear immediately." ]
unique xs = List.foldl (\x seen -> if List.member x seen then seen else seen ++ [ x ]) [] xs
